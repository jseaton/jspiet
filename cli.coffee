_ = require 'underscore'
fs = require 'fs'
argv = require('optimist').argv
prompt = require 'prompt'
colorize = require 'colorize'
cconsole = colorize.console

debug = if argv.debug then (n...) -> cconsole.log(n...) else -> null
prompt.out = (n) -> process.stdout.write n

piet = require('./jspiet')({debug:debug,io:prompt})

data = piet.create fs.readFileSync(argv._[0]).toString()

piet.eval data

