extends "res://../tests/support/suite.gd"

## A wearer taller than typical who starts seated, then stands looking down at the ground and teleports, which refits
## them, stands level, looks down, turns to work beside them and stands on a slope, wearing a built-in and an avatar
## shorter than its wearer whose eyes stand level with its head bone and far ahead of it. While the wearer stands the
## feet stay on the floor, and throughout the arms reach the hands.

const STEP := 1.0 / 60.0
const SEATED := 1.0
const STANDING := 1.8
## From the neck, facing as the wearer does: held before the chest, a forearm's length out.
const HELD: Array[Vector3] = [Vector3(-0.2, -0.3, -0.3), Vector3(0.2, -0.3, -0.3)]
const FLOOR_M := 0.03
const RAMP := deg_to_rad(15.0)

var terrain := Terrain.new()


func _initialize() -> void:
	var rig := Rig.new(terrain)
	root.add_child(rig)
	_finish.call_deferred(rig)


func _finish(rig: Rig) -> void:
	rig.set_process(false)
	var model := Avatar.built_in(2).instantiate()
	model.set_meta("eyes", (model.get_meta("forward") as Vector3) * 0.2)
	var short := PackedScene.new()
	short.pack(model)
	model.free()
	for which: Array in [[Avatar.built_in(2), "the hood"], [short, "an avatar shorter than its wearer, its eyes far ahead of its head"]]:
		_sit_then_stand(rig, which[0], which[1])
	finish()


## Real metres in the play space: the eyes turned `yaw` and looking `down` about a person's neck, which stays put.
static func _eyes(eye_m: float, yaw: float, down: float) -> Transform3D:
	var neck := Vector3(0, eye_m, 0) + Basis(Vector3.UP, yaw) * Torso.NECK
	var turned := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -down)
	return Transform3D(turned, neck - turned * Torso.NECK)


static func _shoulders(a: Avatar) -> Vector3:
	return (a.bone("leftUpperArm").origin + a.bone("rightUpperArm").origin) * 0.5


static func _foot_tilt(a: Avatar) -> float:
	return a.bone("leftFoot").basis.y.normalized().angle_to(Vector3.UP)


func _sit_then_stand(rig: Rig, scene: PackedScene, what: String) -> void:
	rig.stature = Stature.new()
	rig.floor_under = func(p: Vector3) -> float: return terrain.shown_at(p.x, p.z)
	rig.wear(Avatar.open(scene, Color.WHITE))
	rig.place(terrain.ground(0, 0), 0.0)
	var a := rig.body
	var fit := a.eye_height / STANDING
	var flat_tilt := 0.0
	var shoulders := Vector3.ZERO
	# Name, eye height, yaw, down, seconds, seconds before the checks.
	var phases := [["seated", SEATED, 0.0, 0.3, 15.0, 1.0], ["standing, looking down", STANDING, 0.0, 0.7, 6.0, 4.0], ["standing", STANDING, 0.0, 0.0, 6.0, 1.0], ["looking down", STANDING, 0.0, 0.7, 3.0, 1.0], ["turned to work beside them", STANDING, 1.0, 0.5, 3.0, 1.0], ["on a slope", STANDING, 0.0, 0.0, 3.0, 1.0]]
	for p: Array in phases:
		if p[0] == "on a slope":
			var g := rig.global_position
			rig.floor_under = func(q: Vector3) -> float: return g.y + (g.z - q.z) * tan(RAMP)
		var worst_scale := 0.0
		var off_floor := 0.0
		var stretched := 0
		var most_tilt := 0.0
		for i in int(p[4] / STEP):
			var eyes := _eyes(p[1], p[2], p[3])
			var s := rig.world_scale
			rig.head.transform = Transform3D(eyes.basis, eyes.origin * s)
			for side in 2:
				var body := Transform3D(Basis(Vector3.UP, p[2]), eyes * Torso.NECK)
				rig.hands[side].transform = Transform3D(body.basis, body * HELD[side] * s)
			rig._process(STEP)
			if p[0] == "standing, looking down" and i == int(3.5 / STEP):
				rig.place(terrain.ground(0, 0), 0.0)
			a._process(STEP)
			rig.pose_body()
			if i * STEP < p[5]:
				continue
			worst_scale = maxf(worst_scale, absf(rig.world_scale / fit - 1.0))
			most_tilt = maxf(most_tilt, _foot_tilt(a))
			for k in 2:
				var arm: Avatar.Arm = a._arms[k]
				if arm.wrist(a.hands[k] * a.palms[k]).origin.distance_to(a._get_joint(arm.upper).origin) > arm.upper_length + arm.lower_length:
					stretched += 1
			if p[1] == STANDING and p[0] != "on a slope":
				for k in 2:
					var ankle := a.bone(["leftFoot", "rightFoot"][k]).origin
					var floor_y: float = rig.floor_under.call(ankle)
					off_floor = maxf(off_floor, absf(ankle.y - floor_y - a._legs[k].ankle) / rig.world_scale)
		check(stretched == 0, "%s, %s: the arms reach the hands held before the chest: %d hand-frames short" % [what, p[0], stretched])
		if p[1] == SEATED:
			var typical := a.eye_height / Rig.EYE
			check(rig.world_scale < typical * 1.02, "%s, seated: the wearer is not taken for a short one: a scale of %.3f, %.3f for a typical one" % [what, rig.world_scale, typical])
			continue
		check(worst_scale < 0.02, "%s, %s: the world fits a wearer who stands %.2f m, off by at most %.1f%%" % [what, p[0], STANDING, 100.0 * worst_scale])
		if p[0] != "on a slope":
			check(off_floor < FLOOR_M, "%s, %s: the feet stand on the floor, at most %.3f m off" % [what, p[0], off_floor])
		match p[0]:
			"standing":
				shoulders = _shoulders(a)
				flat_tilt = _foot_tilt(a)
			"looking down":
				var moved := _shoulders(a).distance_to(shoulders) / rig.world_scale
				check(moved < 0.015, "%s, looking down: the shoulders stay where they stood, %.3f m off" % [what, moved])
			"turned to work beside them":
				check(absf(wrapf(a.torso - 1.0, -PI, PI)) < 0.05, "%s, turned: the body faces between the hands: %.2f rad, the hands at 1.00" % [what, a.torso])
			"on a slope":
				var tilt := most_tilt - flat_tilt
				check(tilt > deg_to_rad(5.0), "%s, on a slope: the planted foot turns %.1f degrees to keep its toes on the ground" % [what, rad_to_deg(tilt)])
