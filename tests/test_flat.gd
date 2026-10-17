extends SceneTree

## Headless checks of flat mode: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_flat.gd
## Taking a photo and joining a garden need a renderer and a second game: demo/flat-host.json and demo/flat-join.json.

var failures := 0
var main: Main
var flat: Flat


func _initialize() -> void:
	_only_a_game_without_a_headset_comes_up_flat()
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	flat = Flat.new(main.rig)
	main.add_child(flat)
	await _frames(2)
	var sent := main.world._next_token
	await _keys_and_a_gamepad_walk_and_look()
	await _the_hands_hang_at_the_sides_until_a_tool_is_raised()
	await _the_trigger_reaches_only_the_camera_and_the_visit_tool()
	await _every_control_on_every_tool_sends_no_edit(sent)
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _key(down: bool, code: Key) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.pressed = down
	Input.parse_input_event(e)


func _axis(axis: JoyAxis, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)


func _button(down: bool, button: JoyButton) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = down
	Input.parse_input_event(e)


func _mouse(down: bool, button: MouseButton) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = down
	Input.parse_input_event(e)


## `press(down)`: a control's helper bound to it, `down` first since bound arguments follow the call's.
func _tap(press: Callable, frames := 3) -> void:
	press.call(true)
	await _frames(frames)
	press.call(false)
	await _frames(2)


func _only_a_game_without_a_headset_comes_up_flat() -> void:
	_check(Main.flat_wanted({}, false, true), "a game played without a headset comes up flat")
	_check(not Main.flat_wanted({}, true, true), "one played in a headset does not")
	_check(not Main.flat_wanted({"desktop": true}, false, true), "nor one rendering on the desktop")
	_check(not Main.flat_wanted({}, false, false), "nor a script or test, unless it asks")
	_check(Main.flat_wanted({"flat": true}, false, false), "which --flat does")


func _forward() -> Vector3:
	var f := -main.rig.head.global_basis.z
	return Vector3(f.x, 0, f.z).normalized()


func _keys_and_a_gamepad_walk_and_look() -> void:
	var eye := main.rig.head.global_position
	var ahead := _forward()
	await _tap(_key.bind(KEY_W), 60)
	var moved := main.rig.head.global_position - eye
	_check(absf(moved.dot(ahead) - Flat.WALK) < 0.2, "W walks ahead at walking pace: %.2f m in a second" % moved.dot(ahead))
	var feet := main.rig.head.global_position
	_check(absf(feet.y - Terrain.height_at(feet.x, feet.z) - Rig.EYE) < 0.05, "with the eyes at standing height over the ground")
	eye = main.rig.head.global_position
	_axis(JOY_AXIS_LEFT_X, 1.0)
	await _frames(30)
	_axis(JOY_AXIS_LEFT_X, 0.0)
	await _frames(2)
	var right := ahead.cross(Vector3.UP)
	_check((main.rig.head.global_position - eye).dot(right) > Flat.WALK * 0.4, "the left stick steps sideways")

	var yaw := flat.yaw
	var e := InputEventMouseMotion.new()
	e.relative = Vector2(100, 0)
	Input.parse_input_event(e)
	await _frames(2)
	_check(flat.yaw == yaw, "the mouse turns nothing before a click in the window takes it")
	await _tap(_mouse.bind(MOUSE_BUTTON_LEFT))
	_check(flat.mouse_held, "a click takes the mouse")
	Input.parse_input_event(e)
	await _frames(2)
	_check(absf(flat.yaw - (yaw - 100 * Flat.MOUSE_LOOK)) < 1e-4, "moving it right turns the view right")
	_check(_forward().dot(ahead.rotated(Vector3.UP, -100 * Flat.MOUSE_LOOK)) > 0.999, "and the head with it")
	await _tap(_key.bind(KEY_ESCAPE))
	_check(not flat.mouse_held, "Escape lets it go")
	var pitch := flat.pitch
	_axis(JOY_AXIS_RIGHT_Y, -1.0)
	await _frames(20)
	_axis(JOY_AXIS_RIGHT_Y, 0.0)
	await _frames(2)
	_check(flat.pitch > pitch + 0.5, "the right stick pushed up looks up")
	_axis(JOY_AXIS_RIGHT_Y, -1.0)
	await _frames(120)
	_axis(JOY_AXIS_RIGHT_Y, 0.0)
	await _frames(2)
	_check(absf(flat.pitch - Flat.PITCH) < 1e-4, "never past straight up")
	flat.pitch = 0.0
	await _frames(1)


func _near(a: Transform3D, b: Transform3D) -> bool:
	return a.origin.distance_to(b.origin) < 0.01 and a.basis.x.distance_to(b.basis.x) < 0.01 and a.basis.z.distance_to(b.basis.z) < 0.01


