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
		psh : 'stack.push(n)',
		pop : 'stack.pop()',
		add : 'stack.push(stack.pop()+stack.pop())',
		sub : 'stack.push(-stack.pop()+stack.pop())',
		mul : 'stack.push(stack.pop()*stack.pop())',
		div : 't=stack.pop();stack.push(stack.pop()/t|0)',
		mod : 't=stack.pop();stack.push(stack.pop()%t)',
		not : 'stack.push(stack.pop() ? 0 : 1)',
		gth : 'stack.push(stack.pop() <= stack.pop() ? 1 : 0)',
		ptr : 'dp = (dp + stack.pop()) % 4',
		swt : 'cc = stack.pop() % 2 == 0 ? cc : -cc',
		dup : 'stack.push(stack[stack.length-1])',
		rll : 'console.log("TODO RLL")',
		inn : 'console.log("TODO INN"); stack.push(7)',
		inc : 'console.log("TODO INC"); stack.push(104)',
		otn : 'process.stdout.write(stack.pop())',
		otc : 'process.stdout.write(String.fromCharCode(stack.pop()))'
	}[inst]

compilejs = (list) -> "(function(stack,n,dp,cc) {\n" + list.map((i) -> "\t" + jsinst(i[0]) + ";\tn=" + i[1]).join(";\n") + ";\n\n\treturn [n,dp,cc];\n})"

neighbours = (grid, x, y) -> ((grid[yi] or [])[xi] for [xi,yi] in [[x-1,y], [x+1,y], [x,y-1], [x,y+1]]).select (e) -> e

rotate = ([x,y]) -> [-y,x]

way = (dp) -> dp % 2
pos = (dp) -> if dp < 2 then 1 else -1

edge = (list, dp) ->
	_.max list, (e) -> e.pos[way(dp)]*pos(dp)

ccmost = (list, cc, way, max) ->
	maxes = list.filter (e) -> e.pos[way] == max.pos[way]
	_.max maxes, (e) -> e.pos[1-way] * cc

corner = (list, cc, dp) ->
	max = edge list, dp
	ccmost list, cc, way(dp), max

dpwise = (data, c, dp) ->
	x = [1,0,-1,0][dp]
	y = [0,1,0,-1][dp]
	(data.grid[c.pos[1]+y] or [])[c.pos[0]+x]

nextcodel = (data, list, cc, dp) ->
	succ = corner list, cc, dp
	dpwise data, succ, dp

compile = (data, curr, last, dp, cc) ->
	console.log curr
	list = []
	loop
		cconsole.log curr.colour("colour"), dp, cc, list[list.length-1]
		
		if not curr or curr.black
			throw "INVALID CELL" + curr
		block = data.blocks[curr.label]
		if curr.white
			seen = [curr]
			precc = cc
			predp = dp
			loop
				curr = edge block.codels.filter((e) -> e.pos[1 - way(dp)] == curr.pos[1 - way(dp)]), dp
				return {list:list} if _.contains seen, succ
				next = dpwise data, succ, dp
				if next and not next.black
					#TODO: account for cc/dp change in instructions
					break
				cc = -cc
				dp = (dp + 1) % 4
				seen.push curr
		else
			if not last.white
				ins = inst last, curr
				list.push [ins, curr.count]
			else
				list.push ["nop", curr.count]
			block.exits[[dp,cc]] ||= {}
			block.exits[[dp,cc]].list = new ArraySlice(list)
			if ins == 'ptr' or ins == 'swt'
				return {list:list,terminal:curr}
		last = curr
		
		count = 0
		loop
			succ = corner block.codels, cc, dp
			curr = dpwise data, succ, dp
			#curr = nextcodel data, block.codels, dp, cc
			#TODO: account for cc/dp change in instructions
			break if curr and not curr.black
			if count % 2 == 0
				cc = -cc
			else
				dp = (dp + 1) % 4
			count += 1
			return {list:list} if count >= 4

peval = (data) ->
	dp =  0
	cc = -1
	last = new Codel(0,0,'white')

	start = compile data, data.grid[0][0], last, dp, cc
	jscode = compilejs start.list
	console.log jscode
	
	f = eval jscode
	next = start.terminal
	
	stack = []
	n = 0
	while true
		console.time 'evaluation'
		[n,dp,cc] = f(stack,n,dp,cc)
		console.timeEnd 'evaluation'
		return unless next
		block = data.blocks[next.label]
		block.exits[[dp,cc]] ||= {}
		exits = block.exits[[dp,cc]]
		if exits.js
			f = exits.js
		else
			unless exits.list
				succ = corner block.codels, cc, dp
				curr = dpwise data, succ, dp
				exits.list = compile data, curr, next, dp, cc
			jscode = compilejs exits.list
			f = exits.js = eval jscode

data = parse_ppm process.argv[2]

data.blocks = ({codels:c,exits:{}} for c in fill(data))

for row in data.grid
	cconsole.log row.map((i) -> ( i.colour(if i.label > 9 then i.label else "0" + i.label ))).join(' ')

peval data

