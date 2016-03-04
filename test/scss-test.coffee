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

transpile = (_options) -> (done) ->
  options = makeOptions _options
  parallelTranspile options, done

setupTranspiler = (_options) -> (done) ->
  options = makeOptions _options,
    watch: true
    initialBuildComplete: done
  @transpiler = parallelTranspile options, (err) ->
    throw err if err
    console.log "Transpiler exited"

teardownTranspile = ->
  @transpiler?.kill()
  delete @transpiler

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
  includePaths: ["#{SCRATCHPAD}/lib/scss"]
  indentedSyntax: false

RULES =
  scss:
    inExt: ".scss"
    loaders: ["sass-loader?#{JSON.stringify(scssOptions)}"]
    outExt: ".css"



makeOptions = (opts...) ->
  Object.assign {
    output: "#{SCRATCHPAD_OUTPUT}",
    source: "#{SCRATCHPAD_SOURCE}",
  }, opts...


describe 'SCSS', ->

  describe 'normal', ->
    before setupScratchpad

    before transpile
      rules: [
        RULES.scss
      ]


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

  describe 'newer', ->
    before setupScratchpad

    before transpile
      newer: true
      rules: [
        RULES.scss
      ]

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

    it 'then modifies bar.css', ->
      fs.writeFileSync "#{SCRATCHPAD_OUTPUT}/scss/foo.css", "UNMODIFIED"
      fs.writeFileSync "#{SCRATCHPAD_OUTPUT}/scss/bar.css", "UNMODIFIED"
      fs.writeFileSync "#{SCRATCHPAD_SOURCE}/scss/bar.scss",
        """
        @import "vars";
        .bar {
          background-color: $green;
        }
        """

    it 'then compiles again', transpile
      newer: true
      rules: [
        RULES.scss
      ]


    it 'foo.css should be unchanged', ->
      expect(output("scss/foo.css", 'utf-8')).to.eql """
        UNMODIFIED
        """

    it 'compiles bar.css', ->
      expect(output("scss/bar.css", 'utf-8')).to.eql """
        .bar {
          background-color: #0f0; }
        """

    it 'then modifies _vars.css', ->
      fs.writeFileSync "#{SCRATCHPAD_OUTPUT}/scss/foo.css", "UNMODIFIED"
      fs.writeFileSync "#{SCRATCHPAD_OUTPUT}/scss/bar.css", "UNMODIFIED"
      fs.writeFileSync "#{SCRATCHPAD}/lib/scss/_vars.scss",
        """
        $red: red;
        $green: green;
        """

    it 'then compiles again', transpile
      newer: true
      rules: [
        RULES.scss
      ]

    it 'compiles foo.css', ->
      expect(output("scss/foo.css", 'utf-8')).to.eql """
        .foo {
          color: red; }
        """

    it 'compiles bar.css', ->
      expect(output("scss/bar.css", 'utf-8')).to.eql """
        .bar {
          background-color: green; }
        """
