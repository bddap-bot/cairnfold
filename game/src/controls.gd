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
}

## Native layouts. Extra Frame buttons have distinct inputs but no game action; only B and D-pad up open wheels.
## The Quest's left menu is left out: held, it did not open the wheel on a Quest 3.
const DEVICES := {
	"frame": {
		"A": ["right_hand", "ax_button"],
		"B": ["right_hand", "by_button"],
		"X": ["right_hand", "x_button"],
		"Y": ["right_hand", "y_button"],
		"dpad_down": ["left_hand", "ax_button"],
		"dpad_up": ["left_hand", "by_button"],
		"dpad_left": ["left_hand", "dpad_left_button"],
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


## The capacitive touches the action map binds, each with the inputs of the control it lies on. A finger resting on
## one unpressed previews what those inputs do (TouchHints). The Touch profile has no grip touch, so "grip_touch" is
## the grip squeezed past GRIP_TOUCH, short of grabbing (Buttons.down), except on the native Frame profile.
const TOUCHES := {
	"ax_touch": ["ax_button"],
	"by_touch": ["by_button"],
	"trigger_touch": ["trigger_click"],
	"primary_touch": ["primary_click", "primary_up", "primary_down", "primary_left", "primary_right"],
	"grip_touch": ["grip_click"],
}
const GRIP_TOUCH := 0.05

## Where each touch's control lies on the Touch profile's right controller, in metres in its aim pose (x right, y up,
## -z ahead); the left controller mirrors it in x. Each is the control's centre on Meta's Quest 2 controller model for
## WebXR, carried from its grip pose to the aim pose by the offset measured on the Quest; the Quest 3's lie within 5 mm
## of them. A profile not listed shows no hints.
const TOUCH_PLACES := {
	"ax_touch": Vector3(0.001, 0.0, 0.044),
	"by_touch": Vector3(-0.005, 0.0, 0.029),
	"trigger_touch": Vector3(0.005, -0.020, 0.012),
	"primary_touch": Vector3(0.016, 0.004, 0.030),
	"grip_touch": Vector3(0.001, -0.028, 0.054),
}
const FRAME_PROFILE := "/interaction_profiles/valve/frame_controller_valve"

## Valve's SteamVR frame_controller render-model component origins, transformed by inverse(openxr_aim).
## The left D-pad shares one rocker, so both direction hints use its centre.
const FRAME_PLACES := {
	"left_hand": {
		"ax_touch": Vector3(-0.015768, 0.008815, 0.031984),
		"by_touch": Vector3(-0.015768, 0.008815, 0.031984),
		"trigger_touch": Vector3(-0.006707, -0.036056, 0.009207),
		"primary_touch": Vector3(0.012015, 0.010019, 0.041948),
		"grip_touch": Vector3(0.007007, -0.028275, 0.061512),
	},
	"right_hand": {
		"ax_touch": Vector3(0.016683, 0.009095, 0.040842),
		"by_touch": Vector3(0.024532, 0.010815, 0.031256),
		"trigger_touch": Vector3(0.006707, -0.036056, 0.009207),
		"primary_touch": Vector3(-0.012015, 0.010019, 0.041948),
		"grip_touch": Vector3(-0.007007, -0.028275, 0.061512),
	},
}
const PLACES := {
	"/interaction_profiles/oculus/touch_controller": TOUCH_PLACES,
	FRAME_PROFILE: FRAME_PLACES,
}


## The actions the control under `touch` does on the hand `tracker`.
static func touched(touch: String, tracker: String) -> Array[String]:
	var out: Array[String] = []
	for action in ACTIONS:
		if ACTIONS[action].get(tracker, "") in TOUCHES[touch]:
			out.append(action)
	return out


## Where `touch`'s control lies on `profile`'s controller held in `tracker`, in its aim pose, or Vector3.INF.
static func place(profile: String, touch: String, tracker: String) -> Vector3:
	if profile == FRAME_PROFILE:
		return FRAME_PLACES.get(tracker, {}).get(touch, Vector3.INF)
	var at: Vector3 = PLACES.get(profile, {}).get(touch, Vector3.INF)
	return at * Vector3(-1, 1, 1) if tracker == "left_hand" and at != Vector3.INF else at


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
## half axis by its sign. The camera and the visit tool fire on "tool", as a controller's trigger does.
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
