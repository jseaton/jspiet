_ = require '/usr/lib/node_modules/underscore'
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

parse = (n) -> new Codel {
	'0 0 0':[0,0,'black'], '255 255 255':[0,0,'white'],
	'255 192 192':[0,0], '255 0 0'  :[0,1], '192 0 0'  :[0,2],
	'255 255 192':[1,0], '255 255 0':[1,1], '192 192 0':[1,2],
	'192 255 192':[2,0], '0 255 0'  :[2,1], '0 192 0'  :[2,2],
	'192 255 255':[3,0], '0 255 255':[3,1], '0 192 192':[3,2],
	'192 192 255':[4,0], '0 0 255'  :[4,1], '0 0 192'  :[4,2],
	'255 192 255':[5,0], '255 0 255':[5,1], '192 0 192':[5,2]
	}[n.replace(/\s+/g,' ')]...

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

neighbours = (grid, x, y) -> ((grid[yi] or [])[xi] for [xi,yi] in [[x-1,y], [x+1,y], [x,y-1], [x,y+1]]).select (e) -> e

rotate = ([x,y]) -> [-y,x]

way = (dp) -> (dp[0] == 0) + 0
edge = (list, dp) -> _.max(list, (e) -> e.pos[way(dp)]*dp[way(dp)])

ccmost = (list, cc, way, max) ->
	maxes = list.filter (e) -> e.pos[way] == max.pos[way]
	_.min maxes, (e) -> e.pos[way] * cc

compile = (x, y, data, members, last, dp, cc) ->
	list = []
	for i in [1 .. 10]
		c = data.grid[y][x]
		cconsole.log c.colour("start")
		cconsole.log last.colour("last"), c, list
		if not c or c.black
			if last.white
				cc = -cc
				rotate dp
			else
				x -= dp[0]
				y -= dp[1]
				cc = -cc
		else if c.white
			[x,y] = edge(members[c.label].filter((e) -> e.pos[1 - way(dp)] == [x,y][1 - way(dp)]), dp).pos
			x += dp[0]
			y += dp[1]
		else
			if not last.white
				ins = inst last, c
				list.push [ins, last.count]
				if ins == 'ptr' or ins == 'swt'
					return {list:list, exits:neighbours(data.grid,x,y)}
			else
				list.push ["nop", 0]
			last = c
		
			#console.log members[c.label],	dp, cc, way(dp)
			max = edge members[c.label], dp
			#console.log max
			suc = ccmost members[c.label], cc, way(dp), max
			[x, y] = suc.pos
			x += dp[0]
			y += dp[1]

peval = ({list:list, exits:exits}) ->
	for i in list
		console.log i


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
	console.log equiv
	for e in equiv
		members[e[0]].push members[e[1]].splice(0)...

	for m,i in members
		for e in m
			e.label = i
			e.count = m.length
	
	members


data = parse_ppm process.argv[2]

members = fill data

console.log data.width, data.height
for row in data.grid
	cconsole.log row.map((i) -> ( i.colour(if i.label > 9 then i.label else "0" + i.label ))).join(' ')

for i in members
	cconsole.log i[0].colour(i[0].count + " " + i[0].pos) if i[0]
dp = [1,0]
cc = -1
last = new Codel(0,0,'white')

exits = {} for i in members

first = compile 0, 0, data, members, last, dp, cc

console.log "first", first

#peval first

