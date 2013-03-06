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

class SectSlice
	constructor: (ref,n) ->
		@ref = ref
		@index = if n == undefined then @ref.list.length - 1 else 0

	list: -> @ref.list[@index..-1]
	terminal: -> @ref.terminal

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
		otn : 'process.stdout.write("============"+stack.pop().toString()+"===========\\n")',
		otc : 'process.stdout.write(String.fromCharCode(stack.pop()))'
	}[inst]

compilejs = (list) -> "(function(stack,n,dp,cc) {\n" + list.map((i) -> "\t" + jsinst(i[0]) + ";\n\tn=" + i[1]).join(";\n") + ";\n\n\treturn [n,dp,cc];\n})"

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
	sect = {list:[]}
	loop
		#cconsole.log curr.colour("loop" + curr.pos), dp, cc, sect.list
		
		if not curr or curr.black
			throw "INVALID CELL" + curr
		block = data.blocks[curr.label]
		if block.exits[[dp,cc]]
			sect.terminal = curr
			return new SectSlice sect, 0
		if curr.white
			seen = []
			precc = cc
			predp = dp
			succ = curr
			last = curr
			loop
				#console.log "curr", way(dp), curr.pos
				while cand = dpwise(data, succ, dp) and cand and cand.label == succ.label
					succ = cand
				#console.log succ
				#return {list:list} if _.contains seen, succ
				curr = dpwise data, succ, dp
				if curr and not curr.black
					#console.log "breaking", curr.pos
					#TODO: account for cc/dp change in instructions
					break
				cc = -cc
				sect.list.push ["psh", 1]
				sect.list.push ["swt", 1]
				
				dp = (dp + 1) % 4
				sect.list.push ["psh", 1]
				sect.list.push ["ptr", 1]
				
				seen.push succ
		else
			if not last.white
				ins = inst last, curr
				sect.list.push [ins, curr.count]
			else
				sect.list.push ["nop", curr.count]
			block.exits[[dp,cc]] = new SectSlice sect
			if ins == 'ptr' or ins == 'swt'
				sect.terminal = curr
				return new SectSlice sect, 0
			last = curr
		
			count = 0
			loop
				#console.log "from", curr
				succ = corner block.codels, cc, dp
				curr = dpwise data, succ, dp
				#console.log "next", curr
				#curr = nextcodel data, block.codels, dp, cc
				#TODO: account for cc/dp change in instructions
				break if curr and not curr.black
				if count % 2 == 0
					cc = -cc
					sect.list.push ["psh", 1]
					sect.list.push ["swt", 1]
				else
					dp = (dp + 1) % 4
					sect.list.push ["psh", 1]
					sect.list.push ["ptr", 1]
				count += 1
				return new SectSlice(sect, 0) if count >= 4

peval = (data) ->
	dp =  0
	cc = -1
	last = new Codel(0,0,'white')

	start = compile data, data.grid[0][0], last, dp, cc
	jscode = compilejs start.list()
	console.log jscode
	
	f = eval jscode
	terminal = start.terminal()
	
	stack = []
	n = 0
	while true
		#console.time 'evaluation'
		console.log "stack", stack
		[n,dp,cc] = f(stack,n,dp,cc)
		#console.timeEnd 'evaluation'
		#console.log terminal
		return unless terminal
		block = data.blocks[terminal.label]
		block.exits[[dp,cc]] ||= {}
		exits = block.exits[[dp,cc]]
		if exits.js
			f = exits.js
		else
			unless exits.list
				#console.log "doin", block
				succ = corner block.codels, cc, dp
				curr = dpwise data, succ, dp
				#console.log "goin", curr
				exits = compile data, curr, terminal, dp, cc
			jscode = compilejs exits.list()
			console.log jscode
			f = exits.js = eval jscode
		terminal = exits.terminal()

data = parse_ppm process.argv[2]

data.blocks = ({codels:c,exits:{}} for c in fill(data))

#for row in data.grid
#	cconsole.log row.map((i) -> ( i.colour(if i.label > 9 then i.label else "0" + i.label ))).join(' ')

peval data

