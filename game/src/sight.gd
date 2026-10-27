class_name Sight
extends MeshInstance3D

## What a held tool aims with, standing at its tip: a ring across the aim to look down the tool through. It belongs
## to the tool, so no ray leaves the hand.


func _init() -> void:
	material_override = Meshes.glow(Color.WHITE)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false
	var torus := TorusMesh.new()
	torus.inner_radius = 0.011
	torus.outer_radius = 0.014
	torus.rings = 20
	torus.ring_segments = 4
	mesh = torus
	basis = Basis(Vector3.RIGHT, PI * 0.5)


func tint(colour: Color) -> void:
	(material_override as StandardMaterial3D).albedo_color = colour
