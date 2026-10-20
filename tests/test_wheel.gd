extends SceneTree

## Headless checks of the tool wheel's selection by direction: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_wheel.gd

var failures := 0


func _init() -> void:
	_every_tool_has_one_fixed_path()
	_the_wheel_opens_with_nothing_hot()
	_a_sweep_picks_the_slot_it_heads_for()
	_a_subtree_opens_away_from_the_swing()
	_inside_a_subtree_the_swing_side_picks_nothing()
	_colour_and_style_are_one_swing_up()
	_a_deep_pick_zig_zags()
	_the_wheel_faces_the_head_wherever_the_hand_is()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _every_tool_has_one_fixed_path() -> void:
	var paths := ToolWheel.paths(Hand.TREE)
	_check(Hand.TREE.size() == ToolWheel.SLOTS, "the wheel has %d slots, not %d" % [Hand.TREE.size(), ToolWheel.SLOTS])
	_check(paths.size() == Hand.Tool.size() - 1 and not paths.has(Hand.Tool.NONE), "%d of %d tools, every one but none, are on the wheel" % [paths.size(), Hand.Tool.size()])
	for t in paths:
		var w := ToolWheel.new(Hand.TREE)
		for p in ToolWheel.sweep(Hand.TREE, paths[t]):
			w.move(p)
		_check(w.chosen() == t, "sweeping along its path picks %s, got %s" % [Hand.Tool.keys()[t], w.chosen()])
	for k in Hand.TREE.size():
		var d := ToolWheel.ring_dirs()[k]
		if Hand.TREE[k] is Array:
			var most := 4 if absf(d.x) > 0.5 else 2
			_check(Hand.TREE[k].size() <= most, "subtree slot %d holds at most %d" % [k, most])


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
	w.move(dirs[3] * ToolWheel.DEAD * 1.3)
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
		var fan: Array = w.levels[1].dirs.slice(0, Hand.TREE[k].size())
		if absf(dirs[k].x) > 0.01:
			for d in fan:
				_check(signf(d.x) == -signf(dirs[k].x), "subtree %d's items open on the side away from the swing" % k)
		else:
			_check(fan[0].x < -0.99 and fan[1].x > 0.99, "subtree %d's two items open one to each side" % k)
		var items: Array = Hand.TREE[k]
		for j in items.size():
			var v := ToolWheel.new(Hand.TREE)
			v.move(dirs[k] * ToolWheel.RADIUS)
			v.move(w.levels[1].centre + w.levels[1].dirs[j] * ToolWheel.RADIUS)
			if items[j] is Array:
				_check(v.levels.size() == 3 and v.chosen() == null, "swinging back onto item %d of subtree %d opens it" % [j, k])
			else:
				_check(v.chosen() == items[j], "swinging back onto item %d of subtree %d picks it" % [j, k])


func _inside_a_subtree_the_swing_side_picks_nothing() -> void:
	var right := 2
	assert(Hand.TREE[right] is Array)
	var w := ToolWheel.new(Hand.TREE)
	var at := ToolWheel.ring_dirs()[right] * ToolWheel.RADIUS
	w.move(at)
	w.move(at + Vector2(ToolWheel.RADIUS, 0))
	_check(w.levels.size() == 2 and w.chosen() == null, "overshooting a subtree picks nothing")
	var up := ToolWheel.new(Hand.TREE)
	up.move(ToolWheel.ring_dirs()[0] * ToolWheel.RADIUS)
	up.move(ToolWheel.ring_dirs()[0] * ToolWheel.RADIUS * 2.0)
	_check(up.levels.size() == 2 and up.chosen() == null, "overshooting the top subtree upward picks nothing")


func _colour_and_style_are_one_swing_up() -> void:
	_check(ToolWheel.paths(Hand.TREE)[Hand.Tool.COLOUR] == [0, 0], "colour is up, then left")
	_check(ToolWheel.paths(Hand.TREE)[Hand.Tool.STYLE] == [0, 1], "style is up, then right")


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


func _the_wheel_faces_the_head_wherever_the_hand_is() -> void:
	var head := Vector3(0, 1.6, 0)
	var forward := Vector3(0, -0.3, -1)
	var prev := Basis()
	for i in 37:
		var a := deg_to_rad(-90.0 + i * 5.0)
		var hand := head + Vector3(0, sin(a), -cos(a)) * 0.5
		if i == 0:
			hand.z -= 1e-4
		var b := ToolWheel.facing(hand, head, forward)
		var z := (head - hand).normalized()
		_check(b.z.dot(z) > 0.9999, "at %.0f° the wheel's face points at the head" % rad_to_deg(a))
		_check(b.is_equal_approx(b.orthonormalized()) and b.determinant() > 0.0, "at %.0f° the frame is a rotation" % rad_to_deg(a))
		_check(b.x.dot(Vector3.RIGHT) > 0.9999, "at %.0f° x is the player's right" % rad_to_deg(a))
		if i > 0:
			_check(b.y.dot(prev.y) > cos(deg_to_rad(6.0)), "the wheel turns smoothly through %.0f°" % rad_to_deg(a))
		prev = b
	var below := ToolWheel.facing(head + Vector3(0, -0.6, 0), head, forward)
	_check(absf(below.z.y) > 0.9999 and below.y.dot(Vector3.FORWARD) > 0.9999, "under the head the wheel lies flat, its top away")
	var above := ToolWheel.facing(head + Vector3(0, 0.6, 0), head, forward)
	_check(absf(above.z.y) > 0.9999 and above.y.dot(Vector3.BACK) > 0.9999, "over the head it lies flat, its top toward the player")
	var ahead := ToolWheel.facing(head + Vector3(0, 0, -0.5), head, forward)
	_check(ahead.y.dot(Vector3.UP) > 0.9999 and ahead.z.dot(Vector3.BACK) > 0.9999, "level with the head it stands upright")
	var side := ToolWheel.facing(head + Vector3(0.4, -0.3, -0.3), head, forward)
	_check(side.z.dot((head - (head + Vector3(0.4, -0.3, -0.3))).normalized()) > 0.9999, "off to one side it still faces the head")


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)
