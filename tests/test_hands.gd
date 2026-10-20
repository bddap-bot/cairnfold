extends SceneTree

## Headless checks of empty hands: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_hands.gd

var failures := 0
var main: Node


func _initialize() -> void:
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	var rig: Rig = main.rig
	await _play([{"op": "place", "x": 0, "z": 6}, {"op": "wait", "seconds": 0.2}])
	var tracker := XRPositionalTracker.new()
	tracker.type = XRServer.TRACKER_CONTROLLER
	tracker.name = &"right_hand"
	XRServer.add_tracker(tracker)
	var at := rig.head.global_position + Vector3(0.2, -0.4, -0.3)
	var spot := Terrain.ground(2, 2)
	tracker.set_pose(&"aim", rig.global_transform.affine_inverse() * Transform3D(Basis.looking_at(spot - at, Vector3.UP), at), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	var hand := rig.right
	_check(not ToolWheel.paths(Hand.TREE).has(Hand.Tool.NONE), "the wheel holds no empty-hand slot")
	hand.tool = Hand.Tool.FLOWERS
	await _frames(3)
	_check(hand._beam.visible, "a hand holding flowers over the ground shows its ray")
	await _play([{"op": "pick", "hand": "right", "tool": "none"}])
	_check(hand.tool == Hand.Tool.NONE, "opening the wheel and letting go with nothing picked empties the hand")
	var shown := 0
	for i in 30:
		await process_frame
		shown += int(hand._beam.visible or hand._dot.visible)
	_check(shown == 0, "an empty hand over the ground shows no ray, shown on %d of 30 frames" % shown)
	var bar: BudgetBar = hand.get_children().filter(func(c: Node) -> bool: return c is BudgetBar)[0]
	_check(not bar.visible, "an empty hand shows no budget bar")
	var on_top := hand._models[Hand.Tool.NONE]
	_check(on_top.get_child_count() == 0, "nothing stands on an empty hand's controller")
	await _play([{"op": "pick", "hand": "right", "tool": "dirt_path"}])
	await _frames(3)
	_check(hand._beam.visible, "picking a tool brings its ray back")
	_check(bar.visible, "picking a tool brings its budget bar back")
	for camera in [Hand.Tool.CAMERA, Hand.Tool.SELFIE]:
		hand.tool = camera
		await _frames(1)
		_check(not bar.visible, "a camera builds nothing, so shows no budget bar either")
	XRServer.remove_tracker(tracker)
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _play(steps: Array) -> void:
	var d := Driver.new(main, steps)
	main.add_child(d)
	await d.finished
	d.queue_free()
