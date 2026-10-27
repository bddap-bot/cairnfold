class_name Flat
extends Node

## A player without a headset, on a flat screen with mouse and keyboard or a gamepad (`Controls.FLAT`). It walks the
## ground instead of teleporting and looks with the mouse or the right stick; its input stands in for the controllers
## through the same tool entry points. The only tools it holds are the camera, the seed dish and the mirror, in the
## right hand raised before the eye, or none, so there is no edit path to keep it from: with none, both hands hang at
## the sides, as other players see them.

const WAVE: Animation = preload("res://animations/wave.tres")

const TOOLS: Array[Hand.Tool] = [Hand.Tool.NONE, Hand.Tool.CAMERA, Hand.Tool.SEEDS, Hand.Tool.MIRROR]
const WALK := 2.5
## Radians a second at full stick, and per pixel of mouse.
const STICK_LOOK := 2.6
const MOUSE_LOOK := 0.003
const PITCH := deg_to_rad(85.0)
## The camera is held on the line of sight, its screen the viewfinder, so the photo frames what the view shows.
const CAMERA_HELD := Vector3(0.0, 0.0, -0.32)
const WHEEL_HELD := Vector3(0.0, -0.13, -0.45)
## The seed dish is held out low in the view and kept level, for an animal to stand on or eat under.
const DISH_HELD := Vector3(0.08, -0.22, -0.42)
## Holding the dish, looking down stoops the player by up to this many metres, so the dish reaches the animals that
## eat low; no faster than STOOP_SPEED, metres a second, below what startles them (`Wildlife.CALM`).
const STOOP := 0.8
const STOOP_SPEED := 0.5
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
var _wheel_button := ""
var _reach := Vector2.ZERO
var _wheeling := false
var _firing := false
var _wave_time := -1.0
var stoop := 0.0


func _init(player: Rig) -> void:
	name = "Flat"
	rig = player
	process_priority = -20
	_wheel_button = "%s/%s" % [rig.right.tracker, Controls.input("wheel", rig.right.tracker)]
	_trigger = "%s/%s" % [rig.right.tracker, Controls.input("tool", rig.right.tracker)]
	for h in rig.hands:
		h.flat_only = true
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
	Buttons.injected.erase(_wheel_button)
	Hand.injected_reach.erase(rig.right.tracker)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and not mouse_held:
		mouse_held = true
		_taking_click = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and mouse_held:
		if rig.right.picking:
			_reach += Vector2(event.relative.x, -event.relative.y) * 0.0005
			return
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


## The right hand's aim pose from the eyes, tipped by `pitch`, while it holds `tool`.
static func held(tool: Hand.Tool, pitch: float) -> Transform3D:
	if tool == Hand.Tool.CAMERA:
		return Transform3D(Basis.IDENTITY, CAMERA_HELD)
	if tool == Hand.Tool.SEEDS:
		return Transform3D(Basis(Vector3.RIGHT, -pitch), DISH_HELD)
	return Transform3D(Basis.IDENTITY, WHEEL_HELD)


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
	var wheel := Input.is_action_pressed("flat_wheel")
	if wheel:
		if not Buttons.injected.has(_wheel_button):
			_reach = Vector2.ZERO
		Buttons.injected[_wheel_button] = true
		_reach += stick * delta * 0.25
		Hand.injected_reach[rig.right.tracker] = _reach
	else:
		if _wheeling:
			Buttons.injected.erase(_wheel_button)
		if not rig.right.picking:
			Hand.injected_reach.erase(rig.right.tracker)
		turn(-stick.x * STICK_LOOK * delta, stick.y * STICK_LOOK * delta)
	_wheeling = wheel
	var low := STOOP * maxf(0.0, -sin(pitch)) if rig.right.tool == Hand.Tool.SEEDS else 0.0
	stoop = move_toward(stoop, low, STOOP_SPEED * delta)
	var level := Basis(Vector3.UP, yaw)
	var eyes := Transform3D(level * Basis(Vector3.RIGHT, pitch), Vector3.UP * (Rig.EYE * rig.world_scale - stoop))
	rig.head.transform = eyes
	var move := Input.get_vector("flat_left", "flat_right", "flat_forward", "flat_back")
	if move != Vector2.ZERO:
		_walk(rig.global_basis * level * Vector3(move.x, 0.0, move.y) * WALK * delta)
	if Input.is_action_just_pressed("flat_next_tool") and not _taking_click and not wheel:
		rig.right.tool = TOOLS[(TOOLS.find(rig.right.tool) + 1) % TOOLS.size()]
	var raised := rig.right.tool != Hand.Tool.NONE or wheel or rig.right.picking
	if raised:
		_wave_time = -1.0
	elif Input.is_action_just_pressed("flat_wave") and _wave_time < 0.0:
		_wave_time = 0.0
	elif _wave_time >= 0.0:
		_wave_time += delta
		if _wave_time > WAVE.length:
			_wave_time = -1.0
	for s in 2:
		var at_side := Transform3D(level, eyes.origin) * Avatar.AT_SIDES[s]
		rig.hands[s].transform = eyes * (Transform3D(Basis.IDENTITY, WHEEL_HELD) if wheel or rig.right.picking else Flat.held(rig.right.tool, pitch)) if raised and s == 1 else at_side
		if _wave_time >= 0.0:
			var hand := Transform3D(Basis(WAVE.rotation_track_interpolate(s * 2 + 1, _wave_time)), WAVE.position_track_interpolate(s * 2, _wave_time))
			rig.hands[s].transform = Transform3D(level, eyes.origin) * hand
	var firing := raised and not wheel and not rig.right.picking and Input.is_action_pressed("flat_tool") and not _taking_click
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
		if not rig.solid_hit.call(Vector3(head.x, y, head.z), step.normalized(), step.length() + BODY).is_empty():
			return
	var room := Terrain.ROOM
	var to := head + step
	to.x = clampf(to.x, room.position.x, room.end.x)
	to.z = clampf(to.z, room.position.z, room.end.z)
	to.y = rig.global_position.y + STEP_UP
	rig.place(Vector3(to.x, rig.floor_under.call(to), to.z), 0.0)
