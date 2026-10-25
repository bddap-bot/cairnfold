class_name Underfoot
extends Node3D

## While the player floats, a faint ring at the floor they float on and a soft shadow on the ground below, both by
## height alone: standing on nothing tens of metres up is the classic trigger of fear of heights and of lost balance.

## Per-build: whether they show at all. Over the stress garden from 8 m up they cost the Quest 2 0.35 ms of GPU time.
const SHOWN := true
## Floating this much over LIFTED shows both at full strength.
const FULL_ABOVE := 1.0
const RING := 1.2
const RING_ALPHA := 0.3
const SHADOW := 1.6
const SHADOW_ALPHA := 0.5
## How far over its floor each is drawn, clear of the ground's own surface.
const RAISE := 0.03

var _ring: MeshInstance3D
var _shadow: MeshInstance3D


func _init() -> void:
	top_level = true
	visible = false
	_ring = _disc(RING, [0.0, 0.72, 0.86, 1.0], [0.0, 0.0, 1.0, 0.0], Color(1.0, 0.97, 0.88))
	_shadow = _disc(SHADOW, [0.0, 0.45, 1.0], [1.0, 0.7, 0.0], Color(0.0, 0.0, 0.0))


func _disc(size: float, offsets: Array, alphas: Array, colour: Color) -> MeshInstance3D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(alphas.map(func(a: float) -> Color: return Color(1, 1, 1, a)))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = tex
	mat.albedo_color = colour
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	var m := MeshInstance3D.new()
	m.mesh = plane
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	return m


## Shows both under `head`, the player's feet at `feet` over a floor at `floor_y`.
func follow(head: Vector3, feet: float, floor_y: float) -> void:
	var k := clampf((feet - floor_y - Rig.LIFTED) / FULL_ABOVE, 0.0, 1.0)
	visible = SHOWN and k > 0.0
	if not visible:
		return
	_ring.global_position = Vector3(head.x, feet + RAISE, head.z)
	_shadow.global_position = Vector3(head.x, floor_y + RAISE, head.z)
	(_ring.material_override as StandardMaterial3D).albedo_color.a = RING_ALPHA * k
	(_shadow.material_override as StandardMaterial3D).albedo_color.a = SHADOW_ALPHA * k
