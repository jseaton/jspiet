# Copyright 2013 Joe Seaton
#
# This file is part of jspiet.
#
# jspiet is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
#
# jspiet is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with jspiet. If not, see http://www.gnu.org/licenses/.

io    = null
debug = null
_ = null unless 'undefined' == typeof module

util = require 'util'

unless 'undefined' == typeof module
  _ = require 'underscore'
  module.exports = exports = (opt) ->
    io    = opt.io
    debug = opt.debug
    {create:create, eval:piet_eval}

Number.prototype.mod = (n) -> ((this%n)+n)%n
String.prototype.format = (args) ->
  this.replace(/{(\d+)}/g, (match, number) ->
    if typeof args[number] isnt 'undefined' then "(#{args[number]})" else match
  ).replace /{(.)}/g, (match, sym) ->
    args.join sym

class Codel
  constructor: (hue, light, bw) ->
    @hue   = hue
    @light = light
    @black = bw == 'black'
    @white = bw == 'white'

  isEqual: (other) -> @hue == other.hue and @light == other.light and @black == other.black and @white == other.white

  colour: (a) ->
    if @black
      "#black[#{a}]"
    else if @white
      "#white[#{a}]"
    else
      c = "##{["red[","yellow[","green[","cyan[","blue[","magenta["][@hue]}#{a}]"
      ["#italic[#{c}]",c,"#underline[#{c}]"][@light]

class SectSlice
  constructor: (data,ref,n) ->
    @data = data
    @ref  = ref
    @index = if n == undefined then @ref.list.length - 1 else 0

  list: -> @ref.list[@index..-1].concat (@next and @next.list() or [])
  terminal: -> @ref.terminal
  slow_js: (data, stack, curr, dp, cc) ->
    @slow_js = eval compilejs(@list())
    @slow_js data, stack, curr, dp, cc

  js: (data, stack, curr, dp, cc) ->
    source = compilejs2(@list())
    debug "list", @list()
    #debug "sourco", compilejs(@list())
    debug "source", source
    @js = eval source
    @js data, stack, curr, dp, cc

class Block
  constructor: (data, codels) ->
    @data   = data
    @codels = codels
    @exits  = []
    @any    = @codels[0]

  exit: (dp,cc) ->
    i = dp*4 + cc
    if not @exits[i]
      [next, app] = findexit @data, this, dp, cc
      
      slice =  compile @data, next, @any, dp, cc
      @exits[i] = new SectSlice @data, {list:app, terminal:slice.terminal()}
      @exits[i].next = slice
      debug "list", @exits[i].list()
    
    @exits[i]

parse = (n) -> new Codel {
  '0 0 0':[0,0,'black'], '255 255 255':[0,0,'white'],
  '255 192 192':[0,0], '255 0 0'  :[0,1], '192 0 0'  :[0,2],
  '255 255 192':[1,0], '255 255 0':[1,1], '192 192 0':[1,2],
  '192 255 192':[2,0], '0 255 0'  :[2,1], '0 192 0'  :[2,2],
  '192 255 255':[3,0], '0 255 255':[3,1], '0 192 192':[3,2],
  '192 192 255':[4,0], '0 0 255'  :[4,1], '0 0 192'  :[4,2],
  '255 192 255':[5,0], '255 0 255':[5,1], '192 0 192':[5,2]
  }[n.replace(/\s+/g,' ')]...

parse_ppm = (file) ->
  [width, height] = file.match(/^(\d+) (\d+)$/m).slice(1,3)
  list = file.replace(/^P3\n/,'').replace(/^#.*\n/m,'').replace(/^\d+ \d+\n/m,'').replace(/^\d+/,'').match(/\d+\s+\d+\s+\d+/g).map(parse)
  data = []
  for i in [0 ... height]
    data.push list.splice(0, width)
  for row, y in data
    for el, x in row
      el.pos = [x, y]
  return {grid:data,width:width,height:height}

fill = (data) ->
  c = 0
  equiv = []
  members = [[]]
  for x in [0 ... data.width]
    for y in [0 ... data.height]
      i = data.grid[y][x]
      w = data.grid[y][x-1]
      n = (data.grid[y-1] or [])[x]
      if w and n and i.isEqual(n) and w.isEqual(n) and w.label != n.label
        pair = [w.label, n.label].sort()
        i.label = pair[0]
        equiv.push pair
      else if w and i.isEqual(w)
        i.label = w.label
      else if n and i.isEqual(n)
        i.label = n.label
      else
        c += 1
        i.label = c
        members.push []
      members[i.label].push i
  
  for e in equiv
    members[e[0]].push members[e[1]].splice(0)...

  for m,i in members
    for e in m
      e.label = i
      e.count = m.length
  
  members

inst = (a, b) ->
  [
    'nop', 'psh', 'pop',
    'add', 'sub', 'mul',
    'div', 'mod', 'not',
    'gth', 'ptr', 'swt',
    'dup', 'rll', 'inn',
    'inc', 'otn', 'otc'
  ][(b.hue-a.hue).mod(6)*3 + (b.light-a.light).mod(3)]

jsinst = (inst) ->
  {
    nop : '/*nop*/',
    psh : "stack.unshift(#{inst[1]})",
    pop : 'stack.shift()',
    add : 'stack.unshift(stack.shift()+stack.shift())',
    sub : 'stack.unshift(-stack.shift()+stack.shift())',
    mul : 'stack.unshift(stack.shift()*stack.shift())',
    div : 't=stack.shift();stack.unshift(stack.shift()/t|0)',
    mod : 't=stack.shift();stack.unshift(stack.shift().mod(t))',
    not : 'stack.unshift(stack.shift() ? 0 : 1)',
    gth : 'stack.unshift(stack.shift() < stack.shift() ? 1 : 0)',
    ptr : 'dp = (dp + stack.shift()) % 4',
    ptri: "dp = (dp + #{inst[1]}) % 4",
    swt : 'cc = stack.shift() % 2 == 0 ? cc : -cc',
    swti: 'cc = -cc',
    dup : 'stack.unshift(stack[0])',
    rll : 't=stack.shift();d=stack.shift();\n\t
if (t>=0) { for(var i=0;i<t;i++) { stack.splice(d-1,0,stack.shift()); }\n\t
} else { for (var i=0;i>t;i--) { stack.unshift(stack.splice(d-1,1)[0]); } }',
    inn : 'io.get(["input"], function (err, result) {\n\t\t
if (err) { return 1; }\n\t\t
stack.unshift(parseInt(result.input));\n\t\t
peval(data,stack,curr.terminal().exit(dp,cc),dp,cc);\n\t\t
});\n\t
return',
    inc : 'io.get(["input"], function (err, result) {\n\t\t
if (err) { return 1; }\n\t\t
stack.unshift(result.input.charCodeAt(0));\n\t\t
peval(data,stack,curr.terminal().exit(dp,cc),dp,cc);\n\t
});\n\t
return',
    otn : 'io.out(stack.shift().toString())',
    otc : 'io.out(String.fromCharCode(stack.shift()))'
  }[inst[0]]

compilejs = (list) -> "(function(data,stack,curr,dp,cc) {\n" + list.map((i) -> "\tdebug('#{i}',stack,dp,cc);\n\t" + jsinst(i)).join(";\n") + ";\n\n\treturn [dp,cc];\n})"

class Node
  constructor: (inst,children) ->
    @inst = inst
    @chld = children or []
    @taint = {
      gen:true,
      inn:true,inc:true,
      otn:true,otc:true
    }[@inst[0]] or children.filter(
      (e) -> e.taint
    ).length != 0

  format: (seen, dups) ->
    debug "format", this
    {
      psh : "#{@inst[1]}",
      add : '{0}+{1}',     sub : '{0}-{1}',      mul : '{0}*{1}',
      div : '{0}/{1}|0',   mod : '{0}.mod({1})', not : '{0} ? 0 : 1',
      gth : '({0} > {1}) ? 1 : 0',
      ptr : '{0}',         ptri: "#{@inst[1]}",
      swt : '{0}',         swti: '1',
      dup : '{0}',
      otn : 'io.out({0}.toString())',
      otc : 'io.out(String.fromCharCode({0}))'
      inn : 'io.get(["input"], function (err, result) {\n\t\t
if (err) { return 1; }\n\t\t
stack.unshift(parseInt(result.input));\n\t\t
peval(data,stack,curr.terminal().exit(dp,cc),dp,cc);\n\t
});\n\treturn;\n\t',
      inc : 'io.get(["input"], function (err, result) {\n\t\t
if (err) { return 1; }\n\t\t
stack.unshift(result.input.charCodeAt(0));\n\t\t
peval(data,stack,curr.terminal().exit(dp,cc),dp,cc);\n\t
});\n\treturn;\n\t',
      gen : @inst[1],
      join: '{+}'
    }[@inst[0]].format(@chld.map((e) -> flatten(e, seen, dups)))

