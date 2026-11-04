extends "res://../tests/support/suite.gd"

## A hand the runtime reports joints for is played by them only when they are the hand's own, and its pinch reads as the
## trigger: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_hand_tracking.gd


func _initialize() -> void:
	boot_main()
	_run.call_deferred()


func _run() -> void:
	await frames(3)
	var right: Hand = main.rig.right
	var controller := XRControllerTracker.new()
	controller.name = right.tracker
	controller.type = XRServer.TRACKER_CONTROLLER
	XRServer.add_tracker(controller)
	var joints := XRHandTracker.new()
	joints.name = "/user/hand_tracker/right"
	joints.hand = XRPositionalTracker.TRACKER_HAND_RIGHT
	XRServer.add_tracker(joints)
	var palm := Transform3D(Basis.IDENTITY, Vector3(0.2, 1.3, -0.3))
	var pressed := Buttons.new(right).watch(["tool"])

	_shape(joints, palm, "index", XRHandTracker.HAND_TRACKING_SOURCE_CONTROLLER)
	await frames(2)
	check(not right.bare, "joints a controller drives leave the hand on its controller")

	_shape(joints, palm, "", XRHandTracker.HAND_TRACKING_SOURCE_UNKNOWN)
	controller.set_pose("aim", Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	await frames(2)
	check(not right.bare, "joints of unknown source, with the controller posed, leave the hand on its controller")
	controller.invalidate_pose("aim")
	await frames(2)
	check(right.bare, "joints of unknown source with no controller pose play the hand")

	_shape(joints, palm, "", XRHandTracker.HAND_TRACKING_SOURCE_UNOBSTRUCTED)
	controller.set_pose("aim", Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	await frames(2)
	check(right.bare, "the hand's own joints play it even with a controller posed")
	check(right.global_position.is_equal_approx(main.rig.global_transform * palm.origin), "a bare hand stands at its palm: %s" % right.global_position)
	check(not pressed.held("tool"), "an open hand holds no trigger")
	_shape(joints, palm, "index", XRHandTracker.HAND_TRACKING_SOURCE_UNOBSTRUCTED)
	await frames(1)
	check(pressed.held("tool") and right.gesture == "index", "thumb to index holds the trigger: %s" % right.gesture)
	_shape(joints, palm, "fist", XRHandTracker.HAND_TRACKING_SOURCE_UNOBSTRUCTED)
	await frames(1)
	check(right.gesture == "fist" and not pressed.held("tool"), "a fist, its thumb on the index, is a grip, not the trigger: %s" % right.gesture)

	joints.has_tracking_data = false
	await frames(2)
	check(not right.bare, "a hand lost hands back to the controller")
	XRServer.remove_tracker(joints)
	XRServer.remove_tracker(controller)
	finish()


func _shape(t: XRHandTracker, palm: Transform3D, gesture: String, source: XRHandTracker.HandTrackingSource) -> void:
	var made := HandShape.make(palm, false, gesture)
	for j in made.size():
		t.set_hand_joint_transform(j, made[j])
		t.set_hand_joint_flags(j, XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID | XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_VALID)
	t.hand_tracking_source = source
	t.has_tracking_data = true
