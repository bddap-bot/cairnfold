extends "res://../tests/support/suite.gd"

## Headless checks of Posture and of avatars lying and sitting: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_posture.gd

const SAMPLES := ["crimsom-1.0.vrm", "crimsom-0.x.vrm", "godette-0.x.vrm"]



func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_each_recorded_pose_reads_as_itself()
	_standing_takes_upright_heads()
	_a_ledge_needs_a_drop_ahead()
	_heading_turns_recorded_eyes_onto_tracked_ones()
	_switches_wait_and_blend()
	_a_still_player_is_probed_seldom()
	_a_body_reads_at_its_own_size()
	var scenes: Array[PackedScene] = []
	var names: Array[String] = []
	for i in Avatar.BUILT_IN.size():
		scenes.append(Avatar.built_in(i))
		names.append("built-in %d" % i)
	for path in SAMPLES:
		scenes.append(Avatar.read(FileAccess.get_file_as_bytes(ProjectSettings.globalize_path("res://").path_join("../tests/avatars").path_join(path))))
		names.append(path)
	for i in scenes.size():
		_poses_keep_head_and_hands_tracked(scenes[i], names[i])
		_a_figure_only_stands(scenes[i], names[i])
	finish()



func _index(name: String) -> int:
	return Posture.poses.find_custom(func(p: Dictionary) -> bool: return p.name == name)


## A recorded pose's tracked points, turned `yaw` and stood at `at` (its floor there).
func _tracked(k: int, yaw: float, at: Vector3) -> Array[Transform3D]:
	var p: Dictionary = Posture.poses[k]
	var frame := Transform3D(Basis(Vector3.UP, yaw), at)
	var eyes: Transform3D = p.eyes
	return [frame * eyes, frame * Transform3D(eyes.basis, p.hands[0]), frame * Transform3D(eyes.basis, p.hands[1])]


## A support at `floor`, with a ledge `seat` high around `ledge` (half a metre on a side) when it is given.
func _support(floor: float, ledge := Vector3.INF, seat := 0.0) -> Callable:
	return func(p: Vector3) -> float:
		if ledge != Vector3.INF and absf(p.x - ledge.x) < 0.5 and absf(p.z - ledge.z) < 0.5:
			return floor + seat
		return floor


## Every recorded pose, held by a player at any heading and over ground at any height, reads as that pose.
func _each_recorded_pose_reads_as_itself() -> void:
	for k in range(1, Posture.poses.size()):
		var p: Dictionary = Posture.poses[k]
		for yaw in [0.0, 1.3, -2.4]:
			for floor in [0.0, 7.5]:
				var t := _tracked(k, yaw, Vector3(3, floor, -2))
				var support := _support(floor)
				if p.seat > 0.0:
					var behind := t[0].origin + Vector3(-t[0].basis.z.x, 0, -t[0].basis.z.z).normalized() * -Posture.SEAT_BACK
					support = _support(floor, behind, p.seat)
				var got := Posture.nearest(Posture.reading(t[0], t[1].origin, t[2].origin, support), Posture.STANDING)
				check(got == k, "%s at heading %.1f over ground %.1f reads as itself (%s)" % [p.name, yaw, floor, Posture.poses[got].name])


## A head held upright from STAND_LOW up stands, whatever it looks at and wherever the hands are: a crouch or a kneel
## is not told from sitting by three trackers, so it keeps the standing body.
func _standing_takes_upright_heads() -> void:
	var flat := _support(2.0)
	var level := Transform3D(Basis.IDENTITY, Vector3(0, 2.0 + Rig.EYE, 0))
	check(Posture.nearest(Posture.reading(level, level * Vector3(-0.3, -0.65, 0), level * Vector3(0.3, -0.65, 0), flat), Posture.STANDING) == Posture.STANDING, "standing reads as standing")
	var down := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-60.0)), level.origin)
	check(Posture.nearest(Posture.reading(down, down * Vector3(0, -0.2, -0.5), down * Vector3(0.2, 0.3, -0.6), flat), Posture.STANDING) == Posture.STANDING, "looking down at a build with the hands out still stands")
	for h in [Posture.STAND_LOW, 1.05, 1.25]:
		var crouch := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-30.0)), Vector3(0, 2.0 + h, 0))
		var forward := crouch.origin + Vector3(-0.15, -0.5, -0.35)
		var low := crouch.origin + Vector3(0.2, -h + 0.05, -0.3)
		check(Posture.nearest(Posture.reading(crouch, forward, low, flat), Posture.STANDING) == Posture.STANDING, "a crouch with its head %.2f up, a hand on the ground, stands" % h)
	var sitting := _index("sitting, hands forward")
	var t := _tracked(sitting, 0.4, Vector3(0, 2.0, 0))
	check(Posture.nearest(Posture.reading(t[0], t[1].origin, t[2].origin, flat), sitting) == sitting, "a sitter stays sitting")


