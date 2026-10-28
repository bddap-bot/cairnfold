class_name Water
extends Node3D

## Every pond, as `World` fills them (`show`). Pond levels are shared with shaders (water.gdshaderinc), so the
## bed turns to sand and the meadow's drowned grass and flowers go without touching an instance. Hands that break a
## surface ripple it.

const RIPPLE_MOVE := 0.07
## Water deeper than this over a plant's root drowns it, as water.gdshaderinc's `drowned` reads it.
const DROWNS := 0.02
## How finely `crosses` looks for water where a pond is near.
const WADE := 0.1

## Water came, went or changed level over `area`.
signal refilled(area: Rect2)

var hands: Array[Node3D] = []
var terrain: Terrain
var ponds: Array[PondWater] = []
## Index into `ponds` of the pond over each grid point, wet or shore; -1 elsewhere.
var _owner := PackedInt32Array()
## The grid points `_owner` and the levels were last written at.
var _written := PackedInt32Array()
var _wet := {}
## Fills worked out ahead of a command on another thread, as [heights, grid point, level, near, pond], for `fill`.
static var _known: Array = []


## A hand's last contact with the water.
class Wade:
	var pond: PondWater
	var at := Vector3.ZERO
	var since := 0.0


func _init(ground: Terrain, touching: Array[Node3D]) -> void:
	terrain = ground
	hands = touching
	_owner.resize(Terrain.VERTS * Terrain.VERTS)
	_owner.fill(-1)
	terrain.dry_water()


## The pond grid point `at` fills over `ground` as it stands, with water no higher than `level`, or null; `near`
## as `PondLayout.fill` takes it.
static func fill(ground: Terrain, at: Vector2i, level: float, near := -INF) -> PondLayout.Pond:
	var heights := ground.read(Terrain.ALL)
	for k: Array in _known:
		if k[1] == at and k[2] == level and k[3] == near and k[0] == heights:
			return k[4]
	return PondLayout.fill(heights, Terrain.ALL, at, level, near)


## Keeps `known` ([heights, grid point, level, near, pond] each) for `fill`, in place of those kept before.
static func know(known: Array) -> void:
	_known = known


## The level a hollow pressed into `ground` at (x, z) out to `radius` holds to its brim, 8 cm under the lowest point
## of its rim, as if what spilled over ran away; -INF when it holds none. On ground lower all round, water filled
## higher spills into the ground around and fills that too.
static func brim(ground: Terrain, x: float, z: float, radius: float) -> float:
	var cells := Terrain.cells_around(x, z, radius + Terrain.STEP * 2.0)
	var p := PondLayout.fill(ground.read(cells), cells, Terrain.grid_point(x, z))
	return p.level if p != null else -INF


## The pond that filling to the height of `ground`'s point `point` makes: of the hollows the grid points around it
## run down into, the one holding the most water. Null when none holds any.
static func pointed(ground: Terrain, point: Vector3) -> PondLayout.Pond:
	return deepest(candidates(ground, point), point.y)


## What `deepest` fills from for a point of `ground`: per hollow the grid points around it run down into, one of
## those points and the ground around it, as [grid point, window, heights].
static func candidates(ground: Terrain, point: Vector3) -> Array:
	var g := Terrain.grid_point(point.x, point.z)
	var heights := ground.read(Terrain.ALL)
	var out := []
	var bottoms := {}
	for o in [Vector2i.ZERO] + PondLayout.NEIGHBOURS:
		var at: Vector2i = (g + o).clamp(Vector2i.ZERO, Vector2i.ONE * Terrain.CELLS)
		var bottom := ground.downhill(at)
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



func clear() -> void:
	show_ponds([])


func _process(delta: float) -> void:
	if not ponds.is_empty():
		for h in hands:
			_wade(h, delta)


## What `Refill.publish` works out from: the ponds shown, the grid points their levels were written at and the index
## of the one over each grid point.
func shown() -> Array[PondLayout.Pond]:
	var out: Array[PondLayout.Pond] = []
	for w in ponds:
		out.append(w.pond)
	return out


func written() -> PackedInt32Array:
	return _written


func owners() -> PackedInt32Array:
	return _owner


## Shows `found` as the ponds, as `refill` worked out when it has (Refill.publish). A pond that covers water already
## shown keeps that surface and its water.
func show_ponds(found: Array[PondLayout.Pond], refill: Refill = null) -> void:
	if refill == null or refill.image == null:
		refill = Refill.new()
		refill.found = found
		refill.heights = terrain.read(Terrain.ALL)
		refill.publish(terrain.water_levels(), _written, _owner, shown())
	var was := ponds
	var old := ponds.duplicate()
	ponds = []
	for n in found.size():
		var p := found[n]
		var w: PondWater = was[refill.covers[n]] if refill.covers[n] >= 0 else null
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
	_owner = refill.owner
	_written = refill.written
	terrain.set_water(refill.levels, refill.image)
	if refill.changed.has_area():
		refilled.emit(Terrain.world_rect(refill.changed.grow_individual(0, 0, 1, 1)))


static func drowned(ground: Terrain, at: Vector3) -> bool:
	return ground.depth_at(at.x, at.z) > DROWNS


func floor_at(p: Vector3) -> float:
	var ground := terrain.height_at(p.x, p.z)
	var pond := pond_at(p.x, p.z)
	return maxf(ground, pond.surface_y()) if pond != null else ground


## The pond whose water is over (x, z), or null.
func pond_at(x: float, z: float) -> PondWater:
	var g := Terrain.grid_point(x, z)
	var i := _owner[g.y * Terrain.VERTS + g.x]
	if i < 0 or terrain.height_at(x, z) >= ponds[i].pond.level:
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
