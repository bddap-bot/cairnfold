class_name Fish
extends Node3D

## A few small fish in each pond, more in a bigger one: each cruises from one deep spot of its pond to another
## just under the surface, and darts off away from a hand or the head that comes near. Steering only, no physics;
## one MultiMesh, the tail's beat in the shader. Part of `Wildlife`.

const CAP := 24
## Wet grid points a fish.
const CELLS_EACH := 5
const PER_POND := Vector2i(2, 7)
## Water shallower than this over the ground is not swum through.
const MIN_DEPTH := 0.16
## How far under the surface a fish swims, as a share of the water there, and the least and most.
const SWIM_AT := 0.2
const SWIM_DEPTH := Vector2(0.04, 0.1)
const CRUISE := 0.14
const DART := 0.75
## Per second, how quickly a dart slows back to cruising.
const CALM_DOWN := 1.6
## Radians a second it turns at cruise; darting it turns faster.
const TURN := 1.8
const SHY := 0.55
const DART_FOR := 0.9
const ARRIVED := 0.2
const LENGTH := 0.24
const STRIDE := 20
const COLOURS: Array[Color] = [Color(1.0, 0.47, 0.12), Color(1.0, 0.95, 0.86), Color(1.0, 0.74, 0.18), Color(0.92, 0.3, 0.16)]

var wildlife: Wildlife
var rng := RandomNumberGenerator.new()
var mm := MultiMesh.new()
var mat := ShaderMaterial.new()
## Fish by the bottom grid point of their pond; dug wider, a pond may get a new bottom and its fish follow.
var schools := {}
var _buffer := PackedFloat32Array()


class One:
	var at := Vector3.ZERO
	var heading := 0.0
	var speed := CRUISE
	var goal := Vector2.ZERO
	var dart := 0.0
	var tint := Color.WHITE
	var phase := 0.0


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
	mat.shader = load("res://src/fish.gdshader")
	mat.shader.get_rid()
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


func count() -> int:
	var n := 0
	for k in schools:
		n += schools[k].size()
	return n


func tick(delta: float) -> void:
	var ponds := {}
	for p: PondWater in wildlife.water.ponds:
		ponds[p.pond.bottom] = p
	for k in schools.keys():
		if ponds.has(k):
			continue
		var list: Array = schools[k]
		schools.erase(k)
		var now := wildlife.water.pond_at(list[0].at.x, list[0].at.z)
		if now != null:
			schools[now.pond.bottom] = schools.get(now.pond.bottom, []) + list
	for k in ponds:
		var p: PondWater = ponds[k]
		var want := clampi(p.pond.cells.size() / CELLS_EACH, PER_POND.x, PER_POND.y)
		var list: Array = schools.get(k, [])
		while list.size() > want:
			list.pop_back()
		while list.size() < want and count() + 1 <= CAP:
			var f := _spawn(p)
			if f == null:
				break
			list.append(f)
		if list.is_empty():
			schools.erase(k)
		else:
			schools[k] = list
		for f: One in list:
			_swim(f, p, delta)
	_upload()


func _spawn(p: PondWater) -> One:
	var spot := _deep_spot(p, Vector3.INF)
	if spot == Vector2.INF:
		return null
	var f := One.new()
	f.at = Vector3(spot.x, _swim_y(p, spot), spot.y)
	f.heading = rng.randf() * TAU
	f.goal = _deep_spot(p, f.at)
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


func _deep(p: PondWater, xz: Vector2) -> bool:
	return wildlife.water.pond_at(xz.x, xz.y) == p and p.pond.level - Terrain.height_at(xz.x, xz.y) >= MIN_DEPTH


func _swim_y(p: PondWater, xz: Vector2) -> float:
	var water := p.pond.level - Terrain.height_at(xz.x, xz.y)
	return p.surface_y() - clampf(water * SWIM_AT, SWIM_DEPTH.x, SWIM_DEPTH.y)


func _swim(f: One, p: PondWater, delta: float) -> void:
	var near := wildlife._nearest(f.at, SHY)
	if near != null and f.dart <= 0.0:
		var away := Vector2(f.at.x - near.global_position.x, f.at.z - near.global_position.z)
		var dir := away.normalized() if away.length() > 1e-3 else Vector2.from_angle(rng.randf() * TAU)
		var spot := _flee_spot(p, f, dir)
		if spot != Vector2.INF:
			f.goal = spot
			f.dart = DART_FOR
			f.speed = DART
	f.dart -= delta
	f.speed = lerpf(f.speed, CRUISE, 1.0 - exp(-delta * CALM_DOWN)) if f.dart <= 0.0 else f.speed
	var here := Vector2(f.at.x, f.at.z)
	if here.distance_to(f.goal) < ARRIVED or f.goal == Vector2.INF:
		f.goal = _deep_spot(p, f.at)
		if f.goal == Vector2.INF:
			return
	var to := f.goal - here
	var want := atan2(to.x, to.y)
	var turn := TURN * (f.speed / CRUISE) * delta
	f.heading += clampf(wrapf(want - f.heading, -PI, PI), -turn, turn)
	var next := here + Vector2(sin(f.heading), cos(f.heading)) * f.speed * delta
	if not _deep(p, next):
		f.goal = _deep_spot(p, f.at)
		f.speed = minf(f.speed, CRUISE)
		return
	f.at = Vector3(next.x, lerpf(f.at.y, _swim_y(p, next), 1.0 - exp(-delta * 2.0)), next.y)


## Somewhere deep a metre or so along `dir` from `f`, or turned a little off it; Vector2.INF if nowhere is.
func _flee_spot(p: PondWater, f: One, dir: Vector2) -> Vector2:
	for attempt in 6:
		var xz := Vector2(f.at.x, f.at.z) + dir.rotated(rng.randf_range(-0.9, 0.9)) * rng.randf_range(0.6, 1.2)
		if _deep(p, xz) and wildlife._swims_clear(f.at, xz):
			return xz
	return Vector2.INF


func _upload() -> void:
	var i := 0
	for k in schools:
		for f: One in schools[k]:
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
			_buffer[at + 18] = 0.0
			_buffer[at + 19] = 0.0
			i += 1
	if i > 0 or mm.visible_instance_count > 0:
		mm.buffer = _buffer
	mm.visible_instance_count = i
