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
## A basin wider than this many grid points from its grid point is open ground, not a pond.
const REACH := 24
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
	## Water over the bottom.
	var depth := 0.0


## The pond in the basin below grid point `at` with water no higher than `cap`, or null when it is open ground
## or too shallow. `heights` holds the grid points of `window`, row by row.
static func fill(heights: PackedFloat32Array, window: Rect2i, at: Vector2i, cap := INF) -> Pond:
	var h := func(g: Vector2i) -> float: return heights[(g.y - window.position.y) * window.size.x + g.x - window.position.x]
	var inner := window.grow(-1)
	var bottom := at
	while inner.has_point(bottom):
		var next := bottom
		for o in NEIGHBOURS:
			if h.call(bottom + o) < h.call(next):
				next = bottom + o
		if next == bottom:
			break
		bottom = next
	var start := bottom
	var seen := {bottom: true}
	var heap := MinHeap.new()
	heap.push(h.call(bottom), bottom)
	var spill := -INF
	var basin := {}
	var enclosed := {}
	while true:
		if heap.empty():
			return null
		var g := heap.pop()
		var gh: float = h.call(g)
		if gh - FREEBOARD >= cap:
			spill = gh
			break
		if gh < spill and not enclosed.has(g):
			var hollow := _hollow(h, inner, g, spill, basin)
			if hollow.is_empty():
				break
			enclosed.merge(hollow)
		if not inner.has_point(g):
			return null
		spill = maxf(spill, gh)
		basin[g] = true
		for o in NEIGHBOURS:
			if not seen.has(g + o):
				seen[g + o] = true
				heap.push(h.call(g + o), g + o)
	var pond := Pond.new()
	pond.at = at
	pond.level = minf(cap, spill - FREEBOARD)
	if h.call(start) >= pond.level:
		return null
	var wet := {start: true}
	var todo: Array[Vector2i] = [start]
	while not todo.is_empty():
		var g: Vector2i = todo.pop_back()
		pond.cells.append(g)
		var low: float = h.call(bottom)
		if h.call(g) < low or h.call(g) == low and (g.y < bottom.y or g.y == bottom.y and g.x < bottom.x):
			bottom = g
		for o in NEIGHBOURS:
			var n: Vector2i = g + o
			if basin.has(n) and not wet.has(n) and h.call(n) < pond.level:
				wet[n] = true
				todo.append(n)
	pond.bottom = bottom
	pond.depth = pond.level - h.call(bottom)
	if pond.depth < MIN_DEPTH:
		return null
	var lo := bottom
	var hi := bottom
	var dry := {}
	for g in pond.cells:
		lo = Vector2i(mini(lo.x, g.x), mini(lo.y, g.y))
		hi = Vector2i(maxi(hi.x, g.x), maxi(hi.y, g.y))
		for o in AROUND:
			var n: Vector2i = g + o
			if not wet.has(n) and not dry.has(n) and h.call(n) >= pond.level:
				dry[n] = true
				pond.shore.append(n)
	pond.box = Rect2i(lo, hi - lo + Vector2i.ONE)
	return pond


## The ground below `level` reachable from `from` outside the pond so far, if it is enclosed: water spilling
## there fills it rather than running away. Empty when it reaches the window's edge, where water drains to
## open ground.
static func _hollow(h: Callable, inner: Rect2i, from: Vector2i, level: float, pond: Dictionary) -> Dictionary:
	var seen := {from: true}
	var todo: Array[Vector2i] = [from]
	while not todo.is_empty():
		var g: Vector2i = todo.pop_back()
		if not inner.has_point(g):
			return {}
		for o in NEIGHBOURS:
			var n: Vector2i = g + o
			if not seen.has(n) and not pond.has(n) and h.call(n) < level:
				seen[n] = true
				todo.append(n)
	return seen


## Grid points, lowest first.
class MinHeap:
	var keys := PackedFloat32Array()
	var values: Array[Vector2i] = []

	func empty() -> bool:
		return keys.is_empty()

	func push(k: float, v: Vector2i) -> void:
		keys.append(k)
		values.append(v)
		var i := keys.size() - 1
		while i > 0:
			var p := (i - 1) / 2
			if keys[p] <= keys[i]:
				break
			_swap(i, p)
			i = p

	func pop() -> Vector2i:
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
