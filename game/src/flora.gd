class_name Flora
extends Node3D

## Every plant in the glade: the meadow's own and those painted or placed since. Painted plants of each
## kind share one MultiMesh allocated up front, so painting writes instances without resizing GPU buffers. A plant's
## transform counts its height from the ground under its anchor, which its shader reads from the
## terrain each frame, so reshaping the ground moves no instance.

const PAINTED_GRASS := 12000
const PAINTED_FLOWERS := 4000
const PLACED_TREES := 64
## Where an untracked hand is, as far as the grass knows.
const NO_HAND := Vector3(0, -1000, 0)
## Painted plant kinds, as build commands name them; "tree" is the other kind of group.
const BRUSHES := ["grass", "flowers"]


## One kind of plant, in numbered slots. Slots filled before `keep()` are the meadow's own: `keep()` bakes them into
## one MultiMesh per CELL square, so the camera culls those off screen, and they are never recycled. Later slots fill
## a fixed-capacity MultiMesh in order and, once it is full, replace the oldest. Every tree has the same number of
## blobs, so the trunk and foliage pools recycle in step.
class Pool:
	const GONE := Vector3(1e9, 0, 1e9)
	const CELL := 16.0
	var mm := MultiMesh.new()
	## The mesh each plant was made with; `draw_with` may draw a simpler one in its place.
	var mesh: Mesh
	var kept := 0
	var last := -1
	var _next := 0
	## Bumped each time a slot is reused, so a remembered plant knows when its slot has moved on.
	var stamps := PackedInt32Array()
	var anchors := PackedVector3Array()
	var plants: Array[Plant] = []
	var _parent: Node3D
	var _mat: Material
	var _shadows: bool
	## Each slot's colour and custom data until `keep()` bakes it: a MultiMesh does not give them back.
	var _colors := PackedColorArray()
	var _customs := PackedColorArray()
	var _cell_of: Array[MultiMesh] = []
	var _index_in_cell := PackedInt32Array()
	var _cells: Array[MultiMeshInstance3D] = []
	var _centres := PackedVector2Array()

	func _init(parent: Node3D, m: Mesh, capacity: int, mat: Material, shadows: bool) -> void:
		mesh = m
		_parent = parent
		_mat = mat
		_shadows = shadows
		_setup(mm, m, capacity)
		mm.visible_instance_count = 0
		stamps.resize(capacity)
		anchors.resize(capacity)
		plants.resize(capacity)
		_colors.resize(capacity)
		_customs.resize(capacity)
		# Painting changes the instance list every frame; a fixed box spares a bounds pass over every plant.
		mm.custom_aabb = Terrain.bounds()
		_show(mm)

	## `custom`'s blue and alpha are taken for `anchor`.
	func add(xform: Transform3D, color: Color, anchor: Vector3, custom := Color()) -> Plant:
		var n := mm.visible_instance_count
		var i := kept + n
		if n < mm.instance_count:
			mm.visible_instance_count = n + 1
		elif mm.instance_count == 0:
			return null
		else:
			i = kept + _next
			_next = (_next + 1) % mm.instance_count
		last = i
		xform.origin.y -= Terrain.base_at(anchor.x, anchor.z)
		custom.b = anchor.x
		custom.a = anchor.z
		mm.set_instance_transform(i - kept, xform)
		mm.set_instance_color(i - kept, color)
		mm.set_instance_custom_data(i - kept, custom)
		if i < _colors.size():
			_colors[i] = color
			_customs[i] = custom
		stamps[i] += 1
		anchors[i] = anchor
		plants[i] = Plant.new(self, i, xform, anchor)
		return plants[i]

	func keep() -> void:
		kept = mm.visible_instance_count
		var cells := {}
		for i in kept:
			var o := plants[i].xform.origin
			cells.get_or_add(Vector2i(floori(o.x / CELL), floori(o.z / CELL)), []).append(i)
		_cell_of.resize(kept)
		_index_in_cell.resize(kept)
		var ground := Terrain.bounds()
		for key: Vector2i in cells:
			var slots: Array = cells[key]
			var cell := MultiMesh.new()
			_setup(cell, mm.mesh, slots.size())
			var box: AABB = plants[slots[0]].xform * mesh.get_aabb()
			for j in slots.size():
				var i: int = slots[j]
				cell.set_instance_transform(j, plants[i].xform)
				cell.set_instance_color(j, _colors[i])
				cell.set_instance_custom_data(j, _customs[i])
				_cell_of[i] = cell
				_index_in_cell[i] = j
				box = box.merge(plants[i].xform * mesh.get_aabb())
			# Heights are kept above the ground, which the shaders add; wind and hands bend blades a little further.
			box.position.y += ground.position.y
			box.size.y += ground.size.y
			cell.custom_aabb = box.grow(0.5)
			_cells.append(_show(cell))
			_centres.append((Vector2(key) + Vector2(0.5, 0.5)) * CELL)
		_colors = PackedColorArray()
		_customs = PackedColorArray()
		mm.instance_count = mm.instance_count - kept
		mm.visible_instance_count = 0

	func size() -> int:
		return kept + mm.visible_instance_count

	## Back to the kept plants; plants remembered from the rest no longer find their slots.
	func reset() -> void:
		for i in range(kept, size()):
			plants[i] = null
			stamps[i] += 1
		mm.visible_instance_count = 0
		_next = 0

	func place(slot: int, xform: Transform3D) -> void:
		if slot < kept:
			_cell_of[slot].set_instance_transform(_index_in_cell[slot], xform)
		else:
			mm.set_instance_transform(slot - kept, xform)

	func draw_with(m: Mesh) -> void:
		mm.mesh = m
		for c in _cells:
			c.multimesh.mesh = m

	## Not `visibility_range_end`: that measures to the box's centre, which sits high above the ground because a
	## cell's box spans every height the terrain can be pulled to.
	func cull(eye: Vector3, reach: float) -> void:
		var r := reach + CELL * sqrt(0.5)
		for i in _cells.size():
			_cells[i].visible = _centres[i].distance_to(Vector2(eye.x, eye.z)) < r

	func _setup(m: MultiMesh, drawn: Mesh, count: int) -> void:
		m.transform_format = MultiMesh.TRANSFORM_3D
		m.use_colors = true
		m.use_custom_data = true
		m.mesh = drawn
		m.instance_count = count

	func _show(m: MultiMesh) -> MultiMeshInstance3D:
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = m
		mmi.material_override = _mat
		if not _shadows:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_parent.add_child(mmi)
		return mmi


