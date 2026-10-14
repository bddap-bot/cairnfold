class_name Wall
extends Node3D

static var _meshes: Array[ArrayMesh] = []
static var _material: ShaderMaterial
static var _leaf_material: StandardMaterial3D
static var _leaf: ArrayMesh

var layout := WallLayout.new()
var _instances: Array[MultiMeshInstance3D] = []
var _ivy := MultiMeshInstance3D.new()
var _ivy_times: Array[float] = []
## Seconds since the wall was finished, which is how far its ivy has grown; negative while it is being drawn.
var ivy_age := -1.0


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


static func leaf_material() -> StandardMaterial3D:
	if _leaf_material == null:
		_leaf_material = StandardMaterial3D.new()
		_leaf_material.vertex_color_use_as_albedo = true
		_leaf_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_leaf_material.roughness = 0.75
		_leaf_material.backlight_enabled = true
		_leaf_material.backlight = Color(0.2, 0.3, 0.06)
		_leaf = Meshes.leaf()
	return _leaf_material


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
	var ivy := MultiMesh.new()
	ivy.transform_format = MultiMesh.TRANSFORM_3D
	ivy.use_colors = true
	_ivy.material_override = leaf_material()
	ivy.mesh = _leaf
	_ivy.multimesh = ivy
	_ivy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ivy)
	set_process(false)


## Start the ivy growing; called once the wall is finished.
func grow_ivy() -> void:
	ivy_age = 0.0
	_layout_ivy()
	set_process(true)


func _process(delta: float) -> void:
	ivy_age += delta
	_ivy.multimesh.visible_instance_count = _ivy_times.bsearch(ivy_age)
	if _ivy_times.is_empty() or ivy_age > _ivy_times[-1]:
		set_process(false)


func _layout_ivy() -> void:
	var leaves := IvyLayout.grow(layout)
	var mm := _ivy.multimesh
	mm.instance_count = leaves.size()
	_ivy_times.clear()
	for i in leaves.size():
		mm.set_instance_transform(i, leaves[i].xform)
		mm.set_instance_color(i, leaves[i].color)
		_ivy_times.append(leaves[i].t)
	mm.visible_instance_count = _ivy_times.bsearch(ivy_age)
	set_process(ivy_age >= 0.0)


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
	if ivy_age >= 0.0:
		_layout_ivy()


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
