extends SceneTree

## Headless checks of the tool wheel's selection by direction: godot4 --headless --path game --script ../tests/test_wheel.gd

var failures := 0


func _init() -> void:
	_every_tool_has_one_fixed_path()
	_the_wheel_opens_with_nothing_hot()
	_a_sweep_picks_the_slot_it_heads_for()
	_a_subtree_opens_away_from_the_swing()
	_inside_a_subtree_the_swing_side_picks_nothing()
	_a_deep_pick_zig_zags()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	quit(1 if failures else 0)


func _every_tool_has_one_fixed_path() -> void:
	var paths := ToolWheel.paths(Hand.TREE)
	_check(Hand.TREE.size() == ToolWheel.SLOTS, "the wheel has %d slots, not %d" % [Hand.TREE.size(), ToolWheel.SLOTS])
	_check(paths.size() == Hand.Tool.size(), "%d of %d tools are on the wheel" % [paths.size(), Hand.Tool.size()])
	for t in paths:
		var w := ToolWheel.new(Hand.TREE)
		for p in ToolWheel.sweep(Hand.TREE, paths[t]):
			w.move(p)
		_check(w.chosen() == t, "sweeping along its path picks %s, got %s" % [Hand.Tool.keys()[t], w.chosen()])
	for k in Hand.TREE.size():
		var d := ToolWheel.ring_dirs()[k]
		if Hand.TREE[k] is Array:
			_check(absf(d.x) > 0.5, "subtree slot %d is reached by a sideways swing" % k)
			_check(Hand.TREE[k].size() <= 4, "subtree slot %d holds at most four" % k)


func _the_wheel_opens_with_nothing_hot() -> void:
	var w := ToolWheel.new(Hand.TREE)
	w.move(Vector2.ZERO)
	_check(w.chosen() == null and w.levels[0].hot == -1, "an unmoved hand is on nothing")
	w.move(Vector2(0.02, 0.02))
	_check(w.levels[0].hot == -1, "a tremble inside the dead zone is on nothing")


func _a_sweep_picks_the_slot_it_heads_for() -> void:
	var dirs := ToolWheel.ring_dirs()
	_check(dirs[0].y > 0.99, "slot 0 is at the top")
	_check(dirs[2].x > 0.99, "slot 2 is on the player's right")
	for k in ToolWheel.SLOTS:
		for off in [-20.0, 0.0, 20.0]:
			var w := ToolWheel.new(Hand.TREE)
			w.move(dirs[k].rotated(deg_to_rad(off)) * ToolWheel.DEAD * 1.3)
			_check(w.levels[0].hot == k, "a short sweep %+.0f° off slot %d heads for it, got %d" % [off, k, w.levels[0].hot])
	var w := ToolWheel.new(Hand.TREE)
	w.move(dirs[0] * ToolWheel.RADIUS)
	w.move(dirs[4] * ToolWheel.RADIUS)
	_check(w.chosen() == Hand.TREE[4], "sweeping on to another slot moves the pick")
	var empty := Hand.TREE.find(null)
	if empty >= 0:
		w.move(dirs[empty] * ToolWheel.RADIUS)
		_check(w.levels[0].hot == empty and w.chosen() == null, "an empty slot picks nothing")


func _a_subtree_opens_away_from_the_swing() -> void:
	var dirs := ToolWheel.ring_dirs()
	for k in Hand.TREE.size():
		if not Hand.TREE[k] is Array:
			continue
		var w := ToolWheel.new(Hand.TREE)
		w.move(dirs[k] * ToolWheel.DEAD * 1.5)
		_check(w.levels.size() == 1 and w.chosen() == null, "heading for subtree %d marks it without opening it" % k)
		w.move(dirs[k] * ToolWheel.RADIUS)
		_check(w.levels.size() == 2 and w.chosen() == null, "reaching subtree %d opens it, with nothing in it hot" % k)
		for d in w.levels[1].dirs.slice(0, Hand.TREE[k].size()):
			_check(signf(d.x) == -signf(dirs[k].x), "subtree %d's items open on the side away from the swing" % k)
		var items: Array = Hand.TREE[k]
		for j in items.size():
			var v := ToolWheel.new(Hand.TREE)
			v.move(dirs[k] * ToolWheel.RADIUS)
			v.move(w.levels[1].centre + w.levels[1].dirs[j] * ToolWheel.RADIUS)
			_check(v.chosen() == items[j], "swinging back onto item %d of subtree %d picks it" % [j, k])


func _inside_a_subtree_the_swing_side_picks_nothing() -> void:
	var right := 2
	assert(Hand.TREE[right] is Array)
	var w := ToolWheel.new(Hand.TREE)
	var at := ToolWheel.ring_dirs()[right] * ToolWheel.RADIUS
	w.move(at)
	w.move(at + Vector2(ToolWheel.RADIUS, 0))
	_check(w.levels.size() == 2 and w.chosen() == null, "overshooting a subtree picks nothing")


func _a_deep_pick_zig_zags() -> void:
	var tree := ["a", "b", ["c", ["d", "e", "f"], "g"], "h", "i", "j", "k", "l"]
	var path := ToolWheel.paths(tree)["e"] as Array[int]
	_check(path == [2, 1, 1], "e's path is %s" % [path])
	var w := ToolWheel.new(tree)
	var points := ToolWheel.sweep(tree, path)
	var from := Vector2.ZERO
	var swings: Array[float] = []
	for p in points:
		for f in 8:
			w.move(from.lerp(p, (f + 1) / 8.0))
		swings.append(signf(p.x - from.x))
		from = p
	_check(swings == [1.0, -1.0, 1.0], "the pick swings right, left, right: %s" % [swings])
	_check(w.levels.size() == 3 and w.chosen() == "e", "and lands on e, got %s" % [w.chosen()])


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)
