class_name Fireflies
extends Node3D

## Fireflies at dusk over what has been made: a few drift and blink over each pond's shore and each painted
## flower patch once the sun is low, in the seasons that have them. Each hovers about a spot of its own; the
## drift and the blinking run in the shader, so the CPU writes them only when the spots change. One
## MultiMesh, no lights. Part of `Wildlife`.

const CAP := 48
const PER_HABITAT := Vector2i(6, 10)
## Sun elevations in degrees over which they come out as the light goes.
const DUSK := Vector2(4.0, -3.0)
const HEIGHT := Vector2(0.25, 1.4)
## How far from a shore point over the grass, or from a bloom, they hover.
const SHORE_SPREAD := 2.2
const BLOOM_SPREAD := 1.3
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
## Starts a fade in, so a death back-dated to its fade-in's brightness still lies in the past.
var _clock := FADE
var _since := INF
var _buffer := PackedFloat32Array()


class Habitat:
	var points := PackedVector2Array()
	var spread := 0.0

	func _init(at: PackedVector2Array, reach: float) -> void:
		points = at
		spread = reach


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
	return smoothstep(DUSK.x, DUSK.y, Daylight.elevation(sky.time))


func active() -> bool:
	return dusk() > 0.0 and wildlife.palette.fireflies()


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
		if _settle(_habitats() if active() else {}):
			_upload()
	mat.set_shader_parameter("clock", _clock)
	mat.set_shader_parameter("dusk", dusk())


## Each pond and flower patch by key, with where its fireflies may hover. A pond is keyed by its shore, so a
## reshaped pond is a new habitat and its fireflies move to the new shore.
func _habitats() -> Dictionary:
	var found := {}
	for p: PondWater in wildlife.water.ponds:
		var shore := PackedVector2Array()
		for g in p.pond.shore:
			shore.append(Terrain.grid_xz(g))
		if not shore.is_empty():
			found[p.pond.shore.hash()] = Habitat.new(shore, SHORE_SPREAD)
	for key: Vector2i in wildlife.butterflies.patches:
		var blooms := PackedVector2Array()
		for b in wildlife.butterflies.patches[key]:
			blooms.append(Vector2(b.x, b.z))
		found[key] = Habitat.new(blooms, BLOOM_SPREAD)
	return found


## Spots of habitats gone start fading and faded ones are dropped; new habitats get spots, an even share of
## the cap each. True if anything changed.
func _settle(habitats: Dictionary) -> bool:
	var changed := false
	for k in spots.keys():
		var list: Array = spots[k]
		if not habitats.has(k):
			for i in list.size():
				if list[i].w > 0.0:
					_die(list, i)
					changed = true
		var kept := list.filter(func(s: Vector4) -> bool: return s.w > 0.0 or _clock + s.w < FADE)
		changed = changed or kept.size() != list.size()
		if kept.is_empty():
			spots.erase(k)
		else:
			spots[k] = kept
	var share := maxi(1, CAP / maxi(1, habitats.size()))
	var waiting := habitats.keys().any(func(k: Variant) -> bool: return not spots.has(k))
	for k in spots:
		var alive := 0
		for i in spots[k].size():
			if spots[k][i].w > 0.0:
				alive += 1
				if waiting and alive > share:
					_die(spots[k], i)
					changed = true
	for k in habitats:
		var room := CAP - count()
		if spots.has(k) or room <= 0:
			continue
		var list := []
		for i in mini(mini(rng.randi_range(PER_HABITAT.x, PER_HABITAT.y), share), room):
			list.append(_spot(habitats[k]))
		spots[k] = list
		changed = true
	return changed


## Starts spot `i` fading out from however bright its fade in had made it.
func _die(list: Array, i: int) -> void:
	list[i].w = -(_clock - FADE * (1.0 - clampf((_clock - list[i].w) / FADE, 0.0, 1.0)))


func _spot(h: Habitat) -> Vector4:
	var xz := h.points[rng.randi() % h.points.size()] + Vector2.from_angle(rng.randf() * TAU) * rng.randf() * h.spread
	var y := Terrain.height_at(xz.x, xz.y)
	var p := wildlife.water.pond_at(xz.x, xz.y)
	if p != null:
		y = maxf(y, p.surface_y())
	return Vector4(xz.x, y + rng.randf_range(HEIGHT.x, HEIGHT.y), xz.y, maxf(_clock, 1e-3))


func _upload() -> void:
	var i := 0
	for k in spots:
		for s: Vector4 in spots[k]:
			var at := i * STRIDE
			for r in 3:
				for c in 3:
					_buffer[at + r * 4 + c] = SIZE if r == c else 0.0
			_buffer[at + 3] = s.x
			_buffer[at + 7] = s.y
			_buffer[at + 11] = s.z
			_buffer[at + 12] = s.w
			_buffer[at + 13] = fposmod(s.x * 12.9898 + s.z * 78.233, 1.0) * 100.0
			_buffer[at + 14] = 0.0
			_buffer[at + 15] = 0.0
			i += 1
	mm.buffer = _buffer
	mm.visible_instance_count = i