## One instance in a pool, remembered so it can be taken out and put back.
class Plant:
	var pool: Pool
	var slot: int
	var stamp: int
	var xform: Transform3D
	var anchor: Vector3
	## Where build commands find it: its group (0 is the meadow's own, else the command that grew it)
	## and its place in that group.
	var group := -1
	var index := -1

	func _init(p: Pool, i: int, x: Transform3D, a: Vector3) -> void:
		pool = p
		slot = i
		stamp = p.stamps[i]
		xform = x
		anchor = a

	func current() -> bool:
		return pool.stamps[slot] == stamp

	func shown() -> bool:
		return current() and pool.anchors[slot] != Pool.GONE

	func set_shown(on: bool) -> void:
		if not current():
			return
		pool.place(slot, xform if on else Transform3D(Basis.from_scale(Vector3.ZERO), xform.origin))
		pool.anchors[slot] = anchor if on else Pool.GONE


var grass: Pool
var grass_mat := ShaderMaterial.new()
var flowers: Pool
var trunks: Pool
var foliage: Pool
## Each tree's trunk and blobs, by trunk slot.
var _trees := {}
var _kept_trees := {}
## Every plant a build command can name, by group, in the order its command grew them.
var groups := {}
## A player's own stroke while it is painted and until its build command comes back, drawn apart from the
## garden's plants so that those fill their pools in command order on every machine.
var ghost_grass: Pool
var ghost_flowers: Pool
## How far from the eye grass is drawn, as Quality steps it; sub-pixel blades beyond it cost the Quest 2 most of its frame.
var grass_reach: float = Quality.ladder[0].grass_m:
	set(m):
		grass_reach = m
		grass_mat.set_shader_parameter(&"draw_reach", m)
## How far flowers are drawn, as Quality steps it: meadow, painted and a stroke's flowers alike, as grass reach is.
var flower_reach: float = Quality.ladder[0].flowers_m:
	set(m):
		flower_reach = m
		flower_mat.set_shader_parameter(&"draw_reach", m)
## Which of `_blobs` the foliage is drawn with, as Quality steps it.
var blob_detail: int = Quality.ladder[0].blob_detail:
	set(n):
		if n != blob_detail:
			blob_detail = n
			foliage.draw_with(_blobs[n])
var flower_mat: ShaderMaterial
## Foliage blobs at each detail, made up front so a step changes only which one is drawn.
var _blobs := {}


