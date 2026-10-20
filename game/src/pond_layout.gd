class_name PondLayout
extends RefCounted

## Where water stands: from a pond's grid point water runs downhill to the bottom of its hollow, then fills it,
## lowest ground first, up to the level it was given, or until it would spill over the lowest point of the rim
## onto ground that drains away. Spilling into another enclosed hollow fills that too, so neighbouring digs
## become one pond.

## How far the water sits below its spill point, so it never brims over.
const FREEBOARD := 0.08
## Shallower basins than this hold no pond.
const MIN_DEPTH := 0.12
const NEIGHBOURS := [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]
const AROUND := [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]


class Pond:
	## The grid point it fills from.
	var at := Vector2i()
	var level := 0.0
	## The lowest grid point of the pond, the first in row order on a flat floor.
	var bottom := Vector2i()
	## Grid points under water.
	var cells: Array[Vector2i] = []
	## Dry grid points touching the water: the shaders read the level there too, so it is exact to the shore.
	var shore: Array[Vector2i] = []
	var box := Rect2i()
	## The ground the fill read: an edit outside it leaves this pond as it is.
	var ground := Rect2i()
	## Water over the bottom.
	var depth := 0.0


## The pond in the basin below grid point `at` with water no higher than `cap`, or null when it drains to the
## edge of `window` or is too shallow. `heights` holds the grid points of `window`, row by row. `near` is a level the
## water is likely to reach, as the pond's before an edit: the ground below it is checked and filled at once.
## A lake can be the whole world, tens of thousands of points: the fill keeps indices and flags in packed arrays,
## and floods lowest first, a heap's work a point, only above the ground known to hold water.
static func fill(heights: PackedFloat32Array, window: Rect2i, at: Vector2i, cap := INF, near := -INF) -> Pond:
	var w := window.size.x
	var rows := window.size.y
	var steps := PackedInt32Array([-1, 1, -w, w])
	var around := PackedInt32Array([-w - 1, -w, -w + 1, -1, 1, w - 1, w, w + 1])
	var flags := PackedByteArray()
	flags.resize(heights.size())
	var marks := PackedInt32Array()
	marks.resize(heights.size())
	var k := (at.y - window.position.y) * w + at.x - window.position.x
	var lo := Vector2i(k % w, k / w)
	var hi := lo
	while _inner(k, w, rows):
		var next := k
		for s in steps:
			if heights[k + s] < heights[next]:
				next = k + s
		if next == k:
			break
		k = next
		lo = lo.min(Vector2i(k % w, k / w))
		hi = hi.max(Vector2i(k % w, k / w))
	var start := k
	var spill := -INF
	var heap := MinHeap.new()
	var basin := PackedInt32Array()
	if cap < INF and _held(heights, w, rows, start, cap, flags, basin):
		spill = INF
	else:
		flags.fill(0)
		basin.clear()
		if near > -INF and near < cap and _held(heights, w, rows, start, near, flags, basin):
			for g in basin:
				spill = maxf(spill, heights[g])
				flags[g] |= SEEN
			for g in basin:
				for s in steps:
					if not flags[g + s] & SEEN:
						flags[g + s] |= SEEN
						heap.push(heights[g + s], g + s)
		else:
			flags.fill(0)
			basin.clear()
			flags[start] |= SEEN
			heap.push(heights[start], start)
	for g in basin:
		lo = lo.min(Vector2i(g % w, g / w) - Vector2i.ONE)
		hi = hi.max(Vector2i(g % w, g / w) + Vector2i.ONE)
	var hollows := 0
	while spill < INF:
		if heap.empty():
			return null
		var g := heap.pop()
		var gh := heights[g]
		if gh - FREEBOARD >= cap:
			spill = gh
			break
		if gh < spill and not flags[g] & ENCLOSED:
			hollows += 1
			var hollow := _hollow(heights, w, rows, g, spill, flags, marks, hollows)
			for c in hollow[1]:
				lo = lo.min(Vector2i(c % w, c / w))
				hi = hi.max(Vector2i(c % w, c / w))
			if not hollow[0]:
				break
			for c in hollow[1]:
				flags[c] |= ENCLOSED
		if not _inner(g, w, rows):
			return null
		spill = maxf(spill, gh)
		flags[g] |= BASIN
		lo = lo.min(Vector2i(g % w, g / w) - Vector2i.ONE)
		hi = hi.max(Vector2i(g % w, g / w) + Vector2i.ONE)
		for s in steps:
			var n := g + s
			if not flags[n] & SEEN:
				flags[n] |= SEEN
				heap.push(heights[n], n)
	var pond := Pond.new()
	pond.at = at
	pond.level = minf(cap, spill - FREEBOARD)
	if heights[start] >= pond.level:
		return null
	var wet := PackedInt32Array([start])
	flags[start] |= WET
	var todo := PackedInt32Array([start])
	var bottom := start
	while not todo.is_empty():
		var g := todo[todo.size() - 1]
		todo.resize(todo.size() - 1)
		if g != start:
			wet.append(g)
		if heights[g] < heights[bottom] or heights[g] == heights[bottom] and g < bottom:
			bottom = g
		for s in steps:
			var n := g + s
			if flags[n] & BASIN and not flags[n] & WET and heights[n] < pond.level:
				flags[n] |= WET
				todo.append(n)
	pond.depth = pond.level - heights[bottom]
	if pond.depth < MIN_DEPTH:
		return null
	pond.ground = Rect2i(lo + window.position, hi - lo + Vector2i.ONE).grow(1)
	lo = Vector2i(bottom % w, bottom / w)
	hi = lo
	for g in wet:
		var c := Vector2i(g % w, g / w)
		pond.cells.append(c + window.position)
		lo = lo.min(c)
		hi = hi.max(c)
		for s in around:
			var n := g + s
			if not flags[n] & (WET | DRY) and heights[n] >= pond.level:
				flags[n] |= DRY
				pond.shore.append(Vector2i(n % w, n / w) + window.position)
	pond.bottom = Vector2i(bottom % w, bottom / w) + window.position
	pond.box = Rect2i(lo + window.position, hi - lo + Vector2i.ONE)
	return pond


