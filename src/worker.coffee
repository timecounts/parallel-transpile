fs = require 'fs'
Path = require 'path'
mkdirp = require 'mkdirp'
Checksum = require 'checksum'
utils = require './utils'
{SourceMapGenerator, SourceMapConsumer} = require 'source-map'

EnhancedResolve = require 'enhanced-resolve'

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
  try
    process.chdir(source)
  catch e
    console.error "ERROR: could not change into source folder '#{source}'"
    throw e

process.on 'message', (m) ->
  try
    return init(m.init) if m.init
    throw new Error "Not initialised" unless source
    {path, rule: {inExt, loaders, outExt}} = m
    fullPath = Path.resolve(path)
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
        if sourceMaps.length is 1
          sourceMapString = JSON.stringify sourceMaps[0]
        else
          last = sourceMaps.pop()
          compoundMap = SourceMapGenerator.fromSourceMap(new SourceMapConsumer(JSON.stringify(last)))
          while nextMap = sourceMaps.pop()
            compoundMap.applySourceMap(new SourceMapConsumer(JSON.stringify(nextMap)))
          sourceMapString = compoundMap.toString()

        src =
          """
          #{src.toString('utf8')}
          //# sourceMappingURL=#{Path.basename(mapPath)}
          """
      fs.writeFileSync(outPath, src)
      fs.writeFileSync(mapPath, sourceMapString) if sourceMapString
      send {msg: 'complete', details: details}

    absoluteOutPath = Path.resolve(outPath)
    absolutePath = Path.resolve(path)
    stat = fs.statSync absolutePath
    inFile = Path.relative(Path.dirname(absoluteOutPath), absolutePath)
    outFile = Path.basename(outPath)
    prevFile = inFile

    details =
      outPath: absoluteOutPath
      #mtime: +new Date
      dependencies: {
        "#{absolutePath}": {
          mtime: +stat.mtime
          checksum: Checksum(fs.readFileSync(absolutePath))
        }
      }


    applyNext = ->
      next = remainingLoaderModules.pop()
      i--
      return finished() unless next
      asyncCallback = false
      cacheable = false
      context =
        options: {} #TODO: https://github.com/webpack/webpack/blob/eba472773387376ed027146aa0f0c524ffb4c314/lib/WebpackOptionsDefaulter.js
        cacheable: (_cacheable = true) -> cacheable = _cacheable
        version: 1
        request: next.request
        context: Path.dirname(fullPath)
        path: next.path
        resource: baseName
        resourcePath: baseName
        resourceQuery: ""
        query: next.query
        sourceMap: true
        loaderIndex: i
        loaders: webpackLoaders
        addDependency: addDependency = (file) ->
          try
            fileStat = fs.statSync Path.resolve(file)
            details.dependencies[Path.resolve(file)] =
              mtime: +fileStat.mtime
          catch e
            console.error "FAILED TO STAT DEPENDENCY '#{file}' of '#{inFile}'"
            details.dependencies[Path.resolve(file)] =
              mtime: 0
        dependency: addDependency
        resolveSync: EnhancedResolve.sync
        resolve: EnhancedResolve
        async: ->
          asyncCallback = true
          context.callback
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
            map.sources = [prevFile]
            if i > 0
              map.file = "#{outFile}-#{i}"
            else
              map.file = outFile
            prevFile = map.file
            delete map.sourcesContent
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
  catch err
    send err
