class_name Controls
extends RefCounted

## The one controls table: each action as the input each hand reads for it. Both hands do the same with
## their face buttons, trigger and grip, each for the tool it holds; the sticks move the body and walk the
## history. A stick direction reads as a button (see `Buttons`).
const ACTIONS := {
	"tool": {"left_hand": "trigger_click", "right_hand": "trigger_click"},
	"grab": {"left_hand": "grip_click", "right_hand": "grip_click"},
	"wheel": {"left_hand": "by_button", "right_hand": "by_button"},
	"alternate": {"left_hand": "ax_button", "right_hand": "ax_button"},
	"teleport": {"left_hand": "primary_up"},
	"turn_left": {"right_hand": "primary_left"},
	"turn_right": {"right_hand": "primary_right"},
	"undo": {"right_hand": "primary_down"},
	"redo": {"right_hand": "primary_up"},
}

## What each shipped device's controls arrive as. Every one binds the Touch profile. Godot 4.5 has no Frame
## profile, so SteamVR remaps the Frame's onto it: B, X and Y arrive as one button, D-pad down as Touch
## left X, its other directions as left Y, View as left menu. The Quest's left menu button is left out:
## held, it does not open the wheel on a Quest 3.
const DEVICES := {
	"frame": {
		"A": ["right_hand", "ax_button"],
		"B": ["right_hand", "by_button"],
		"X": ["right_hand", "by_button"],
		"Y": ["right_hand", "by_button"],
		"dpad_down": ["left_hand", "ax_button"],
		"dpad_up": ["left_hand", "by_button"],
		"dpad_left": ["left_hand", "by_button"],
		"dpad_right": ["left_hand", "by_button"],
		"view": ["left_hand", "menu_button"],
		"left_trigger": ["left_hand", "trigger_click"],
		"right_trigger": ["right_hand", "trigger_click"],
		"left_grip": ["left_hand", "grip_click"],
		"right_grip": ["right_hand", "grip_click"],
		"left_stick_click": ["left_hand", "primary_click"],
		"right_stick_click": ["right_hand", "primary_click"],
		"left_stick_up": ["left_hand", "primary_up"],
		"left_stick_down": ["left_hand", "primary_down"],
		"left_stick_left": ["left_hand", "primary_left"],
		"left_stick_right": ["left_hand", "primary_right"],
		"right_stick_up": ["right_hand", "primary_up"],
		"right_stick_down": ["right_hand", "primary_down"],
		"right_stick_left": ["right_hand", "primary_left"],
		"right_stick_right": ["right_hand", "primary_right"],
	},
	"quest": {
		"A": ["right_hand", "ax_button"],
		"B": ["right_hand", "by_button"],
		"X": ["left_hand", "ax_button"],
		"Y": ["left_hand", "by_button"],
		"left_trigger": ["left_hand", "trigger_click"],
		"right_trigger": ["right_hand", "trigger_click"],
		"left_grip": ["left_hand", "grip_click"],
		"right_grip": ["right_hand", "grip_click"],
		"left_stick_click": ["left_hand", "primary_click"],
		"right_stick_click": ["right_hand", "primary_click"],
		"left_stick_up": ["left_hand", "primary_up"],
		"left_stick_down": ["left_hand", "primary_down"],
		"left_stick_left": ["left_hand", "primary_left"],
		"left_stick_right": ["left_hand", "primary_right"],
		"right_stick_up": ["right_hand", "primary_up"],
		"right_stick_down": ["right_hand", "primary_down"],
		"right_stick_left": ["right_hand", "primary_left"],
		"right_stick_right": ["right_hand", "primary_right"],
	},
}


static func input(action: String, tracker: String) -> String:
	return ACTIONS[action][tracker]


## The `device`'s controls that do `action` on the hand `tracker`.
static func bound(device: String, action: String, tracker: String) -> Array[String]:
	var out: Array[String] = []
	var want: String = ACTIONS[action].get(tracker, "")
	for name in DEVICES[device]:
		if DEVICES[device][name] == [tracker, want]:
			out.append(name)
	return out


## Every action on `device`'s controls, each as {hand: [controls]}.
static func layout(device: String) -> Dictionary:
	var out := {}
	for action in ACTIONS:
		out[action] = {}
		for tracker in ACTIONS[action]:
			out[action][tracker] = bound(device, action, tracker)
	return out
