extends SceneTree

## Headless checks of the touch hints: a finger resting on each touch-bound control of each hand shows that control's
## actions beside it, and lifting or pressing takes them away:
## godot4 --headless --fixed-fps 60 --path game --script ../tests/test_touch_hints.gd

const TOUCH := "/interaction_profiles/oculus/touch_controller"
## Farther than this from its control, an icon is not beside it.
const NEAR := 0.08

var failures := 0
var main: Node


func _initialize() -> void:
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _play(steps: Array) -> void:
	var d := Driver.new(main, steps)
	main.add_child(d)
	await d.finished
	d.queue_free()


func _run() -> void:
	await _play([{"op": "place", "x": 0, "z": 6}, {"op": "wait", "seconds": 0.2},
		{"op": "hands", "left": [-0.2, -0.3, -0.4], "right": [0.2, -0.3, -0.4]}])
	_every_touched_action_has_a_place_and_an_icon()
	Hand.injected_profile = TOUCH
	await _frames(2)
	for hand: Hand in main.rig.hands:
		for touch in Controls.TOUCHES:
			if not Controls.touched(touch, hand.tracker).is_empty():
				await _resting_shows_beside_the_control(hand, touch)
				await _pressing_hides_until_lifted(hand, touch)
	await _the_trigger_shows_the_tool_held()
	await _a_profile_with_no_places_shows_nothing()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _every_touched_action_has_a_place_and_an_icon() -> void:
	for tracker in ["left_hand", "right_hand"]:
		for touch in Controls.TOUCHES:
			_check(Controls.place(TOUCH, touch, tracker) != Vector3.INF, "the Touch profile places %s" % touch)
	_check(Controls.place(TOUCH, "ax_touch", "left_hand").x == -Controls.place(TOUCH, "ax_touch", "right_hand").x, "the left controller mirrors the right")
	_check(Controls.touched("ax_touch", "left_hand") == ["undo"] and Controls.touched("ax_touch", "right_hand") == ["redo"], "X undoes, A redoes")
	_check(Controls.touched("primary_touch", "right_hand") == ["turn_left", "turn_right"], "the right stick turns")


func _key(hand: Hand, touch: String) -> String:
	return "%s/%s" % [hand.tracker, touch]


func _hints(hand: Hand) -> TouchHints:
	return hand.get_children().filter(func(c: Node) -> bool: return c is TouchHints)[0]


## Every other touch's actions, which must not show while only `touch` rests.
func _shown_elsewhere(hand: Hand, touch: String) -> Array[String]:
	var out: Array[String] = []
	for other in Controls.TOUCHES:
		if other == touch:
			continue
		for action in Controls.touched(other, hand.tracker):
			if _hints(hand).showing(other, action) != null:
				out.append("%s/%s" % [other, action])
	return out


func _resting_shows_beside_the_control(hand: Hand, touch: String) -> void:
	var what := "%s %s" % [hand.tracker, touch]
	Buttons.injected[_key(hand, touch)] = true
	await _frames(15)
	for action in Controls.touched(touch, hand.tracker):
		_check(_hints(hand).showing(touch, action) == null, "%s: a quarter second's rest shows nothing yet" % what)
	await _frames(30)
	var control := hand.global_transform * Controls.place(TOUCH, touch, hand.tracker)
	for action in Controls.touched(touch, hand.tracker):
		var i := _hints(hand).showing(touch, action)
		_check(i != null, "%s: resting shows %s" % [what, action])
		if i == null:
			continue
		var d := i.global_position.distance_to(control)
		_check(d < NEAR, "%s: %s shows %.3f m from the control, past %.2f" % [what, action, d, NEAR])
		_check(i.scale.x > TouchHints.SIZE * 0.95, "%s: %s has grown in" % [what, action])
		var eye: Vector3 = main.rig.head.global_position
		_check(i.global_basis.z.normalized().dot((eye - i.global_position).normalized()) > 0.99, "%s: %s faces the eye" % [what, action])
	_check(_shown_elsewhere(hand, touch).is_empty(), "%s: only its own icons show, not %s" % [what, _shown_elsewhere(hand, touch)])
	Buttons.injected.erase(_key(hand, touch))
	await _frames(12)
	for action in Controls.touched(touch, hand.tracker):
		_check(_hints(hand).showing(touch, action) == null, "%s: lifting the finger takes %s away" % [what, action])


func _press(hand: Hand, touch: String, on: bool) -> void:
	if touch == "primary_touch":
		if on:
			Hand.injected_sticks[hand.tracker] = Vector2(0, 0.5)
		else:
			Hand.injected_sticks.erase(hand.tracker)
		return
	for input in Controls.TOUCHES[touch]:
		if on:
			Buttons.injected["%s/%s" % [hand.tracker, input]] = true
		else:
			Buttons.injected.erase("%s/%s" % [hand.tracker, input])


func _any_shows(hand: Hand, touch: String) -> bool:
	return Controls.touched(touch, hand.tracker).any(func(a: String) -> bool: return _hints(hand).showing(touch, a) != null)


func _pressing_hides_until_lifted(hand: Hand, touch: String) -> void:
	var what := "%s %s" % [hand.tracker, touch]
	Buttons.injected[_key(hand, touch)] = true
	await _frames(45)
	_check(_any_shows(hand, touch), "%s: shows before the press" % what)
	_press(hand, touch, true)
	await _frames(12)
	_check(not _any_shows(hand, touch), "%s: pressing takes it away" % what)
	_press(hand, touch, false)
	await _frames(60)
	_check(not _any_shows(hand, touch), "%s: a finger left resting after a press brings nothing back" % what)
	Buttons.injected.erase(_key(hand, touch))
	await _frames(3)
	Buttons.injected[_key(hand, touch)] = true
	await _frames(45)
	_check(_any_shows(hand, touch), "%s: touched again, it shows again" % what)
	Buttons.injected.erase(_key(hand, touch))
	await _frames(12)


func _the_trigger_shows_the_tool_held() -> void:
	var hand: Hand = main.rig.right
	var hints := _hints(hand)
	for tool in [Hand.Tool.TREES, Hand.Tool.DELETE]:
		hand.tool = tool
		Buttons.injected[_key(hand, "trigger_touch")] = true
		await _frames(45)
		var i := hints.showing("trigger_touch", "tool")
		_check(i != null and hints._tool_icon == tool, "the trigger shows the %s held" % Hand.Tool.keys()[tool])
		Buttons.injected.erase(_key(hand, "trigger_touch"))
		await _frames(12)


func _a_profile_with_no_places_shows_nothing() -> void:
	Hand.injected_profile = "/interaction_profiles/htc/vive_focus3_controller"
	await _frames(2)
	var hand: Hand = main.rig.right
	Buttons.injected[_key(hand, "ax_touch")] = true
	await _frames(60)
	_check(not _any_shows(hand, "ax_touch"), "a profile with no places shows no hints")
	Buttons.injected.erase(_key(hand, "ax_touch"))
	Hand.injected_profile = TOUCH
