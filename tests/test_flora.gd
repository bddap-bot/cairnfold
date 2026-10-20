extends SceneTree

## Headless checks of flora placement and the flower and grass brushes: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_flora.gd

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_brush_fills_its_disc()
	_painting_again_thickens()
	_a_stroke_grows_over_frames()
	_brush_grows_with_distance()
	_tree_stands_on_its_spot()
	_full_pools_recycle_only_painted()
	_only_placed_plants_grow_under_water()
	_planted_flowers_take_their_water_form_by_depth()
	_trees_recycle_whole()
	_grass_grows_in_clumps()
	_flowers_vary_by_patch()
	_grass_thins_with_distance()
	_flowers_out_of_reach_are_not_drawn()
	_far_plants_follow_the_pool()
	_blob_detail_changes_only_what_is_drawn()
	_crowns_cast_one_shade_each()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _rng(seed: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	return r


func _brush_fills_its_disc() -> void:
	var c := Vector3(3, 0, -2)
	var pts := FloraLayout.brush(c, 1.5, 400, _rng(1), Terrain.height_at)
	_check(pts.size() == 400, "the brush places what it is asked to")
	var inner := 0
	for p in pts:
		if Vector2(p.x - c.x, p.z - c.z).length() > 1.5 + 1e-4:
			_check(false, "a plant at %s is outside the brush" % p)
			return
		if absf(p.y - (Terrain.height_at(p.x, p.z) - 0.02)) > 1e-4:
			_check(false, "a plant at %s is not set into the ground" % p)
			return
		if Vector2(p.x - c.x, p.z - c.z).length() < 1.5 / sqrt(2.0):
			inner += 1
	_check(absf(inner - 200) < 40, "spread evenly over the disc's area, %d of 400 in the inner half" % inner)


func _tool() -> FloraTool:
	var rig := Rig.new()
	root.add_child(rig)
	var flora := Flora.new()
	root.add_child(flora)
	var world := World.new()
	root.add_child(world)
	var paths := Paths.new()
	root.add_child(paths)
	var t := FloraTool.new(rig, flora, paths, world)
	t.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(t)
	world.attach(null, flora, paths, null)
	return t


func _a_stroke_grows_over_frames() -> void:
	var t := _tool()
	var b := t.brushes[0]
	b.hand.tool = Hand.Tool.GRASS
	for i in 60:
		t.paint(b, Terrain.ground(20, 20), 3.0, 1.0 / 60.0)
	var ghost := b.stroke.filter(func(p: Variant) -> bool: return p != null)
	var before := t.flora.grass.size()
	t.end_stroke(b)
	var group: int = t.world.seq
	_check(t.flora.growing() and t.flora.grass.size() == before, "a committed stroke grows nothing in the frame it lands in")
	var ticks := [0]
	t.flora._grow(Flora.GROW_USEC, func() -> int:
		ticks[0] += 100
		return ticks[0])
	var grown := t.flora.grass.size() - before
	_check(grown > 0 and grown < ghost.size(), "a frame grows a share of its %d plants, %d" % [ghost.size(), grown])
	_check(ghost.all(func(p: Flora.Plant) -> bool: return p.shown()), "its ghost stands until it has grown")
	t.world.submit({"op": "plant", "kind": "tree", "seed": 1, "at": Terrain.ground(26, 20)})
	_check(t.flora.growing(), "a tree planted meanwhile leaves it growing")
	t.world.submit({"op": "show", "plants": {group: PackedInt32Array([0])}, "on": false})
	_check(not t.flora.growing() and t.flora.grass.size() - before == ghost.size(), "a command on its plants grows it all first, %d of %d" % [t.flora.grass.size() - before, ghost.size()])
	_check(not t.flora.groups[group][0].shown(), "and then applies to them")
	_check(ghost.all(func(p: Flora.Plant) -> bool: return not p.shown()), "and then its ghost goes")
	var looks := func(p: Flora.Plant) -> Array: return [p.anchor, p.xform, p.pool.mm.get_instance_color(p.slot - p.pool.kept)]
	var grown_looks: Array = t.flora.groups[group].filter(func(p: Variant) -> bool: return p != null).map(looks)
	_check(grown_looks == ghost.map(looks), "the stroke grows the plants its ghost showed, as it showed them")


func _painting_again_thickens() -> void:
	var t := _tool()
	var at := Vector3(2, Terrain.height_at(2, 2), 2)
	var b := t.brushes[0]
	b.hand.tool = Hand.Tool.FLOWERS
	for i in 60:
		t.paint(b, at, 1.0, 1.0 / 60.0)
	var once := t.flora.ghost_flowers.size()
	for i in 60:
		t.paint(b, at, 1.0, 1.0 / 60.0)
	_check(once > 0, "a second of painting adds flowers")
	_check(absf(t.flora.ghost_flowers.size() - 2 * once) <= 1, "a second pass doubles them, %d then %d" % [once, t.flora.ghost_flowers.size()])
	_check(t.flora.ghost_grass.size() == 0, "the flower brush leaves the grass alone")
	var painted := t.flora.ghost_flowers.size()
	t.end_stroke(b)
	t.flora.grow_now()
	_check(t.flora.flowers.size() - t.flora.flowers.kept == painted, "letting go grows the stroke in the garden, %d of %d" % [t.flora.flowers.size() - t.flora.flowers.kept, painted])
	_check(t.flora.ghost_flowers.size() == 0, "and clears its ghost, %d left" % t.flora.ghost_flowers.size())
	b.hand.tool = Hand.Tool.GRASS
	t.paint(b, at, 1.0, 1.0)
	_check(t.flora.ghost_grass.size() > once, "the grass brush paints grass, denser than flowers")


func _brush_grows_with_distance() -> void:
	var hand := Vector3(0, 1.2, 0)
	var near := FloraTool.brush_radius(hand, Vector3(0, 0, -2))
	var far := FloraTool.brush_radius(hand, Vector3(0, 0, -12))
	_check(far > near * 1.5, "pointing farther paints wider, %.2f to %.2f" % [near, far])
	_check(FloraTool.brush_radius(hand, Vector3(0, 0, -200)) == FloraTool.MAX_RADIUS, "the brush has a cap")


func _tree_stands_on_its_spot() -> void:
	var at := Vector3(4, Terrain.height_at(4, -3), -3)
	var tree := FloraLayout.tree(at, 3)
	var trunk: Transform3D = tree.trunk
	_check(Vector2(trunk.origin.x - at.x, trunk.origin.z - at.z).length() < 1e-4, "the trunk stands where the hand pointed")
	_check(trunk.origin.y - trunk.basis.y.length() * 0.5 < at.y, "the trunk's foot is in the ground")
	_check(tree.blobs.size() == FloraLayout.BLOBS, "a fixed number of foliage blobs")
	for b in tree.blobs:
		if b[0].origin.y < at.y + 1.5:
			_check(false, "foliage hangs below the crown")
			return


func _full_pools_recycle_only_painted() -> void:
	var t := _tool()
	var pool := t.flora.flowers
	var rng := _rng(4)
	var spots := []
	for i in 100:
		spots.append(Vector3(rng.randf_range(-30, 30), 0, rng.randf_range(-30, 30)))
		t.flora.add_flower(spots[-1], rng)
	t.flora.keep()
	var slots := {}
	for i in pool.mm.instance_count + 10:
		t.flora.add_flower(Vector3.ZERO, rng)
		slots[pool.last] = true
	_check(pool.size() == 100 + pool.mm.instance_count, "a full pool draws all it holds")
	_check(slots.keys().min() == 100, "overpainting recycles painted flowers, never the meadow's own")
	_check(slots.size() == pool.mm.instance_count, "and every painted slot in turn")
	var meadow := 0
	var boxes := []
	for mmi: MultiMeshInstance3D in t.flora.get_children():
		if mmi.multimesh != pool.mm and mmi.multimesh != t.flora.ghost_flowers.mm and mmi.multimesh.mesh == pool.kept_mesh:
			meadow += mmi.multimesh.instance_count
			boxes.append(mmi.multimesh.custom_aabb)
	_check(meadow == 100, "the meadow's own flowers are baked into cells: %d" % meadow)
	var own := pool.plants[0]
	own.set_shown(false)
	_check(not own.shown(), "a meadow flower can be taken out of its cell")
	own.set_shown(true)
	_check(own.shown(), "and put back")
	_check(boxes.size() > 4, "spread over cells the camera can cull: %d" % boxes.size())
	for p: Vector3 in spots:
		_check(boxes.any(func(b: AABB) -> bool: return b.has_point(Vector3(p.x, Terrain.height_at(p.x, p.z) + 0.1, p.z))), "a meadow flower at %s lies in a cell's box" % p)


## The grass and flower shaders grow placed plants under a pond as water plants and drown the meadow's own, told apart
## by `planted`.
func _only_placed_plants_grow_under_water() -> void:
	var t := _tool()
	var rng := _rng(9)
	for i in 50:
		t.flora.add_grass(Vector3(rng.randf_range(-30, 30), 0, rng.randf_range(-30, 30)), rng)
		t.flora.add_flower(Vector3(rng.randf_range(-30, 30), 0, rng.randf_range(-30, 30)), rng)
	t.flora.keep()
	var placed := [t.flora.grass.mm, t.flora.ghost_grass.mm, t.flora.flowers.mm, t.flora.ghost_flowers.mm]
	var cells := 0
	for mmi: MultiMeshInstance3D in t.flora.get_children():
		if mmi.material_override not in [t.flora.grass_mat, t.flora.flower_mat]:
			continue
		var flag: Variant = mmi.get_instance_shader_parameter(&"planted")
		if mmi.multimesh in placed:
			_check(flag == 1.0, "placed grass and flowers draw as planted")
		else:
			cells += 1
			_check(flag == null or flag == 0.0, "the meadow's own grass and flowers draw as meadow")
	_check(cells > 1, "the meadow's plants are baked into cells: %d" % cells)


## A flower planted in shallow water stands up out of it as an iris and in deep water floats as a lily, by the flower
## shader's own `water_form` of the pond depth under its root, read where the shader reads it.
func _planted_flowers_take_their_water_form_by_depth() -> void:
	var t := _tool()
	var code := (load("res://src/plant.gdshaderinc") as ShaderInclude).code
	var pick := RegEx.create_from_string("float water_form\\(float (\\w+), float (\\w+)\\) \\{\\s*return ([^;]+);\\s*\\}").search(code)
	var lily_depth := RegEx.create_from_string("uniform float lily_depth = ([0-9.]+);").search(code)
	_check(pick != null and lily_depth != null, "the flower shader picks its water form in one expression")
	if pick == null or lily_depth == null:
		return
	var form := Expression.new()
	_check(form.parse(pick.get_string(3), [pick.get_string(1), pick.get_string(2), "lily_depth"]) == OK, "the pick parses")
	Terrain.dry_water()
	var spots := {Vector2i(60, 60): 0.15, Vector2i(70, 60): 0.8, Vector2i(80, 60): Terrain.DRY}
	var water := {}
	for g: Vector2i in spots:
		if spots[g] != Terrain.DRY:
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var at := g + Vector2i(dx, dz)
					water[at] = Terrain._heights[at.y * Terrain.VERTS + at.x] + spots[g]
	Terrain.set_water(water)
	var forms := []
	for g: Vector2i in spots:
		var p := Vector3(g.x * Terrain.STEP - Terrain.SIZE * 0.5, 0, g.y * Terrain.STEP - Terrain.SIZE * 0.5)
		var plant := t.flora.add_flower(Vector3(p.x, Terrain.height_at(p.x, p.z) - 0.02, p.z), _rng(3))
		var root := plant.xform.origin
		var depth := Terrain._water_image.get_pixelv(Vector2i(roundi((root.x + Terrain.SIZE * 0.5) / Terrain.STEP), roundi((root.z + Terrain.SIZE * 0.5) / Terrain.STEP))).r
		var planted: Variant = plant.pool.live.get_instance_shader_parameter(&"planted")
		forms.append(form.execute([planted, depth, lily_depth.get_string(1).to_float()], self))
	_check(forms == [1.0, 2.0, 0.0], "a flower planted in the shallows is an iris, in deep water a lily, on land a flower: %s" % [forms])
	Terrain.dry_water()


func planted_water(placed: float, depth: float) -> float:
	var code := (load("res://src/water.gdshaderinc") as ShaderInclude).code
	var pick := RegEx.create_from_string("float planted_water\\(float (\\w+), float (\\w+)\\) \{\\s*return ([^;]+);\\s*\}").search(code)
	var wet := Expression.new()
	wet.parse(pick.get_string(3), [pick.get_string(1), pick.get_string(2)])
	return float(wet.execute([placed, depth], self))


func step(edge: float, x: float) -> float:
	return 0.0 if x < edge else 1.0


func _trees_recycle_whole() -> void:
	var t := _tool()
	var rng := _rng(5)
	for i in Meadow.TREES:
		t.flora.add_tree(Vector3.ZERO, rng.randi())
	for i in Meadow.BUSHES:
		t.flora.add_bush(Vector3.ZERO, rng)
	t.flora.keep()
	var trunks := t.flora.trunks
	var foliage := t.flora.foliage
	for i in Flora.PLACED_TREES * 2 + 3:
		t.flora.add_tree(Vector3.ZERO, rng.randi())
		var tree := trunks.last - trunks.kept
		var blob := foliage.last - foliage.kept
		if blob != (tree + 1) * FloraLayout.BLOBS - 1:
			_check(false, "placed tree %d: trunk slot %d but its last blob in slot %d" % [i, tree, blob])
			return


func _grass_grows_in_clumps() -> void:
	var rng := _rng(6)
	var c := FloraLayout.clump(Vector3(5.3, 0, -2.1), FloraLayout.GRASS_CLUMP)
	var sizes := []
	for i in 40:
		var a := rng.randf() * TAU
		var p := Vector3(c.x + cos(a) * 0.05, 0, c.z + sin(a) * 0.05)
		_check(FloraLayout.clump(p, FloraLayout.GRASS_CLUMP) == c, "points beside a clump's centre belong to it")
		sizes.append(FloraLayout.grass(p, c, rng).basis.y.y)
	var spread: float = sizes.max() / sizes.min()
	_check(spread < 1.8, "a clump's blades share a height, spread %.2f" % spread)
	var across := []
	for i in 40:
		var o := FloraLayout.clump(Vector3(i * 1.3, 0, i * 0.7), FloraLayout.GRASS_CLUMP)
		across.append(FloraLayout.grass(o, o, rng).basis.y.y)
	_check(across.max() / across.min() > spread * 1.2, "clumps differ in height more than blades within one, %.2f against %.2f" % [across.max() / across.min(), spread])
	var lean := FloraLayout.grass(c + Vector3(0.05, 0, 0), c, rng).basis.y
	_check(lean.x > 0.0 and absf(lean.z) < 1e-4, "blades lean away from their clump's centre")


func _flowers_vary_by_patch() -> void:
	var rng := _rng(3)
	var kinds := 0
	for stroke in 20:
		var colours := {}
		for p in FloraLayout.brush(Vector3(rng.randf_range(-20, 20), 0, rng.randf_range(-20, 20)), 1.2, 150, rng, Terrain.height_at):
			colours[FloraLayout.flower_color(p)] = true
		kinds += colours.size()
	_check(kinds >= 80, "a stroke paints a few colours, %.1f on average" % (kinds / 20.0))
	var pts := FloraLayout.brush(Vector3(-2, 0, 3), 2.0, 600, _rng(9), Terrain.height_at)
	var same := 0
	var near := 0
	for i in pts.size():
		var c := FloraLayout.flower_color(pts[i])
		for j in range(i + 1, pts.size()):
			if Vector2(pts[i].x - pts[j].x, pts[i].z - pts[j].z).length() < 0.15:
				near += 1
				same += int(FloraLayout.flower_color(pts[j]) == c)
	_check(same > near * 0.85, "neighbouring flowers mostly share a colour, %d of %d" % [same, near])


func _grass_thins_with_distance() -> void:
	var flora := Flora.new()
	root.add_child(flora)
	var g := flora.grass
	_check(g.sparse_from < flora.grass_reach, "grass turns sparse before its reach")
	var rng := _rng(7)
	var near := Vector3(2, 0, 0)
	var mid := g.sparse_from + g.cell * 2.0
	var survivor := Vector3(mid, 0, 0.5)
	while FloraLayout.thin_rank(survivor) >= g.survivors:
		survivor.z += 0.01
	var thinned := Vector3(mid, 0, 0.5)
	while FloraLayout.thin_rank(thinned) < g.survivors:
		thinned.z += 0.01
	var far := Vector3(flora.grass_reach + g.cell * 1.5, 0, 0)
	for p in [near, survivor, thinned, far]:
		flora.add_grass(p, rng)
	flora.keep()
	g.cull(Vector3.ZERO, flora.grass_reach)
	var whole := []
	var few := []
	for mmi: MultiMeshInstance3D in flora.get_children():
		if mmi.multimesh in [g.mm, flora.ghost_grass.mm] or not mmi.visible or not mmi.layers & Quality.VIEW_MASK:
			continue
		var at := mmi.multimesh.custom_aabb.get_center()
		if mmi.multimesh.mesh == g.mesh:
			whole.append(at.x)
		elif mmi.multimesh.mesh == g.sparse:
			few.append([at.x, mmi.multimesh.instance_count])
	_check(whole.size() == 1 and absf(whole[0] - near.x) < 1.0, "only the near cell draws every clump: %s" % [whole])
	_check(few.size() == 1 and absf(few[0][0] - mid) < 1.0 and few[0][1] == 1, "the cell past sparse_from draws its survivor alone: %s" % [few])
	_check(g.sparse.get_faces().size() < g.mesh.get_faces().size(), "from a mesh with fewer blades")
	var photo := []
	for mmi: MultiMeshInstance3D in flora.get_children():
		if mmi.multimesh not in [g.mm, flora.ghost_grass.mm] and mmi.multimesh.mesh in [g.mesh, g.sparse] and mmi.visible and mmi.layers & Quality.PHOTO_MASK:
			photo.append(mmi.multimesh.mesh == g.mesh)
	_check(photo.size() == 3 and not photo.has(false), "a photo draws every cell with every clump: %s" % [photo])
	# A dummy renderer keeps no instance transforms, so where taking a plant out writes is checked instead.
	_check(g._cell_of[1] == g._cell_of[2] and g._index_in_cell[1] != g._index_in_cell[2], "each clump of a cell has its own place in it")
	_check(g._sparse_cell_of[1] != null and g._sparse_cell_of[2] == null, "and a survivor its place in the sparse cell too")
	flora.queue_free()


func _flowers_out_of_reach_are_not_drawn() -> void:
	var flora := Flora.new()
	root.add_child(flora)
	var eye := Camera3D.new()
	root.add_child(eye)
	eye.make_current()
	_check(flora.flower_mat.get_shader_parameter(&"draw_reach") == minf(flora.flower_reach, Flora.FLOWER_NEAR), "the flowers' shader is told their reach")
	var rng := _rng(8)
	flora.add_flower(Vector3(5, 0, 0), rng)
	flora.add_flower(Vector3(5 + flora.flowers.cell * 3, 0, 0), rng)
	flora.keep()
	flora.flower_reach = 10.0
	_check(flora.flower_mat.get_shader_parameter(&"draw_reach") == 10.0, "and each new reach")
	flora._process(0.0)
	var shown := []
	for mmi: MultiMeshInstance3D in flora.get_children():
		if mmi.multimesh != flora.flowers.mm and mmi.multimesh.mesh == flora.flowers.kept_mesh and mmi.multimesh.instance_count == 1:
			shown.append(mmi.visible and mmi.layers & Quality.VIEW_MASK != 0)
	_check(shown.count(true) == 1 and shown.count(false) == 1, "of two meadow flowers, the one beyond reach is not drawn: %s" % [shown])
	eye.queue_free()
	flora.queue_free()


func _blob_detail_changes_only_what_is_drawn() -> void:
	var flora := Flora.new()
	root.add_child(flora)
	flora.add_tree(Vector3.ZERO, 9)
	flora.keep()
	flora.add_tree(Vector3(20, 0, 0), 10)
	var made := flora.foliage.mesh
	var foliage: Array[MultiMesh] = []
	for mmi: MultiMeshInstance3D in flora.get_children():
		if mmi.multimesh.mesh == made:
			foliage.append(mmi.multimesh)
	_check(foliage.size() >= 2, "the meadow's cell and the planted pool both draw foliage: %d" % foliage.size())
	flora.blob_detail = Quality.ladder[-1].blob_detail
	var coarse := flora.foliage.mm.mesh
	_check(coarse.surface_get_array_len(0) < made.surface_get_array_len(0), "the bottom step draws coarser blobs")
	_check(foliage.all(func(m: MultiMesh) -> bool: return m.mesh == coarse), "in every cell")
	_check(flora.foliage.mesh == made, "birds still find crowns on the blobs as made")
	flora.blob_detail = Quality.ladder[0].blob_detail
	_check(flora.foliage.mm.mesh == made, "and full quality draws them as made again")
	flora.queue_free()


func _crowns_cast_one_shade_each() -> void:
	var flora := Flora.new()
	root.add_child(flora)
	var tree := flora.add_tree(Vector3.ZERO, 9)
	flora.add_bush(Vector3(6, 0, 0), _rng(11))
	flora._shade_crowns()
	_check(flora.crown_shade.visible_instance_count == 2, "one shade blob for the tree and one for the bush: %d" % flora.crown_shade.visible_instance_count)
	var centre := flora.shade_of(tree).origin
	var lowest := INF
	for b in tree.slice(1):
		lowest = minf(lowest, b.xform.origin.y)
	_check(Vector2(centre.x, centre.z).length() < 2.0 and centre.y > lowest - 1.0, "the tree's shade blob sits in its crown, at %s" % centre)
	for mmi: MultiMeshInstance3D in flora.get_children():
		if mmi.multimesh.mesh == flora.foliage.mesh:
			_check(mmi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "foliage blobs cast no shade of their own")
		elif mmi.multimesh == flora.crown_shade:
			_check(mmi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "the shade blobs are never drawn, only cast")
	for p in tree:
		p.draw(false)
	flora._shade_crowns()
	_check(flora.crown_shade.visible_instance_count == 1, "a tree a tool shows taken casts no shade")
	for p in tree:
		p.draw(true)
	flora._shade_crowns()
	_check(flora.crown_shade.visible_instance_count == 2, "and casts it again when shown back")
	flora.queue_free()


func _far_plants_follow_the_pool() -> void:
	var flora := Flora.new()
	root.add_child(flora)
	var rng := _rng(91)
	for pool: Flora.Pool in [flora.grass, flora.flowers, flora.ghost_grass, flora.ghost_flowers]:
		var near := pool.mm
		var far: MultiMeshInstance3D = pool.far_live
		_check(far.layers == Quality.LADDER_LAYER, "the far representation leaves full-detail photos alone")
		_check(far.multimesh.mesh.get_faces().size() == 3, "a far plant is one triangle")
		var p := pool.add(Transform3D(Basis.IDENTITY, Vector3(4, 0, 5)), Color.RED, Vector3(4, 0, 5))
		_check(far.multimesh.visible_instance_count == 1, "painting shows a near and far instance together")
		_check_far_buffers(pool)
		p.set_shown(false)
		_check_far_buffers(pool)
		_check(not p.shown(), "mowing addresses the same plant")
		p.set_shown(true)
		_check_far_buffers(pool)
		pool.keep()
		_check_far_buffers(pool)
		var cell: MultiMesh = pool._cell_of[0]
		_check(pool.far.visible_instance_count == 1 and cell.instance_count == 1, "keeping retains the same far slot while baking its near cell")
		_check(far.multimesh.instance_count == near.instance_count + pool.kept, "the far batch retains capacity for kept and painted slots")
		pool.add(FloraLayout.flower(Vector3(9, 0, 5), rng), Color.BLUE, Vector3(9, 0, 5))
		pool.repose(p, Transform3D(Basis.from_scale(Vector3.ONE * 1.2), p.anchor), Color.GREEN)
		_check_far_buffers(pool)
		pool.reset()
		_check_far_buffers(pool)
		_check(far.multimesh.visible_instance_count == pool.kept, "reset leaves only the kept far plants")
	flora.queue_free()


func _check_far_buffers(pool: Flora.Pool) -> void:
	# The dummy renderer does not retain instance buffers; the desktop run checks every attribute, including mown transforms.
	if RenderingServer.get_rendering_device() == null:
		return
	for i in pool.size():
		var source: MultiMesh = pool._cell_of[i] if i < pool.kept else pool.mm
		var index: int = pool._index_in_cell[i] if i < pool.kept else i - pool.kept
		_check(source.buffer.slice(index * 20, (index + 1) * 20) == pool.far.buffer.slice(i * 20, (i + 1) * 20), "both representations contain identical transforms, colours and custom attributes")
