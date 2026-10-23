extends "res://../tests/support/suite.gd"

## Headless checks of empty hands: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_hands.gd


func _initialize() -> void:
	boot_main()
	_run.call_deferred()


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
	check(not ToolWheel.paths(Hand.TREE).has(Hand.Tool.NONE), "the wheel holds no empty-hand slot")
	hand.tool = Hand.Tool.FLOWERS
	await frames(3)
	check(hand.aiming(), "a hand holding flowers over the ground shows its sight")
	check(not hand._controller.visible, "a hand holding a tool is drawn as the tool alone")
	check(hand._sight.global_position.is_equal_approx(hand.body.global_transform * (Hand.TOP + ToolModels.tip(Hand.Tool.FLOWERS))), "the sight stands at the flowers' tip")
	hand.tool = Hand.Tool.STYLE
	await frames(int(Hand.POP * 60) + 3)
	var wand := hand.model(Hand.Tool.STYLE)
	check(wand.scale.is_equal_approx(Vector3.ONE * Hand.HELD[Hand.Tool.STYLE]), "the wand is held as long as a hand's tool")
	check(hand._sight.global_position.distance_to(wand.global_transform * ToolModels.WAND_STAR) < 0.03, "the sight stands at the wand's star")
	check((hand._sight.global_position - hand.body.global_position).dot(-hand.body.global_basis.z) > 0.1, "the wand reaches ahead of the hand, along its aim")
	hand.tool = Hand.Tool.FLOWERS
	await frames(3)
	await _play([{"op": "pick", "hand": "right", "tool": "none"}])
	check(hand.tool == Hand.Tool.NONE, "opening the wheel and letting go with nothing picked empties the hand")
	var shown := 0
	for i in 30:
		await process_frame
		shown += int(hand.aiming() or hand._dot.visible)
	check(shown == 0, "an empty hand over the ground shows no sight, shown on %d of 30 frames" % shown)
	check(hand._controller.visible, "an empty hand shows the controller")
	hand.tool = Hand.Tool.BOOK
	await frames(2)
	check(not hand._controller.visible, "the held book shows no hand beneath it, just the book")
	hand.tool = Hand.Tool.NONE
	await frames(2)
	var on_top := hand._models[Hand.Tool.NONE]
	check(on_top.get_child_count() == 0, "nothing stands on an empty hand's controller")
	await _play([{"op": "pick", "hand": "right", "tool": "dirt_path"}])
	await frames(3)
	check(hand.aiming(), "picking a tool brings its sight back")
	await _teleport_draws_no_ray(rig)
	XRServer.remove_tracker(tracker)
	finish()


## Teleport aims with the left hand whatever it holds, and shows only where it lands: no ray, no sight.
func _teleport_draws_no_ray(rig: Rig) -> void:
	rig.left.tool = Hand.Tool.FLOWERS
	rig.left.held_still = true
	rig.left.global_transform = Driver.aim_pose(rig.head.global_transform, [0, -0.3, -1])
	Hand.injected_sticks[rig.left.tracker] = Vector2(0, 1)
	await frames(5)
	check(rig.aim_hand == rig.left and rig._landing.visible, "the stick aims a teleport and its preview shows where it lands")
	check(not rig.left.aiming() and not rig.left._dot.visible, "a teleport draws no ray from the hand")
	Hand.injected_sticks[rig.left.tracker] = Vector2.ZERO
	await frames(3)
	Hand.injected_sticks.erase(rig.left.tracker)
	rig.left.held_still = false


func _play(steps: Array) -> void:
	var d := Driver.new(main, steps)
	main.add_child(d)
	await d.finished
	d.queue_free()
