fs = require 'fs'
cluster = require 'cluster'
utils = require './utils'

cluster.setupMaster
  exec: "#{__dirname}/worker"
  args: []

if !cluster.isMaster
  require './worker'
  return

EventEmitter = require 'events'
chokidar = require 'chokidar'
os = require 'os'
child_process = require 'child_process'

error = (code, message) ->
  err = new Error message
  err.code = code
  return err

endsWith = (str, end) ->
  str.substr(str.length - end.length) is end

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
    @perform()
    if message is 'complete'
      @emit 'complete', this, null, task
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

  destroy: =>
    return unless @buckets
    process.removeListener 'exit', @destroy
    bucket.destroy() for bucket in @buckets
    @buckets = null

  complete: (bucket, err, task) =>
    {path} = task
    if err
      @options.onError?(err)
      console.log "[#{bucket.id}] Failed: #{path}"
    else
      console.log "[#{bucket.id}] Processed: #{path}"
    i = @inProgress.indexOf(path)
    if i is -1
      throw new Error "This shouldn't be able to happen"
    @inProgress.splice(i, 1)
    @processNext()
    if @inProgress.length is 0
      @emit 'empty'
      @destroy() if @oneshot
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
    @emit 'empty' unless @inProgress.length > 0

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

module.exports = (options, callback) ->

  if !fs.existsSync(options.source) or !fs.statSync(options.source).isDirectory()
    return callback error(2, "Input must be a directory")

  if !options.output
    return callback error(1, "No output directory specified")

  if !fs.existsSync(options.output) or !fs.statSync(options.output).isDirectory()
    return callback error(3, "Output option must be a directory")

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
    watcher = chokidar.watch options.source
    watcher.on 'ready', ->
      watcher.on 'add', watchQueue.add
      watcher.on 'change', watchQueue.add
      watcher.on 'unlink', watchQueue.remove

  oldOnError = options.onError
  errorOccurred = false
  options.onError = ->
    errorOccurred = true
    oldOnError?.apply(this, arguments)

  queue = new Queue(options, true)
  recurse = (path) ->
    files = fs.readdirSync(path)
    for file in files when !file.match(/^\.+$/)
      filePath = "#{path}/#{file}"
      stat = fs.statSync(filePath)
      if stat.isDirectory()
        recurse(filePath)
      else if stat.isFile()
        shouldAdd = true
        if options.newer
          rule = null
          for aRule in options.rules when endsWith(filePath, aRule.inExt)
            rule = aRule
            break
          if rule
            {inExt, outExt} = rule
            relativePath = filePath.substr(options.source.length)
            outPath = "#{options.output}/#{utils.swapExtension(relativePath, inExt, outExt)}"
            try
              stat2 = fs.statSync(outPath)
            if stat2 and stat2.mtime > stat.mtime
              shouldAdd = false
        queue.add(filePath) if shouldAdd
    return

  recurse options.source

  queue.on 'empty', ->
    console.log "INITIAL BUILD COMPLETE"
    status = null
    if errorOccurred
      status = new Error "An error occurred"
    options.initialBuildComplete?(status)
    if watchQueue?
      watchQueue.run()
    else
      # Finished
      queue.destroy()
      callback(status)
  queue.run()
