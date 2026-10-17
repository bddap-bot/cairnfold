extends SceneTree

## Headless checks of the ground mask and stone ground: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_ground.gd

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_a_stroke_lays_stone_with_a_soft_edge()
	_grass_and_flowers_skip_stone()
	_a_stone_stroke_is_one_undo_step()
	_one_ground_stroke_at_a_time()
	_meadow_takes_back_stone_but_not_a_path()
	_lifting_a_path_keeps_the_stone_laid_after_it()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


## The stone tool in hand, its paths and plants, idle so a test drives it.
func _setup() -> Array:
	Ground.install()
	var rig := Rig.new()
	root.add_child(rig)
	var world := World.new()
	root.add_child(world)
	var paths := Paths.new()
	root.add_child(paths)
	var flora := Flora.new()
	root.add_child(flora)
	flora.keep()
	var tool := FloraTool.new(rig, flora, paths, world)
	root.add_child(tool)
	tool.set_process(false)
	world.attach(null, flora, paths, null)
	return [tool, paths, world, flora]


## Draws a path and sends it to the garden, as the path tool does; returns its id.
func _lay(nodes: Array, a: Vector2, b: Vector2, half: float) -> int:
	var paths: Paths = nodes[1]
	var world: World = nodes[2]
	paths.begin(Terrain.ground(a.x, a.y), half)
	for i in 41:
		var p := a.lerp(b, i / 40.0)
		paths.extend(Terrain.ground(p.x, p.y), half)
	var ghost := paths.end()
	world.submit({"op": "path", "path": ghost.data}, paths.drop.bind(ghost))
	return world.seq


func _teardown(nodes: Array) -> void:
	for n in nodes:
		n.queue_free()


## Sweeps the brush of `hand` holding `held` from `a` to `b` over a second and lets go, as a trigger held does.
func _stroke(t: FloraTool, hand: int, held: Hand.Tool, a: Vector2, b: Vector2, radius: float) -> void:
	var brush := t.brushes[hand]
	brush.hand.tool = held
	brush.meadow = FloraTool.paints_meadow(held, Terrain.ground(a.x, a.y))
	for i in 61:
		var p := a.lerp(b, i / 60.0)
		t.paint(brush, Terrain.ground(p.x, p.y), radius, 1.0 / 60.0)
	t.end_stroke(brush)
	t.flora.grow_now()


func _a_stroke_lays_stone_with_a_soft_edge() -> void:
	var nodes := _setup()
	_stroke(nodes[0], 0, Hand.Tool.STONE, Vector2(-4, 10), Vector2(4, 10), 2.0)
	_check(Ground.stone(0, 10) > 0.99 and Ground.bare(0, 10) > 0.99, "the stroke's middle is stone (%.2f)" % Ground.stone(0, 10))
	var edge := Ground.stone(0, 11.8)
	_check(edge > 0.05 and edge < 0.95, "its edge fades into the meadow (%.2f)" % edge)
	_check(Ground.stone(0, 13) == 0.0, "the meadow a metre past the brush is untouched (%.2f)" % Ground.stone(0, 13))
	_teardown(nodes)


func _grass_and_flowers_skip_stone() -> void:
	var nodes := _setup()
	var t: FloraTool = nodes[0]
	var flora: Flora = nodes[3]
	_stroke(t, 0, Hand.Tool.STONE, Vector2(-4, 20), Vector2(4, 20), 2.0)
	var grass := flora.grass.size()
	var flowers := flora.flowers.size()
	_stroke(t, 1, Hand.Tool.GRASS, Vector2(-2, 20), Vector2(2, 20), 0.8)
	_stroke(t, 1, Hand.Tool.FLOWERS, Vector2(-2, 20), Vector2(2, 20), 0.8)
	_check(flora.grass.size() == grass, "grass painted on stone takes no plants (%d added)" % (flora.grass.size() - grass))
	_check(flora.flowers.size() == flowers, "flowers painted on stone take no plants (%d added)" % (flora.flowers.size() - flowers))
	_check(Ground.stone(0, 20) > 0.99, "painting plants leaves the stone (%.2f)" % Ground.stone(0, 20))
	_stroke(t, 1, Hand.Tool.GRASS, Vector2(-2, 26), Vector2(2, 26), 0.8)
	_check(flora.grass.size() > grass, "grass beside the stone still grows")
	_teardown(nodes)