## The same seated head and hands sit on a ledge only where the support behind them drops ahead.
func _a_ledge_needs_a_drop_ahead() -> void:
	var ledge := _index("sitting on a ledge")
	var t := _tracked(ledge, 0.0, Vector3.ZERO)
	var reading := Posture.reading(t[0], t[1].origin, t[2].origin, _support(0.0))
	check(Posture.nearest(reading, Posture.STANDING) != ledge, "a ledge sitter's head and hands over flat ground do not sit on a ledge")
	var behind := t[0].origin + Vector3(0, 0, Posture.SEAT_BACK)
	reading = Posture.reading(t[0], t[1].origin, t[2].origin, _support(0.0, behind, Posture.poses[ledge].seat))
	check(Posture.nearest(reading, Posture.STANDING) == ledge, "and over a ledge they do")


func _heading_turns_recorded_eyes_onto_tracked_ones() -> void:
	for k in range(1, Posture.poses.size()):
		for yaw in [0.0, 0.8, -2.9]:
			var eyes: Basis = Basis(Vector3.UP, yaw) * (Posture.poses[k].eyes as Transform3D).basis
			check(absf(angle_difference(Posture.heading(k, eyes), yaw)) < 0.001, "%s's heading at %.1f is found again (%.3f)" % [Posture.poses[k].name, yaw, Posture.heading(k, eyes)])


## A pose shows only once it has been nearest for DWELL, then blends in over BLEND, the weights always summing to one
## (the tracked poses are read every READ_EVERY, so the wait is that much early or late);
## a reading flickering between two poses changes nothing.
func _switches_wait_and_blend() -> void:
	var p := Posture.new()
	var back := _index("back")
	var t := _tracked(back, 0.5, Vector3(0, 1, 0))
	var flat := _support(1.0)
	var standing := Transform3D(Basis.IDENTITY, Vector3(0, 1.0 + Rig.EYE, 0))
	for i in 60:
		var lying := i % 2 == 0
		p.update(t[0] if lying else standing, t[1].origin if lying else standing.origin, t[2].origin if lying else standing.origin, flat, 1.0 / 60.0)
	check(p.target == Posture.STANDING and p.weights[Posture.STANDING] == 1.0, "a reading flickering between lying and standing keeps the body standing")
	var frames := 0
	while p.weights[back] < 1.0 and frames < 300:
		p.update(t[0], t[1].origin, t[2].origin, flat, 1.0 / 60.0)
		frames += 1
		var sum := 0.0
		for w in p.weights:
			sum += w
		check(absf(sum - 1.0) < 1e-5, "the weights sum to one (%f)" % sum)
	var expected := int(ceil((Posture.DWELL + Posture.BLEND) * 60.0))
	check(absi(frames - expected) <= ceili(Posture.READ_EVERY * 60.0) + 1, "lying down waits DWELL, then blends over BLEND (%d frames, %d expected)" % [frames, expected])
	check(absf(angle_difference(p.yaws[back], 0.5)) < 0.01, "the lying body faces where the recorded one did, turned as the head is")
	var turned := Transform3D(Basis(Vector3.UP, 0.4) * t[0].basis, t[0].origin)
	p.update(turned, t[1].origin, t[2].origin, flat, 1.0 / 60.0)
	check(absf(angle_difference(p.yaws[back], 0.5)) < 0.01, "turning the head a little leaves the lying body where it is")
	turned = Transform3D(Basis(Vector3.UP, 1.5) * t[0].basis, t[0].origin)
	p.update(turned, t[1].origin, t[2].origin, flat, 1.0 / 60.0)
	check(absf(angle_difference(p.yaws[back], 0.5 + 1.5 - Posture.YAW_SLACK)) < 0.01, "turning it far turns the body after it, to within YAW_SLACK")


## What is under a player is probed once while they hold still, every PROBE_EVERY, and again as soon as they move.
func _a_still_player_is_probed_seldom() -> void:
	var p := Posture.new()
	var calls := [0]
	var counted := func(_at: Vector3) -> float:
		calls[0] += 1
		return 0.0
	var t := _tracked(_index("sitting, hands forward"), 0.3, Vector3.ZERO)
	for i in 60:
		p.update(t[0], t[1].origin, t[2].origin, counted, 1.0 / 60.0)
	check(calls[0] == 2, "a second sitting still probes what is under once, behind and ahead (%d calls)" % calls[0])
	var moved := Transform3D(t[0].basis, t[0].origin + Vector3(0.3, 0, 0))
	for i in 7:
		p.update(moved, t[1].origin, t[2].origin, counted, 1.0 / 60.0)
	check(calls[0] == 4, "moving past PROBE_MOVE probes again within a reading (%d calls)" % calls[0])


