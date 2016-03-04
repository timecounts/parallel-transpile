FIXTURES = "#{__dirname}/../fixtures/"
SCRATCHPAD = "#{__dirname}/scratchpad/"
SCRATCHPAD_SOURCE = "#{SCRATCHPAD}/src"
SCRATCHPAD_OUTPUT = "#{SCRATCHPAD}/build"

fs = require 'fs'
childProcess = require 'child_process'
chai = require 'chai'
expect = chai.expect

parallelTranspile = require '../index'

setupScratchpad = ->
  childProcess.spawnSync 'rm', ['-Rf', SCRATCHPAD]
  fs.mkdirSync SCRATCHPAD
  childProcess.spawnSync 'rsync', ['-a', FIXTURES, SCRATCHPAD]
  fs.mkdirSync SCRATCHPAD_OUTPUT

output = (path, options) ->
  try
    ret = fs.readFileSync("#{SCRATCHPAD_OUTPUT}/#{path}", options)
    if ret.trim
      return ret.trim()
    else
      return ret
  catch e
    return null

scssOptions =
  includePaths: ["#{FIXTURES}/lib/scss"]
  indentedSyntax: false

RULES =
  scss:
    inExt: ".scss"
    loaders: ["sass-loader?#{JSON.stringify(scssOptions)}"]
    outExt: ".css"



makeOptions = (opts) ->
  Object.assign {
    output: "#{SCRATCHPAD_OUTPUT}",
    source: "#{SCRATCHPAD_SOURCE}",
  }, opts


describe 'SCSS', ->

  options = makeOptions
    rules: [
      RULES.scss
    ]

  before setupScratchpad

  describe 'normal', ->
    before (done) ->
      parallelTranspile options, done

    it 'compiles foo.css', ->
      expect(output("scss/foo.css", 'utf-8')).to.eql """
        .foo {
          color: #f00; }
        """

    it 'compiles bar.css', ->
      expect(output("scss/bar.css", 'utf-8')).to.eql """
        .bar {
          color: #0f0; }
        """
