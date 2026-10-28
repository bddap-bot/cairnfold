extends "res://../tests/support/suite.gd"

## Headless checks of the dial every twisted choice turns on, styles, colours, avatars and gardens alike:
## godot4 --headless --fixed-fps 60 --path game --script ../tests/test_dial.gd


func _initialize() -> void:
	_twisting_wraps_round_the_dial()
	_half_a_turn_reaches_every_choice()
	_a_clockwise_twist_counts_up()
	await _neighbours_stay_apart_and_the_top_stands_larger()
	finish()


func _twisting_wraps_round_the_dial() -> void:
	var n := Palette.count(Palette.Element.ROOF)
	check(Dial.twisted(n, 0, Dial.STEP) == 1, "one step clockwise is the next choice")
	check(Dial.twisted(n, 0, -Dial.STEP) == n - 1, "one step back wraps to the last")
	check(Dial.twisted(n, 2, Dial.STEP * 0.4) == 2, "a small twist stays put")


func _half_a_turn_reaches_every_choice() -> void:
	for n in [2, 3, 13, DecorationLayout.STYLES.size()]:
		var reached := {}
		for degrees in range(-180, 181):
			reached[Dial.twisted(n, 0, degrees)] = true
		check(reached.size() == n, "half a turn either way reaches all %d choices, not %d" % [n, reached.size()])


func _a_clockwise_twist_counts_up() -> void:
	var start := Basis.looking_at(Vector3(0.3, -0.2, -1.0))
	var fwd := -start.z
	var turned := Basis(fwd, deg_to_rad(40.0)) * start
	check(absf(Dial.roll(start, turned) - 40.0) < 0.1, "a 40° turn clockwise, seen along the hand, reads %.1f" % Dial.roll(start, turned))


func _neighbours_stay_apart_and_the_top_stands_larger() -> void:
	var hand := Node3D.new()
	root.add_child(hand)
	await process_frame
	for n in [2, 13, DecorationLayout.STYLES.size()]:
		var items: Array[Node3D] = []
		for i in n:
			items.append(Node3D.new())
		var dial := Dial.new()
		hand.add_child(dial)
		dial.open(hand, items, 1)
		var apart := INF
		for k in n:
			apart = minf(apart, items[k].position.distance_to(items[(k + 1) % n].position))
		check(apart >= Dial.GAP * 0.99 or n * Dial.GAP < TAU * Dial.RADIUS, "%d choices stand %.3f m apart" % [n, apart])
		check(items[1].position.is_equal_approx(Vector3(0, Dial.radius(n), 0)) and items[1].scale.x > items[0].scale.x, "the choice it opened on stands at the top, larger")
		dial.twist(hand, Dial.step(n))
		dial.follow(hand)
		var next: int = 2 % n
		check(dial.pick == next and items[next].position.is_equal_approx(Vector3(0, Dial.radius(n), 0)), "a step's twist brings the next to the top")
		var back := dial.release()
		check(back == items and items.all(func(c: Node3D) -> bool: return c.get_parent() == null), "a released dial gives its choices back")
		await process_frame
		for c in back:
			c.free()
	hand.free()
