extends "res://../tests/support/suite.gd"

## Headless checks that the controls table reaches every action on every device we ship, each control
## held through the same path the controller feeds:
## godot4 --headless --fixed-fps 60 --path game --script ../tests/test_bindings.gd

const PER_HAND := ["tool", "grab", "wheel"]
## The interaction profile each device's controls arrive through.
const PROFILES := {"frame": "/interaction_profiles/valve/frame_controller_valve", "quest": "/interaction_profiles/oculus/touch_controller"}

## The Quest's controllers after the Touch, each its own profile.
const TOUCH_LATER := ["/interaction_profiles/meta/touch_plus_controller", "/interaction_profiles/meta/touch_pro_controller"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_every_action_is_reachable_on_every_device()
	_no_two_actions_share_an_input()
	_a_tool_is_picked_without_a_stick_click()
	_each_device_profile_binds_its_controls()
	_only_one_control_opens_each_frame_wheel()
	_every_touch_controller_binds_alike()
	await _unused_frame_controls_do_nothing()
	await _each_control_does_its_action_alone()
	await _a_flick_is_one_way()
	finish()


func _every_action_is_reachable_on_every_device() -> void:
	for action in PER_HAND:
		check(Controls.ACTIONS[action].keys().size() == 2, "%s is on both hands" % action)
	for device in Controls.DEVICES:
		for action in Controls.ACTIONS:
			for tracker in Controls.ACTIONS[action]:
				check(not Controls.bound(device, action, tracker).is_empty(), "%s reaches %s on its %s" % [device, action, tracker])


func _no_two_actions_share_an_input() -> void:
	var seen := {}
	for action in Controls.ACTIONS:
		for tracker in Controls.ACTIONS[action]:
			var key := "%s/%s" % [tracker, Controls.input(action, tracker)]
			check(not seen.has(key), "%s and %s share %s" % [seen.get(key, ""), action, key])
			seen[key] = action


func _a_tool_is_picked_without_a_stick_click() -> void:
	for device in Controls.DEVICES:
		for tracker in Controls.ACTIONS.wheel:
			for name in Controls.bound(device, "wheel", tracker):
				check(Controls.DEVICES[device][name][1] != "primary_click", "%s opens the wheel with %s, a stick click" % [device, name])


func _each_device_profile_binds_its_controls() -> void:
	var map: OpenXRActionMap = load("res://openxr_action_map.tres")
	for device in Controls.DEVICES:
		var bound := {}
		for profile in map.interaction_profiles:
			if profile.interaction_profile_path == PROFILES[device]:
				for b in profile.bindings:
					bound[b.binding_path] = bound.get(b.binding_path, []) + [b.action.resource_name]
		for name in Controls.DEVICES[device]:
			var to: Array = Controls.DEVICES[device][name]
			var input: String = "primary" if Hand.FLICKS.has(to[1]) else to[1]
			var path := _path(name, to[0])
			check(input in bound.get(path, []), "%s's %s (%s) arrives as %s/%s: bound to %s" % [device, name, path, to[0], input, bound.get(path, [])])


## The Quest's later controllers arrive through their own profiles, each bound exactly as the Touch controller is, so
## no runtime falls back to a guess.
func _every_touch_controller_binds_alike() -> void:
	var map: OpenXRActionMap = load("res://openxr_action_map.tres")
	var bindings := {}
	for profile in map.interaction_profiles:
		var pairs: Array = profile.bindings.map(func(b: OpenXRIPBinding) -> String: return "%s=%s" % [b.binding_path, b.action.resource_name])
		pairs.sort()
		bindings[profile.interaction_profile_path] = pairs
	var touch: Array = bindings[PROFILES.quest]
	for path in TOUCH_LATER:
		check(bindings.get(path) == touch, "%s binds as the Touch controller: %d of %d bindings" % [path, bindings.get(path, []).size(), touch.size()])


func _only_one_control_opens_each_frame_wheel() -> void:
	check(Controls.bound("frame", "wheel", "left_hand") == ["dpad_left"], "only D-pad left opens the left Frame wheel")
	check(Controls.bound("frame", "wheel", "right_hand") == ["B"], "only B opens the right Frame wheel")


func _unused_frame_controls_do_nothing() -> void:
	var hands := _hands()
	for control in ["X", "Y", "dpad_up", "dpad_right", "left_bumper", "right_bumper", "menu", "view"]:
		Driver.hold("frame", control, true)
		await process_frame
		for action in Controls.ACTIONS:
			for tracker in Controls.ACTIONS[action]:
				check(not Buttons.new(hands[tracker]).held(action), "%s does not trigger %s on %s" % [control, action, tracker])
		Driver.hold("frame", control, false)
	for hand in hands.values():
		hand.free()


## The OpenXR path of a control named as in `Controls.DEVICES`, on the hand `tracker`.
func _path(name: String, tracker: String) -> String:
	var input := name.trim_prefix("left_").trim_prefix("right_")
	var parts: Dictionary = {"trigger": "trigger/value", "grip": "squeeze/value", "stick_click": "thumbstick/click"}
	var leaf: String = parts.get(input, "thumbstick" if input.begins_with("stick_") else input.to_lower() + "/click")
	return "/user/hand/%s/input/%s" % [tracker.trim_suffix("_hand"), leaf]


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
					check(b.held(action) and also.is_empty(), "%s's %s holds %s alone, held %s, also %s" % [device, control, action, b.held(action), also])
					Driver.hold(device, control, false)
					await process_frame
					await process_frame
					check(not b.held(action), "letting go of %s's %s lets go of %s" % [device, control, action])
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
	check(turns == 2 and seen == ["primary_right", "primary_right", "primary_right", "primary_right", "", "primary_right", ""], "a flick right drifting down stays right until the stick comes back: %d turns, %s" % [turns, seen])
	for h in hands.values():
		h.free()
