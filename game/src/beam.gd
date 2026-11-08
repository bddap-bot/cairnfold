class_name Beam
extends MeshInstance3D

## How many times its natural width it is drawn.
var thick := 1.0

func _init(color: Color) -> void:
	mesh = ToolModels.cylinder(0.004, 0.004, 1.0, 5)
	material_override = Meshes.glow(color)
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func span(a: Vector3, b: Vector3) -> void:
	var up := (b - a).normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	global_transform = Transform3D(Basis(side * thick, up * a.distance_to(b), side.cross(up) * thick), (a + b) * 0.5)
