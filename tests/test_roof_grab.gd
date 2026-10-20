extends SceneTree

var main: Node
var failures := 0
var trackers: Array[XRControllerTracker] = []


func _initialize() -> void:
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _frames(count := 4) -> void:
	for i in count:
		await process_frame


func _run() -> void:
	var driver := Driver.new(main, [{"op": "house", "at": [0, 0], "size": [6, 4], "seconds": 0.1}])
	main.add_child(driver)
	await driver.finished
	driver.queue_free()
	await _frames(30)
	var tool: WallTool = main.tool
	var w: Wall = tool.walls[0]
	var rig: Rig = main.rig
	var pitch := w.roof.pitch
	var points := w.layout.points.duplicate()
	var mid: Vector3 = w.roof.frame().mid
	for hand in rig.hands:
		var tracker := XRControllerTracker.new()
		tracker.name = hand.tracker
		tracker.type = XRServer.TRACKER_CONTROLLER
		tracker.set_pose("aim", Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		XRServer.add_tracker(tracker)
		trackers.append(tracker)
		hand.global_transform = Transform3D(Basis.looking_at(Vector3(0, -1, -0.1)), mid + Vector3(-0.5 if hand == rig.left else 0.5, pitch + 2, 0.5))
	await _frames()
	Buttons.injected["left_hand/grip_click"] = true
	await _frames()
	_check(tool.mason(rig.left).roofing == w, "first grip picks the roof")
	rig.left.position.x -= 0.1
	await _frames()
	_check(w.roof.curve == 0.0, "one hand sideways cannot bow the roof")
	Buttons.injected["right_hand/grip_click"] = true
	await _frames()
	_check(tool.resizing == w and tool._resize_roof, "second roof grip selects curvature in the building grab")
	var start := rig.right.position
	for spread in [0.3, 0.0, -0.3, -0.301]:
		rig.right.position = start + Vector3(spread, 0, 0)
		await _frames()
		_check(absf(w.roof.curve - spread * 2.0) < 0.0001, "separation drives continuous signed curvature: %s" % spread)
		_check(w.roof.pitch == pitch and w.layout.points == points, "bowing keeps pitch and footprint")
	var curve := w.roof.curve
	Buttons.injected.erase("left_hand/grip_click")
	await _frames()
	_check(tool.resizing == null, "either hand releases the shared grab")
	_check(is_equal_approx(main.world.state.walls[w.id].roof.curve, curve), "release submits curvature to the shared garden")
	Buttons.injected.clear()
	await _frames()
	main.world.undo()
	await _frames()
	_check(main.world.state.walls[w.id].roof.curve == 0.0, "one undo restores the original roof")
	for tracker in trackers:
		XRServer.remove_tracker(tracker)
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)
