class_name Stones
extends Node3D

## Laid stones as one MultiMesh: walls in world space, or paving whose heights count from the ground under
## each stone. Every stone is the same lumpy mesh, turned one of three ways by its variant so neighbours
## differ, with simplified levels of detail the renderer swaps in as it shrinks on screen.

const FLIPS: Array[Basis] = [Basis.IDENTITY, Basis(Vector3.UP, PI), Basis(Vector3.RIGHT, PI)]

static var _mesh: ArrayMesh
static var _material: ShaderMaterial
static var _paving_material: ShaderMaterial

var _instance := MultiMeshInstance3D.new()
var _paving := false


static func shared_material() -> ShaderMaterial:
	if _material == null:
		_material = _stone_material("stone")
	return _material


static func _stone_material(shader: String) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/%s.gdshader" % shader)
	mat.set_shader_parameter("detail", Look.detail_noise())
	return mat


static func mesh() -> ArrayMesh:
	if _mesh == null:
		_mesh = Meshes.rounded_box(0.14, 3, 100)
	return _mesh


func _init(paving := false) -> void:
	_paving = paving
	if paving and _paving_material == null:
		_paving_material = _stone_material("paving")
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh()
	_instance.multimesh = mm
	_instance.material_override = _paving_material if paving else shared_material()
	add_child(_instance)


## `stones` are dictionaries with `xform`, `color`, `ao` (occlusion), `variant` (0–2) and, painted with
## a material of the palette, `kind`.
func lay(stones: Array[Dictionary]) -> void:
	var mm := _instance.multimesh
	mm.instance_count = stones.size()
	if _paving and not stones.is_empty():
		# Paving heights count from the ground, so the bounds span the terrain's heights over the stones' ground.
		var area := Rect2(Vector2(stones[0].xform.origin.x, stones[0].xform.origin.z), Vector2.ZERO)
		for s in stones:
			area = area.expand(Vector2(s.xform.origin.x, s.xform.origin.z))
		area = area.grow(1.0)
		var t := Terrain.bounds()
		mm.custom_aabb = AABB(Vector3(area.position.x, t.position.y, area.position.y), Vector3(area.size.x, t.size.y, area.size.y))
	for i in stones.size():
		var s: Dictionary = stones[i]
		var x: Transform3D = s.xform
		x.basis = x.basis * FLIPS[s.variant]
		mm.set_instance_transform(i, x)
		mm.set_instance_color(i, s.color)
		mm.set_instance_custom_data(i, custom(s))


## A laid part's custom data: its occlusion, and the code of the material it is painted with.
static func custom(part: Dictionary) -> Color:
	return Color(part.ao, Palette.code(part.get("kind", "")), 0, 0)