flatten = (inst, seen, dups) ->
  debug "flatten", inst
  if inst.dup
    if not inst.taint
      if dups[inst.dup] != undefined
        dups[inst.dup]
      else
        flatten inst.chld[0], seen, dups
    else if seen[inst.dup]
      "dups[#{inst.dup}]"
    else
      seen[inst.dup] = true
      "dups[#{inst.dup}] = #{inst.format(seen, dups)}"
  else if not inst.taint
    result = inst.format(seen, dups)
    debug "result", result
    eval result
  else
    inst.format seen, dups

compilejs2 = (list) ->
  #return compilejs(list) if list.filter((e) -> {rll:true}[e[0]] ).length != 0
  stack = []
  ccs = []
  dps = []
  output = []
  terms = null
  dupn = 0
  dups = []
  pops = 0
  seen = []
  noout = {otn:true,otc:true,ptri:true,swti:true,ptr:true,ptri:true,inn:true,inc:true}
  for i in list
    debug "i", i, stack
    pre = {
      psh : 0, pop : 1,
      add : 2, sub : 2, mul : 2,
      div : 2, mod : 2, not : 1,
      gth : 2, ptr : 1, swt : 1,
      ptri: 0, swti: 0, rll : 2,
      inn : 0, inc : 0,
      dup : 1, otn : 1, otc : 1
    }[i[0]]
    if pre != undefined
      args = []
      for j in [0...pre]
        n = stack.pop()
        n = new Node(["gen","pops[#{pops++}]"]) if n == undefined
        args.unshift n

      debug "args", i, args

      node = new Node(i, args)
      switch i[0]
        when 'rll'
          debug "Roll?", i, util.inspect(node,true,10), stack
          return compilejs(list) if node.taint
          d = flatten node.chld[0], [], dups
          t = flatten node.chld[1], [], dups
          diff = _.min [0, stack.length - d]
          stack.unshift(new Node ["gen","pops[#{pops++}]"]) for j in [0...diff]
          debug "ROLL ME", d, t
          if t>=0
            stack.splice(stack.length-d,0,stack.pop()) for j in [0...t]
          else
            stack.push(stack.splice(stack.length-d,1)[0]) for j in [0...-t]
        when 'otn', 'otc'
          output.push node
        when 'ptr', 'ptri'
          dps.push node
        when 'swt', 'swti'
          ccs.push node
        when 'inn', 'inc'
          throw "INVALID INPUT" if term
          term = node
        when 'pop'
          #Delete
        else
          stack.push node
        
      if i[0] == "dup"
        stack[stack.length-1].dup = dupn++
        stack.push stack[stack.length-1]

  debug("stack", s.inst, s.chld) for s in stack

  out = "(function(data,stack,curr,dp,cc) {\n\t
