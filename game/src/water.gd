class_name Water
extends Node3D

## Every pond, as `World` fills them (`show`). Pond levels are shared with shaders (water.gdshaderinc), so the
## bed turns to sand and drowned plants go without touching an instance. Hands that break a surface ripple it.

const RIPPLE_MOVE := 0.07
## How finely `crosses` looks for water where a pond is near.
const WADE := 0.1

## Water came, went or changed level over `area`.
signal refilled(area: Rect2)

var hands: Array[Node3D] = []
var ponds: Array[PondWater] = []
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


## The pond grid point `at` fills over the ground as it stands, with water no higher than `level`, or null; `near`
## as `PondLayout.fill` takes it.
static func fill(at: Vector2i, level: float, near := -INF) -> PondLayout.Pond:
	return PondLayout.fill(Terrain.read(Terrain.ALL), Terrain.ALL, at, level, near)


## The level a hollow pressed at (x, z) out to `radius` holds to its brim, 8 cm under the lowest point of its rim,
## as if what spilled over ran away; -INF when it holds none. On ground lower all round, water filled higher spills
## into the ground around and fills that too.
static func brim(x: float, z: float, radius: float) -> float:
	var cells := Terrain.cells_around(x, z, radius + Terrain.STEP * 2.0)
	var p := PondLayout.fill(Terrain.read(cells), cells, Terrain.grid_point(x, z))
	return p.level if p != null else -INF


## The pond that filling to the height of ground point `point` makes: of the hollows the grid points around it
## run down into, the one holding the most water. Null when none holds any.
static func pointed(point: Vector3) -> PondLayout.Pond:
	return deepest(candidates(point), point.y)


## What `deepest` fills from for a point: per hollow the grid points around it run down into, one of those
## points and the ground around it, as [grid point, window, heights].
static func candidates(point: Vector3) -> Array:
	var g := Terrain.grid_point(point.x, point.z)
	var heights := Terrain.read(Terrain.ALL)
	var out := []
	var bottoms := {}
	for o in [Vector2i.ZERO] + PondLayout.NEIGHBOURS:
		var at: Vector2i = (g + o).clamp(Vector2i.ZERO, Vector2i.ONE * Terrain.CELLS)
		var bottom := Terrain.downhill(at)
		if not bottoms.has(bottom):
			bottoms[bottom] = true
			out.append([at, Terrain.ALL, heights])
	return out


## Of `candidates`, the pond holding the most water up to `level`; reads no shared state, so any thread may run it.
static func deepest(candidates: Array, level: float) -> PondLayout.Pond:
	var best: PondLayout.Pond = null
	for c: Array in candidates:
		var p := PondLayout.fill(c[2], c[1], c[0], level)
		if p != null and (best == null or p.cells.size() > best.cells.size()):
			best = p
	return best



func reset() -> void:
	show_ponds([])


func _process(delta: float) -> void:
	if not ponds.is_empty():
		for h in hands:
			_wade(h, delta)


## Shows `found` as the ponds. A pond that covers water already shown keeps that surface and its water.
func show_ponds(found: Array[PondLayout.Pond]) -> void:
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
			Cues.play(Cues.Act.POND_FILL, Vector3(mid.x, p.level, mid.y))
		if w.pond != p:
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
			Cues.play(Cues.Act.DIP, at)
			w.at = p
			w.since = 0.0
		elif w.at.distance_to(p) > RIPPLE_MOVE and w.since >= PondWater.RIPPLE_EVERY:
			now.ripple(at, 0.45)
			w.at = p
			w.since = 0.0
	w.pond = now
