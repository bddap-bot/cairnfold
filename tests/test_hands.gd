extends "res://../tests/support/booted.gd"

## Headless checks of empty hands: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_hands.gd

var terrain: Terrain:
	get:
		return main.world.terrain


func _run() -> void:
	var rig: Rig = main.rig
	await play([{"op": "place", "x": 0, "z": 6}])
	var tracker := XRPositionalTracker.new()
	tracker.type = XRServer.TRACKER_CONTROLLER
	tracker.name = &"right_hand"
	XRServer.add_tracker(tracker)
	var at := rig.head.global_position + Vector3(0.2, -0.4, -0.3)
	var spot := terrain.ground(2, 2)
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
	await play([{"op": "pick", "hand": "right", "tool": "none"}])
	check(hand.tool == Hand.Tool.NONE, "opening the wheel and letting go with nothing picked empties the hand")
	var shown := 0
	for i in 30:
		await process_frame
		shown += int(hand.aiming() or hand._dot.visible)
	check(shown == 0, "an empty hand over the ground shows no sight, shown on %d of 30 frames" % shown)
	check(hand._controller.visible, "an empty hand shows the controller")
	var left_holds := rig.left.tool
	rig.left.tool = Hand.Tool.NONE
	await frames(2)
	check(not hand._controller.visible, "with both hands empty the eyes see the avatar's own hand, with no controller drawn over it")
	rig.left.tool = left_holds
	hand.tool = Hand.Tool.BOOK
	await frames(2)
	check(not hand._controller.visible, "the held book shows no hand beneath it, just the book")
	hand.tool = Hand.Tool.NONE
	await frames(2)
	var on_top := hand._models[Hand.Tool.NONE]
	check(on_top.get_child_count() == 0, "nothing stands on an empty hand's controller")
	await play([{"op": "pick", "hand": "right", "tool": "path"}])
	await frames(3)
	check(hand.aiming(), "picking a tool brings its sight back")
	await _teleport_draws_no_ray(rig)
	await _the_avatar_holds_the_grip(rig, tracker)
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
	rig.left.tool = Hand.Tool.SEEDS
	var thrown: int = Cues.asked.get(Cues.Act.SEEDS_THROW, 0)
	await _tap(rig.left)
	check(Cues.asked.get(Cues.Act.SEEDS_THROW, 0) == thrown, "a hand aiming a teleport throws no seeds")
	rig.left.tool = Hand.Tool.FLOWERS
	Hand.injected_sticks[rig.left.tracker] = Vector2.ZERO
	await frames(3)
	Hand.injected_sticks.erase(rig.left.tracker)
	rig.left.tool = Hand.Tool.SEEDS
	rig.left.picking = true
	var unthrown: int = Cues.asked.get(Cues.Act.SEEDS_THROW, 0)
	await _tap(rig.left)
	rig.left.picking = false
	check(Cues.asked.get(Cues.Act.SEEDS_THROW, 0) == unthrown, "a hand picking from the wheel throws no seeds")
	rig.left.tool = Hand.Tool.FLOWERS
	rig.left.held_still = false
	rig.left.bare = true
	check(rig.left.tracked(), "a bare hand the runtime follows by its joints is tracked")
	rig.left.bare = false
	Hand.injected_sticks[rig.right.tracker] = Vector2(0, 0.9)
	await frames(2)
	var flicked := rig.right.flick
	Hand.injected_sticks[rig.right.tracker] = Vector2(0, 0.5)
	await frames(2)
	check(flicked == "primary_up" and rig.right.flick == flicked, "a flicked stick eased back short of the push stays one flick")
	Hand.injected_sticks[rig.right.tracker] = Vector2.ZERO
	await frames(2)
	check(rig.right.flick == "", "and lets go back near the middle")
	Hand.injected_sticks.erase(rig.right.tracker)


## The avatar's hand closes round the controller where the runtime puts the palm, never at its aim, which stands out
## ahead of the hand on every controller. Its grip_surface pose gives the palm whole; the grip pose only its centre, the
## fingers then pointing as the aim does, since its axes follow the handle rather than the hand.
func _the_avatar_holds_the_grip(rig: Rig, tracker: XRPositionalTracker) -> void:
	var hand := rig.right
	hand.tool = Hand.Tool.FLOWERS
	var aim := Transform3D(Basis.looking_at(Vector3(0, -0.2, -1), Vector3.UP), Vector3(0.2, 1.2, -0.35))
	var from_aim := Transform3D(Basis(Vector3.RIGHT, 0.6), Vector3(0, -0.03, 0.08))
	var s := rig.world_scale
	tracker.set_pose(&"aim", aim, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	tracker.set_pose(&"grip", aim * from_aim, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	await frames(3)
	var expected := Transform3D(Basis(), from_aim.origin * s)
	check(hand.palm.is_equal_approx(expected), "the palm stands at the grip pose's position, turned as the aim: %s, not %s" % [hand.palm, expected])
	check(hand.palm_from == "grip", "and is read from the grip, not %s" % hand.palm_from)
	var grip := rig.global_transform * Transform3D((aim * from_aim).basis, (aim * from_aim).origin * s)
	var held := rig.body.hands[1] * rig.body.palms[1]
	check(held.origin.distance_to(grip.origin) < 0.001, "the avatar holds its palm at the grip, %.3f m from it" % held.origin.distance_to(grip.origin))
	check(rig.body.hands[1].origin.distance_to(hand.body.global_position) < 0.001, "and the hand it streams, and holds tools in, stays the controller's")
	check((-held.basis.z).dot(-rig.body.hands[1].basis.z) > 0.999, "its fingers point as the aim does")
	var surface := Transform3D(Basis(Vector3.RIGHT, -0.3) * Basis(Vector3.UP, 0.1), Vector3(0.005, -0.02, 0.07))
	tracker.set_pose(&"palm_pose", aim * surface, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	await frames(3)
	expected = Transform3D(surface.basis, surface.origin * s)
	check(hand.palm.is_equal_approx(expected), "with a grip_surface pose the palm is that pose from the aim: %s, not %s" % [hand.palm, expected])
	check(hand.palm_from == "grip_surface", "read from the grip_surface, not %s" % hand.palm_from)
	tracker.invalidate_pose(&"palm_pose")
	tracker.invalidate_pose(&"grip")


func _tap(hand: Hand) -> void:
	Buttons.injected[Controls.key("tool", hand.tracker)] = true
	await frames(3)
	Buttons.injected.erase(Controls.key("tool", hand.tracker))
	await frames(2)