func _one_ground_stroke_at_a_time() -> void:
	var nodes := _setup()
	var t: FloraTool = nodes[0]
	t.brushes[0].hand.tool = Hand.Tool.STONE
	t.brushes[1].hand.tool = Hand.Tool.STONE
	t.paint(t.brushes[0], Terrain.ground(0, 60), 1.5, 0.1)
	t.paint(t.brushes[1], Terrain.ground(10, 60), 1.5, 0.1)
	_check(Ground.stone(10, 60) == 0.0 and t.brushes[1].ground == null, "the other hand lays no stone while one stroke is live")
	t.end_stroke(t.brushes[0])
	_teardown(nodes)


func _a_stone_stroke_is_one_undo_step() -> void:
	var nodes := _setup()
	var world: World = nodes[2]
	var steps: int = world.stacks.get(world.me(), {"undo": []}).undo.size()
	_stroke(nodes[0], 0, Hand.Tool.STONE, Vector2(-4, 30), Vector2(4, 30), 1.5)
	_check(world.stacks[world.me()].undo.size() == steps + 1, "a stroke is one history step (%d)" % (world.stacks[world.me()].undo.size() - steps))
	world.undo()
	_check(Ground.stone(0, 30) == 0.0, "undo takes the stone up (%.2f)" % Ground.stone(0, 30))
	world.redo()
	Ground.settle()
	_check(Ground.stone(0, 30) > 0.99, "redo lays it again (%.2f)" % Ground.stone(0, 30))
	var under := Ground.Stroke.new(Ground.Kind.STONE)
	under.add(10, 30, 2.0, 0.5)
	Ground.lay(under, 1000)
	var over := Ground.Stroke.new(Ground.Kind.STONE)
	over.add(10, 30, 0.8, 0.5)
	Ground.lay(over, 1001)
	Ground.lift(under)
	_check(Ground.stone(10, 30) > 0.99 and Ground.stone(12, 30) == 0.0, "stone laid over stone keeps its own when the stone under it is lifted (%.2f)" % Ground.stone(10, 30))
	_teardown(nodes)


func _meadow_takes_back_stone_but_not_a_path() -> void:
	var nodes := _setup()
	var t: FloraTool = nodes[0]
	var world: World = nodes[2]
	_lay(nodes, Vector2(-6, 40), Vector2(6, 40), 0.8)
	_stroke(t, 0, Hand.Tool.STONE, Vector2(-4, 40.5), Vector2(4, 40.5), 1.5)
	_check(Ground.stone(0, 40) > 0.99, "stone laid over the path covers it (%.2f)" % Ground.stone(0, 40))
	_stroke(t, 0, Hand.Tool.STONE, Vector2(-4, 40.5), Vector2(4, 40.5), 2.5)
	_check(Ground.stone(0, 40.5) == 0.0 and Ground.stone(0, 40) == 0.0, "a stone stroke begun on stone paints it back to meadow (%.2f)" % Ground.stone(0, 40.5))
	Ground.settle()
	_check(Ground.bare(0, 40) > 0.99, "and the path under the stone is still worn (%.2f)" % Ground.bare(0, 40))
	world.undo()
	_check(Ground.stone(0, 40.5) > 0.99, "undoing the meadow stroke brings the stone back (%.2f)" % Ground.stone(0, 40.5))
	_teardown(nodes)


func _lifting_a_path_keeps_the_stone_laid_after_it() -> void:
	var nodes := _setup()
	var world: World = nodes[2]
	var path := _lay(nodes, Vector2(-6, 50), Vector2(6, 50), 0.8)
	_stroke(nodes[0], 0, Hand.Tool.STONE, Vector2(0, 46), Vector2(0, 54), 1.5)
	world._order({"op": "unpath", "id": path}, world.me())
	_check(Ground.stone(0, 50) > 0.99, "stone laid over a path stays when the path is lifted (%.2f)" % Ground.stone(0, 50))
	_check(Ground.bare(5, 50) == 0.0, "the path's own wear goes with it (%.2f)" % Ground.bare(5, 50))
	_teardown(nodes)