if (stack.length < #{pops}) { return this.slow_js(data,stack,curr,dp,cc); }\n\t"
  out += "var dups = [];\n\t" unless dups == 0
  out += "var pops = stack.splice(0,#{pops});\n\t" unless pops == 0

  out += stack.map(
    (e) -> "stack.unshift(#{flatten(e,seen,dups)})"
  ).concat(output.map(
    (e) -> flatten(e,seen,dups)
  )).join(";\n\t")
  dpn = new Node ["join"], dps
  totaldps = flatten dpn, seen, dups
  out += ";\n\tdp = (dp + (#{totaldps})).mod(4) //" + dpn.taint + "\n" if totaldps
  totalccs = flatten new Node(["join"], ccs), seen, dups
  out += ";\n\tcc = (#{totalccs}).mod(2) == 0 ? cc : -cc" if totalccs
  out += if term then ";\n\t" + flatten(term, seen, dups) else "\n\t\treturn [dp,cc]"
  out + "\n})"


way = (dp) -> dp % 2
pos = (dp) -> if dp < 2 then 1 else -1
sgn = (dp) -> if way(dp) then -1 else 1

edge = (list, dp) ->
  _.max list, (e) -> e.pos[way(dp)]*pos(dp)

ccmost = (list, dp, cc, max) ->
  maxes = list.filter (e) -> e.pos[way(dp)] == max.pos[way(dp)]
  _.max maxes, (e) -> e.pos[1-way(dp)] * cc * [1,-1,-1,1][dp]

corner = (list, dp, cc) ->
  max = edge list, dp
  ccmost list, dp, cc, max

dpwise = (data, c, dp) ->
  x = [1,0,-1,0][dp]
  y = [0,1,0,-1][dp]
  (data.grid[c.pos[1]+y] or [])[c.pos[0]+x]

findexit = (data, block, dp, cc) ->
  list = []
  for count in [0..7]
    succ = corner block.codels, dp, cc
    curr = dpwise data, succ, dp
    if curr and not curr.black
      list.push ["ptri", count/2|0] if count > 1
      list.push ["swti", 1] if (count+1)&2
      return [curr,list,dp,cc]
    if count % 2 == 0
      cc = -cc
    else
      dp = (dp + 1) % 4
  return [false]

compile = (data, curr, last, dp, cc) ->
  sect = {list:[]}
  loop
    debug sect.list[-10..-1]
    debug last.colour("loop" + last.pos)
    debug curr.colour("loop" + curr.pos), dp, cc
    
    if not curr or curr.black
      throw "INVALID CELL" + curr
    block = data.blocks[curr.label]
    if block.exits[dp*4+cc]
      sect.terminal = block
      return new SectSlice data, sect, 0
    if curr.white
      seen = []
      succ = curr
      last = curr
      count = 0
      loop
        while cand = dpwise(data, succ, dp) and cand and cand.label == succ.label
          succ = cand
        curr = dpwise data, succ, dp
        if curr and not curr.black
          break
        cc = -cc
        dp = (dp + 1) % 4
        
        seen.push succ
        count++
      sect.list.push ["ptri", count % 4] if count % 4 != 0
      sect.list.push ["swti", 1] if count % 2 != 0
    else
      if not last.white
        ins = inst last, curr
        count = if ins == 'psh' then last.count else 1
        sect.list.push [ins, count]
      else
        sect.list.push ["nop"]
      if ins == 'ptr' or ins == 'swt' or ins == 'inn' or ins == 'inc'
        sect.terminal = block
        return new SectSlice data, sect, 0
      else
        block.exits[dp*4+cc] = new SectSlice data, sect
      last = curr
      [curr, app, dp, cc] = findexit data, block, dp, cc
      return new SectSlice(data, sect, 0) unless curr
      sect.list.push app...

piet_eval = (data) ->
  dp =  0
  cc = -1
  last = new Codel(0,0,'white')

  curr = compile data, data.grid[0][0], last, dp, cc
  debug "list", curr.list()
  
  stack = []

  io.start()
  peval data, stack, curr, dp, cc

peval = (data, stack, curr, dp, cc) ->
  while true
    debug "pre", stack, dp, cc
    debug "curr", curr.js.toString()
    ret = curr.js data, stack, curr, dp, cc
    return unless ret
    [dp,cc] = ret
    debug "post", stack, dp, cc
    
    term = curr.terminal()
    return unless term
    curr = term.exit dp, cc
    return unless curr

create = (file) ->
  data = parse_ppm file
  debug "data", data.grid[0]
  data.blocks = (new Block(data, c) for c in fill(data))
  data

