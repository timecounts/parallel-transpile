fs = require 'fs'
cluster = require 'cluster'
utils = require './utils'
debug = require('debug')('parallelTranspile')
Path = require 'path'
Checksum = require 'checksum'
async = require 'async'
VERSION = require("#{__dirname}/package.json").version

STATE_FILENAME = ".parallel-transpile.state"

cluster.setupMaster
  exec: "#{__dirname}/worker"
  args: []

if !cluster.isMaster
  require "#{__dirname}/worker"
  return

EventEmitter = require 'events'
chokidar = require 'chokidar'
os = require 'os'

error = (code, message) ->
  err = new Error message
  err.code = code
  return err

endsWith = (str, end) ->
  str.substr(str.length - end.length) is end

versionFromLoaderString = (l) ->
  loaderName = l.replace /\?.*$/, ""
  return require("#{loaderName}/package.json").version

watcher = null

class Bucket extends EventEmitter
  constructor: (@options = {}) ->
    @capacity = @options.bucketCapacity ? 3
    @queue = []
    @child = cluster.fork()
    @id = @child.id
    @child.send {init: @options}
    @child.on 'message', @receive

  receive: (message) =>
    task = @queue.shift()
    if !task
      # Error during startup?
      return
    @perform()
    if message?.msg is 'complete'
      @emit 'complete', this, null, task, message.details
    else
      # Must be an error
      @emit 'complete', this, message, task

  add: (task) ->
    @queue.push task
    @perform() if @queue.length is 1

  perform: ->
    task = @queue[0]
    return unless task
    @child.send task

  destroy: ->
    @child.kill()


class Queue extends EventEmitter
  constructor: (@options, @oneshot) ->
    @paused = true
    @queue = []
    @inProgress = []
    @delayEmptyCount = 0

  destroy: =>
    return unless @buckets
    process.removeListener 'exit', @destroy
    bucket.destroy() for bucket in @buckets
    @buckets = null

  complete: (bucket, err, task, details = {}) =>
    {path} = task
    next = =>
      i = @inProgress.indexOf(path)
      if i is -1
        throw new Error "This shouldn't be able to happen"
      @inProgress.splice(i, 1)
      @processNext()
      @checkEmpty()
    if err
      @options.onError?(err)
      debug "[#{bucket.id}] Failed: #{path}"
      next()
    else
      deps = Object.keys(details.dependencies)[1..]
      if deps.length
        if watcher
          deps.forEach (p) -> watcher.add(p)
        deps = deps.map (p) => Path.relative(@options.source, p)
        debug "[#{bucket.id}] Processed: #{path} (deps: #{deps})"
      else
        debug "[#{bucket.id}] Processed: #{path}"
      outPath = details.outPath
      delete details.outPath
      details.loaders = task.rule.loaders.map (l) ->
        [l, {version: versionFromLoaderString(l)}]
      initialDeps = (task.rule.dependencies || [])
      getStats = (dep, done) ->
        subDetails = {}
        async.parallel
          getMtime: (done) ->
            fs.stat dep, (err, depStat) ->
              return done err if err
              subDetails.mtime = +depStat.mtime
              done()
          getChecksum: (done) ->
            Checksum.file dep, (err, csum) ->
              return done err if err
              subDetails.checksum = csum
              done()
        , (err) ->
          done err, [dep, subDetails]
      async.map initialDeps, getStats, (err, deps) =>
        if err
          console.error err
          return next()
        details.ruleDependencies = deps || initialDeps.map((dep) -> [dep, {}])
        @options.setFileState outPath, details
        next()
    return

  run: ->
    @buckets = []
    for i in [0...@options.parallel]
      bucket = new Bucket @options
      bucket.on 'complete', @complete
      @buckets.push bucket
    process.on 'exit', @destroy
    delete @paused
    @processNext()
    @checkEmpty()
    return this

  rule: (path) ->
    for rule in @options.rules
      if endsWith(path, rule.inExt)
        return rule
    return null

  add: (path) =>
    if @queue.indexOf(path) is -1 and @rule(path)
      #console.log "Queueing #{path}"
      @queue.push path
      @processNext()

  remove: (path) =>
    i = @queue.indexOf(path)
    if i isnt -1
      @queue.splice(i, 1)

  processNext: ->
    return if @paused
    return unless @buckets # kicked it
    return unless @queue.length
    bestBucket = null
    bestBucketScore = 0
    for bucket in @buckets when (score = bucket.capacity - bucket.queue.length) > 0
      if !bestBucket || score > bestBucketScore
        bestBucket = bucket
    return unless bestBucket
    for path, i in @queue when @inProgress.indexOf(path) is -1
      availablePath = path
      @queue.splice(i, 1)
      break
    return unless availablePath
    @inProgress.push availablePath
    bestBucket.add({path: availablePath, rule: @rule(availablePath)})
    @processNext()

  delayEmpty: ->
    @delayEmptyCount++
    return =>
      @delayEmptyCount--
      @checkEmpty()

  checkEmpty: ->
    if @delayEmptyCount == 0 && @inProgress.length == 0
      @emit 'empty'
      @destroy() if @oneshot
    return

