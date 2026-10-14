class_name Wall
extends Node3D

static var _leaf_material: StandardMaterial3D
static var _leaf := Meshes.leaf()
static var _tile := Meshes.rounded_box(0.22, 2, 41)
static var _plaster: StandardMaterial3D

var layout := WallLayout.new()
var _stones := Stones.new()
var _fittings := Fittings.new()
var _ivy := MultiMeshInstance3D.new()
var _ivy_times := PackedFloat32Array()
var _ivy_task := -1
var _ivy_baked := {}
var _ivy_stale := false
var finished := false
## The roof on a house or tower, laid again with the walls under it.
var roof: RoofLayout
var _tiles: MultiMeshInstance3D
var _gables: MeshInstance3D
## Seconds since the wall was finished: how far its ivy has grown.
var ivy_age := 0.0


static func leaf_material() -> StandardMaterial3D:
	if _leaf_material == null:
		_leaf_material = StandardMaterial3D.new()
		_leaf_material.vertex_color_use_as_albedo = true
		_leaf_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_leaf_material.roughness = 0.75
		_leaf_material.backlight_enabled = true
		_leaf_material.backlight = Color(0.2, 0.3, 0.06)
	return _leaf_material


func _init(seed: int) -> void:
	layout.seed = seed
	add_child(_stones)
	add_child(_fittings)
	var ivy := MultiMesh.new()
	ivy.transform_format = MultiMesh.TRANSFORM_3D
	ivy.use_colors = true
	_ivy.material_override = leaf_material()
	ivy.mesh = _leaf
	_ivy.multimesh = ivy
	_ivy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ivy)


## Puts a roof on this closed wall; its stones then stop flush under the eaves.
func add_roof(r: RoofLayout) -> void:
	roof = r
	layout.roofed = true
	_tiles = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _tile
	_tiles.multimesh = mm
	_tiles.material_override = Stones.shared_material()
	add_child(_tiles)
	if _plaster == null:
		_plaster = StandardMaterial3D.new()
		_plaster.albedo_color = Color(0.8, 0.73, 0.6)
		_plaster.roughness = 0.95
		_plaster.cull_mode = BaseMaterial3D.CULL_DISABLED
	_gables = MeshInstance3D.new()
	_gables.material_override = _plaster
	add_child(_gables)


func _ready() -> void:
	set_process(finished)


func _process(delta: float) -> void:
	ivy_age += delta
	if _ivy_task >= 0 and WorkerThreadPool.is_task_completed(_ivy_task):
		WorkerThreadPool.wait_for_task_completion(_ivy_task)
		_ivy_task = -1
		_apply_ivy()
		if _ivy_stale:
			_layout_ivy()
	_ivy.multimesh.visible_instance_count = _ivy_times.bsearch(ivy_age)
	if _ivy_task < 0 and (_ivy_times.is_empty() or ivy_age > _ivy_times[-1]):
		set_process(false)


func _exit_tree() -> void:
	if _ivy_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_ivy_task)
		_ivy_task = -1


## Ivy for a long wall takes longer than a frame to lay out, so it grows on a worker thread from a snapshot.
func _layout_ivy() -> void:
	set_process(true)
	if _ivy_task >= 0:
		_ivy_stale = true
		return
	_ivy_stale = false
	var shape := layout.snapshot()
	var out := _ivy_baked
	out.clear()
	_ivy_task = WorkerThreadPool.add_task(func(): out.merge(IvyLayout.bake(shape)))


func _apply_ivy() -> void:
	var mm := _ivy.multimesh
	_ivy_times = _ivy_baked.times
	mm.instance_count = _ivy_times.size()
	if _ivy_times.size() > 0:
		mm.buffer = _ivy_baked.buffer
	mm.custom_aabb = _ivy_baked.bounds


## Lays the stones again; the ivy too unless `with_ivy` is false, which hides it while a grip lift is under way.
func rebuild(with_ivy := true) -> void:
	layout.build(Terrain.height_at)
	_ivy.visible = with_ivy
	_stones.lay(layout.stones)
	if roof != null:
		rebuild_roof()
	else:
		_fittings.lay(layout.flames, layout.cloths)
	if finished and with_ivy and not layout.fence:
		_layout_ivy()


func rebuild_roof() -> void:
	roof.base = layout.samples[0].y + layout.height + WallLayout.CAP
	if roof.kind == RoofLayout.Kind.GABLE:
		roof.corners = layout.points
	roof.build()
	var mm := _tiles.multimesh
	mm.instance_count = roof.tiles.size()
	for i in roof.tiles.size():
		var t: Dictionary = roof.tiles[i]
		mm.set_instance_transform(i, t.xform)
		mm.set_instance_color(i, t.color)
		mm.set_instance_custom_data(i, Color(t.ao, 0, 0, 0))
	_fittings.lay(layout.flames, layout.cloths + roof.cloths)
	var tris := roof.gables()
	if tris.is_empty():
		_gables.mesh = null
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in tris:
		st.add_vertex(p)
	st.generate_normals()
	_gables.mesh = st.commit()


func footprint() -> Rect2:
	return layout.bounds.grow(WallLayout.THICKNESS)


## Distance from a ray to this wall's body, with the arc length it is nearest.
func ray_distance(origin: Vector3, dir: Vector3) -> Dictionary:
	var best := {"distance": INF, "s": 0.0, "point": Vector3.ZERO, "along": INF}
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