func _init() -> void:
	grass_mat.shader = load("res://src/grass.gdshader")
	grass_mat.set_shader_parameter(&"draw_reach", grass_reach)
	part(NO_HAND, NO_HAND)
	var clump := Meshes.grass_clump(7, 1, 3)
	var bloom := Meshes.flower(6)
	grass = Pool.new(self, clump, Meadow.GRASS_CLUMPS + PAINTED_GRASS, grass_mat, false)
	flower_mat = _plant_material("flower", Color.WHITE, 0.8)
	flower_mat.set_shader_parameter("stalk", Meshes.STALK)
	flower_mat.set_shader_parameter("eye", Meshes.EYE)
	flower_mat.set_shader_parameter(&"draw_reach", flower_reach)
	flowers = Pool.new(self, bloom, Meadow.FLOWERS + PAINTED_FLOWERS, flower_mat, false)
	ghost_grass = Pool.new(self, clump, Commands.MAX_STROKE * 2, grass_mat, false)
	ghost_flowers = Pool.new(self, bloom, Commands.MAX_STROKE * 2, flower_mat, false)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.16
	trunk.bottom_radius = 0.3
	trunk.height = 1.0
	trunk.radial_segments = 8
	trunk.rings = 1
	trunks = Pool.new(self, trunk, Meadow.TREES + PLACED_TREES, _plant_material("plant", Color(0.36, 0.27, 0.2), 1.0), true)
	var leaf_mat := _plant_material("leaf", Color.WHITE, 1.0)
	leaf_mat.set_shader_parameter("backlight", Color(0.25, 0.35, 0.08))
	for step in Quality.ladder:
		_blobs.get_or_add(step.blob_detail, Meshes.blob(4, step.blob_detail))
	foliage = Pool.new(self, _blobs[blob_detail], (Meadow.TREES + PLACED_TREES) * FloraLayout.BLOBS + Meadow.BUSHES, leaf_mat, true)


