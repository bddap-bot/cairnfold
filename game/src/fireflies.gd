class_name Fireflies
extends Node3D

## Fireflies at dusk over what has been made: a few drift and blink over each pond and each painted flower
## patch once the sun is low, in spring and summer. Each hovers about a spot of its own; the drift and the
## blinking run in the shader, so the CPU writes them only when the spots change. One MultiMesh, no lights.
## Part of `Wildlife`.

const CAP := 48
const PER_HABITAT := Vector2i(6, 10)
## Sun elevations in degrees over which they come out as the light goes.
const DARK := Vector2(4.0, -3.0)
const SEASONS := [0, 1, 2]
const HEIGHT := Vector2(0.25, 1.4)
## How far from a pond's shore over the grass, or from a patch's centre, they hover.
const SPREAD := 2.2
const FADE := 2.0
const REFRESH := 1.0
const SIZE := 0.22
const STRIDE := 16

var wildlife: Wildlife
var sky: Look
var rng := RandomNumberGenerator.new()
var mm := MultiMesh.new()
var mat := ShaderMaterial.new()
## Spots by habitat key: each a Vector4 of position and the clock time it came, or went if negative.
var spots := {}
var _clock := 0.0
var _since := INF
var _buffer := PackedFloat32Array()


func _init(home: Wildlife, light: Look, seed: int) -> void:
	wildlife = home
	sky = light
	rng.seed = seed
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	mm.mesh = quad
	mm.instance_count = CAP
	mm.visible_instance_count = 0
	mm.custom_aabb = Terrain.bounds()
	_buffer.resize(CAP * STRIDE)
	mat.shader = load("res://src/firefly.gdshader")
	mat.set_shader_parameter("fade", FADE)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## 0 in daylight to 1 once the sun is well down.
func dusk() -> float:
	if sky == null:
		return 0.0
	return smoothstep(DARK.x, DARK.y, Daylight.elevation(sky.time))


func active() -> bool:
	return dusk() > 0.0 and SEASONS.has(wildlife.palette.picks[Palette.Element.MEADOW])


func count() -> int:
	var n := 0
	for k in spots:
		n += spots[k].size()
	return n


func tick(delta: float) -> void:
	_clock += delta
	_since += delta
	if not active() and spots.is_empty():
		mm.visible_instance_count = 0
		return
	if _since >= REFRESH:
		_since = 0.0
		_settle(_habitats() if active() else {})
		_upload()
	mat.set_shader_parameter("clock", _clock)
	mat.set_shader_parameter("dusk", dusk())


## Each pond and flower patch, by key, with where its fireflies may hover: shore points or the patch's blooms.
func _habitats() -> Dictionary:
	var found := {}
	for p: PondWater in wildlife.water.ponds:
		if not p.pond.shore.is_empty():
			found[p] = p.pond.shore
	for key in wildlife.butterflies.patches:
		found[key] = wildlife.butterflies.patches[key]
	return found


## Habitats that are new get their spots; spots of habitats gone start fading; faded ones are dropped.
func _settle(habitats: Dictionary) -> void:
	for k in spots.keys():
		var list: Array = spots[k]
		if not habitats.has(k):
			for i in list.size():
				if list[i].w > 0.0:
					list[i].w = -_clock
		list = list.filter(func(s: Vector4) -> bool: return s.w > 0.0 or _clock + s.w < FADE)
		if list.is_empty():
			spots.erase(k)
		else:
			spots[k] = list
	for k in habitats:
		if spots.has(k) or count() >= CAP:
			continue
		var list := []
		for i in mini(rng.randi_range(PER_HABITAT.x, PER_HABITAT.y), CAP - count()):
			list.append(_spot(habitats[k]))
		spots[k] = list


func _spot(around: Variant) -> Vector4:
	var a: Variant = around[rng.randi() % around.size()]
	var xz := Terrain.grid_xz(a) if a is Vector2i else Vector2(a.x, a.z)
	var off := Vector2.from_angle(rng.randf() * TAU) * rng.randf() * SPREAD * (1.0 if a is Vector2i else 0.6)
	xz += off
	var y := Terrain.height_at(xz.x, xz.y)
	var p := wildlife.water.pond_at(xz.x, xz.y)
	if p != null:
		y = maxf(y, p.surface_y())
	return Vector4(xz.x, y + rng.randf_range(HEIGHT.x, HEIGHT.y), xz.y, maxf(_clock, 1e-3))


func _upload() -> void:
	var i := 0
	for k in spots:
		for s: Vector4 in spots[k]:
			var k4 := i * STRIDE
			for r in 3:
				for c in 3:
					_buffer[k4 + r * 4 + c] = SIZE if r == c else 0.0
			_buffer[k4 + 3] = s.x
			_buffer[k4 + 7] = s.y
			_buffer[k4 + 11] = s.z
			_buffer[k4 + 12] = s.w
			_buffer[k4 + 13] = fposmod(s.x * 12.9898 + s.z * 78.233, 1.0) * 100.0
			_buffer[k4 + 14] = 0.0
			_buffer[k4 + 15] = 0.0
			i += 1
	mm.buffer = _buffer
	mm.visible_instance_count = i
