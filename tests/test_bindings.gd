extends SceneTree

## Headless checks that the controls table reaches every action on every device we ship, each control
## held through the same path the controller feeds:
## godot4 --headless --path game --script ../tests/test_bindings.gd

const PER_HAND := ["tool", "grab", "wheel"]
const TOUCH := "/interaction_profiles/oculus/touch_controller"

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_every_action_is_reachable_on_every_device()
	_no_two_actions_share_an_input()
	_a_tool_is_picked_without_a_stick_click()
	_the_touch_profile_binds_every_device_input()
	await _each_control_does_its_action_alone()
	await _a_flick_is_one_way()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _every_action_is_reachable_on_every_device() -> void:
	for action in PER_HAND:
		_check(Controls.ACTIONS[action].keys().size() == 2, "%s is on both hands" % action)
	for device in Controls.DEVICES:
		for action in Controls.ACTIONS:
			for tracker in Controls.ACTIONS[action]:
				_check(not Controls.bound(device, action, tracker).is_empty(), "%s reaches %s on its %s" % [device, action, tracker])


func _no_two_actions_share_an_input() -> void:
	var seen := {}
	for action in Controls.ACTIONS:
		for tracker in Controls.ACTIONS[action]:
			var key := "%s/%s" % [tracker, Controls.input(action, tracker)]
			_check(not seen.has(key), "%s and %s share %s" % [seen.get(key, ""), action, key])
			seen[key] = action


func _a_tool_is_picked_without_a_stick_click() -> void:
	for device in Controls.DEVICES:
		for tracker in Controls.ACTIONS.wheel:
			for name in Controls.bound(device, "wheel", tracker):
				_check(Controls.DEVICES[device][name][1] != "primary_click", "%s opens the wheel with %s, a stick click" % [device, name])


func _the_touch_profile_binds_every_device_input() -> void:
	var map: OpenXRActionMap = load("res://openxr_action_map.tres")
	var bound := {}
	for profile in map.interaction_profiles:
		if profile.interaction_profile_path != TOUCH:
			continue
		for b in profile.bindings:
			bound["%s_hand/%s" % [b.binding_path.split("/")[3], b.action.resource_name]] = true
	for device in Controls.DEVICES:
		for name in Controls.DEVICES[device]:
			var to: Array = Controls.DEVICES[device][name]
			var input: String = "primary" if Hand.FLICKS.has(to[1]) else to[1]
			_check(bound.has("%s/%s" % [to[0], input]), "%s's %s arrives as %s/%s, which the Touch profile binds" % [device, name, to[0], input])


func _hands() -> Dictionary:
	var hands := {}
	for tracker in ["left_hand", "right_hand"]:
		hands[tracker] = Hand.new(tracker, Hand.Tool.WALLS)
		root.add_child(hands[tracker])
	return hands


## Holding a control makes its hand's action held, and no other action on that hand.
func _each_control_does_its_action_alone() -> void:
	var hands := _hands()
	var watching := {}
	for tracker in hands:
		watching[tracker] = Buttons.new(hands[tracker]).watch(Controls.ACTIONS.keys().filter(func(a: String) -> bool: return Controls.ACTIONS[a].has(tracker)))
	for device in Controls.DEVICES:
		for action in Controls.ACTIONS:
			for tracker in Controls.ACTIONS[action]:
				var b: Buttons = watching[tracker]
				for control in Controls.bound(device, action, tracker):
					Driver.hold(device, control, true)
					await process_frame
					await process_frame
					var also: Array = b._was.keys().filter(func(a: String) -> bool: return a != action and b.held(a))
					_check(b.held(action) and also.is_empty(), "%s's %s holds %s alone, held %s, also %s" % [device, control, action, b.held(action), also])
					Driver.hold(device, control, false)
					await process_frame
					await process_frame
					_check(not b.held(action), "letting go of %s's %s lets go of %s" % [device, control, action])
	for h in hands.values():
		h.free()


## A flick one way stays that way as the thumb drifts, until the stick comes back.
func _a_flick_is_one_way() -> void:
	var hands := _hands()
	var right: Hand = hands.right_hand
	var b := Buttons.new(right).watch(["turn_right"])
	var turns := 0
	var seen: Array[String] = []
	for at in [Vector2(1, 0), Vector2(0.6, -0.5), Vector2(0.3, -0.75), Vector2(0, -0.9), Vector2.ZERO, Vector2(0.9, 0.2), Vector2.ZERO]:
		Hand.injected_sticks["right_hand"] = at
		await process_frame
		turns += int(b.pressed("turn_right"))
		seen.append(right.flick)
		b.latch()
	Hand.injected_sticks.clear()
	_check(turns == 2 and seen == ["primary_right", "primary_right", "primary_right", "primary_right", "", "primary_right", ""], "a flick right drifting down stays right until the stick comes back: %d turns, %s" % [turns, seen])
	for h in hands.values():
		h.free()


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)
