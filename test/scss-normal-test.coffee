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

describe 'SCSS normal', ->

  before setupScratchpad

  before transpile
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