## A body of any size, its player fitted to it, reads every pose as the recorded people's own: a short avatar standing
## stands, though its eyes are lower than a seated adult's.
func _a_body_reads_at_its_own_size() -> void:
	for eye_height in [0.85, 1.2, 2.1]:
		var size: float = eye_height / Rig.EYE
		for k in Posture.poses.size():
			if Posture.poses[k].seat > 0.0:
				continue
			var t := Posture.held(k, eye_height)
			var frame := Transform3D(Basis(Vector3.UP, 0.7), Vector3(1, 3, -2))
			var got := Posture.nearest(Posture.reading(frame * t[0], frame * t[1].origin, frame * t[2].origin, _support(3.0), size), Posture.STANDING)
			check(got == k, "%s held by a body with its eyes %.2f m up reads as itself (%s)" % [Posture.poses[k].name, eye_height, Posture.poses[got].name])


## In every pose, and every frame of the blends into and out of it (Posture driven here at 60 Hz, as an avatar with a
## support drives its own each frame), the eyes sit at the tracked head and the hands at
## the controllers, the arms keep their length, and the body's bones turn as the recording's did.
func _poses_keep_head_and_hands_tracked(scene: PackedScene, what: String) -> void:
	var a := Avatar.open(scene, Color.WHITE)
	root.add_child(a)
	var floor := 0.6
	var support := _support(floor)
	var arm_lengths := []
	for side in ["left", "right"]:
		arm_lengths.append([a._joints[side + "UpperArm"].rest.origin.distance_to(a._joints[side + "LowerArm"].rest.origin), a._joints[side + "LowerArm"].rest.origin.distance_to(a._joints[side + "Hand"].rest.origin)])
	var worst := 0.0
	var stretched := 0
	for k in range(1, Posture.poses.size()):
		var p: Dictionary = Posture.poses[k]
		if p.seat > 0.0:
			continue
		var t := _tracked(k, 0.9, Vector3(-1, floor, 2))
		for frame in 90:
			a.posture.update(t[0], t[1].origin, t[2].origin, support, 1.0 / 60.0)
			a.pose(t[0], t[1], t[2])
			var seen: Vector3 = a.bone("head") * (a._model.get_meta("eyes") as Vector3)
			worst = maxf(worst, maxf(seen.distance_to(t[0].origin), maxf(a.bone("leftHand").origin.distance_to(t[1].origin), a.bone("rightHand").origin.distance_to(t[2].origin))))
			for s in 2:
				var side: String = ["left", "right"][s]
				var sh := a.bone(side + "UpperArm").origin
				var el := a.bone(side + "LowerArm").origin
				if absf(sh.distance_to(el) - arm_lengths[s][0]) > 0.002:
					stretched += 1
		check(a.posture.target == k and a.posture.weights[k] == 1.0, "%s: %s's tracked points blend fully into it" % [what, p.name])
		var yaw := Quaternion(Vector3.UP, a.posture.yaws[k])
		var off := 0.0
		for b: String in p.turns:
			if a._joints.has(b) and not b.ends_with("UpperArm"):
				var j: Avatar.Joint = a._joints[b]
				var want := Basis(yaw * (p.turns[b] as Quaternion)) * a._facing * j.rest.basis
				var got := a.bone(b).basis
				off = maxf(off, rad_to_deg(got.get_rotation_quaternion().angle_to(want.get_rotation_quaternion())))
		check(off < 0.1, "%s: in %s each body bone turns as the recording's did (worst %.3f degrees off)" % [what, p.name, off])
		if a._joints.has("leftUpperLeg"):
			check(a.bone("hips").origin.y < floor + 0.6, "%s: in %s the hips are down by the ground (%.2f over it)" % [what, p.name, a.bone("hips").origin.y - floor])
	check(worst < 0.002, "%s: through every pose and blend the eyes and hands stay where they are tracked (worst %.4f m)" % [what, worst])
	check(stretched == 0, "%s: the upper arms keep their length (%d frames stretched)" % [what, stretched])
	a.free()


## A figure, with no support under it, stands whatever its head does: the inventory wheel's figures never lie down.
func _a_figure_only_stands(scene: PackedScene, what: String) -> void:
	var a := Avatar.open(scene, Color.WHITE)
	root.add_child(a)
	var t := _tracked(_index("back"), 0.0, Vector3.ZERO)
	for i in 120:
		a.pose(t[0], t[1], t[2])
	check(a.posture.target == Posture.STANDING and a.posture.weights[Posture.STANDING] == 1.0, "%s: a figure without support stands" % what)
	a.stand()
	var hips: Basis = a.bone("hips").basis * a._joints.hips.rest.basis.inverse()
	check(hips.y.is_equal_approx(Vector3.UP), "%s: standing, the figure's body is upright" % what)
	a.free()
