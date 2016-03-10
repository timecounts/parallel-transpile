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

describe 'SCSS', ->

  describe 'normal', ->
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

  describe 'newer', ->
    before setupScratchpad

    before transpile
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
      fs.writeFileSync "#{SCRATCHPAD_OUTPUT}/scss/foo.css", "UNMODIFIED"
      fs.writeFileSync "#{SCRATCHPAD_OUTPUT}/scss/bar.css", "UNMODIFIED"
      fs.writeFileSync "#{SCRATCHPAD_SOURCE}/scss/bar.scss",
        """
        @import "vars";
        .bar {
          background-color: $green;
        }
        """

    it 'then we compile again', transpile
      newer: true
      rules: [
        RULES.scss
      ]


    it 'foo.css should be unchanged', ->
      expect(getOutput("scss/foo.css", 'utf-8')).to.eql """
        UNMODIFIED
        """

    it 'compiles bar.css', ->
      expect(getOutput("scss/bar.css", 'utf-8')).to.eql """
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

    it 'then we compile again', transpile
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

    it 'then we delete foo.scss', ->
      fs.unlinkSync "#{SCRATCHPAD_SOURCE}/scss/foo.scss"
      fs.writeFileSync "#{SCRATCHPAD_OUTPUT}/scss/bar.css", "UNMODIFIED"

    it 'then we compile again', transpile
      newer: true
      delete: true
      rules: [
        RULES.scss
      ]

    it 'deletes foo.css', ->
      expect(getOutput("scss/foo.css", 'utf-8')).to.eql null

    it 'doesn\'t remember foo.css', ->
      expect(getState().files).not.to.contain.all.keys("#{SCRATCHPAD_OUTPUT}/scss/foo.css")

    it 'leaves bar.css unmodified', ->
      expect(getOutput("scss/bar.css", 'utf-8')).to.eql "UNMODIFIED"

    it 'still remembers bar.css', ->
      expect(getState().files).to.contain.all.keys("#{SCRATCHPAD_OUTPUT}/scss/bar.css")


  describe 'watch', ->
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
      fs.writeFileSync "#{SCRATCHPAD_OUTPUT}/scss/foo.css", "UNMODIFIED"
      fs.writeFileSync "#{SCRATCHPAD_OUTPUT}/scss/bar.css", "UNMODIFIED"
      fs.writeFileSync "#{SCRATCHPAD_SOURCE}/scss/bar.scss",
        """
        @import "vars";
        .bar {
          background-color: $green;
        }
        """

    it 'foo.css should be unchanged', ->
      expect(getOutput("scss/foo.css", 'utf-8')).to.eql """
        UNMODIFIED
        """

    it 'compiles bar.css', ->
      expect(getOutput("scss/bar.css", 'utf-8')).to.eql """
        .bar {
          background-color: #0f0; }
        """

    it 'then modifies _vars.css and waits for transpile', transpileWait ->
      fs.writeFileSync "#{SCRATCHPAD_OUTPUT}/scss/foo.css", "UNMODIFIED"
      fs.writeFileSync "#{SCRATCHPAD_OUTPUT}/scss/bar.css", "UNMODIFIED"
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
