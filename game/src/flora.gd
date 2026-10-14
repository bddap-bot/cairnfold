class_name Flora
extends Node3D

## Every plant in the glade: the meadow's own and those painted or placed since. Each kind is one
## MultiMesh allocated up front, so painting writes instances without resizing GPU buffers. A plant's
## transform counts its height from the ground under its anchor, which its shader reads from the
## terrain each frame, so reshaping the ground moves no instance.

const PAINTED_GRASS := 12000
const PAINTED_FLOWERS := 4000
const PLACED_TREES := 64
## Where an untracked hand is, as far as the grass knows.
const NO_HAND := Vector3(0, -1000, 0)


## A fixed-capacity MultiMesh that fills in order; once full, new plants replace the oldest added after `keep()`.
## Every tree has the same number of blobs, so the trunk and foliage pools recycle in step.
class Pool:
	var mm := MultiMesh.new()
	var kept := 0
	var last := -1
	var _next := 0

	func _init(mesh: Mesh, capacity: int) -> void:
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = capacity
		mm.visible_instance_count = 0
		# Painting changes the instance list every frame; a fixed box spares a bounds pass over every plant.
		mm.custom_aabb = Terrain.bounds()

	## `custom`'s blue and alpha are taken for `anchor`.
	func add(xform: Transform3D, color: Color, anchor: Vector3, custom := Color()) -> void:
		var i := mm.visible_instance_count
		if i < mm.instance_count:
			mm.visible_instance_count = i + 1
		elif kept == mm.instance_count:
			return
		else:
			i = kept + _next
			_next = (_next + 1) % (mm.instance_count - kept)
		last = i
		xform.origin.y -= Terrain.height_at(anchor.x, anchor.z)
		custom.b = anchor.x
		custom.a = anchor.z
		mm.set_instance_transform(i, xform)
		mm.set_instance_color(i, color)
		mm.set_instance_custom_data(i, custom)

	func keep() -> void:
		kept = mm.visible_instance_count

	func size() -> int:
		return mm.visible_instance_count


var grass: Pool
var grass_mat := ShaderMaterial.new()
var flowers: Pool
var trunks: Pool
var foliage: Pool


func _init() -> void:
	grass_mat.shader = load("res://src/grass.gdshader")
	part(NO_HAND, NO_HAND)
	grass = _pool(Meshes.grass_clump(7, 1), Meadow.GRASS_CLUMPS + PAINTED_GRASS, grass_mat, false)
	flowers = _pool(Meshes.flower(6), Meadow.FLOWERS + PAINTED_FLOWERS, _plant_material("flower", Color.WHITE, 0.8), false)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.16
	trunk.bottom_radius = 0.3
	trunk.height = 1.0
	trunk.radial_segments = 8
	trunk.rings = 1
	trunks = _pool(trunk, Meadow.TREES + PLACED_TREES, _plant_material("plant", Color(0.36, 0.27, 0.2), 1.0), true)
	var leaf_mat := _plant_material("leaf", Color.WHITE, 1.0)
	leaf_mat.set_shader_parameter("backlight", Color(0.25, 0.35, 0.08))
	foliage = _pool(Meshes.blob(4), (Meadow.TREES + PLACED_TREES) * FloraLayout.BLOBS + Meadow.BUSHES, leaf_mat, true)


static func _plant_material(shader: String, albedo: Color, roughness: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/%s.gdshader" % shader)
	mat.set_shader_parameter("albedo", albedo)
	mat.set_shader_parameter("roughness", roughness)
	return mat


func _pool(mesh: Mesh, capacity: int, mat: Material, shadows: bool) -> Pool:
	var pool := Pool.new(mesh, capacity)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = pool.mm
	mmi.material_override = mat
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return pool


func part(left: Vector3, right: Vector3) -> void:
	grass_mat.set_shader_parameter(&"hand_left", left)
	grass_mat.set_shader_parameter(&"hand_right", right)


func add_grass(p: Vector3, rng: RandomNumberGenerator) -> void:
	var v := rng.randf_range(0.85, 1.1)
	var c := FloraLayout.clump(p)
	grass.add(FloraLayout.grass(p, c, rng), Color(v, v, v), p, Color(FloraLayout.dryness(p), FloraLayout.clump_trait(c, FloraLayout.Trait.TINT), 0, 0))


func add_flower(p: Vector3, rng: RandomNumberGenerator) -> void:
	flowers.add(FloraLayout.flower(p, rng), FloraLayout.flower_color(p), p)


func add_tree(at: Vector3, rng: RandomNumberGenerator) -> void:
	var t := FloraLayout.tree(at, rng)
	trunks.add(t.trunk, Color.WHITE, at)
	for b in t.blobs:
		foliage.add(b[0], b[1], at)


func add_bush(at: Vector3, rng: RandomNumberGenerator) -> void:
	var b := FloraLayout.bush(at, rng)
	foliage.add(b[0], b[1], at)


func keep() -> void:
	for p in [grass, flowers, trunks, foliage]:
		p.keep()
