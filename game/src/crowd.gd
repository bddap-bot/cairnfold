class_name Crowd
extends MultiMeshInstance3D

## A population of small animals drawn as one MultiMesh, unshadowed, its bounds lifted to the terrain's: each
## instance a transform, a colour if the crowd has them, and custom data for its shader, all written into one
## buffer and uploaded in one call.

var buffer := PackedFloat32Array()
var stride := 16


func _init(mesh: Mesh, cap: int, material: Material, colours := false) -> void:
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = colours
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = cap
	multimesh.visible_instance_count = 0
	Terrain.lift(multimesh, Terrain.bounds())
	stride = 20 if colours else 16
	buffer.resize(cap * stride)
	material_override = material
	cast_shadow = SHADOW_CASTING_SETTING_OFF


## Writes instance `i`; `colour` is ignored by a crowd without colours.
func put(i: int, x: Transform3D, custom: Color, colour := Color.WHITE) -> void:
	var at := i * stride
	for r in 3:
		buffer[at + r * 4] = x.basis.x[r]
		buffer[at + r * 4 + 1] = x.basis.y[r]
		buffer[at + r * 4 + 2] = x.basis.z[r]
		buffer[at + r * 4 + 3] = x.origin[r]
	if multimesh.use_colors:
		for c in 4:
			buffer[at + 12 + c] = colour[c]
	at += stride - 4
	for c in 4:
		buffer[at + c] = custom[c]


## Draws the first `count` instances as last put.
func upload(count: int) -> void:
	if count > 0 or multimesh.visible_instance_count > 0:
		multimesh.buffer = buffer
	multimesh.visible_instance_count = count
