extends SceneTree

## Go-Go reach: the mapping, its calibration to a short and a long arm, and a far house taken by touch, moved and
## reeled in through the grip: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_reach.gd

var failures := 0
var main: Node


func _initialize() -> void:
	_mapping()
	_calibrates_to_each_arm()
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


## How far `r` throws a controller held `across` from its shoulder, straight ahead at shoulder height, after `seconds`.
func _thrown(r: Reach, eyes: Transform3D, across: float, seconds := 3.0) -> float:
	var at := Vector3.ZERO
	for f in int(seconds * 60.0):
		var shoulder := r.shoulder(eyes)
		at = shoulder + Vector3.FORWARD * across
		var hand := r.project(Transform3D(Basis(), at), eyes, 1.0 / 60.0)
		if f == int(seconds * 60.0) - 1:
			return hand.origin.distance_to(at)
	return 0.0


func _mapping() -> void:
	_check(Reach.stretch(0.3, 0.6) == 0.0 and Reach.stretch(0.39, 0.6) == 0.0, "the hand follows the controller out to two thirds of the arm")
	_check(is_equal_approx(Reach.stretch(0.5, 0.6), 0.5) and Reach.stretch(0.6, 0.6) == 1.0 and Reach.stretch(0.9, 0.6) == 1.0, "past it the stretch runs to the arm's end")
	var r := Reach.new(true)
	var eyes := Transform3D(Basis(), Vector3(0, 1.65, 0))
	var hanging := r.project(Transform3D(Basis(), r.shoulder(eyes) + Vector3(0.05, -0.6, -0.1)), eyes, 1.0)
	_check(r.out < 0.01, "a hand hanging at the side is never thrown, thrown %.2f m" % r.out)
	_check(hanging.origin.is_finite(), "and stays where the controller is")


## A child and an adult, each by their own eyes' height and stretch, throw the hand equally far at the same fraction
## of their own arm, and a stretch past the first guess at the arm is learned.
func _calibrates_to_each_arm() -> void:
	var thrown := {}
	for who in [["child", 1.1, 0.46], ["adult", 1.65, 0.68]]:
		var r := Reach.new(true)
		var eyes := Transform3D(Basis(), Vector3(0, who[1], 0))
		var arm: float = who[2]
		_check(_thrown(r, eyes, arm * 0.5) < 0.01, "a %s's hand at half their arm follows the controller" % who[0])
		var full := _thrown(r, eyes, arm)
		_check(is_equal_approx(r.arm, arm), "a %s's arm is learned from their stretch: %.3f of %.3f m" % [who[0], r.arm, arm])
		_check(absf(full - Reach.FAR) < 0.5, "a %s at full stretch throws the hand %.1f m of %.0f" % [who[0], full, Reach.FAR])
		thrown[who[0]] = _thrown(r, eyes, arm * 5.0 / 6.0)
		_check(_thrown(r, eyes, arm * 0.6) < 0.05, "a %s drawing back reels the hand in" % who[0])
	_check(absf(thrown.child - thrown.adult) < 0.05 and absf(thrown.adult - Reach.FAR * 0.25) < 1.0, "at 5/6 of their arms a child throws %.2f m and an adult %.2f" % [thrown.child, thrown.adult])
	var r := Reach.new(false)
	_thrown(r, Transform3D(Basis(), Vector3(0, 1.65, 0)), 0.7)
	for s in 60 * 30:
		r.project(Transform3D(Basis(), Vector3(0, 1.2, 0)), Transform3D(Basis(), Vector3(0, 1.1, 0)), 1.0 / 60.0)
	_check(r.arm < 0.7 - 0.05, "the learned arm shrinks for the next player, %.3f after half a minute" % r.arm)


func _run() -> void:
	main.world.bounded = false
	var rig: Rig = main.rig
	var hand: Hand = rig.right
	var d := Driver.new(main, [{"op": "place", "x": 0, "z": 6}, {"op": "house", "relative": true, "at": [0, 12], "size": [4.5, 4.5], "seconds": 0.5}])
	main.add_child(d)
	await d.finished
	d.queue_free()
	var house: Wall = main.tool.walls[-1]
	var was: Vector3 = WallTool.house_of(main.world.state.walls[house.id]).center
	hand.tool = Hand.Tool.NONE
	hand.held_still = true
	hand.held_reaches = true
	var eyes := rig.head.transform
	var shoulder := hand.reach.shoulder(eyes)
	var touched := false
	var across := 0.3
	while across < 0.8 and not touched:
		await _pose(hand, shoulder, across, 0.0)
		touched = main.tool.pick_building(hand.grip_from(), -hand.global_basis.z).get("along", INF) <= hand.grip_reach()
		across += 0.0005
	_check(touched, "stretching out, the hand reaches the house %.1f m away" % rig.head.global_position.distance_to(was))
	_check(main.tool.pick_building(hand.at_controller(), -hand.global_basis.z).get("along", INF) > 5.0, "while the controller is far from it")
	Buttons.injected["right_hand/grip_click"] = true
	await _pose(hand, shoulder, across, 0.0)
	await _pose(hand, shoulder, across, 0.0)
	_check(main.tool.held == house, "the grip takes the house the hand touches")
	for f in 40:
		await _pose(hand, shoulder, across, 0.12 * f / 40.0)
	_check(main.tool.held_at.center.x - was.x > 1.0, "swept sideways it moves %.1f m" % (main.tool.held_at.center.x - was.x))
	for f in 120:
		await _pose(hand, shoulder, lerpf(across, 0.3, f / 119.0), 0.12)
	for f in 60:
		await _pose(hand, shoulder, 0.3, 0.12)
	var near := rig.head.global_position.distance_to(main.tool.held_at.center)
	_check(near < rig.head.global_position.distance_to(was) - 4.0, "drawn back it is reeled in, %.1f m from the eyes" % near)
	Buttons.injected.erase("right_hand/grip_click")
	await _pose(hand, shoulder, 0.3, 0.12)
	await _pose(hand, shoulder, 0.3, 0.12)
	var now: Vector3 = WallTool.house_of(main.world.state.walls[house.id]).center
	_check(main.tool.held == null and rig.head.global_position.distance_to(now) < near + 0.5, "let go, the garden has it where it was reeled to")

	Buttons.injected["left_hand/primary_click"] = true
	await _pose(hand, shoulder, 0.3, 0.0)
	_check(Reach.mode == Reach.Mode.GOGO, "one stick clicked in switches nothing")
	Buttons.injected["right_hand/primary_click"] = true
	await _pose(hand, shoulder, 0.3, 0.0)
	Buttons.injected.erase("left_hand/primary_click")
	Buttons.injected.erase("right_hand/primary_click")
	_check(Reach.mode == Reach.Mode.AIM, "both sticks clicked in together switch to the pointing grab")
	await _pose(hand, shoulder, 0.6, 0.0)
	await _pose(hand, shoulder, 0.6, 0.0)
	_check(hand.position.distance_to(hand.controller.origin) < 0.001, "the pointing grab's hand stays at the controller")
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


## Holds the right controller `across` ahead of `shoulder` and `aside` to its right, pointing ahead, for a frame.
func _pose(hand: Hand, shoulder: Vector3, across: float, aside: float) -> void:
	hand.transform = Transform3D(Basis(), shoulder + Vector3(aside, 0.0, -across))
	await process_frame
	await process_frame
