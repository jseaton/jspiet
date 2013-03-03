require 'coffee-trace'
_ = require 'underscore'
fs = require 'fs'
colorize = require 'colorize'
cconsole = colorize.console

Number.prototype.mod = (n) -> ((this%n)+n)%n

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

class ArraySlice
	constructor: (array) ->
		@array = array
		@index = array.length - 1

	get: -> @array[@index..-1]

parse = (n) -> new Codel {
	'0 0 0':[0,0,'black'], '255 255 255':[0,0,'white'],
	'255 192 192':[0,0], '255 0 0'  :[0,1], '192 0 0'  :[0,2],
	'255 255 192':[1,0], '255 255 0':[1,1], '192 192 0':[1,2],
	'192 255 192':[2,0], '0 255 0'  :[2,1], '0 192 0'  :[2,2],
	'192 255 255':[3,0], '0 255 255':[3,1], '0 192 192':[3,2],
	'192 192 255':[4,0], '0 0 255'  :[4,1], '0 0 192'  :[4,2],
	'255 192 255':[5,0], '255 0 255':[5,1], '192 0 192':[5,2]
	}[n.replace(/\s+/g,' ')]...

parse_ppm = (name) ->
	file = fs.readFileSync(name).toString()
	[width, height] = file.match(/^(\d+) (\d+)$/m).slice(1,3)
	list = file.match(/\d+ +\d+ +\d+/g).map(parse)
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
	console.log a.hue, b.hue, a.light, b.light, (b.hue-a.hue).mod(6), (b.light-a.light).mod(3)
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
		psh :	'stack.push(n)',
		pop : 'stack.pop()',
		add : 'stack.push(stack.pop()+stack.pop())',
		sub : 'stack.push(-stack.pop()+stack.pop())',
		mul : 'stack.push(stack.pop()*stack.pop())',
		div : 't=stack.pop();stack.push(stack.pop()/t|0)',
		mod : 't=stack.pop();stack.push(stack.pop()%t)',
		not : 'stack.push(stack.pop() ? 0 : 1)',
		gth : 'stack.push(stack.pop() <= stack.pop() ? 1 : 0)',
		ptr : 'console.log("TODO PTR")',
		swt : 'console.log("TODO SWT")',
		dup : 'console.log("TODO DUP")',
		rll : 'console.log("TODO RLL")',
		inn : 'console.log("TODO INN")',
		inc : 'console.log("TODO INC")',
		otn : 'process.stdout.write(stack.pop())',
		otc : 'process.stdout.write(String.fromCharCode(stack.pop()))'
	}[inst]

compilejs = (list) -> "(function(stack,dp,cc) {\n" + list.map((i) -> "\t" + jsinst(i[0]) + ";\tn=" + i[1]).join(";\n") + ";\n})"

neighbours = (grid, x, y) -> ((grid[yi] or [])[xi] for [xi,yi] in [[x-1,y], [x+1,y], [x,y-1], [x,y+1]]).select (e) -> e

rotate = ([x,y]) -> [-y,x]

way = (dp) -> (dp[0] == 0) + 0
edge = (list, dp) -> _.max(list, (e) -> e.pos[way(dp)]*dp[way(dp)])

ccmost = (list, cc, way, max) ->
	maxes = list.filter (e) -> e.pos[way] == max.pos[way]
	_.max maxes, (e) -> e.pos[1-way] * cc

corner = (list, cc, dp) ->
	max = edge list, dp
	ccmost list, cc, way(dp), max

compile = (x, y, data, blocks, last, dp, cc) ->
	list = []
	for i in [1 .. 50]
		c = data.grid[y][x]
		console.log x,y,c
		cconsole.log c.colour("colour") if c
		cconsole.log last.colour("last"), dp, cc, list
		if not c or c.black
			if last.white
				cc = -cc
				rotate dp
			else
				x -= dp[0]
				y -= dp[1]
				cc = -cc
			continue
		block = blocks[c.label]
		if c.white
			[x,y] = edge(block.codels.filter((e) -> e.pos[1 - way(dp)] == [x,y][1 - way(dp)]), dp).pos
			x += dp[0]
			y += dp[1]
		else
			if not last.white
				ins = inst last, c
				list.push [ins, c.count]
			else
				list.push ["nop", c.count]
			block.exits[[dp,cc]] ||= {}
			block.exits[[dp,cc]].list = new ArraySlice(list)
			if ins == 'ptr' or ins == 'swt'
				return {list:list,terminal:block}
		last = c
		
		suc = corner block.codels, cc, dp
		[x, y] = suc.pos
		x += dp[0]
		y += dp[1]
	
	{list:list,terminal:blocks[0]}


peval = (data, blocks) ->
	dp = [1,0]
	cc = -1
	last = new Codel(0,0,'white')

	start = compile 0, 0, data, blocks, last, dp, cc
	jscode = compilejs start.list
	console.log jscode
	
	f = eval jscode
	
	stack = []
	while true
		console.time 'evaluation'
		next = f(stack)
		console.timeEnd 'evaluation'
		return unless next
		exits = next.exits[[dp,cc]]
		if exits.js
			f = exits.js
		else
			compile next.pos[0], next.pos[1], data, blocks, dp, cc if not exits.list
			jscode = compilejs exits.list
			f = exits.js = eval jscode

data = parse_ppm process.argv[2]

blocks = ({codels:c,exits:{}} for c in fill(data))

console.log blocks

console.log data.width, data.height
for row in data.grid
	cconsole.log row.map((i) -> ( i.colour(if i.label > 9 then i.label else "0" + i.label ))).join(' ')

for block in blocks
	codel = block.codels[0]
	cconsole.log codel.colour(codel.count + " " + codel.pos) if codel

peval data, blocks

