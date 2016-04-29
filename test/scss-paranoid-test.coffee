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

describe 'SCSS paranoid', ->

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

  it 'then we modify *compiled* file bar.css', ->
    @fooMtime = getFileStats("scss/foo.css").mtime
    @barMtime = getFileStats("scss/bar.css").mtime
    fs.writeFileSync "#{SCRATCHPAD_OUTPUT}/scss/bar.css", """
      .bar{}
      """

  it 'then we compile again', transpile
    delete: true
    newer: true
    rules: [
      RULES.scss
    ]


  it 'foo.css should be unchanged', ->
    expect(getFileStats("scss/foo.css").mtime).to.eql @fooMtime

  it 'bar.css should be unchanged', ->
    expect(getOutput("scss/bar.css", 'utf-8')).to.eql """
      .bar{}
      """

  it 'then we compile again, paranoid', transpile
    delete: true
    newer: true
    paranoid: true
    rules: [
      RULES.scss
    ]

  it 'foo.css should be unchanged', ->
    expect(getFileStats("scss/foo.css").mtime).to.eql @fooMtime

  it 'compiles bar.css', ->
    expect(getOutput("scss/bar.css", 'utf-8')).to.eql """
      .bar {
        color: #0f0; }
      """