module.exports = (options, callback) ->

  if !fs.existsSync(options.source) or !fs.statSync(options.source).isDirectory()
    return callback error(2, "Input must be a directory")

  if !options.output
    return callback error(1, "No output directory specified")

  if !fs.existsSync(options.output) or !fs.statSync(options.output).isDirectory()
    return callback error(3, "Output option must be a directory")

  options.output = Path.resolve(options.output)
  options.source = Path.resolve(options.source)

  options.rules ?= []
  options.type = [options.type] if options.type and !Array.isArray(options.type)
  for type in options.type ? []
    matches = type.match /^([^:]*)(?::([^:]*)(?::([^:]*))?)?$/
    if !matches
      return callback error(1, "Invalid type specification: '#{type}'")
    [inExt, loaders, outExt] = matches[1..]
    loaders ?= ""
    outExt ?= inExt
    options.rules.push
      inExt: inExt
      loaders: loaders.split(",").filter (a) -> a.length > 0
      outExt: outExt

  if options.parallel?
    options.parallel = parseInt(options.parallel, 10)
    if !isFinite(options.parallel) or options.parallel < 0
      delete options.parallel
      console.error "Did not understand parallel option value, discarding it."

  if options.maxParallel?
    options.maxParallel = parseInt(options.maxParallel, 10)
    if !isFinite(options.maxParallel) or options.maxParallel < 0
      delete options.maxParallel
      console.error "Did not understand maxParallel option value, discarding it."

  options.parallel ||= os.cpus().length
  options.parallel = Math.min(options.parallel, options.maxParallel ? 16)


  if options.watch
    watchQueue = new Queue(options)
    watchChange = (file) ->
      sourceWithSlash = options.source + "/"
      if file.substr(0, sourceWithSlash.length) is sourceWithSlash
        watchQueue.add(file)
      # Look for anything that depends on us and add that to the queue
      for stateFile, {dependencies} of options.state.files
        [self, deps...] = Object.keys(dependencies)
        if file in deps
          watchQueue.add self
    watchRemove = (file) ->
      watchQueue.remove(file)
      if options.delete
        for stateFile, {dependencies} of options.state.files
          [self, deps...] = Object.keys(dependencies)
          if file is self
            options.setFileState(stateFile, null)
            try
              fs.unlinkSync stateFile

    watcher = chokidar.watch options.source
    watcher.on 'ready', ->
      watcher.on 'add', watchChange
      watcher.on 'change', watchChange
      watcher.on 'unlink', watchRemove

  oldOnError = options.onError
  errorOccurred = false
  options.onError = ->
    errorOccurred = true
    oldOnError?.apply(this, arguments)

  state = null
  try
    state = JSON.parse(fs.readFileSync("#{options.output}/#{STATE_FILENAME}"))
    if state.version isnt VERSION
      # Start from scratch on version update
      console.log "STARTING FROM SCRATCH"
      debug("WARNING: version changed from #{state.version} -> #{VERSION}. Starting from scratch")
      state = null
  catch
    debug("WARNING: no statefile! Starting from scratch")
    state = null

  state ?=
    version: VERSION
  options.state = state
  options.state.files ?= {}
  options.setFileState = (filename, obj) ->
    if !obj
      delete options.state.files[filename]
    else
      options.state.files[filename] = obj
    fs.writeFileSync "#{options.output}/#{STATE_FILENAME}",
      JSON.stringify(options.state)

  upToDate = (filename, rule, done) ->
    obj = options.state.files[filename]
    unless obj
      debug("#{filename} not known")
      return done false
    checkDependency = (file, done) ->
      debug("Checking dependency #{file}")
      {mtime, checksum} = obj.dependencies[file]
      stat2 =
        try
          fs.statSync(file)
      unless stat2
        debug("#{file} doesn't exist")
        return done new Error("NOEXIST")
      if +stat2.mtime > mtime
        debug("#{file} mtime has changed (#{mtime} -> #{+stat2.mtime}), checking checksum")
        return Checksum.file file, (err, csum) ->
          if csum is checksum
            return done()
          else
            debug("#{file} checksums differ")
            return done new Error("CHANGED")
      else
        return done()
    async.map Object.keys(obj.dependencies), checkDependency, (err) =>
      if err
        return done false
      loaderConfigs = obj.loaders?.map((c) -> c[0])
      oldLoaders = loaderConfigs?.join("$$")
      newLoaders = rule.loaders.join("$$")
      if oldLoaders != newLoaders
        debug("Loaders for #{filename} have changed (#{oldLoaders} -> #{newLoaders})")
        return done false
      for c in obj.loaders
        [l, {version}] = c
        currentVersion = versionFromLoaderString(l)
        if currentVersion != version
          debug("Loader version for #{l} (#{filename}) has changed (#{version} -> #{currentVersion})")
          return done false
      ruleDependencyConfigs = obj.ruleDependencies?.map((c) -> c[0]) || []
      if (rule.dependencies ? []).join("$$") != ruleDependencyConfigs.join("$$")
        debug("Rule dependencies for #{filename} have changed")
        return done false
      for c in obj.ruleDependencies
        [f, {mtime}] = c
        currentMtime =
          try
            +fs.statSync(f).mtime
        if !currentMtime || currentMtime > mtime
          debug("Dependency #{f} for #{filename} has changed")
          return done false
      return done true

  queue = new Queue(options, true)

  delayQueueEmptyForCallback = (cb) ->
    release = queue.delayEmpty()
    return (args...) ->
      cb(args...)
      release()

  seen = []
  recurse = (path) ->
    files = fs.readdirSync(path)
    for file in files when !file.match(/^\.+$/) then do (file) ->
      filePath = "#{path}/#{file}"
      stat = fs.statSync(filePath)
      if stat.isDirectory()
        recurse(filePath)
      else if stat.isFile()
        addToQueue = => queue.add(filePath)
        if options.newer
          rule = null
          for aRule in options.rules when endsWith(filePath, aRule.inExt)
            rule = aRule
            break
          if rule
            {inExt, outExt} = rule
            relativePath = filePath.substr(options.source.length)
            outPath = Path.resolve "#{options.output}/#{utils.swapExtension(relativePath, inExt, outExt)}"
            seen.push outPath
            upToDate outPath, rule, delayQueueEmptyForCallback (isUpToDate) ->
              if !isUpToDate
                addToQueue()
          else
            addToQueue()
        else
          addToQueue()
    return

  recurse options.source

  getStatus = (clear) ->
    if errorOccurred
      errorOccurred = false if clear
      return new Error "An error occurred"
    else
      null
  queue.on 'empty', ->
    if options.delete
      all = Object.keys(options.state.files)
      unseen = (file for file in all when file not in seen)
      for file in unseen
        debug "Deleting file with no source: #{file}"
        options.setFileState(file, null)
        try
          fs.unlinkSync file
    debug "INITIAL BUILD COMPLETE"
    status = getStatus(false)
    options.initialBuildComplete?(status)
    queue.destroy()
    queue = null
    if watchQueue?
      errorOccurred = false
      watchQueue.on 'empty', ->
        options.watchBuildComplete?(getStatus(true))
      watchQueue.run()
    else
      # Finished
      callback(status)
  queue.run()
  return {
    kill: ->
      queue?.destroy()
      watchQueue?.destroy()
      watcher?.close()
  }
