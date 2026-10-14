extends SceneTree

## Headless checks of flora placement and the flower and grass brushes: godot4 --headless --path game --script ../tests/test_flora.gd

var failures := 0


func _initialize() -> void:
	_brush_fills_its_disc()
	_painting_again_thickens()
	_brush_grows_with_distance()
	_tree_stands_on_its_spot()
	_full_pools_recycle_only_painted()
	_trees_recycle_whole()
	_grass_grows_in_clumps()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	quit(1 if failures else 0)


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
	var history := History.new(rig.left)
	root.add_child(history)
	var paths := Paths.new()
	root.add_child(paths)
	var t := FloraTool.new(rig, flora, paths, history)
	t.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(t)
	return t


func _painting_again_thickens() -> void:
	var t := _tool()
	var at := Vector3(2, Terrain.height_at(2, 2), 2)
	var b := t.brushes[0]
	b.hand.tool = Hand.Tool.FLOWERS
	for i in 60:
		t.paint(b, at, 1.0, 1.0 / 60.0)
	var once := t.flora.flowers.size()
	for i in 60:
		t.paint(b, at, 1.0, 1.0 / 60.0)
	_check(once > 0, "a second of painting adds flowers")
	_check(absf(t.flora.flowers.size() - 2 * once) <= 1, "a second pass doubles them, %d then %d" % [once, t.flora.flowers.size()])
	_check(t.flora.grass.size() == 0, "the flower brush leaves the grass alone")
	b.hand.tool = Hand.Tool.GRASS
	t.paint(b, at, 1.0, 1.0)
	_check(t.flora.grass.size() > once, "the grass brush paints grass, denser than flowers")


func _brush_grows_with_distance() -> void:
	var hand := Vector3(0, 1.2, 0)
	var near := FloraTool.brush_radius(hand, Vector3(0, 0, -2))
	var far := FloraTool.brush_radius(hand, Vector3(0, 0, -12))
	_check(far > near * 1.5, "pointing farther paints wider, %.2f to %.2f" % [near, far])
	_check(FloraTool.brush_radius(hand, Vector3(0, 0, -200)) == FloraTool.MAX_RADIUS, "the brush has a cap")


func _tree_stands_on_its_spot() -> void:
	var at := Vector3(4, Terrain.height_at(4, -3), -3)
	var tree := FloraLayout.tree(at, _rng(3))
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
	for i in 100:
		t.flora.add_flower(Vector3.ZERO, rng)
	t.flora.keep()
	var slots := {}
	for i in pool.mm.instance_count + 10:
		t.flora.add_flower(Vector3.ZERO, rng)
		slots[pool.last] = true
	_check(pool.size() == pool.mm.instance_count, "a full pool draws all it holds")
	_check(slots.keys().min() == 100, "overpainting recycles painted flowers, never the meadow's own")
	_check(slots.size() == pool.mm.instance_count - 100, "and every painted slot in turn")


func _trees_recycle_whole() -> void:
	var t := _tool()
	var rng := _rng(5)
	for i in Meadow.TREES:
		t.flora.add_tree(Vector3.ZERO, rng)
	for i in Meadow.BUSHES:
		t.flora.add_bush(Vector3.ZERO, rng)
	t.flora.keep()
	var trunks := t.flora.trunks
	var foliage := t.flora.foliage
	for i in Flora.PLACED_TREES * 2 + 3:
		t.flora.add_tree(Vector3.ZERO, rng)
		var tree := trunks.last - trunks.kept
		var blob := foliage.last - foliage.kept
		if blob != (tree + 1) * FloraLayout.BLOBS - 1:
			_check(false, "placed tree %d: trunk slot %d but its last blob in slot %d" % [i, tree, blob])
			return


func _grass_grows_in_clumps() -> void:
	var rng := _rng(6)
	var c := FloraLayout.clump(Vector3(5.3, 0, -2.1))
	var sizes := []
	for i in 40:
		var a := rng.randf() * TAU
		var p := Vector3(c.x + cos(a) * 0.05, 0, c.z + sin(a) * 0.05)
		_check(FloraLayout.clump(p) == c, "points beside a clump's centre belong to it")
		sizes.append(FloraLayout.grass(p, c, rng).basis.y.y)
	var spread: float = sizes.max() / sizes.min()
	_check(spread < 1.8, "a clump's blades share a height, spread %.2f" % spread)
	var across := []
	for i in 40:
		var o := FloraLayout.clump(Vector3(i * 1.3, 0, i * 0.7))
		across.append(FloraLayout.grass(o, o, rng).basis.y.y)
	_check(across.max() / across.min() > spread * 1.2, "clumps differ in height more than blades within one, %.2f against %.2f" % [across.max() / across.min(), spread])
	var lean := FloraLayout.grass(c + Vector3(0.05, 0, 0), c, rng).basis.y
	_check(lean.x > 0.0 and absf(lean.z) < 1e-4, "blades lean away from their clump's centre")
