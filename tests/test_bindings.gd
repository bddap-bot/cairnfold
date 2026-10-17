extends SceneTree

## Headless checks that the controls table reaches every action on every device we ship:
## godot4 --headless --path game --script ../tests/test_bindings.gd

const PER_HAND := ["tool", "grab", "wheel", "alternate"]
const TOUCH := "/interaction_profiles/oculus/touch_controller"

var failures := 0


func _init() -> void:
	_every_action_is_reachable_on_every_device()
	_no_two_actions_share_an_input()
	_a_tool_is_picked_without_a_stick_click()
	_the_touch_profile_binds_every_device_input()
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
			var input: String = "primary" if Buttons.STICK.has(to[1]) else to[1]
			_check(bound.has("%s/%s" % [to[0], input]), "%s's %s arrives as %s/%s, which the Touch profile binds" % [device, name, to[0], input])


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)
