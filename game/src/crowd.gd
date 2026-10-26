class_name Crowd
extends MultiMeshInstance3D

## A population of small animals drawn as one MultiMesh, unshadowed, its bounds lifted to the terrain's: each
## instance a transform, a colour if the crowd has them, and custom data for its shader, all written into one
## buffer and uploaded in one call.

var buffer := PackedFloat32Array()
var stride := 16


func _init(terrain: Terrain, mesh: Mesh, cap: int, material: Material, colours := false) -> void:
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = colours
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = cap
	multimesh.visible_instance_count = 0
	terrain.lift(multimesh, terrain.bounds())
	stride = 20 if colours else 16
	buffer.resize(cap * stride)
	material_override = material
	cast_shadow = SHADOW_CASTING_SETTING_OFF


## Writes instance `i`; `colour` is ignored by a crowd without colours.
func put(i: int, x: Transform3D, custom: Color, colour := Color.WHITE) -> void:
	var at := i * stride
	var a := x.basis.x
	var b := x.basis.y
	var c := x.basis.z
	var o := x.origin
	buffer[at] = a.x
	buffer[at + 1] = b.x
	buffer[at + 2] = c.x
	buffer[at + 3] = o.x
	buffer[at + 4] = a.y
	buffer[at + 5] = b.y
	buffer[at + 6] = c.y
	buffer[at + 7] = o.y
	buffer[at + 8] = a.z
	buffer[at + 9] = b.z
	buffer[at + 10] = c.z
	buffer[at + 11] = o.z
	if multimesh.use_colors:
		buffer[at + 12] = colour.r
		buffer[at + 13] = colour.g
		buffer[at + 14] = colour.b
		buffer[at + 15] = colour.a
	at += stride - 4
	buffer[at] = custom.r
	buffer[at + 1] = custom.g
	buffer[at + 2] = custom.b
	buffer[at + 3] = custom.a


func upload(count: int) -> void:
	if count > 0 or multimesh.visible_instance_count > 0:
		multimesh.buffer = buffer
	multimesh.visible_instance_count = count