func _the_hands_hang_at_the_sides_until_a_tool_is_raised() -> void:
	var rig := main.rig
	_check(rig.hands.all(func(h: Hand) -> bool: return h.tool == Hand.Tool.HANDS), "flat mode starts with empty hands")
	flat.pitch = -0.6
	await _frames(2)
	var level := Transform3D(Basis(Vector3.UP, rig.head.global_basis.get_euler().y), rig.head.global_position)
	for s in 2:
		_check(_near(rig.hands[s].body.global_transform, level * Avatar.AT_SIDES[s]), "the %s hand hangs at the side as others see it, however the head tips" % ["left", "right"][s])
	await _tap(_key.bind(KEY_TAB))
	_check(rig.right.tool == Hand.Tool.CAMERA, "Tab takes up the camera")
	_check(_near(rig.right.global_transform, rig.head.global_transform * Flat.held(Hand.Tool.CAMERA)), "raised before the eye")
	_check(PhotoTool.lens(rig.right).basis.z.dot(rig.head.global_basis.z) > 0.999, "its lens looking where the view does")
	_check(_near(rig.left.body.global_transform, level * Avatar.AT_SIDES[0]), "the other hand still at its side")
	var trigger := "right_hand/" + Controls.input("tool", "right_hand")
	_mouse(true, MOUSE_BUTTON_LEFT)
	await _frames(3)
	_check(flat.mouse_held and not Buttons.injected.has(trigger), "the click that takes the mouse takes no photo")
	_mouse(false, MOUSE_BUTTON_LEFT)
	await _frames(2)
	await _tap(_button.bind(JOY_BUTTON_Y))
	_check(rig.right.tool == Hand.Tool.VISIT, "the gamepad's Y takes up the visit tool")
	await _tap(_mouse.bind(MOUSE_BUTTON_RIGHT))
	_check(rig.right.tool == Hand.Tool.HANDS, "and the right mouse button puts it away")
	await _frames(1)
	_check(_near(rig.right.body.global_transform, level * Avatar.AT_SIDES[1]), "the hand dropping back to the side")
	flat.pitch = 0.0
	await _frames(1)
	var eye := rig.head.global_position
	var solid := rig.solid_hit
	rig.solid_hit = func(origin: Vector3, _dir: Vector3, reach: float) -> Variant: return origin if reach > Flat.BODY else null
	await _tap(_key.bind(KEY_W), 20)
	_check(rig.head.global_position.distance_to(eye) < 1e-4, "a build in the way stops the walk")
	rig.solid_hit = solid


func _the_trigger_reaches_only_the_camera_and_the_visit_tool() -> void:
	var rig := main.rig
	var trigger := "right_hand/" + Controls.input("tool", "right_hand")
	_mouse(true, MOUSE_BUTTON_LEFT)
	await _frames(2)
	_check(not Buttons.injected.has(trigger), "with empty hands a click pulls no trigger")
	_mouse(false, MOUSE_BUTTON_LEFT)
	rig.right.tool = Hand.Tool.VISIT
	await _frames(2)
	_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await _frames(2)
	_check(Buttons.new(rig.right).held("tool"), "holding the visit tool, the right trigger pulls the hand's")
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	await _frames(2)
	_check(not Buttons.injected.has(trigger), "and lets go with it")
	rig.right.tool = Hand.Tool.HANDS
	await _frames(1)


## Every flat control, and every other key, mouse and gamepad button, pressed holding each tool flat mode can hold.
func _every_control_on_every_tool_sends_no_edit(sent: int) -> void:
	var rig := main.rig
	for t in Flat.TOOLS:
		rig.right.tool = t
		await _frames(2)
		for key in range(KEY_SPACE, KEY_ASCIITILDE + 1) + [KEY_TAB, KEY_ESCAPE, KEY_ENTER, KEY_BACKSPACE, KEY_DELETE, KEY_CTRL, KEY_SHIFT, KEY_ALT, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
			if key == KEY_TAB:
				continue
			_key(true, key)
			await process_frame
			_key(false, key)
		for b in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			await _tap(_mouse.bind(b), 2)
		for b in JOY_BUTTON_SDL_MAX:
			if b != JOY_BUTTON_Y:
				await _tap(_button.bind(b), 2)
		for a in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
			await _tap(func(on: bool) -> void: _axis(a, 1.0 if on else 0.0), 2)
		_check(rig.right.tool == t, "no key changes the tool but the next-tool controls")
	_check(rig.hands.all(func(h: Hand) -> bool: return Flat.TOOLS.has(h.tool)), "no hand ever holds an edit tool")
	_check(main.world._next_token == sent, "and no edit command is ever sent: %d sent" % (main.world._next_token - sent))
