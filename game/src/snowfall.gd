class_name Snowfall
extends MeshInstance3D

## Flakes in a box that wraps round the head, so each falls through the world wherever the eye goes; how many fall is
## one uniform, so the CPU writes nothing a frame.

const FLAKES := 24000
const BOX := 20.0

var mat := ShaderMaterial.new()


func _init() -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mat.shader = preload("res://src/snow.gdshader")
	mat.set_shader_parameter("box", BOX)
	material_override = mat
	mesh = flakes(FLAKES)
	custom_aabb = AABB(-Vector3.ONE * BOX, Vector3.ONE * BOX * 2.0)
	visible = false


## Each flake a quad at its own spot in the unit box, ranked so a share of them falls; seeded, so every run lays the same.
static func flakes(n: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var custom := PackedFloat32Array()
	var index := PackedInt32Array()
	for i in n:
		var seed := [rng.randf(), rng.randf(), rng.randf(), (i + 0.5) / n]
		for c: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
			verts.append(Vector3(c.x - 0.5, c.y - 0.5, 0.0))
			uvs.append(c)
			custom.append_array(PackedFloat32Array(seed))
		index.append_array(PackedInt32Array([i * 4, i * 4 + 1, i * 4 + 2, i * 4, i * 4 + 2, i * 4 + 3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_CUSTOM0] = custom
	arrays[Mesh.ARRAY_INDEX] = index
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	return out


## `share` of the flakes falling, the eye seeing `sky` of the sky; none drawn at all when none fall.
func fall(at: Vector3, share: float, sky: float) -> void:
	visible = share > 0.0 and sky > 0.0
	if not visible:
		return
	global_position = at
	mat.set_shader_parameter("amount", share)
	mat.set_shader_parameter("open", sky)
