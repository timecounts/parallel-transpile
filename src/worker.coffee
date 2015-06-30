fs = require 'fs'
Path = require 'path'
mkdirp = require 'mkdirp'
ApplySourceMap = require 'apply-source-map'
utils = require './utils'

loaders = {}
source = null
output = null

send = (message) ->
  if message instanceof Error
    console.error message.stack
    message =
      error: true
      message: message.toString()
      stack: message.stack
  process.send message

init = (options) ->
  source = options.source.replace(/\/*$/, "/")
  output = options.output.replace(/\/+$/, "")

process.on 'message', (m) ->
  return init(m.init) if m.init
  throw new Error "Not initialised" unless source
  {path, rule: {inExt, loaders, outExt}} = m
  relativePath = path.substr(source.length)
  outPath = "#{output}/#{utils.swapExtension(relativePath, inExt, outExt)}"
  mapPath = "#{output}/#{utils.swapExtension(relativePath, inExt, ".map")}"
  webpackLoaders = []
  baseName = Path.basename relativePath
  requestString = baseName
  for loader in loaders
    try
      requestString = "#{loader}!#{requestString}"
      [_, moduleName, query] = loader.match(/^([^?]+)(\?.*)?$/)
      loaderModule = require(moduleName)
      webpackLoaders.push
        request: requestString
        path: baseName
        query: query
        module: loaderModule
    catch err
      return send err
  src = fs.readFileSync(path)
  sourceMaps = []
  remainingLoaderModules = webpackLoaders[..]
  i = remainingLoaderModules.length

  finished = ->
    mkdirp.sync(Path.dirname(outPath))
    # XXX: support CSS/etc source maps
    if sourceMaps.length and outPath.match(/\.js$/)
      sourceMaps.map (sourceMap) ->
        sourceMap.file = Path.basename(outPath)
        absoluteOutPath = Path.resolve(outPath)
        absolutePath = Path.resolve(path)
        sourceMap.sources = [
          Path.relative(Path.dirname(absoluteOutPath), absolutePath)
        ]
        delete sourceMap.sourcesContent
      if sourceMaps.length is 1
        sourceMapString = JSON.stringify sourceMaps[0]
      else
        sourceMapString = JSON.stringify(sourceMaps.shift())
        while nextMap = sourceMaps.shift()
          sourceMapString = ApplySourceMap(sourceMapString, nextMap)

      src =
        """
        #{src.toString('utf8')}
        //# sourceMappingURL=#{Path.basename(mapPath)}
        """
    fs.writeFileSync(outPath, src)
    fs.writeFileSync(mapPath, sourceMapString) if sourceMapString
    send 'complete'

  applyNext = ->
    next = remainingLoaderModules.pop()
    i--
    return finished() unless next
    asyncCallback = false
    context =
      version: 1
      request: next.request
      path: next.path
      resource: baseName
      resourcePath: baseName
      resourceQuery: ""
      query: next.query
      sourceMap: true
      loaderIndex: i
      loaders: webpackLoaders
      async: ->
        asyncCallback = true
      callback: (err, out, map) ->
        asyncCallback = true
        if err
          send err
          return
        if out instanceof Buffer
          src = out
        else
          src = new Buffer(out)
        if map
          sourceMaps.push map
        applyNext()
    try
      if next.module.raw
        input = src
      else
        input = src.toString('utf8')
      out = next.module.call(context, input)
      if !asyncCallback
        if out instanceof Buffer
          src = out
        else
          src = new Buffer(out)
        applyNext()
    catch err
      send err
      return

  applyNext()