const SEEN := 1
const BASIN := 2
const ENCLOSED := 4
const WET := 8
const DRY := 16


## Whether all the ground water up to `cap` would reach from `from` is enclosed, marked as the basin and listed in
## `basin`: then the pond is that ground at `cap`, and the lowest-first flood, a heap's work a point, is not needed
## below it. False when the water would reach the window's edge.
static func _held(heights: PackedFloat32Array, w: int, rows: int, from: int, cap: float, flags: PackedByteArray, basin: PackedInt32Array) -> bool:
	var steps := PackedInt32Array([-1, 1, -w, w])
	if heights[from] - FREEBOARD >= cap:
		return false
	flags[from] |= BASIN
	basin.append(from)
	var todo := PackedInt32Array([from])
	while not todo.is_empty():
		var g := todo[todo.size() - 1]
		todo.resize(todo.size() - 1)
		if not _inner(g, w, rows):
			return false
		for s in steps:
			var n := g + s
			if not flags[n] & BASIN and heights[n] - FREEBOARD < cap:
				flags[n] |= BASIN
				basin.append(n)
				todo.append(n)
	return true


static func _inner(k: int, w: int, rows: int) -> bool:
	var x := k % w
	var y := k / w
	return x > 0 and y > 0 and x < w - 1 and y < rows - 1


## The ground below `level` reachable from `from` outside the pond so far, as [whether it is enclosed, the points
## it took in]: water spilling there fills it rather than running away, unless it reaches the window's edge, where
## water drains to open ground. `marks` holds `id` at the points this call took in.
static func _hollow(heights: PackedFloat32Array, w: int, rows: int, from: int, level: float, flags: PackedByteArray, marks: PackedInt32Array, id: int) -> Array:
	var steps := PackedInt32Array([-1, 1, -w, w])
	marks[from] = id
	var seen := PackedInt32Array([from])
	var todo := PackedInt32Array([from])
	while not todo.is_empty():
		var g := todo[todo.size() - 1]
		todo.resize(todo.size() - 1)
		if not _inner(g, w, rows):
			return [false, seen]
		for s in steps:
			var n := g + s
			if marks[n] != id and not flags[n] & BASIN and heights[n] < level:
				marks[n] = id
				seen.append(n)
				todo.append(n)
	return [true, seen]


## Indices of grid points, lowest first.
class MinHeap:
	var keys := PackedFloat32Array()
	var values := PackedInt32Array()

	func empty() -> bool:
		return keys.is_empty()

	func push(k: float, v: int) -> void:
		keys.append(k)
		values.append(v)
		var i := keys.size() - 1
		while i > 0:
			var p := (i - 1) / 2
			if keys[p] <= keys[i]:
				break
			_swap(i, p)
			i = p

	func pop() -> int:
		var top := values[0]
		var last := keys.size() - 1
		_swap(0, last)
		keys.resize(last)
		values.resize(last)
		var i := 0
		while true:
			var l := i * 2 + 1
			var m := i
			if l < last and keys[l] < keys[m]:
				m = l
			if l + 1 < last and keys[l + 1] < keys[m]:
				m = l + 1
			if m == i:
				break
			_swap(i, m)
			i = m
		return top

	func _swap(a: int, b: int) -> void:
		var k := keys[a]
		keys[a] = keys[b]
		keys[b] = k
		var v := values[a]
		values[a] = values[b]
		values[b] = v
