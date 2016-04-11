{
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
  getFileStats
} = require './test_helper'
fs = require 'fs'

scssOptions =
  includePaths: ["#{SCRATCHPAD}/lib/scss"]
  indentedSyntax: false

RULES =
  scss:
    inExt: ".scss"
    loaders: ["sass-loader?#{JSON.stringify(scssOptions)}"]
    outExt: ".css"

describe 'SCSS newer', ->

  before setupScratchpad

  before transpile
    delete: true
    newer: true
    rules: [
      RULES.scss
    ]

  it 'compiles foo.css', ->
    expect(getOutput("scss/foo.css", 'utf-8')).to.eql """
      .foo {
        color: #f00; }
      """

  it 'compiles bar.css', ->
    expect(getOutput("scss/bar.css", 'utf-8')).to.eql """
      .bar {
        color: #0f0; }
      """

  it 'then modifies bar.css', ->
    @fooMtime = getFileStats("scss/foo.css").mtime
    @barMtime = getFileStats("scss/bar.css").mtime
    fs.writeFileSync "#{SCRATCHPAD_SOURCE}/scss/bar.scss",
      """
      @import "vars";
      .bar {
        background-color: $green;
      }
      """

  it 'then we compile again', transpile
    delete: true
    newer: true
    rules: [
      RULES.scss
    ]


  it 'foo.css should be unchanged', ->
    expect(getFileStats("scss/foo.css").mtime).to.eql @fooMtime

  it 'compiles bar.css', ->
    expect(getOutput("scss/bar.css", 'utf-8')).to.eql """
      .bar {
        background-color: #0f0; }
      """

  it 'then modifies _vars.css', ->
    @fooMtime = getFileStats("scss/foo.css").mtime
    @barMtime = getFileStats("scss/bar.css").mtime
    fs.writeFileSync "#{SCRATCHPAD}/lib/scss/_vars.scss",
      """
      $red: red;
      $green: green;
      """

  it 'then we compile again', transpile
    delete: true
    newer: true
    rules: [
      RULES.scss
    ]

  it 'compiles foo.css', ->
    expect(getOutput("scss/foo.css", 'utf-8')).to.eql """
      .foo {
        color: red; }
      """

  it 'compiles bar.css', ->
    expect(getOutput("scss/bar.css", 'utf-8')).to.eql """
      .bar {
        background-color: green; }
      """

  it 'then we delete bar.scss', ->
    fs.unlinkSync "#{SCRATCHPAD_SOURCE}/scss/bar.scss"
    @fooMtime = getFileStats("scss/foo.css").mtime

  it 'then we compile again', transpile
    delete: true
    newer: true
    rules: [
      RULES.scss
    ]

  it 'deletes bar.css', ->
    expect(getOutput("scss/bar.css", 'utf-8')).to.eql null

  it 'doesn\'t remember bar.css', ->
    expect(getState().files).not.to.contain.all.keys("#{SCRATCHPAD_OUTPUT}/scss/bar.css")

  it 'leaves foo.css unmodified', ->
    expect(getFileStats("scss/foo.css").mtime).to.eql @fooMtime

  it 'still remembers foo.css', ->
    expect(getState().files).to.contain.all.keys("#{SCRATCHPAD_OUTPUT}/scss/foo.css")

  it 'then restores bar.css', ->
    @fooMtime = getFileStats("scss/foo.css").mtime
    fs.writeFileSync "#{SCRATCHPAD_SOURCE}/scss/bar.scss",
      """
      @import "vars";
      .bar {
        background-color: $green;
      }
      """

  it 'then we compile again', transpile
    delete: true
    newer: true
    rules: [
      RULES.scss
    ]

  it 'compiles bar.css', ->
    expect(getOutput("scss/bar.css", 'utf-8')).to.eql """
      .bar {
        background-color: green; }
      """

  it 'leaves foo.css unmodified', ->
    expect(getFileStats("scss/foo.css").mtime).to.eql @fooMtime


  it 'version upgrade', ->
    @fooMtime = getFileStats("scss/foo.css").mtime
    @barMtime = getFileStats("scss/bar.css").mtime
    stateFile = "#{SCRATCHPAD}/build/.parallel-transpile.state"
    state = fs.readFileSync(stateFile, 'utf-8')
    j = JSON.parse(state)
    j.version = '0.0.1'
    fs.writeFileSync(stateFile, JSON.stringify(j))

  it 'transpiles', transpile
    delete: true
    newer: true
    rules: [
      RULES.scss
    ]

  it 'compiles foo.css', ->
    expect(getFileStats("scss/foo.css").mtime).to.not.eql @fooMtime
    expect(getOutput("scss/foo.css", 'utf-8')).to.eql """
      .foo {
        color: red; }
      """

  it 'compiles bar.css', ->
    expect(getFileStats("scss/bar.css").mtime).to.not.eql @barMtime
    expect(getOutput("scss/bar.css", 'utf-8')).to.eql """
      .bar {
        background-color: green; }
      """