static func _plant_material(shader: String, albedo: Color, roughness: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/%s.gdshader" % shader)
	mat.set_shader_parameter("albedo", albedo)
	mat.set_shader_parameter("roughness", roughness)
	return mat


func _process(_delta: float) -> void:
	var eye := get_viewport().get_camera_3d()
	if eye != null:
		grass.cull(eye.global_position, grass_reach)
		flowers.cull(eye.global_position, flower_reach)


## Moves grass and flower reach toward `step`'s at Quality.REACH_RATE and draws its blobs; whether both reaches are
## there, since a step still under way is not yet the step's cost.
func approach(step: Quality.Step, delta: float) -> bool:
	var grass_m := move_toward(grass_reach, step.grass_m, Quality.REACH_RATE * delta)
	if grass_m != grass_reach:
		grass_reach = grass_m
	var flowers_m := move_toward(flower_reach, step.flowers_m, Quality.REACH_RATE * delta)
	if flowers_m != flower_reach:
		flower_reach = flowers_m
	blob_detail = step.blob_detail
	return grass_reach == step.grass_m and flower_reach == step.flowers_m


func part(left: Vector3, right: Vector3) -> void:
	grass_mat.set_shader_parameter(&"hand_left", left)
	grass_mat.set_shader_parameter(&"hand_right", right)


func add_grass(p: Vector3, rng: RandomNumberGenerator, pool := grass) -> Plant:
	var v := rng.randf_range(0.85, 1.1)
	var c := FloraLayout.clump(p, FloraLayout.GRASS_CLUMP)
	return pool.add(FloraLayout.grass(p, c, rng), Color(v, v, v), p, Color(FloraLayout.dryness(p), FloraLayout.clump_trait(c, FloraLayout.Trait.TINT, FloraLayout.GRASS_CLUMP), 0, 0))


func add_flower(p: Vector3, rng: RandomNumberGenerator, pool := flowers) -> Plant:
	return pool.add(FloraLayout.flower(p, rng), FloraLayout.flower_color(p), p, Color(FloraLayout.bloom_rank(p), 0, 0, 0))


func add_tree(at: Vector3, rng: RandomNumberGenerator) -> Array[Plant]:
	var t := FloraLayout.tree(at, rng)
	var parts: Array[Plant] = []
	var trunk := trunks.add(t.trunk, Color.WHITE, at)
	if trunk == null:
		return parts
	parts.append(trunk)
	for b in t.blobs:
		var blob := foliage.add(b[0], b[1], at)
		if blob != null:
			parts.append(blob)
	_trees[trunk.slot] = parts
	return parts


func add_bush(at: Vector3, rng: RandomNumberGenerator) -> void:
	var b := FloraLayout.bush(at, rng)
	foliage.add(b[0], b[1], at)


## The plants so far are the meadow's own: group 0, which every machine grows alike.
func keep() -> void:
	var meadow: Array[Plant] = []
	for p: Pool in [grass, flowers, trunks, foliage]:
		meadow.append_array(p.plants.slice(0, p.size()))
		p.keep()
	_name(0, meadow)
	_kept_trees = _trees.duplicate()


func _name(group: int, plants: Array[Plant]) -> void:
	for i in plants.size():
		if plants[i] != null:
			plants[i].group = group
			plants[i].index = i
	groups[group] = plants


## Whether a painted plant would land on bare ground (a path or stone) in the garden, where it would be
## parted to nothing yet take a slot.
static func on_path(p: Vector3) -> bool:
	return Ground.laid_bare(p.x, p.z) > 0.9


## One dab of a brush into the ghost pools: `count` plants of `kind` spread over a disc, none on bare ground.
func dab(kind: String, center: Vector3, radius: float, count: int, rng: RandomNumberGenerator) -> Array[Plant]:
	var out: Array[Plant] = []
	for p in FloraLayout.brush(center, radius, count, rng, Terrain.base_at):
		out.append(null if Ground.bare(p.x, p.z) > 0.9 else _paint(kind, p, rng, true))
	return out


func _paint(kind: String, p: Vector3, rng: RandomNumberGenerator, ghost: bool) -> Plant:
	if kind == "grass":
		return add_grass(p, rng, ghost_grass if ghost else grass)
	return add_flower(p, rng, ghost_flowers if ghost else flowers)


## Grows a group from its build command: a seeded paint stroke, which grows exactly the plants its
## author's ghost showed, or a tree. A stroke records in `skip` the plants that fell on bare ground when it
## grew, so a garden rebuilt later grows the same plants whatever paths and stone stand by then.
func grow(id: int, g: Dictionary) -> Array[Plant]:
	var plants: Array[Plant] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = g.seed
	if g.kind == "tree":
		plants = add_tree(Vector3(g.at.x, Terrain.base_at(g.at.x, g.at.z), g.at.z), rng)
	else:
		var record := not g.has("skip")
		var skip := {}
		for i in g.get("skip", []):
			skip[i] = true
		var skipped := PackedInt32Array()
		for d in g.dabs:
			for p in FloraLayout.brush(d[0], d[1], d[2], rng, Terrain.base_at):
				var i := plants.size()
				if skip.has(i) or record and on_path(p):
					skipped.append(i)
					plants.append(null)
				else:
					plants.append(_paint(g.kind, p, rng, false))
		g.skip = skipped
	_name(id, plants)
	return plants


func clear_ghosts() -> void:
	ghost_grass.reset()
	ghost_flowers.reset()


## Shows or hides the plants at `indices` of a group; returns the indices that changed.
func set_shown(group: int, indices: PackedInt32Array, on: bool) -> PackedInt32Array:
	var changed := PackedInt32Array()
	var plants: Array = groups.get(group, [])
	for i in indices:
		var p: Plant = plants[i] if i >= 0 and i < plants.size() else null
		if p != null and p.current() and p.shown() != on:
			p.set_shown(on)
			changed.append(i)
	return changed


## Back to the meadow alone, every one of its plants standing.
func reset() -> void:
	for p in [grass, flowers, trunks, foliage, ghost_grass, ghost_flowers]:
		p.reset()
	var meadow: Array[Plant] = groups[0]
	groups = {0: meadow}
	for plant in meadow:
		plant.set_shown(true)
	_trees = _kept_trees.duplicate()


## The standing tree whose trunk is nearest `p` across the ground, within `reach`.
func tree_near(p: Vector3, reach: float) -> Array[Plant]:
	var best: Array[Plant] = []
	var best_d := reach * reach
	for parts: Array[Plant] in _trees.values():
		var trunk := parts[0]
		if not trunk.shown():
			continue
		var d := Vector2(trunk.anchor.x - p.x, trunk.anchor.z - p.z).length_squared()
		if d < best_d:
			best_d = d
			best = parts
	return best


## The standing trees planted in the garden, each as its trunk then its blobs; the meadow's own are left out.
func planted_trees() -> Array[Array]:
	var out: Array[Array] = []
	for parts: Array[Plant] in _trees.values():
		if parts[0].slot >= trunks.kept and parts[0].shown():
			out.append(parts)
	return out


## Painted grass and flowers standing within `radius` of `p` across the ground; the meadow's own stay.
func painted_near(p: Vector3, radius: float) -> Array[Plant]:
	var out: Array[Plant] = []
	var r2 := radius * radius
	for pool in [grass, flowers]:
		var anchors: PackedVector3Array = pool.anchors
		for i in range(pool.kept, pool.size()):
			var q := anchors[i]
			if (q.x - p.x) * (q.x - p.x) + (q.z - p.z) * (q.z - p.z) < r2:
				out.append(pool.plants[i])
	return out


## Where trees and bushes stand: the ground points a wall arches over.
func obstacles() -> PackedVector3Array:
	var out := PackedVector3Array()
	for pool in [trunks, foliage]:
		for i in pool.size():
			if pool.anchors[i] != Pool.GONE:
				out.append(pool.anchors[i])
	return out


## Pools and their plants point at each other; the cycle is cut here so both are freed.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for p in [grass, flowers, trunks, foliage, ghost_grass, ghost_flowers]:
			p.plants.clear()
