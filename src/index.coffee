fs = require 'fs'
cluster = require 'cluster'

cluster.setupMaster
  exec: "#{__dirname}/worker"
  args: []

if !cluster.isMaster
  require './worker'
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

class Bucket extends EventEmitter
  constructor: (@options = {}) ->
    @capacity = @options.bucketCapacity ? 3
    @queue = []
    @child = cluster.fork()
    @id = @child.id
    @child.on 'message', @receive

  receive: (message) =>
    if message is 'complete'
      task = @queue.shift()
      @perform()
      @emit 'complete', this, task

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
    @buckets = []
    for i in [0..os.cpus().length]
      bucket = new Bucket
      bucket.on 'complete', @complete
      @buckets.push bucket
    process.on 'exit', @destroy

  destroy: =>
    process.removeListener 'exit', @destroy
    bucket.destroy() for bucket in @buckets

  complete: (bucket, task) =>
    {path} = task
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
    delete @paused
    @processNext()

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
      console.log "Unqueueing #{path}"
      @queue.splice(i, 1)

  processNext: ->
    return if @paused
    return unless @queue.length
    for bucket in @buckets when bucket.capacity > bucket.queue.length
      availableBucket = bucket
      break
    return unless availableBucket
    for path, i in @queue when @inProgress.indexOf(path) is -1
      availablePath = path
      @queue.splice(i, 1)
      break
    return unless availablePath
    @inProgress.push availablePath
    availableBucket.add({path: availablePath, rule: @rule(availablePath)})
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

  console.dir options.rules


  if options.watch
    watchQueue = new Queue(options)
    watcher = chokidar.watch options.source
    watcher.on 'add', watchQueue.add
    watcher.on 'change', watchQueue.add
    watcher.on 'unlink', watchQueue.remove

  queue = new Queue(options, true)
  recurse = (path) ->
    files = fs.readdirSync(path)
    for file in files when !file.match(/^\.+$/)
      filePath = "#{path}/#{file}"
      stat = fs.statSync(filePath)
      if stat.isDirectory()
        recurse(filePath)
      else if stat.isFile()
        queue.add(filePath)
    return

  recurse options.source

  queue.run()
  queue.on 'empty', ->
    console.log "INITIAL BUILD COMPLETE"
    options.initialBuildComplete?()
    watchQueue?.run()
