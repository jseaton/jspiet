_ = require '/usr/lib/node_modules/underscore'
fs = require 'fs'

Number.prototype.mod = (n) -> ((this%n)+n)%n

class Codel
	constructor: (hue, light, bw) ->
		@hue   = hue
		@light = light
		@black = bw == 'black'
		@white = bw == 'white'

	isEqual: (other) -> @hue == other.hue and @light == other.light and @black == other.black and @white == other.white

parse = (n) -> new Codel {
	'0 0 0':[0,0,'black'], '255 255 255':[0,0,'white'],
	'255 192 192':[0,0], '255 0 0'  :[0,1], '192 0 0'  :[0,2],
	'255 255 192':[1,0], '255 255 0':[1,1], '192 192 0':[1,2],
	'192 255 192':[2,0], '0 255 0'  :[2,1], '0 192 0'  :[2,2],
	'192 255 255':[3,0], '0 255 255':[3,1], '0 192 192':[3,2],
	'192 192 255':[4,0], '0 0 255'  :[4,1], '0 0 192'  :[4,2],
	'255 192 255':[5,0], '255 0 255':[5,1], '192 0 192':[5,2]
	}[n.replace(/\s+/g,' ')]...

inst = (a, b) -> [
	'nop', 'psh', 'pop',
	'add', 'sub', 'mul',
	'div', 'mod', 'not',
	'gth', 'ptr', 'swt',
	'dup', 'rll', 'inn',
	'inc', 'otn', 'otc'
	][(b.hue-a.hue).mod(6)*3 + (b.hue-a.hue)]

# inefficient flood fill, scanline style algorithm
# would be better
fill = (grid, n, nx, ny) -> unless n.count
		console.log n
		q = [[nx, ny]]
		u = []
		while [x, y] = q.shift() or 0
			continue unless x and y
			c = grid[y][x]
			continue unless c.isEqual n
			u.push c
			w = x
			e = x
			w -= 1 while w > 0 and grid[y][w].isEqual n
			e += 1 while e < grid[0].length-1 and grid[y][e].isEqual n
			for i in [w .. e]
				u.push grid[y][i]
				q.push grid[y-1][i] if y > 0
				q.push grid[y+1][i] if y < grid.length-1
		for i in u
			i.count = u.length

parse_ppm = (name) ->
	file = fs.readFileSync(name).toString()
	[width, height] = file.match(/^(\d+) (\d+)$/m).slice(1,3)
	list = file.match(/\d+ +\d+ +\d+/g).map(parse)
	data = []
	for i in [0 ... height]
		data.push list.splice(0, width)
	return {grid:data,width:width,height:height}

neighbours = (grid, x, y) -> ((grid[yi] or [])[xi] for [xi,yi] in [[x-1,y], [x+1,y], [x,y-1], [x,y+1]]).select (e) -> e

data = parse_ppm process.argv[2]
#for row, y in data
#	for cell, x in row
#		fill data, cell, x, y

console.log data.grid

c = 0
equiv = []
members = [[]]
for x in [0 ... data.width]
	for y in [0 ... data.height]
		i = data.grid[y][x]
		w = data.grid[y][x-1]
		n = (data.grid[y-1] or [])[x]
		if w and i.isEqual(w)
			i.label = w.label
			console.log "w"
		else if w and n and w.isEqual(n) and w.label != n.label
			console.log x, y, w, n
			pair = [w.label, n.label].sort()
			i.label = pair[0]
			equiv.push pair
			console.log "wn"
		else if n and i.isEqual(n)
			i.label = n.label
			console.log "n"
		else
			c += 1
			i.label = c
			members.push []
			console.log "c"
		console.log i.label
		members[i.label].push i



console.log equiv

for e in equiv
	members[e[0]].push members[e[1]].splice(0)...

for m,i in members
	for e in m
		e.label = i
		e.count = m.length


for row in data.grid
	console.log row.map((i) -> "#{i.label}-#{i.count}").join(' ')

dp = [1,0]
cc = -1
last = new Codel(0,0,'white')

[x,y] = [0,0]
list = []
exits = {} for i in members
while true
	c = data.grid[y][x]
	if c.white
		false
	else if c.black
		false
	else
		ins = c, last
		if ins == 'ptr'
			return {list:list, exits:neighbours(data.grid,x,y)}
		else
