class_name Stones
extends Node3D

## Laid stones as one MultiMesh: walls in world space, or paving whose heights count from the ground under
## each stone. Every stone is the same lumpy mesh, turned one of three ways by its variant so neighbours
## differ, with simplified levels of detail the renderer swaps in as it shrinks on screen.

const FLIPS: Array[Basis] = [Basis.IDENTITY, Basis(Vector3.UP, PI), Basis(Vector3.RIGHT, PI)]

static var _mesh: ArrayMesh
static var _far_mesh: ArrayMesh
static var _material: ShaderMaterial
static var _paving_material: ShaderMaterial

var _instance := MultiMeshInstance3D.new()
var _paving := false
## Paving only: the same stones drawn with `far_mesh` once the whole chunk is past the near distance, and whole on
## Quality.FULL_LAYER for a photo, as Masonry draws a wall's. The whole stones alone cast the shadows, as they always did.
var _far: MultiMeshInstance3D
var _full: MultiMeshInstance3D
var _radius := 0.0


static func shared_material() -> ShaderMaterial:
	if _material == null:
		_material = _stone_material("stone")
	return _material


static func paving_material() -> ShaderMaterial:
	if _paving_material == null:
		_paving_material = _stone_material("paving")
	return _paving_material


static func _stone_material(shader: String) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/%s.gdshader" % shader)
	mat.set_shader_parameter("detail", Look.detail_noise())
	return mat


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


func _init(paving := false) -> void:
	_paving = paving
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh()
	_instance.multimesh = mm
	_instance.material_override = paving_material() if paving else shared_material()
	add_child(_instance)
	if paving:
		_instance.layers = Quality.LADDER_LAYER
		_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_far = MultiMeshInstance3D.new()
		_far.multimesh = mm.duplicate()
		_far.multimesh.mesh = far_mesh()
		_far.material_override = _instance.material_override
		_far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_far.layers = Quality.LADDER_LAYER
		add_child(_far)
		_full = MultiMeshInstance3D.new()
		_full.multimesh = mm
		_full.material_override = _instance.material_override
		_full.layers = Quality.FULL_LAYER
		add_child(_full)


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
		_radius = area.size.length() * 0.5
		var t := Terrain.bounds()
		Terrain.lift(mm, AABB(Vector3(area.position.x, t.position.y, area.position.y), Vector3(area.size.x, t.size.y, area.size.y)))
	for i in stones.size():
		var s: Dictionary = stones[i]
		var x: Transform3D = s.xform
		x.basis = x.basis * FLIPS[s.variant]
		mm.set_instance_transform(i, x)
		mm.set_instance_color(i, s.color)
		mm.set_instance_custom_data(i, custom(s))
	if _far != null:
		_far.multimesh.instance_count = mm.instance_count
	if _far != null and mm.instance_count > 0:
		Terrain.lift(_far.multimesh, mm.custom_aabb)
		_far.multimesh.buffer = mm.buffer
		_far.multimesh.visible_instance_count = mm.visible_instance_count
		near(Wall.kinds()[Wall.Part.STONE].near)


## Paving only: draws the stones whole up to `metres` from the eye. The renderer measures to the centre of the
## lifted bounds, which span the terrain's whole height, so half that height counts as reach too.
func near(metres: float) -> void:
	var split := metres + _radius + _instance.multimesh.custom_aabb.size.y * 0.5
	_instance.visibility_range_end = split
	_far.visibility_range_begin = split


## A laid part's custom data: its occlusion, and the code of the material it is painted with.
static func custom(part: Dictionary) -> Color:
	return Color(part.ao, Palette.code(part.get("kind", "")), 0, 0)


func count() -> int:
	return _instance.multimesh.instance_count


func reveal(count: int) -> void:
	_instance.multimesh.visible_instance_count = count
	if _far != null:
		_far.multimesh.visible_instance_count = count
