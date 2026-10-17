class_name Fish
extends Node3D

## A few small fish in each pond deep enough, more in a bigger one: each cruises from one deep spot of its pond
## to another just under the surface, and darts off away from a hand or the head that comes near suddenly.
## Steering only, no physics; one MultiMesh, the tail's beat and the water's tint over them in the shader. They
## fade in once their pond has filled and fade out when there are too many; a pond gone takes its own at once.
## Part of `Wildlife`.

const CAP := 24
## Wet grid points a fish.
const CELLS_EACH := 5
const PER_POND := 7
## Water shallower than this over the ground is not swum through.
const MIN_DEPTH := 0.16
## How far under the surface a fish swims, as a share of the water there, and the least and most.
const SWIM_AT := 0.2
const SWIM_DEPTH := Vector2(0.04, 0.1)
const CRUISE := 0.14
const DART := 0.75
## Per second, how quickly a dart slows back to cruising.
const CALM_DOWN := 1.6
## Radians a second the body turns to the way it swims; a fish swims straight between spots, so the way
## checked clear of walls is the way it goes.
const TURN := 6.0
const SHY := 0.55
const DART_FOR := 0.9
const ARRIVED := 0.05
const FADE := 1.5
const LENGTH := 0.24
const STRIDE := 20
const COLOURS: Array[Color] = [Color(1.0, 0.47, 0.12), Color(1.0, 0.95, 0.86), Color(1.0, 0.74, 0.18), Color(0.92, 0.3, 0.16)]

var wildlife: Wildlife
var rng := RandomNumberGenerator.new()
var mm := MultiMesh.new()
var mat := ShaderMaterial.new()
var swimming: Array[One] = []
## How many fish each pond is to have, worked out again whenever the ponds change.
var _want := {}
var _layouts := []
var _buffer := PackedFloat32Array()


class One:
	var pond: PondWater
	var at := Vector3.ZERO
	var heading := 0.0
	var speed := CRUISE
	var goal := Vector2.INF
	var dart := 0.0
	var tint := Color.WHITE
	var phase := 0.0
	var shown := 0.0
	var leaving := false


func _init(home: Wildlife, seed: int) -> void:
	wildlife = home
	rng.seed = seed
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = body()
	mm.instance_count = CAP
	mm.visible_instance_count = 0
	mm.custom_aabb = Terrain.bounds()
	_buffer.resize(CAP * STRIDE)
	var water: Shader = load("res://src/water.gdshader")
	mat.shader = load("res://src/fish.gdshader")
	for tint in ["shallow", "deep"]:
		mat.set_shader_parameter(tint, RenderingServer.shader_get_parameter_default(water.get_rid(), tint))
	mat.render_priority = 1
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## A fish LENGTH long along +z, nose at -z: a round body tapering to the tail, a tail fanned flat like a koi's
## and two side fins, so it reads from above. UV.y runs 0 at the nose to past 1 at the tail's tips, for the
## shader's tail beat; UV.x is 1 on the fins.
static func body() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := [Vector3(0.0, 0.0, -0.5), Vector3(0.5, 0.55, -0.36), Vector3(0.7, 0.85, -0.12), Vector3(0.62, 0.72, 0.12), Vector3(0.32, 0.36, 0.32), Vector3(0.1, 0.1, 0.42)]
	var sides := 8
	var r := LENGTH * 0.2
	for i in rings.size() - 1:
		for s in sides:
			var quad := []
			for k: Vector2i in [Vector2i(i, s), Vector2i(i + 1, s), Vector2i(i + 1, s + 1), Vector2i(i, s + 1)]:
				var ring: Vector3 = rings[k.x]
				var a := TAU * k.y / sides
				var n := Vector3(cos(a) * ring.y, sin(a) * ring.x, 0.0).normalized()
				quad.append([Vector3(cos(a) * ring.y * r, sin(a) * ring.x * r, ring.z * LENGTH), n, ring.z + 0.5])
			for t in [0, 1, 2, 0, 2, 3]:
				st.set_normal(quad[t][1])
				st.set_uv(Vector2(0.0, quad[t][2]))
				st.add_vertex(quad[t][0])
	var root := Vector3(0, 0, 0.4 * LENGTH)
	for side in [-1.0, 1.0]:
		for v: Vector3 in [root, Vector3(side * 0.03, 0.0, 0.5) * LENGTH, Vector3(side * 0.16, 0.0, 0.66) * LENGTH]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(1.0, v.z / LENGTH + 0.5))
			st.add_vertex(v)
		for v: Vector3 in [Vector3(side * 0.03, 0.0, 0.5) * LENGTH, Vector3(0, 0, 0.56) * LENGTH, Vector3(side * 0.16, 0.0, 0.66) * LENGTH]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(1.0, v.z / LENGTH + 0.5))
			st.add_vertex(v)
	for side in [-1.0, 1.0]:
		for v: Vector3 in [Vector3(side * 0.08, -0.02, -0.22), Vector3(side * 0.2, -0.03, -0.12), Vector3(side * 0.08, -0.02, -0.08)]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(1.0, v.z + 0.5))
			st.add_vertex(v * LENGTH)
	return st.commit()


