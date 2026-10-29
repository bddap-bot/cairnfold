extends "res://../tests/support/suite.gd"

const Fixture = preload("res://demo/expressions.gd")


func _initialize() -> void:
	_run.call_deferred()


func _open(hand: Hand) -> void:
	Hand.injected_reach.erase(hand.tracker)
	Buttons.injected["%s/by_button" % hand.tracker] = true
	await frames(2)
	var tree := hand.inventory()
	for at in ToolWheel.sweep(tree, ToolWheel.paths(tree)["expressions"]):
		Hand.injected_reach[hand.tracker] = at
		await frames(2)
	Hand.injected_reach[hand.tracker] = Vector2.ZERO
	await frames(2)


func _release(hand: Hand) -> void:
	Buttons.injected.erase("%s/by_button" % hand.tracker)
	await frames(2)
	Hand.injected_reach.erase(hand.tracker)


func _run() -> void:
	boot_main()
	await until(func() -> bool: return main.rig.expression_store.loaded, "saved expressions read")
	var avatar := Avatar.open(Fixture.scene(), Color.WHITE, "expression-test")
	main.rig.wear(avatar)
	var hand := main.rig.right
	hand.held_still = true
	await _open(hand)
	check(hand.expressions != null and hand._wheel != null, "the B/Y people slot opens the existing wheel on the avatar's controls")
	Hand.injected_reach[hand.tracker] = Vector2(0, ToolWheel.RADIUS)
	await frames(2)
	await _release(hand)
	check(avatar.expressions.state.values.Hat == 1.0, "releasing on the Hat slot toggles its parameter")
	check(avatar.find_child("ExpressionHat", true, false).visible, "the wheel toggle changes the worn avatar")
	await _open(hand)
	Hand.injected_reach[hand.tracker] = ToolWheel.ring_dirs()[2] * ToolWheel.RADIUS
	await frames(1)
	Hand.injected_reach[hand.tracker] = Vector2.ZERO
	await frames(2)
	check(hand.expressions.current.size() == 3 and avatar.expressions.state.values.Menu == 1.0, "a submenu opens another wheel and sets its gate")
	Hand.injected_reach[hand.tracker] = ToolWheel.ring_dirs()[1] * ToolWheel.RADIUS
	await frames(1)
	Hand.injected_reach[hand.tracker] = Vector2.ZERO
	Hand.injected_sticks[hand.tracker] = Vector2(-0.4, 0.6)
	await frames(2)
	check(is_equal_approx(avatar.expressions.state.values.Horizontal, -0.4) and is_equal_approx(avatar.expressions.state.values.Vertical, 0.6), "the active axis puppet reads the right thumbstick")
	await _release(hand)
	check(hand.picking and hand.expressions != null, "releasing B frees the thumb while the axis puppet stays active")
	Hand.injected_sticks[hand.tracker] = Vector2(-0.8, 0.2)
	await frames(2)
	check(is_equal_approx(avatar.expressions.state.values.Horizontal, -0.8), "the free thumb continues operating the puppet")
	Buttons.injected["right_hand/by_button"] = true
	await frames(2)
	await _release(hand)
	Hand.injected_sticks.erase(hand.tracker)
	check(avatar.expressions.state.values.Menu == 0.0 and avatar.expressions.state.values.Puppet == 0.0, "closing the wheel clears submenu and puppet gates")
	check(is_equal_approx(avatar.expressions.state.values.Horizontal, -0.8), "closing the wheel keeps the puppet's axes")
	main.rig.wear(Avatar.open(Avatar.built_in(0), Color.WHITE, "other"))
	await frames(2)
	main.rig.wear(Avatar.open(Fixture.scene(), Color.WHITE, "expression-test"))
	await frames(2)
	check(main.rig.body.expressions.state.values.Hat == 1.0, "switching away and back restores this avatar's saved toggle")
	finish()
