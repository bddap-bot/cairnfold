class_name Sight
extends MeshInstance3D

## What a held tool aims with, standing at its tip: a glowing bead, or a ring across the aim to look down the tool
## through. Either belongs to the tool, so no ray leaves the hand.


func _init(ring: bool) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false
	if ring:
		var torus := TorusMesh.new()
		torus.inner_radius = 0.011
		torus.outer_radius = 0.014
		torus.rings = 20
		torus.ring_segments = 4
		mesh = torus
		basis = Basis(Vector3.RIGHT, PI * 0.5)
	else:
		var bead := SphereMesh.new()
		bead.radius = 0.006
		bead.height = 0.012
		bead.radial_segments = 8
		bead.rings = 4
		mesh = bead


func tint(colour: Color) -> void:
	(material_override as StandardMaterial3D).albedo_color = colour
