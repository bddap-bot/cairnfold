class_name Underwater
extends MeshInstance3D

## What an eye under a pond's surface sees and hears besides the surface itself, which the water shader draws from
## below: Look's fog closes in blue-green with red gone first, sunken stone takes the caustics, shafts of sunlight come
## down through the surface, motes and a few bubbles drift about the head, and the whole mix is muffled. Above water
## none of it is drawn or run.

const MOTES := 160
## One mote in this many is a bubble, rising.
const BUBBLE_EVERY := 8
const SHAFTS := 10
## Motes fill a box this many metres either way of the head; shafts stand over a box half again as wide.
const REACH := 3.0
const MUFFLE_HZ := 650.0
const MUFFLE_DB := -4.0
const WATER_IOR := 1.333

var water: Water
var look: Look
var _mat := ShaderMaterial.new()
var _muffle := AudioEffectLowPassFilter.new()
var _volume_db := 0.0


func _init(ponds: Water, light: Look) -> void:
	water = ponds
	look = light
	mesh = _kit()
	_mat.shader = load("res://src/underwater.gdshader")
	_mat.render_priority = 2
	_mat.set_shader_parameter("reach", REACH)
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Every piece is placed about the head in the vertex shader.
	custom_aabb = AABB(-Vector3.ONE * REACH * 4.0, Vector3.ONE * REACH * 8.0)
	top_level = true
	visible = false
	_muffle.cutoff_hz = MUFFLE_HZ


func _enter_tree() -> void:
	AudioServer.add_bus_effect(0, _muffle)
	AudioServer.set_bus_effect_enabled(0, _muffle_index(), false)


func _exit_tree() -> void:
	if visible:
		_submerge(false)
	AudioServer.remove_bus_effect(0, _muffle_index())


func _muffle_index() -> int:
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) == _muffle:
			return i
	return -1


func _process(_delta: float) -> void:
	var eye := get_viewport().get_camera_3d()
	var pond: PondWater = null if eye == null else water.pond_at(eye.global_position.x, eye.global_position.z)
	var under := pond != null and eye.global_position.y < pond.surface_y()
	if under != visible:
		_submerge(under)
	if under:
		global_position = eye.global_position
		var l := Daylight.light(look.time)
		var sun: Color = l.sun * l.energy
		_mat.set_shader_parameter("level", pond.surface_y())
		_mat.set_shader_parameter("ray", into_water(-Daylight.toward_sun(look.time)))
		_mat.set_shader_parameter("sun", Vector3(sun.r, sun.g, sun.b))
		_mat.set_shader_parameter("ambient", Vector3(Look.UNDER_FOG.r, Look.UNDER_FOG.g, Look.UNDER_FOG.b) * Look.under_light(l))


## Sunlight travelling `way` (downward) bends toward straight down as it enters the water (Snell's law).
static func into_water(way: Vector3) -> Vector3:
	var d := Vector3(way.x, minf(way.y, -0.05), way.z).normalized()
	var eta := 1.0 / WATER_IOR
	var c := -d.y
	return (d * eta + Vector3.UP * (eta * c - sqrt(1.0 - eta * eta * (1.0 - c * c)))).normalized()


func _submerge(on: bool) -> void:
	visible = on
	look.submerge(on)
	RenderingServer.global_shader_parameter_set("eye_under", 1.0 if on else 0.0)
	var i := _muffle_index()
	if i >= 0:
		AudioServer.set_bus_effect_enabled(0, i, on)
	if on:
		_volume_db = AudioServer.get_bus_volume_db(0)
	AudioServer.set_bus_volume_db(0, _volume_db + MUFFLE_DB if on else _volume_db)


## Every mote and shaft as a quad of four corners at one point: COLOR.r its kind (0 a mote, 0.5 a bubble, 1 a shaft),
## g its phase, b its size; the vertex shader spreads the corners.
static func _kit() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var index := PackedInt32Array()
	for i in MOTES + SHAFTS:
		var kind := 1.0 if i >= MOTES else (0.5 if i % BUBBLE_EVERY == 0 else 0.0)
		var at := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * REACH
		var c := Color(kind, rng.randf(), rng.randf())
		var n := verts.size()
		for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
			verts.append(at)
			uvs.append(corner)
			colors.append(c)
		index.append_array([n, n + 1, n + 2, n, n + 2, n + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = index
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m
