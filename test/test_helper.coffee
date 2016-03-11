FIXTURES = "#{__dirname}/../fixtures"
SCRATCHPAD = "#{__dirname}/scratchpad"
SCRATCHPAD_SOURCE = "#{SCRATCHPAD}/src"
SCRATCHPAD_OUTPUT = "#{SCRATCHPAD}/build"
STATE_FILENAME = ".parallel-transpile.state"

fs = require 'fs'
childProcess = require 'child_process'
chai = require 'chai'
expect = chai.expect

parallelTranspile = require '../index'

spawnSync = (cmd, args) ->
  p = childProcess.spawnSync cmd, args
  if p.error
    throw new Error "#{cmd} spawn failed: #{p.error}"
  if p.status > 0
    throw new Error "#{cmd} exited with status #{p.status}"
  return

setupScratchpad = ->
  spawnSync 'rm', ['-Rf', SCRATCHPAD]
  spawnSync 'cp', ['-a', FIXTURES, SCRATCHPAD]
  fs.mkdirSync SCRATCHPAD_OUTPUT

transpile = (_options) -> (done) ->
  options = makeOptions _options
  parallelTranspile options, done

setupTranspiler = (_options) -> (done) ->
  options = makeOptions _options,
    watch: true
    initialBuildComplete: done
    watchBuildComplete: =>
      @transpiler.buildNumber++
  @transpiler = parallelTranspile options, (err) ->
    throw err if err
    console.log "Transpiler exited"
  @transpiler.buildNumber = 0

teardownTranspiler = (done) ->
  @transpiler?.kill()
  delete @transpiler
  setTimeout done, 250 # Ugly hack to give children sufficient time to kill their workers

transpileWait = (fn) -> (done) ->
  counter = @transpiler.buildNumber
  fn()
  check = =>
    if !@transpiler || @transpiler.buildNumber > counter
      done() if @transpiler # On fail, @transpiler will be cleaned up, but we still need to clearInterval
      clearInterval(interval)
  interval = setInterval check, 20
  check()

getOutput = (path, options) ->
  try
    ret = fs.readFileSync("#{SCRATCHPAD_OUTPUT}/#{path}", options)
    if ret.trim
      return ret.trim()
    else
      return ret
  catch e
    return null

getState = ->
  jsonString = getOutput(STATE_FILENAME, 'utf-8')
  try
    return JSON.parse(jsonString)
  catch e
    return null

makeOptions = (opts...) ->
  Object.assign {
    output: "#{SCRATCHPAD_OUTPUT}",
    source: "#{SCRATCHPAD_SOURCE}",
  }, opts...

module.exports = {
  SCRATCHPAD
  SCRATCHPAD_SOURCE
  SCRATCHPAD_OUTPUT
  expect
  parallelTranspile
  setupScratchpad
  transpile
  setupTranspiler
  teardownTranspiler
  transpileWait
  getOutput
  getState
}
