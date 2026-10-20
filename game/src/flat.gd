class_name Flat
extends Node

## A player without a headset, on a flat screen with mouse and keyboard or a gamepad (`Controls.FLAT`). It walks the
## ground instead of teleporting and looks with the mouse or the right stick; its input stands in for the controllers
## through the same tool entry points. The only tools it holds are the camera and the visit tool, in the right hand
## raised before the eye, or none, so there is no edit path to keep it from: with none, both hands hang at the sides,
## as other players see them.

const TOOLS: Array[Hand.Tool] = [Hand.Tool.NONE, Hand.Tool.CAMERA, Hand.Tool.VISIT]
const WALK := 2.5
## Radians a second at full stick, and per pixel of mouse.
const STICK_LOOK := 2.6
const MOUSE_LOOK := 0.003
const PITCH := deg_to_rad(85.0)
## The camera is held on the line of sight, its screen the viewfinder, so the photo frames what the view shows.
const CAMERA_HELD := Vector3(0.0, 0.0, -0.32)
## The visit tool is held low, out of the way of the figures, its beam crossing the line of sight where they stand.
const VISIT_HELD := Vector3(0.0, -0.13, -0.32)
## How far ahead of the head a step must be clear of builds, at the knees and at the eyes.
const BODY := 0.3
const DEADZONE := 0.2
const STEP_UP := 0.5

var rig: Rig
var yaw := 0.0
var pitch := 0.0
## Whether the mouse turns the view: from a click in the window until Escape or the window loses focus.
var mouse_held := false
## The click that took the mouse, held: it neither fires nor changes tools.
var _taking_click := false
var _trigger := ""
var _firing := false


func _init(player: Rig) -> void:
	name = "Flat"
	rig = player
	process_priority = -20
	_trigger = "%s/%s" % [rig.right.tracker, Controls.input("tool", rig.right.tracker)]
	for h in rig.hands:
		h.tool = Hand.Tool.NONE
		h.held_still = true
	for action in Controls.FLAT:
		var named: String = "flat_" + action
		if not InputMap.has_action(named):
			InputMap.add_action(named, DEADZONE)
			for spec: Array in Controls.FLAT[action]:
				InputMap.action_add_event(named, _event(spec))


static func _event(spec: Array) -> InputEvent:
	match spec[0]:
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = spec[1]
			return k
		"mouse":
			var m := InputEventMouseButton.new()
			m.button_index = spec[1]
			return m
		"button":
			var b := InputEventJoypadButton.new()
			b.device = -1
			b.button_index = spec[1]
			return b
	var a := InputEventJoypadMotion.new()
	a.device = -1
	a.axis = spec[1]
	a.axis_value = spec[2]
	return a


func _exit_tree() -> void:
	Buttons.injected.erase(_trigger)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and not mouse_held:
		mouse_held = true
		_taking_click = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and mouse_held:
		turn(-event.relative.x * MOUSE_LOOK, -event.relative.y * MOUSE_LOOK)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_let_go()


func _let_go() -> void:
	mouse_held = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func turn(by_yaw: float, by_pitch: float) -> void:
	yaw = wrapf(yaw + by_yaw, -PI, PI)
	pitch = clampf(pitch + by_pitch, -PITCH, PITCH)


## The right hand's aim pose from the eyes while it holds `tool`.
static func held(tool: Hand.Tool) -> Transform3D:
	if tool == Hand.Tool.CAMERA:
		return Transform3D(Basis.IDENTITY, CAMERA_HELD)
	return Transform3D(Basis.looking_at(Vector3(0, 0, -VisitTool.ARC) - VISIT_HELD), VISIT_HELD)


## Turns the view to look at `at`.
func face(at: Vector3) -> void:
	var d := rig.global_basis.inverse() * (at - rig.head.global_position)
	yaw = atan2(-d.x, -d.z)
	pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -PITCH, PITCH)


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("flat_let_go"):
		_let_go()
	if _taking_click and Input.get_mouse_button_mask() == 0:
		_taking_click = false
	var stick := Input.get_vector("flat_look_left", "flat_look_right", "flat_look_down", "flat_look_up")
	turn(-stick.x * STICK_LOOK * delta, stick.y * STICK_LOOK * delta)
	var level := Basis(Vector3.UP, yaw)
	var eyes := Transform3D(level * Basis(Vector3.RIGHT, pitch), Vector3.UP * Rig.EYE)
	rig.head.transform = eyes
	var move := Input.get_vector("flat_left", "flat_right", "flat_forward", "flat_back")
	if move != Vector2.ZERO:
		_walk(rig.global_basis * level * Vector3(move.x, 0.0, move.y) * WALK * delta)
	if Input.is_action_just_pressed("flat_next_tool") and not _taking_click:
		rig.right.tool = TOOLS[(TOOLS.find(rig.right.tool) + 1) % TOOLS.size()]
	var raised := rig.right.tool != Hand.Tool.NONE
	for s in 2:
		var at_side := Transform3D(level, Vector3.UP * Rig.EYE) * Avatar.AT_SIDES[s]
		rig.hands[s].transform = eyes * Flat.held(rig.right.tool) if raised and s == 1 else at_side
	var firing := raised and Input.is_action_pressed("flat_tool") and not _taking_click
	if firing != _firing:
		_firing = firing
		if firing:
			Buttons.injected[_trigger] = true
		else:
			Buttons.injected.erase(_trigger)


## Walks by `step` over whatever the feet can step up onto, inside the garden; a wall, fence or house stops it.
func _walk(step: Vector3) -> void:
	var head := rig.head.global_position
	for y in [rig.global_position.y + STEP_UP, head.y]:
		if rig.solid_hit.call(Vector3(head.x, y, head.z), step.normalized(), step.length() + BODY) != null:
			return
	var room := Terrain.bounds()
	var to := head + step
	to.x = clampf(to.x, room.position.x, room.end.x)
	to.z = clampf(to.z, room.position.z, room.end.z)
	to.y = rig.global_position.y + STEP_UP
	rig.place(Vector3(to.x, rig.floor_under.call(to), to.z), 0.0)