func tick(delta: float) -> void:
	var layouts := wildlife.water.ponds.map(func(p: PondWater) -> PondLayout.Pond: return p.pond)
	if layouts != _layouts:
		_layouts = layouts
		_rehome()
	var startling: Array[Vector3] = []
	for n in wildlife._watched():
		if wildlife.sudden(n):
			startling.append(n.global_position)
	var have := {}
	for f in swimming:
		if not f.leaving:
			if have.get(f.pond, 0) >= _want.get(f.pond, 0):
				f.leaving = true
			else:
				have[f.pond] = have.get(f.pond, 0) + 1
	for p: PondWater in _want:
		if have.get(p, 0) < _want[p] and swimming.size() < CAP and p.surface_y() >= p.pond.level - 1e-3:
			var f := _spawn(p)
			if f != null:
				swimming.append(f)
	for i in range(swimming.size() - 1, -1, -1):
		var f := swimming[i]
		f.shown = clampf(f.shown + delta / FADE * (-1.0 if f.leaving else 1.0), 0.0, 1.0)
		if f.leaving and f.shown <= 0.0:
			swimming.remove_at(i)
			continue
		_swim(f, startling, delta)
	_upload()


## After the ponds change: each fish stays with the pond now under it, or goes with the water it was in; each
## pond with deep water gets a share of the cap by its size.
func _rehome() -> void:
	swimming = swimming.filter(func(f: One) -> bool:
		f.pond = wildlife.water.pond_at(f.at.x, f.at.z)
		f.goal = Vector2.INF
		return f.pond != null and _deep(f.pond, Vector2(f.at.x, f.at.z)))
	var deep := wildlife.water.ponds.filter(func(p: PondWater) -> bool: return p.pond.cells.any(func(g: Vector2i) -> bool: return _deep(p, Terrain.grid_xz(g), p)))
	_want.clear()
	var share := CAP / maxi(1, deep.size())
	for p: PondWater in deep:
		_want[p] = clampi(p.pond.cells.size() / CELLS_EACH, mini(1, share), mini(PER_POND, share))


func _spawn(p: PondWater) -> One:
	var spot := _deep_spot(p, Vector3.INF)
	if spot == Vector2.INF:
		return null
	var f := One.new()
	f.pond = p
	f.at = Vector3(spot.x, _swim_y(p, spot), spot.y)
	f.heading = rng.randf() * TAU
	f.tint = COLOURS[rng.randi() % COLOURS.size()]
	f.phase = rng.randf() * 100.0
	return f


## A grid point of `p` deep enough to swim at, reached from `from` without swimming into a wall, a little off its
## centre; Vector2.INF if none is found.
func _deep_spot(p: PondWater, from: Vector3) -> Vector2:
	var cells := p.pond.cells
	for attempt in 8:
		var xz := Terrain.grid_xz(cells[rng.randi() % cells.size()]) + Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3))
		if _deep(p, xz) and wildlife._swims_clear(from, xz):
			return xz
	return Vector2.INF


func _deep(p: PondWater, xz: Vector2, under: PondWater = null) -> bool:
	return (under if under != null else wildlife.water.pond_at(xz.x, xz.y)) == p and p.pond.level - Terrain.height_at(xz.x, xz.y) >= MIN_DEPTH


func _swim_y(p: PondWater, xz: Vector2) -> float:
	var water := p.pond.level - Terrain.height_at(xz.x, xz.y)
	return p.pond.level - clampf(water * SWIM_AT, SWIM_DEPTH.x, SWIM_DEPTH.y)


func _swim(f: One, startling: Array[Vector3], delta: float) -> void:
	var here := Vector2(f.at.x, f.at.z)
	if f.dart <= 0.0:
		for n in startling:
			if f.at.distance_to(n) < SHY:
				var away := here - Vector2(n.x, n.z)
				var spot := _flee_spot(f, away.normalized() if away.length() > 1e-3 else Vector2.from_angle(rng.randf() * TAU))
				if spot != Vector2.INF:
					f.goal = spot
					f.dart = DART_FOR
					f.speed = DART
				break
	f.dart -= delta
	if f.dart <= 0.0:
		f.speed = lerpf(f.speed, CRUISE, 1.0 - exp(-delta * CALM_DOWN))
	if f.goal == Vector2.INF or here.distance_to(f.goal) < ARRIVED:
		f.goal = _deep_spot(f.pond, f.at)
		if f.goal == Vector2.INF:
			return
	var to := f.goal - here
	var next := here + to.limit_length(f.speed * delta)
	if not _deep(f.pond, next):
		f.goal = Vector2.INF
		return
	var want := atan2(to.x, to.y)
	f.heading += clampf(wrapf(want - f.heading, -PI, PI), -TURN * delta, TURN * delta)
	f.at = Vector3(next.x, lerpf(f.at.y, _swim_y(f.pond, next), 1.0 - exp(-delta * 2.0)), next.y)


## Somewhere deep a metre or so along `dir` from `f`, or turned a little off it; Vector2.INF if nowhere is.
func _flee_spot(f: One, dir: Vector2) -> Vector2:
	for attempt in 6:
		var xz := Vector2(f.at.x, f.at.z) + dir.rotated(rng.randf_range(-0.9, 0.9)) * rng.randf_range(0.6, 1.2)
		if _deep(f.pond, xz) and wildlife._swims_clear(f.at, xz):
			return xz
	return Vector2.INF


func _upload() -> void:
	for i in swimming.size():
		var f := swimming[i]
		var b := Basis(Vector3.UP, f.heading + PI)
		var at := i * STRIDE
		for r in 3:
			for c in 3:
				_buffer[at + r * 4 + c] = b[c][r]
		_buffer[at + 3] = f.at.x
		_buffer[at + 7] = f.at.y
		_buffer[at + 11] = f.at.z
		_buffer[at + 12] = f.tint.r
		_buffer[at + 13] = f.tint.g
		_buffer[at + 14] = f.tint.b
		_buffer[at + 15] = 1.0
		_buffer[at + 16] = f.phase
		_buffer[at + 17] = f.speed / CRUISE
		_buffer[at + 18] = f.shown
		_buffer[at + 19] = 0.0
	if not swimming.is_empty() or mm.visible_instance_count > 0:
		mm.buffer = _buffer
	mm.visible_instance_count = swimming.size()
