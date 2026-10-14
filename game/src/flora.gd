class_name Flora
extends Node3D

## Every plant in the glade: the meadow's own and those painted or placed since. Each kind is one
## MultiMesh allocated up front, so painting writes instances without resizing GPU buffers.

const PAINTED_GRASS := 12000
const PAINTED_FLOWERS := 4000
const PLACED_TREES := 64


## A fixed-capacity MultiMesh that fills in order; once full, new plants replace the oldest added after `keep()`.
## Every tree has the same number of blobs, so the trunk and foliage pools recycle in step.
class Pool:
	var mm := MultiMesh.new()
	var kept := 0
	## The slot the latest plant went into.
	var last := -1
	var _next := 0

	func _init(mesh: Mesh, capacity: int, custom: bool) -> void:
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = custom
		mm.mesh = mesh
		mm.instance_count = capacity
		mm.visible_instance_count = 0

	func add(xform: Transform3D, color: Color, custom := Color()) -> void:
		var i := mm.visible_instance_count
		if i < mm.instance_count:
			mm.visible_instance_count = i + 1
		else:
			i = kept + _next
			_next = (_next + 1) % (mm.instance_count - kept)
		last = i
		mm.set_instance_transform(i, xform)
		mm.set_instance_color(i, color)
		if mm.use_custom_data:
			mm.set_instance_custom_data(i, custom)

	func keep() -> void:
		kept = mm.visible_instance_count

	func size() -> int:
		return mm.visible_instance_count


var grass: Pool
var flowers: Pool
var trunks: Pool
var foliage: Pool


func _init() -> void:
	var grass_mat := ShaderMaterial.new()
	grass_mat.shader = load("res://src/grass.gdshader")
	grass = _pool(Meshes.grass_clump(7, 1), Meadow.GRASS_CLUMPS + PAINTED_GRASS, true, grass_mat, false)
	var flower_mat := StandardMaterial3D.new()
	flower_mat.vertex_color_use_as_albedo = true
	flower_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	flower_mat.roughness = 0.8
	flowers = _pool(Meshes.flower(6), Meadow.FLOWERS + PAINTED_FLOWERS, false, flower_mat, false)
	var bark_mat := StandardMaterial3D.new()
	bark_mat.albedo_color = Color(0.36, 0.27, 0.2)
	bark_mat.roughness = 1.0
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.16
	trunk.bottom_radius = 0.3
	trunk.height = 1.0
	trunk.radial_segments = 8
	trunk.rings = 1
	trunks = _pool(trunk, Meadow.TREES + PLACED_TREES, false, bark_mat, true)
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.vertex_color_use_as_albedo = true
	leaf_mat.roughness = 1.0
	leaf_mat.backlight_enabled = true
	leaf_mat.backlight = Color(0.25, 0.35, 0.08)
	foliage = _pool(Meshes.blob(4), (Meadow.TREES + PLACED_TREES) * FloraLayout.BLOBS + Meadow.BUSHES, false, leaf_mat, true)


func _pool(mesh: Mesh, capacity: int, custom: bool, mat: Material, shadows: bool) -> Pool:
	var pool := Pool.new(mesh, capacity, custom)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = pool.mm
	mmi.material_override = mat
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return pool


func add_grass(p: Vector3, rng: RandomNumberGenerator) -> void:
	var v := rng.randf_range(0.85, 1.1)
	grass.add(FloraLayout.grass(p, rng), Color(v, v, v), Color(FloraLayout.dryness(p), 0, 0, 0))


func add_flower(p: Vector3, rng: RandomNumberGenerator) -> void:
	flowers.add(FloraLayout.flower(p, rng), FloraLayout.flower_color(p))


func add_tree(at: Vector3, rng: RandomNumberGenerator) -> void:
	var t := FloraLayout.tree(at, rng)
	trunks.add(t.trunk, Color.WHITE)
	for b in t.blobs:
		foliage.add(b[0], b[1])


func add_bush(at: Vector3, rng: RandomNumberGenerator) -> void:
	var b := FloraLayout.bush(at, rng)
	foliage.add(b[0], b[1])


## Everything added so far stays; painting past capacity recycles only what comes after.
func keep() -> void:
	for p in [grass, flowers, trunks, foliage]:
		p.keep()
