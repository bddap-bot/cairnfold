class_name Stones
extends Node3D

## Laid stones as one MultiMesh per lumpy variant: walls in world space, or paving whose heights count from
## the ground under each stone.

static var _meshes: Array[ArrayMesh] = []
static var _material: ShaderMaterial
static var _paving: ShaderMaterial

var _instances: Array[MultiMeshInstance3D] = []


static func shared_material() -> ShaderMaterial:
	if _material == null:
		_material = _stone_material("stone")
	return _material


static func _stone_material(shader: String) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/%s.gdshader" % shader)
	mat.set_shader_parameter("detail", Look.detail_noise())
	return mat


static func meshes() -> Array[ArrayMesh]:
	if _meshes.is_empty():
		for v in 3:
			_meshes.append(Meshes.rounded_box(0.14, 3, 100 + v))
	return _meshes


func _init(paving := false) -> void:
	if paving and _paving == null:
		_paving = _stone_material("paving")
	for mesh in meshes():
		var mmi := MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = mesh
		if paving:
			mm.custom_aabb = Terrain.bounds()
		mmi.multimesh = mm
		mmi.material_override = _paving if paving else shared_material()
		_instances.append(mmi)
		add_child(mmi)


## `stones` are dictionaries with `xform`, `color`, `ao` (occlusion) and `variant` (0–2).
func lay(stones: Array[Dictionary]) -> void:
	var buckets: Array[Array] = [[], [], []]
	for s in stones:
		buckets[s.variant].append(s)
	for v in 3:
		var mm := _instances[v].multimesh
		mm.instance_count = buckets[v].size()
		for i in buckets[v].size():
			var s: Dictionary = buckets[v][i]
			mm.set_instance_transform(i, s.xform)
			mm.set_instance_color(i, s.color)
			mm.set_instance_custom_data(i, Color(s.ao, 0, 0, 0))
