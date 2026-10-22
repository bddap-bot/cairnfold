class_name Refill
extends RefCounted

## What a ponds or ground command does to the water, worked out from plain values so any thread may run it: which
## ponds fill again and how, which go, and the levels, depth texture and surfaces showing what stays. A lake is
## tens of thousands of grid points, hundreds of milliseconds of script on a headset, so `World` works a large one
## out on another thread before the command applies and applies it as this leaves it.

## Each pond's level by its grid point, as the command leaves them before any fills.
var ponds := {}
## The ponds the command puts, which win over any their water meets.
var put := {}
## Each pond's level and how it last filled, by its grid point (`World._fills`).
var fills := {}
## The ground the command changed: only ponds whose fill read it fill again.
var ground := Rect2i()
## The ground's heights the fills read, as the command leaves them.
var heights := PackedFloat32Array()

## Each pond as it fills now, or null for one holding no water.
var filled := {}
## The ponds that go: holding no water, or under the water of one the command puts or a higher one.
var gone: Array[Vector2i] = []
## The grid points under water, all ponds together.
var wet := 0
## The ponds that stay, in `ponds` order.
var found: Array[PondLayout.Pond] = []

## What `publish` leaves for `Water`: the level at every grid point, the index into `found` of the pond over each
## (-1 where none is), the grid points written, the depth texture's image and the grid points whose level changed.
var levels := PackedFloat32Array()
var owner := PackedInt32Array()
var written := PackedInt32Array()
var image: Image
var changed := Rect2i()
## Per pond in `found`, the index among the ponds shown before of the one whose water covered its bottom, else any of
## its ground, so it keeps that surface; -1 for a new one.
var covers := PackedInt32Array()


## What the ponds `levels_by_point`, `putting` among them, come to over the ground `over`, after an edit to
## `changed_ground`, where they last filled as `last`; still to be worked out (`work`).
static func of(levels_by_point: Dictionary, putting: Dictionary, last: Dictionary, changed_ground: Rect2i, over: PackedFloat32Array) -> Refill:
	var r := Refill.new()
	r.ponds = levels_by_point
	r.put = putting
	r.fills = last
	r.ground = changed_ground
	r.heights = over
	return r


## `of`, worked out.
static func make(levels_by_point: Dictionary, putting: Dictionary, last: Dictionary, changed_ground: Rect2i, over: PackedFloat32Array) -> Refill:
	var r := of(levels_by_point, putting, last, changed_ground, over)
	r.work()
	return r


## Whether this was worked out from the garden as it now stands, so applying it is applying the command.
func matches(levels_by_point: Dictionary, putting: Dictionary, last: Dictionary, changed_ground: Rect2i) -> bool:
	return ponds == levels_by_point and put == putting and fills == last and ground == changed_ground and heights == Terrain.read(Terrain.ALL)


## Fills every pond and settles which stay.
func work() -> void:
	for g: Vector2i in ponds:
		var was: Array = fills.get(g, [])
		if not was.is_empty() and was[0] == ponds[g] and not was[1].ground.intersects(ground):
			filled[g] = was[1]
		elif not was.is_empty() and was[0] == ponds[g]:
			filled[g] = _refilled(g, ponds[g], was[1])
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


## Pond `was`, at `level`, filled again over the ground as it stands, or null when none of its water is left where it
## stood: filled in, it is gone, rather than running downhill into whatever hollow holds its level.
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


## Works out what `Water` shows of `found` where it showed the ponds `shown`, their levels `before` at grid points
## `was_written` and the index into `shown` of the one over each grid point `was_owner`: each pond's level at its wet
## and shore grid points, the depth the shaders read, the surface each keeps and each new one's quads.
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
	owner.resize(Terrain.VERTS * Terrain.VERTS)
	owner.fill(-1)
	for i in found.size():
		var p := found[i]
		PondWater.quads(p)
		for g in p.cells + p.shore:
			var k := g.y * Terrain.VERTS + g.x
			levels[k] = p.level
			owner[k] = i
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
