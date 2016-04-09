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
  getFileStats
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
      @fooMtime = getFileStats("jsx/foo.js").mtime
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
      expect(getFileStats("jsx/foo.js").mtime).to.eql @fooMtime

    it 'compiles bar.js', ->
      expect(getOutput("jsx/bar.js", 'utf-8')).to.match /bar = null/
      expect(getOutput("jsx/bar.js", 'utf-8')).to.match /exports.default/

    it 'then modifies babelrc', ->
      @fooMtime = getFileStats("jsx/foo.js").mtime
      @barMtime = getFileStats("jsx/bar.js").mtime
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
      expect(getFileStats("jsx/foo.js").mtime).to.not.eql @fooMtime
      expect(getOutput("jsx/foo.js", 'utf-8')).to.match /key: 'render',/
      expect(getOutput("jsx/foo.js", 'utf-8')).to.match /'Hello world!'/

    it 'compiles bar.js', ->
      expect(getFileStats("jsx/bar.js").mtime).to.not.eql @barMtime
      expect(getOutput("jsx/bar.js", 'utf-8')).to.match /bar = null/
      expect(getOutput("jsx/bar.js", 'utf-8')).to.match /export default/
