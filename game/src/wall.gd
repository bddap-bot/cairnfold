class_name Wall
extends Node3D

static var _meshes: Array[ArrayMesh] = []
static var _material: ShaderMaterial

var layout := WallLayout.new()
var _instances: Array[MultiMeshInstance3D] = []


static func shared_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://src/stone.gdshader")
		_material.set_shader_parameter("detail", Look.detail_noise())
	return _material


static func stone_meshes() -> Array[ArrayMesh]:
	if _meshes.is_empty():
		for v in 3:
			_meshes.append(Meshes.rounded_box(0.14, 3, 100 + v))
	return _meshes


func _init(seed: int) -> void:
	layout.seed = seed
	for mesh in stone_meshes():
		var mmi := MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = mesh
		mmi.multimesh = mm
		mmi.material_override = shared_material()
		_instances.append(mmi)
		add_child(mmi)


func rebuild() -> void:
	layout.build(Terrain.height_at)
	var buckets: Array[Array] = [[], [], []]
	for s in layout.stones:
		buckets[s.variant].append(s)
	for v in 3:
		var mm := _instances[v].multimesh
		mm.instance_count = buckets[v].size()
		for i in buckets[v].size():
			var s: Dictionary = buckets[v][i]
			mm.set_instance_transform(i, s.xform)
			mm.set_instance_color(i, s.color)
			mm.set_instance_custom_data(i, Color(s.ao, 0, 0, 0))


## Distance from a ray to this wall's body, with the arc length it is nearest.
func ray_distance(origin: Vector3, dir: Vector3) -> Dictionary:
	var best := {"distance": INF, "s": 0.0, "point": Vector3.ZERO}
	for i in layout.samples.size():
		var base := layout.samples[i]
		var top := base + Vector3.UP * (layout.height + WallLayout.CAP)
		var hit := _ray_segment(origin, dir, base, top)
		if hit.distance < best.distance:
			best = {"distance": hit.distance, "s": layout.lengths[i], "point": hit.point, "along": hit.along}
	return best


static func _ray_segment(o: Vector3, d: Vector3, a: Vector3, b: Vector3) -> Dictionary:
	var u := b - a
	var w := o - a
	var uu := u.dot(u)
	var ud := u.dot(d)
	var uw := u.dot(w)
	var dw := d.dot(w)
	var denom := uu - ud * ud
	var sc := 0.0 if absf(denom) < 1e-6 else clampf((uw - ud * dw) / denom, 0.0, 1.0)
	var t := maxf(0.0, ud * sc - dw)
	var p_seg := a + u * sc
	var p_ray := o + d * t
	return {"distance": p_seg.distance_to(p_ray), "point": p_seg, "along": t}
