class_name Refill
extends RefCounted

## Plain values only, so any thread may run it: a lake is tens of thousands of grid points, hundreds of milliseconds of
## script on a headset, so `World` works a large one out off-thread before its command applies.

## Level by grid point, before any fills.
var ponds := {}
## Win over any pond their water meets.
var put := {}
## [level, Pond it last filled as] by grid point (`World._fills`).
var fills := {}
## Only ponds whose fill read this ground fill again.
var ground := Rect2i()
var heights := PackedFloat32Array()

## Null for a pond holding no water.
var filled := {}
## Holding no water, or under the water of one put or higher.
var gone: Array[Vector2i] = []
## Grid points under water, all ponds.
var wet := 0
## In `ponds` order.
var found: Array[PondLayout.Pond] = []

var levels := PackedFloat32Array()
## Index into `found` of the pond over each grid point, -1 where none.
var owners := PackedInt32Array()
var written := PackedInt32Array()
var image: Image
## Grid points whose level changed.
var changed := Rect2i()
## Per pond in `found`, the index of the shown pond whose water covered its bottom or ground, -1 for a new one.
var covers := PackedInt32Array()


static func of(levels_by_point: Dictionary, putting: Dictionary, last: Dictionary, changed_ground: Rect2i, over: PackedFloat32Array) -> Refill:
	var r := Refill.new()
	r.ponds = levels_by_point
	r.put = putting
	r.fills = last
	r.ground = changed_ground
	r.heights = over
	return r


static func make(levels_by_point: Dictionary, putting: Dictionary, last: Dictionary, changed_ground: Rect2i, over: PackedFloat32Array) -> Refill:
	var r := of(levels_by_point, putting, last, changed_ground, over)
	r.work()
	return r


func matches(levels_by_point: Dictionary, putting: Dictionary, last: Dictionary, changed_ground: Rect2i, over: PackedFloat32Array) -> bool:
	return ponds == levels_by_point and put == putting and fills == last and ground == changed_ground and heights == over


func work() -> void:
	for g: Vector2i in ponds:
		var was: Array = fills.get(g, [])
		if not was.is_empty() and was[0] == ponds[g]:
			filled[g] = _refilled(g, ponds[g], was[1]) if was[1].ground.intersects(ground) else was[1]
		else:
			filled[g] = PondLayout.fill(heights, Terrain.ALL, g, ponds[g], was[1].level if not was.is_empty() else -INF)
	var order: Array = ponds.keys()
	order.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if put.has(a) != put.has(b):
			return put.has(a)
		var la: float = filled[a].level if filled[a] != null else -INF
		var lb: float = filled[b].level if filled[b] != null else -INF
		return la > lb if la != lb else a.y < b.y or a.y == b.y and a.x < b.x)
	var taken := PackedByteArray()
	taken.resize(Terrain.VERTS * Terrain.VERTS)
	var boxes: Array[Rect2i] = []
	for g in order:
		var p: PondLayout.Pond = filled[g]
		if p == null or boxes.any(func(b: Rect2i) -> bool: return b.intersects(p.box)) and _covered(p, taken):
			gone.append(g)
			continue
		boxes.append(p.box)
		for c in p.cells:
			taken[c.y * Terrain.VERTS + c.x] = 1
		wet += p.cells.size()
	for g in ponds:
		if not g in gone:
			found.append(filled[g])


static func _covered(p: PondLayout.Pond, taken: PackedByteArray) -> bool:
	for c in p.cells:
		if taken[c.y * Terrain.VERTS + c.x]:
			return true
	return false


## Null when none of its water is left where it stood: filled in, it is gone, not run downhill to another hollow.
func _refilled(g: Vector2i, level: float, was: PondLayout.Pond) -> PondLayout.Pond:
	var p := PondLayout.fill(heights, Terrain.ALL, g, level, was.level)
	if p == null:
		return null
	var wet_now := PackedByteArray()
	wet_now.resize(Terrain.VERTS * Terrain.VERTS)
	for c in p.cells:
		wet_now[c.y * Terrain.VERTS + c.x] = 1
	for c in was.cells:
		if wet_now[c.y * Terrain.VERTS + c.x]:
			return p
	return null


## `was_owner`: the index into `shown` of the pond over each grid point, -1 where none.
func publish(before: PackedFloat32Array, was_written: PackedInt32Array, was_owner: PackedInt32Array, shown: Array[PondLayout.Pond]) -> void:
	var kept := {}
	for p in found:
		var at := -1
		for g in [p.bottom] + p.cells:
			var i := was_owner[g.y * Terrain.VERTS + g.x]
			if i >= 0 and not kept.has(i) and g in shown[i].cells:
				at = i
				break
		kept[at] = true
		covers.append(at)
	levels = before.duplicate()
	for k in was_written:
		levels[k] = Terrain.NO_WATER
	owners.resize(Terrain.VERTS * Terrain.VERTS)
	owners.fill(-1)
	for i in found.size():
		var p := found[i]
		PondWater.quads(p)
		for g in p.cells + p.shore:
			var k := g.y * Terrain.VERTS + g.x
			levels[k] = p.level
			owners[k] = i
			written.append(k)
	var lo := Vector2i(Terrain.VERTS, Terrain.VERTS)
	var hi := Vector2i(-1, -1)
	for k in was_written + written:
		if absf(levels[k] - before[k]) >= 1e-4:
			var g := Vector2i(k % Terrain.VERTS, k / Terrain.VERTS)
			lo = lo.min(g)
			hi = hi.max(g)
	if hi.x >= 0:
		changed = Rect2i(lo, hi - lo + Vector2i.ONE)
	image = Terrain.depth_image(levels, heights, written)
