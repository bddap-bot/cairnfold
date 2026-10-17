class_name Water
extends Node3D

## Every pond. Each dig leaves a seed; after any settled edit to the ground the basin below each seed
## fills to just under its spill point (PondLayout). Pond levels are shared with shaders
## (water.gdshaderinc), so the bed turns to sand and drowned plants go without touching an instance.
## Hands that break a surface ripple it.

const RIPPLE_MOVE := 0.07
## How finely `crosses` looks for water where a pond is near.
const WADE := 0.1

signal splashed(kind: StringName, at: Vector3)
## Water came, went or changed level over `area`.
signal refilled(area: Rect2)

var hands: Array[Node3D] = []
var ponds: Array[PondWater] = []
var _seeds: Array[Vector2i] = []
var _dirty := false
## Index into `ponds` of the pond over each grid point, wet or shore; -1 elsewhere.
var _owner := PackedInt32Array()
var _written: Array[Vector2i] = []
var _wet := {}


## A hand's last contact with the water.
class Wade:
	var pond: PondWater
	var at := Vector3.ZERO
	var since := 0.0


func _init(touching: Array[Node3D]) -> void:
	hands = touching
	_owner.resize(Terrain.VERTS * Terrain.VERTS)
	_owner.fill(-1)
	Terrain.dry_water()
	PondWater.prepare()


func add_seed(g: Vector2i) -> void:
	_seeds.append(g)
	_dirty = true


func remove_seed(g: Vector2i) -> void:
	_seeds.erase(g)
	_dirty = true


func reset() -> void:
	_seeds.clear()
	_dirty = true


func reground(_area: Rect2, settled: bool) -> void:
	_dirty = _dirty or (settled and not _seeds.is_empty())


func _process(delta: float) -> void:
	if _dirty:
		refill()
	if not ponds.is_empty():
		for h in hands:
			_wade(h, delta)


## Fills the basin below every seed. A pond that covers water already shown keeps that surface and its water.
func refill() -> void:
	_dirty = false
	var filled: Array[PondLayout.Pond] = []
	for g in _seeds:
		var window := Rect2i(g - Vector2i.ONE * PondLayout.REACH, Vector2i.ONE * (PondLayout.REACH * 2 + 1)).intersection(Rect2i(0, 0, Terrain.VERTS, Terrain.VERTS))
		var p := PondLayout.fill(Terrain.read(window), window, g)
		if p != null:
			filled.append(p)
	# Seeds see the ground through their own windows, so two may disagree on whether a neighbouring hollow
	# drains; the higher, fuller pond wins and nothing is covered twice.
	filled.sort_custom(func(a: PondLayout.Pond, b: PondLayout.Pond) -> bool: return a.level > b.level)
	var found: Array[PondLayout.Pond] = []
	var taken := {}
	for p in filled:
		if p.cells.any(func(c: Vector2i) -> bool: return taken.has(c)):
			continue
		for c in p.cells:
			taken[c] = true
		found.append(p)
	var shown := ponds
	var old := ponds.duplicate()
	ponds = []
	for p in found:
		var w := _covering(p, shown)
		old.erase(w)
		if w == null:
			w = PondWater.new()
			add_child(w)
			var mid := Terrain.grid_xz(p.bottom)
			splashed.emit(&"fill", Vector3(mid.x, p.level, mid.y))
		w.show_pond(p)
		ponds.append(w)
	for w in old:
		w.queue_free()
	_publish()


## The surface in `shown` whose water covered `p`'s bottom, else any of its ground, before this refill.
func _covering(p: PondLayout.Pond, shown: Array[PondWater]) -> PondWater:
	for g in [p.bottom] + p.cells:
		var i := _owner[g.y * Terrain.VERTS + g.x]
		if i >= 0 and not ponds.has(shown[i]) and g in shown[i].pond.cells:
			return shown[i]
	return null


## Writes each pond's level at its wet and shore grid points, for `pond_at`, the shaders and what stands in it.
func _publish() -> void:
	var changed := {}
	for g in _written:
		_owner[g.y * Terrain.VERTS + g.x] = -1
		changed[g] = Terrain.NO_WATER
	_written.clear()
	for i in ponds.size():
		var p := ponds[i].pond
		for g in p.cells + p.shore:
			_owner[g.y * Terrain.VERTS + g.x] = i
			changed[g] = p.level
			_written.append(g)
	for g in changed.keys():
		if absf(Terrain.water_level(g) - changed[g]) < 1e-4:
			changed.erase(g)
	if changed.is_empty():
		return
	Terrain.set_water(changed)
	var cells := Rect2i(changed.keys()[0], Vector2i.ONE)
	for g in changed:
		cells = cells.expand(g)
	refilled.emit(Terrain.world_rect(cells.grow_individual(0, 0, 1, 1)))


## The ground under `p`, or the water over it.
func floor_at(p: Vector3) -> float:
	var ground := Terrain.height_at(p.x, p.z)
	var pond := pond_at(p.x, p.z)
	return maxf(ground, pond.surface_y()) if pond != null else ground


## The pond whose water is over (x, z), or null.
func pond_at(x: float, z: float) -> PondWater:
	var g := Terrain.grid_point(x, z)
	var i := _owner[g.y * Terrain.VERTS + g.x]
	if i < 0 or Terrain.height_at(x, z) >= ponds[i].pond.level:
		return null
	return ponds[i]


## Whether a straight way across the ground from `a` to `b` goes into water, as `pond_at` finds it every WADE
## metres. Only the grid squares a pond reaches are looked at that closely, so a way over dry ground costs one
## step a square. Water the way starts in does not count until the way has left it.
func crosses(a: Vector2, b: Vector2) -> bool:
	var length := a.distance_to(b)
	if length < 1e-4:
		return false
	var dir := (b - a) / length
	var dry := pond_at(a.x, a.y) == null
	var t := 0.0
	while t < length:
		var p := a + dir * t
		var g := Terrain.grid_point(p.x, p.y)
		var centre := Terrain.grid_xz(g)
		var out := INF
		for axis in 2:
			if absf(dir[axis]) > 1e-6:
				out = minf(out, (centre[axis] + signf(dir[axis]) * Terrain.STEP * 0.5 - p[axis]) / dir[axis])
		var end := minf(t + maxf(out, 0.0) + 1e-3, length)
		if _owner[g.y * Terrain.VERTS + g.x] < 0:
			dry = true
		else:
			var s := t
			while s < end:
				s = minf(s + WADE, end)
				var q := a + dir * s
				var wet := pond_at(q.x, q.y) != null
				if wet and dry:
					return true
				dry = dry or not wet
		t = end
	return false


## A hand dipping into a pond, or moving through its surface, rings out a ripple; entering it plays a dip.
func _wade(hand: Node3D, delta: float) -> void:
	var p := hand.global_position
	var w: Wade = _wet.get(hand)
	if w == null:
		w = Wade.new()
		_wet[hand] = w
	var now := pond_at(p.x, p.z)
	if now != null and absf(p.y - now.surface_y()) > 0.08:
		now = null
	w.since += delta
	if now != null:
		var at := Vector3(p.x, now.surface_y(), p.z)
		if not is_instance_valid(w.pond) or w.pond != now:
			now.ripple(at, 1.0)
			splashed.emit(&"dip", at)
			w.at = p
			w.since = 0.0
		elif w.at.distance_to(p) > RIPPLE_MOVE and w.since >= PondWater.RIPPLE_EVERY:
			now.ripple(at, 0.45)
			w.at = p
			w.since = 0.0
	w.pond = now
