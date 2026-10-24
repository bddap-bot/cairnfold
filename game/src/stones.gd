class_name Stones
extends Node3D

## Shared stone meshes and instanced stones in world space.

const FLIPS: Array[Basis] = [Basis.IDENTITY, Basis(Vector3.UP, PI), Basis(Vector3.RIGHT, PI)]

static var _mesh: ArrayMesh
static var _far_mesh: ArrayMesh
static var _material: ShaderMaterial
static var _small: ShaderMaterial

var _instance := Masonry.Kind.new(mesh(), small_material(), true, true, GeometryInstance3D.SHADOW_CASTING_SETTING_ON).instance()


static func shared_material() -> ShaderMaterial:
	if _material == null:
		_material = _stone(preload("res://src/stone.gdshader"))
	return _material


## shared_material for pieces small enough that the light volumes do not vary over a triangle, stones and tiles:
## they read the volumes once a vertex (Bounce's given_at), not once a fragment.
static func small_material() -> ShaderMaterial:
	if _small == null:
		_small = _stone(preload("res://src/stone_small.gdshader"))
	return _small


static func _stone(shader: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("window_glow", Lamps.WINDOW_GLOW)
	StoneStyles.apply(m)
	return m


static func mesh() -> ArrayMesh:
	if _mesh == null:
		_mesh = Meshes.rounded_box(0.14, 3, 100)
	return _mesh


## A stone for far off, 12 triangles to `mesh`'s 108. Its faces stand where `mesh`'s do, so a piece that meets its
## neighbours up close still meets them far off; corners alone, as a coarse `rounded_box` is, pull every face in.
static func far_mesh() -> ArrayMesh:
	if _far_mesh == null:
		_far_mesh = Meshes.plain_box()
	return _far_mesh


func _init() -> void:
	add_child(_instance)


## `stones` are dictionaries with `xform`, `color`, `ao` (occlusion), `variant` (0–2) and, painted with
## a material of the palette, `kind`.
func lay(stones: Array[Dictionary]) -> void:
	var mm := _instance.multimesh
	mm.instance_count = stones.size()
	for i in stones.size():
		var s: Dictionary = stones[i]
		var x: Transform3D = s.xform
		x.basis = x.basis * FLIPS[s.variant]
		mm.set_instance_transform(i, x)
		mm.set_instance_color(i, s.color)
		mm.set_instance_custom_data(i, custom(s))


## A laid part's custom data: its occlusion, the code of the material it is painted with, and its end turns.
static func custom(part: Dictionary) -> Color:
	var e := ends(part)
	return Color(part.ao, Palette.code(part.get("kind", "")), e.x, e.y)


## A laid part's end turns (`WallLayout._wedge`) in its mesh's own frame, under the flip of its variant (FLIPS): turning
## about local y swaps its ends, about local x reverses its z.
static func ends(part: Dictionary) -> Vector2:
	var e: Vector2 = part.get("ends", Vector2.ZERO)
	match int(part.get("variant", 0)):
		1:
			return Vector2(e.y, e.x)
		2:
			return -e
	return e


func count() -> int:
	return _instance.multimesh.instance_count


func reveal(count: int) -> void:
	_instance.multimesh.visible_instance_count = count
