class_name Stones
extends Node3D

const FLIPS: Array[Basis] = [Basis.IDENTITY, Basis(Vector3.UP, PI), Basis(Vector3.RIGHT, PI)]

static var _mesh: ArrayMesh
static var _far_mesh: ArrayMesh
static var _materials := {}

var _instance := Masonry.Kind.new(mesh(), small_material(), true, true, GeometryInstance3D.SHADOW_CASTING_SETTING_ON).instance()


static func shared_material() -> ShaderMaterial:
	return _made(preload("res://src/stone.gdshader"))


## For pieces small enough that the light volumes do not vary over a triangle: read once a vertex (Bounce's given_at).
static func small_material() -> ShaderMaterial:
	return _made(preload("res://src/stone_small.gdshader"))


static func baked_material() -> ShaderMaterial:
	return _made(preload("res://src/stone_far.gdshader"))


static func _made(shader: Shader) -> ShaderMaterial:
	if not _materials.has(shader):
		_materials[shader] = stone(shader)
	return _materials[shader]


static func stone(shader: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("window_glow", Lamps.WINDOW_GLOW)
	m.set_shader_parameter("glass_colour", Vector3(WallLayout.GLASS.r, WallLayout.GLASS.g, WallLayout.GLASS.b))
	StoneStyles.apply(m)
	return m


static func mesh() -> ArrayMesh:
	if _mesh == null:
		_mesh = Meshes.rounded_box(0.14, 3, 100)
	return _mesh


## 12 triangles to `mesh`'s 108, its faces where `mesh`'s are so neighbours still meet; a coarse rounded_box pulls them in.
static func far_mesh() -> ArrayMesh:
	if _far_mesh == null:
		_far_mesh = Meshes.plain_box()
	return _far_mesh


func _init() -> void:
	add_child(_instance)


## `stones`: {xform (world space), color, ao (occlusion), variant (0–2), kind (palette material, if painted)}.
func lay(stones: Array[Dictionary]) -> void:
	var mm := _instance.multimesh
	mm.instance_count = stones.size()
	for i in stones.size():
		var s: Dictionary = stones[i]
		var x: Transform3D = s.xform
		x.basis = x.basis * FLIPS[s.variant]
		mm.set_instance_transform(i, x)
		mm.set_instance_color(i, glazed(s, s.color))
		mm.set_instance_custom_data(i, custom(s))


## Alpha 0 marks glass, which the lamps light from behind.
static func glazed(part: Dictionary, color: Color) -> Color:
	color.a = 0.0 if part.get("kind") == "glass" else 1.0
	return color


static func custom(part: Dictionary) -> Color:
	var e := ends(part)
	return Color(part.ao, Palette.code(part.get("kind", "")), e.x, e.y)


## End turns (`WallLayout._wedge`) in the mesh's own frame, under the variant's flip (FLIPS): about local y swaps them, about local x negates them.
static func ends(part: Dictionary) -> Vector2:
	var e: Vector2 = part.get("ends", Vector2.ZERO)
	match int(part.get("variant", 0)):
		1:
			return Vector2(e.y, e.x)
		2:
			return -e
	return e


func reveal(count: int) -> void:
	_instance.multimesh.visible_instance_count = count
