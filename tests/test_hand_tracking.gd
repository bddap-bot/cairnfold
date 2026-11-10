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
	var pressed := Buttons.new(right)

	_shape(joints, palm, "index", XRHandTracker.HAND_TRACKING_SOURCE_CONTROLLER)
	await frames(2)
	check(not right.bare, "joints a controller drives leave the hand on its controller")
	await _fingers_follow_the_controller(right, joints, controller, pressed)

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


## A held controller's fingers curl as its joints show, or with none as its sensors feel, and neither makes a gesture
## or presses an input.
func _fingers_follow_the_controller(right: Hand, joints: XRHandTracker, controller: XRControllerTracker, pressed: Buttons) -> void:
	var palm := Transform3D(Basis.IDENTITY, Vector3(0.2, 1.3, -0.3))
	_curled(joints, palm, PackedFloat32Array([0, 1, 0, 1, 0]))
	await frames(10)
	check(not right.bare and right.gesture == "" and not pressed.held("tool"), "a controller's curled joints make no gesture: %s" % right.gesture)
	check(right.curls[1] > 0.9 and right.curls[3] > 0.9, "the index and ring curl as the controller's joints do: %s" % right.curls)
	check(right.curls[0] < 0.1 and right.curls[2] < 0.1 and right.curls[4] < 0.1, "the thumb, middle and little stay straight as the joints do: %s" % right.curls)
	joints.has_tracking_data = false
	controller.set_pose("aim", Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	await frames(10)
	check(Array(right.curls).all(func(c: float) -> bool: return c < 0.05), "a controller sensing nothing leaves every finger straight: %s" % right.curls)
	Buttons.injected["right_hand/trigger_touch"] = true
	Buttons.injected["right_hand/ax_touch"] = true
	await frames(10)
	check(absf(right.curls[1] - Hand.REST[1]) < 0.02 and right.curls[0] > 0.95, "a finger on the trigger rests half closed and the thumb on a button closes: %s" % right.curls)
	check(right.curls[2] < 0.05, "a finger on no sensor stays straight: %s" % right.curls)
	check(not pressed.held("tool") and right.gesture == "", "a touched trigger presses nothing")
	Buttons.injected.clear()
	await frames(10)
	check(right.curls[0] < 0.05 and right.curls[1] < 0.05 and not pressed.held("tool"), "fingers lifted off their sensors straighten and press nothing: %s" % right.curls)
	controller.invalidate_pose("aim")


## Sets `t` to a hand at `palm`, fingers ahead, each finger thumb to little bent closed by `by` (0 straight, 1 closed),
## as a controller's runtime shapes it.
func _curled(t: XRHandTracker, palm: Transform3D, by: PackedFloat32Array) -> void:
	t.set_hand_joint_transform(HandShape.PALM, palm)
	for f in 5:
		var chain: Array = HandShape.CHAINS[f]
		var at := Vector3((f - 2) * 0.02, 0, 0.04)
		var way := Vector3.FORWARD
		var turn := Basis(Vector3.RIGHT, -by[f] * HandShape.CLOSED[f] / (chain.size() - 2))
		for i in chain.size():
			t.set_hand_joint_transform(chain[i], palm * Transform3D(Basis.IDENTITY, at))
			if i >= 1:
				way = turn * way
			at += way * 0.03
	for j in HandShape.JOINTS:
		t.set_hand_joint_flags(j, XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID | XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_VALID)
	t.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_CONTROLLER
	t.has_tracking_data = true


func _shape(t: XRHandTracker, palm: Transform3D, gesture: String, source: XRHandTracker.HandTrackingSource) -> void:
	var made := HandShape.make(palm, false, gesture)
	for j in made.size():
		t.set_hand_joint_transform(j, made[j])
		t.set_hand_joint_flags(j, XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID | XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_VALID)
	t.hand_tracking_source = source
	t.has_tracking_data = true
