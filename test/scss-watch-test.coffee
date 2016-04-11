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

describe 'SCSS watch', ->
  before setupScratchpad

  after teardownTranspiler
  before setupTranspiler
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

  it 'then modifies bar.css and waits for transpile', transpileWait ->
    @fooMtime = getFileStats("scss/foo.css").mtime
    @barMtime = getFileStats("scss/bar.css").mtime
    fs.writeFileSync "#{SCRATCHPAD_SOURCE}/scss/bar.scss",
      """
      @import "vars";
      .bar {
        background-color: $green;
      }
      """

  it 'foo.css should be unchanged', ->
    expect(getFileStats("scss/foo.css").mtime).to.eql @fooMtime

  it 'compiles bar.css', ->
    expect(getOutput("scss/bar.css", 'utf-8')).to.eql """
      .bar {
        background-color: #0f0; }
      """

  it 'waits a second', (done) -> setTimeout done, 1000

  it 'then touches bar.css and waits for transpile', transpileWait ->
    @fooMtime = getFileStats("scss/foo.css").mtime
    @barMtime = getFileStats("scss/bar.css").mtime
    fs.writeFileSync "#{SCRATCHPAD_SOURCE}/scss/bar.scss",
      """
      @import "vars";
      .bar {
        background-color: $green;
      }
      """
  , 3000

  it 'foo.css should be unchanged', ->
    expect(getFileStats("scss/foo.css").mtime).to.eql @fooMtime

  it 'bar.css should be unchanged', ->
    expect(getFileStats("scss/bar.css").mtime).to.eql @barMtime

  it 'then modifies _vars.css and waits for transpile', transpileWait ->
    @fooMtime = getFileStats("scss/foo.css").mtime
    @barMtime = getFileStats("scss/bar.css").mtime
    fs.writeFileSync "#{SCRATCHPAD}/lib/scss/_vars.scss",
      """
      $red: red;
      $green: green;
      """

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

  it 'then deletes bar.scss and waits for transpile', transpileWait ->
    @fooMtime = getFileStats("scss/foo.css").mtime
    fs.unlinkSync "#{SCRATCHPAD_SOURCE}/scss/bar.scss"

  it 'foo.css should be unchanged', ->
    expect(getFileStats("scss/foo.css").mtime).to.eql @fooMtime

  it 'bar.css should be deleted', ->
    expect(getFileStats("scss/bar.css")).to.eql null
