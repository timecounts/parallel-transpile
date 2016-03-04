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
} = require './test_helper'
fs = require 'fs'

RULES =
  jsx:
    inExt: ".jsx"
    loaders: ['babel-loader']
    outExt: ".js"
    dependencies: [
      "#{SCRATCHPAD}/.babelrc"
    ]

describe 'JSX', ->

  describe 'newer', ->
    before setupScratchpad

    before transpile
      newer: true
      rules: [
        RULES.jsx
      ]

    it 'compiles foo.js', ->
      expect(getOutput("jsx/foo.js", 'utf-8')).to.match /key: 'render',/
      expect(getOutput("jsx/foo.js", 'utf-8')).to.match /'Hello world!'/

    it 'compiles bar.js', ->
      expect(getOutput("jsx/bar.js", 'utf-8')).to.match /key: 'render',/
      expect(getOutput("jsx/bar.js", 'utf-8')).to.match /'Howdy, partner!'/

    it 'then modifies bar.js', ->
      fs.writeFileSync "#{SCRATCHPAD_OUTPUT}/jsx/foo.js", "UNMODIFIED"
      fs.writeFileSync "#{SCRATCHPAD_OUTPUT}/jsx/bar.js", "UNMODIFIED"
      fs.writeFileSync "#{SCRATCHPAD_SOURCE}/jsx/bar.jsx",
        """
        const bar = null;
        export default bar;
        """

    it 'then compiles again', transpile
      newer: true
      rules: [
        RULES.jsx
      ]


    it 'foo.js should be unchanged', ->
      expect(getOutput("jsx/foo.js", 'utf-8')).to.eql """
        UNMODIFIED
        """

    it 'compiles bar.js', ->
      expect(getOutput("jsx/bar.js", 'utf-8')).to.match /bar = null/
      expect(getOutput("jsx/bar.js", 'utf-8')).to.match /exports.default/

    it 'then modifies babelrc', ->
      fs.writeFileSync "#{SCRATCHPAD_OUTPUT}/jsx/foo.js", "UNMODIFIED"
      fs.writeFileSync "#{SCRATCHPAD_OUTPUT}/jsx/bar.js", "UNMODIFIED"
      fs.writeFileSync "#{SCRATCHPAD}/.babelrc",
        """
        {
          "presets": ["es2015-native-modules", "react"]
        }
        """

    it 'then compiles again', transpile
      newer: true
      rules: [
        RULES.jsx
      ]

    it 'compiles foo.js', ->
      expect(getOutput("jsx/foo.js", 'utf-8')).to.match /key: 'render',/
      expect(getOutput("jsx/foo.js", 'utf-8')).to.match /'Hello world!'/

    it 'compiles bar.js', ->
      expect(getOutput("jsx/bar.js", 'utf-8')).to.match /bar = null/
      expect(getOutput("jsx/bar.js", 'utf-8')).to.match /export default/
