fs = require 'fs'
Path = require 'path'
mkdirp = require 'mkdirp'

loaders = {}
source = null
output = null

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
  loaderModules = []
  webpackLoaders = []
  for loader in loaders
    try
      # TODO: support loader arguments
      loaderModule = require(loader)
      loaderModules.push loaderModule
      webpackLoaders.push
        request: ""
        path: path
        query: ""
        module: loaderModule
    catch e
      return process.send e
  src = fs.readFileSync(path, 'utf8')
  sourceMap = null
  remainingLoaderModules = loaderModules[..]
  i = remainingLoaderModules.length

  finished = ->
    mkdirp.sync(Path.dirname(outPath))
    fs.writeFileSync(outPath, src)
    fs.writeFileSync(mapPath, sourceMap) if sourceMap
    process.send 'complete'

  applyNext = ->
    next = remainingLoaderModules.pop()
    i--
    return finished() unless next
    asyncCallback = false
    context =
      version: 1
      request: ""
      query: ""
      sourceMap: sourceMap
      loaderIndex: i
      loaders: webpackLoaders
      async: ->
        asyncCallback = true
      callback: (err, js, map) ->
        asyncCallback = true
        if err
          process.send err
          return
        src = js
        sourceMap = map
        applyNext()
    out = next.call(context, src)
    if !asyncCallback
      src = out
      applyNext()

  applyNext()
