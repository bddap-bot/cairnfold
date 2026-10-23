class_name Controls
extends RefCounted

## The one controls table: each action as the input each hand reads for it (a stick direction is a flick, see
## `Hand.FLICKS`). Code reads actions through `Buttons`, never inputs.
const ACTIONS := {
	"tool": {"left_hand": "trigger_click", "right_hand": "trigger_click"},
	"grab": {"left_hand": "grip_click", "right_hand": "grip_click"},
	"wheel": {"left_hand": "by_button", "right_hand": "by_button"},
	"undo": {"left_hand": "ax_button"},
	"redo": {"right_hand": "ax_button"},
	"teleport": {"left_hand": "primary_up"},
	"turn_left": {"right_hand": "primary_left"},
	"turn_right": {"right_hand": "primary_right"},
	"reach": {"left_hand": "primary_click", "right_hand": "primary_click"},
}

## A tracked hand as the controller it stands in for: each gesture (`HandShape`) as the input it presses. The little
## pinch holds the stick, which the hand then pushes by moving from where it pinched (`Hand.STICK_REACH`).
const HAND := {"index": "trigger_click", "fist": "grip_click", "middle": "by_button", "ring": "ax_button", "little": "primary"}

## Native layouts. Extra Frame buttons have distinct inputs but no game action; only B and D-pad left open wheels.
## The Quest's left menu is left out: held, it did not open the wheel on a Quest 3.
const DEVICES := {
	"frame": {
		"A": ["right_hand", "ax_button"],
		"B": ["right_hand", "by_button"],
		"X": ["right_hand", "x_button"],
		"Y": ["right_hand", "y_button"],
		"dpad_down": ["left_hand", "ax_button"],
		"dpad_up": ["left_hand", "dpad_up_button"],
		"dpad_left": ["left_hand", "by_button"],
		"dpad_right": ["left_hand", "dpad_right_button"],
		"view": ["left_hand", "view_button"],
		"menu": ["right_hand", "menu_button"],
		"left_bumper": ["left_hand", "bumper_button"],
		"right_bumper": ["right_hand", "bumper_button"],
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
	for name in DEVICES[device]:
		if DEVICES[device][name] == [tracker, ACTIONS[action].get(tracker, "")]:
			out.append(name)
	return out


## The flat-screen controls (`Flat`): each action as the keys, mouse buttons and gamepad inputs that do it, a stick's
## half axis by its sign. The camera fires on "tool", as a controller's trigger does.
const FLAT := {
	"wheel": [["key", KEY_Q], ["button", JOY_BUTTON_LEFT_SHOULDER]],
	"forward": [["key", KEY_W], ["key", KEY_UP], ["axis", JOY_AXIS_LEFT_Y, -1.0]],
	"back": [["key", KEY_S], ["key", KEY_DOWN], ["axis", JOY_AXIS_LEFT_Y, 1.0]],
	"left": [["key", KEY_A], ["key", KEY_LEFT], ["axis", JOY_AXIS_LEFT_X, -1.0]],
	"right": [["key", KEY_D], ["key", KEY_RIGHT], ["axis", JOY_AXIS_LEFT_X, 1.0]],
	"look_left": [["axis", JOY_AXIS_RIGHT_X, -1.0]],
	"look_right": [["axis", JOY_AXIS_RIGHT_X, 1.0]],
	"look_up": [["axis", JOY_AXIS_RIGHT_Y, -1.0]],
	"look_down": [["axis", JOY_AXIS_RIGHT_Y, 1.0]],
	"tool": [["mouse", MOUSE_BUTTON_LEFT], ["axis", JOY_AXIS_TRIGGER_RIGHT, 1.0], ["button", JOY_BUTTON_A]],
	"next_tool": [["key", KEY_TAB], ["mouse", MOUSE_BUTTON_RIGHT], ["button", JOY_BUTTON_Y]],
	"wave": [["key", KEY_F], ["button", JOY_BUTTON_X]],
	"let_go": [["key", KEY_ESCAPE]],
}
