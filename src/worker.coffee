fs = require 'fs'
Path = require 'path'
mkdirp = require 'mkdirp'
ApplySourceMap = require 'apply-source-map'

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

swapExtension = (path, a, b) ->
  if path.substr(path.length - a.length) is a
    return path.substr(0, path.length - a.length) + b
  return path

process.on 'message', (m) ->
  return init(m.init) if m.init
  throw new Error "Not initialised" unless source
  {path, rule: {inExt, loaders, outExt}} = m
  relativePath = path.substr(source.length)
  outPath = "#{output}/#{swapExtension(relativePath, inExt, outExt)}"
  mapPath = "#{output}/#{swapExtension(relativePath, inExt, ".map")}"
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
  src = fs.readFileSync(path, 'utf8')
  sourceMaps = []
  remainingLoaderModules = webpackLoaders[..]
  i = remainingLoaderModules.length

  finished = ->
    mkdirp.sync(Path.dirname(outPath))
    if sourceMaps.length and outPath.match(/\.js$/)
      sourceMaps.map (sourceMap) ->
        sourceMap.file = Path.basename(outPath)
        sourceMap.sources = [Path.basename(relativePath)]
        delete sourceMap.sourcesContent
      if sourceMaps.length is 1
        sourceMapString = JSON.stringify sourceMaps[0]
      else
        sourceMapString = ApplySourceMap(sourceMaps[0], sourceMaps[1])

      src = "#{src}\n//# sourceMappingURL=#{Path.basename(mapPath)}"
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
      callback: (err, js, map) ->
        asyncCallback = true
        if err
          send err
          return
        src = js
        if map
          sourceMaps.push map
        applyNext()
    try
      out = next.module.call(context, src)
      if !asyncCallback
        src = out
        applyNext()
    catch err
      send err
      return

  applyNext()
