extends SceneTree

var failures := 0
var main: Node
var trackers: Array[XRControllerTracker] = []


func _initialize() -> void:
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _frames() -> void:
	for i in 3:
		await process_frame


func _capture(name: String) -> void:
	if main.args.has("capture-dir"):
		await main.capture(name)


func _run() -> void:
	var d := Driver.new(main, [{"op": "wall", "points": [[-3, 0], [3, 0]], "seconds": 0.2}])
	main.add_child(d)
	await d.finished
	d.queue_free()
	var rig: Rig = main.rig
	for hand in rig.hands:
		var tracker := XRControllerTracker.new()
		tracker.name = hand.tracker
		tracker.type = XRServer.TRACKER_CONTROLLER
		tracker.set_pose("aim", Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		XRServer.add_tracker(tracker)
		trackers.append(tracker)
		var at := rig.head.global_position + Vector3(-0.35 if hand == rig.left else 0.35, -0.4, -0.5)
		var target := Vector3(at.x, Terrain.height_at(at.x, 0) + 1.0, 0)
		hand.global_transform = Transform3D(Basis.looking_at(target - at), at)
	await _frames()
	var hand := rig.right
	_check(hand._beam.visible and hand._dot.visible, "idle hand points at the wall")
	Buttons.injected["right_hand/grip_click"] = true
	await _frames()
	_check(main.tool.mason(hand).lifting != null, "grip takes the wall")
	_check(not hand._beam.visible and not hand._dot.visible, "wall grab hides beam and dot")
	hand.point(Vector3.ZERO, Color.WHITE)
	_check(not hand._beam.visible and not hand._dot.visible, "a later tool cannot redraw a held hand pointer")
	_check(rig.left._beam.visible, "other hand can still point")
	await _capture("grab")
	var height: float = main.tool.walls[0].layout.height
	hand.rotate_x(0.2)
	await _frames()
	_check(is_equal_approx(main.tool.walls[0].layout.height, height), "rotating a held wall does not lift it")
	hand.position.y += 0.2
	await _frames()
	_check(main.tool.walls[0].layout.height > height, "translating the hand lifts the wall")
	Buttons.injected.erase("right_hand/grip_click")
	await _frames()
	_check(main.tool.mason(hand).lifting == null, "release drops the wall")
	_check(hand._beam.visible, "pointer returns on release")
	await _capture("released")
	for tool in [Hand.Tool.TERRAIN, Hand.Tool.POND]:
		hand.tool = tool
		hand.global_basis = Basis.looking_at(Vector3(0, -0.6, -1))
		Buttons.injected["right_hand/trigger_click"] = true
		await _frames()
		_check(main.terrain_tool.busy(), "trigger takes the ground with tool %d" % tool)
		_check(not hand._beam.visible and not hand._dot.visible, "ground grab hides pointer with tool %d" % tool)
		hand.tool = Hand.Tool.WALLS
		await _frames()
		_check(not main.terrain_tool.busy(), "tool switch cancels ground grab")
		_check(hand._beam.visible, "tool switch restores pointer")
		Buttons.injected.erase("right_hand/trigger_click")
		await _frames()
	var sun: SunTool = main.sun_tool
	var time: float = main.look.time
	hand.global_basis = Basis.looking_at(Daylight.toward_sun(time))
	Buttons.injected["right_hand/grip_click"] = true
	await _frames()
	_check(sun.holder == hand, "grip takes the sun")
	hand.rotate_y(0.3)
	await _frames()
	_check(is_equal_approx(main.look.time, time), "wrist rotation does not drag the held sun")
	_check(not hand._beam.visible, "sun grab hides the pointer")
	hand.position += -Daylight.RISE * 0.2
	await _frames()
	_check(main.look.time > time, "hand translation advances the sun")
	Buttons.injected.erase("right_hand/grip_click")
	await _frames()
	_check(sun.holder == null, "release drops the sun")
	var left := rig.left
	left.global_basis = Basis.looking_at(Daylight.toward_sun(main.look.time))
	Buttons.injected["left_hand/grip_click"] = true
	await _frames()
	Hand.injected_sticks[left.tracker] = Vector2(0, 1)
	await _frames()
	_check(sun.holder == left, "left hand keeps the sun while aiming teleport")
	_check(not left._beam.visible and not left._dot.visible, "teleport cannot bypass a held hand pointer rule")
	Hand.injected_sticks.clear()
	Buttons.injected.clear()
	await _frames()
	for tracker in trackers:
		XRServer.remove_tracker(tracker)
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)
