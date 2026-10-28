class_name Underfoot
extends Node3D

## While the player floats, a soft shadow on the ground below, by height alone: standing on nothing tens of metres up
## is the classic trigger of fear of heights and of lost balance. Nothing marks the air at their feet.

## Per-build: whether it shows at all.
const SHOWN := true
## Floating this much over LIFTED shows it at full strength.
const FULL_ABOVE := 1.0
const SHADOW := 1.6
const SHADOW_ALPHA := 0.5
## How far over the ground it is drawn, clear of the ground's own surface.
const RAISE := 0.03

var _shadow: MeshInstance3D


func _init() -> void:
	top_level = true
	visible = false
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0.0)])
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
	mat.albedo_color = Color(0.0, 0.0, 0.0)
	var plane := PlaneMesh.new()
	plane.size = Vector2(SHADOW, SHADOW)
	_shadow = MeshInstance3D.new()
	_shadow.mesh = plane
	_shadow.material_override = mat
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadow)


## Shows it under `head`, the player's feet at `feet` over a floor at `floor_y`.
func follow(head: Vector3, feet: float, floor_y: float) -> void:
	var k := clampf((feet - floor_y - Rig.LIFTED) / FULL_ABOVE, 0.0, 1.0)
	visible = SHOWN and k > 0.0
	if not visible:
		return
	_shadow.global_position = Vector3(head.x, floor_y + RAISE, head.z)
	(_shadow.material_override as StandardMaterial3D).albedo_color.a = SHADOW_ALPHA * k
