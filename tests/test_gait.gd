extends "res://../tests/support/suite.gd"

## Headless checks of a three-point body's legs: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_gait.gd

const UnityAvatar = preload("res://../scripts/unity_avatar.gd")
const STEP := 1.0 / 60.0
## The floor the checks stand on, sloped so a foot's height depends on where it lands.
const SLOPE := 0.1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_balance_steps_before_distance()
	var models := {"the built-in": Avatar.built_in(0), "Crimsom": Avatar.read(FileAccess.get_file_as_bytes(_sample("crimsom-1.0.vrm"))), "Seed-san": Avatar.model(UnityAvatar.avatar_scene(_sample("seed-san")))}
	for what: String in models:
		var scene: PackedScene = models[what]
		_sway_keeps_the_feet(scene, what)
		_crouch_bends_the_knees(scene, what)
		_lean_bends_the_spine(scene, what)
		_turning_steps_around(scene, what)
		_walking_steps_along(scene, what)
		_teleport_and_float(scene, what)
		_two_players_see_one_pose(scene, what)
	finish()


static func _floor(p: Vector3) -> float:
	return SLOPE * p.x


func _open(scene: PackedScene) -> Avatar:
	var a := Avatar.open(scene, Color.WHITE)
	a.ground = _floor
	root.add_child(a)
	return a


## Eyes at `p` looking along `yaw`, pitched down `down` radians, hands held low in front.
static func _eyes(p: Vector3, yaw := 0.0, down := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -down), p)


func _pose(a: Avatar, at: Transform3D) -> void:
	a._process(STEP)
	a.pose(at, at * Avatar.AT_SIDES[0], at * Avatar.AT_SIDES[1])


## Where each foot's ankle is, in the avatar's space.
static func _ankles(a: Avatar) -> Array[Vector3]:
	return [a._get_joint(a._joints.leftFoot).origin, a._get_joint(a._joints.rightFoot).origin]


## How far each ankle is over where it stands at rest on the floor under it.
static func _float(a: Avatar) -> float:
	var worst := 0.0
	for s in 2:
		var p := _ankles(a)[s]
		worst = maxf(worst, absf(p.y - _floor(p) - a._legs[s].ankle))
	return worst


## The COM rule steps once balance leaves the soles, where the distance rule alone stands still.
func _balance_steps_before_distance() -> void:
	var places: Array[Vector3] = [Vector3(-0.1, 0, 0), Vector3(0.1, 0, 0)]
	for balance in [true, false]:
		var g := Gait.new(0.8, 0.9)
		g.balance = balance
		var flat := func(_p: Vector3) -> float: return 0.0
		g.update(Vector3(0, 0.9, 0), Vector3(0, 1.0, 0), 0.0, places, flat, STEP)
		check(g.supported(Vector3(0, 1, 0)), "standing, the centre of mass is over the soles")
		var at := g.feet[0].at
		for i in 60:
			var x := 0.2 * (i + 1) / 60.0
			g.update(Vector3(x, 0.9, 0), Vector3(x, 1.0, 0), 0.0, places, flat, STEP)
		var stepped := g.feet.any(func(f: Gait.Foot) -> bool: return f.t >= 0.0) or not g.feet[0].at.is_equal_approx(at)
		check(stepped == balance, "a 20 cm sway sideways %s with balance %s (supported %s)" % ["steps" if stepped else "stands", balance, g.supported(Vector3(0.2, 1, 0))])


## Swaying a hand's width either way over 3 s, the feet neither slide nor leave the floor.
func _sway_keeps_the_feet(scene: PackedScene, what: String) -> void:
	var a := _open(scene)
	var h := a.eye_height
	_pose(a, _eyes(Vector3(0, h, 0)))
	var start := _ankles(a)
	var slid := 0.0
	var floated := 0.0
	for i in 180:
		var t := i * STEP
		_pose(a, _eyes(Vector3(0.06 * sin(t * TAU / 1.5), h + _floor(Vector3.ZERO) - 0.02 * absf(sin(t * TAU / 1.5)), 0.04 * sin(t * TAU / 3.0))))
		for s in 2:
			slid = maxf(slid, _ankles(a)[s].distance_to(start[s]))
		floated = maxf(floated, _float(a))
	check(slid < 0.002, "%s: swaying, the feet stay where they stood (moved %.4f m)" % [what, slid])
	check(floated < 0.01, "%s: swaying, the feet stay on the floor (%.4f m off)" % [what, floated])
	a.free()


## Crouching to 60% of the eye height, the feet stay put on the floor and the knees bend forward.
func _crouch_bends_the_knees(scene: PackedScene, what: String) -> void:
	var a := _open(scene)
	var h := a.eye_height
	_pose(a, _eyes(Vector3(0, h, 0)))
	var start := _ankles(a)
	for i in 60:
		_pose(a, _eyes(Vector3(0, h * (1.0 - 0.4 * (i + 1) / 60.0), 0)))
	var slid := maxf(_ankles(a)[0].distance_to(start[0]), _ankles(a)[1].distance_to(start[1]))
	check(slid < 0.002, "%s: crouching, the feet stay put (moved %.4f m)" % [what, slid])
	check(_float(a) < 0.01, "%s: crouching, the feet stay on the floor (%.4f m off)" % [what, _float(a)])
	for side in ["left", "right"]:
		var hip := a.bone(side + "UpperLeg").origin
		var knee := a.bone(side + "LowerLeg").origin
		var ankle := a.bone(side + "Foot").origin
		check(knee.z < (hip.z + ankle.z) * 0.5 - 0.05, "%s: crouching, the %s knee bends forward (%.3f ahead)" % [what, side, (hip.z + ankle.z) * 0.5 - knee.z])
	var spine := a.bone("head").origin - a.bone("hips").origin
	check(spine.z < -0.05, "%s: crouching, the spine leans forward (%.3f)" % [what, spine.z])
	a.free()


## Looking down past LOOK bends the spine forward about the head, so the hips go back.
func _lean_bends_the_spine(scene: PackedScene, what: String) -> void:
	var a := _open(scene)
	var h := a.eye_height
	_pose(a, _eyes(Vector3(0, h, 0)))
	var upright := a.bone("hips").origin
	_pose(a, _eyes(Vector3(0, h, 0), 0.0, deg_to_rad(60.0)))
	check(a.bone("hips").origin.z > upright.z + 0.02, "%s: looking down, the hips go back behind the head (%.3f m)" % [what, a.bone("hips").origin.z - upright.z])
	a.free()


## Turning on the spot, the body turns once the head passes a neck's turn and the feet step after it; standing again
## they face within Gait.TURN of the body.
func _turning_steps_around(scene: PackedScene, what: String) -> void:
	var a := _open(scene)
	var h := a.eye_height
	for i in 120:
		_pose(a, _eyes(Vector3(0, h, 0), PI * minf(i / 60.0, 1.0)))
	var off := 0.0
	for f in a.gait.feet:
		off = maxf(off, absf(angle_difference(f.yaw, a.torso)))
	check(a.gait.feet.all(func(f: Gait.Foot) -> bool: return f.t < 0.0) and off <= Gait.TURN, "%s: after turning half round, both feet stand turned with the body (%.0f° off)" % [what, rad_to_deg(off)])
	check(_float(a) < 0.01, "%s: after turning, the feet stand on the floor (%.4f m off)" % [what, _float(a)])
	a.free()


## Walking 2 m at 1 m/s up the slope, the feet step along, a planted foot never slides, and stopping the body stands over
## its feet.
func _walking_steps_along(scene: PackedScene, what: String) -> void:
	var a := _open(scene)
	var h := a.eye_height
	var steps := 0
	var slid := 0.0
	var was: Array[Vector3] = []
	var planted: Array[bool] = [true, true]
	for i in 180:
		var x := minf(i * STEP, 2.0)
		_pose(a, _eyes(Vector3(x, h + _floor(Vector3(x, 0, 0)), 0), -PI / 2.0))
		for s in 2:
			var f := a.gait.feet[s]
			if f.t < 0.0 and planted[s] and not was.is_empty():
				slid = maxf(slid, f.at.distance_to(was[s]))
			if f.t >= 0.0 and planted[s]:
				steps += 1
			planted[s] = f.t < 0.0
		was.assign(a.gait.feet.map(func(f: Gait.Foot) -> Vector3: return f.at))
	check(steps >= 4, "%s: walking 2 m takes steps (%d)" % [what, steps])
	check(slid < 0.0001, "%s: walking, a planted foot never slides (%.5f m)" % [what, slid])
	var hips := a.bone("hips").origin
	var mid := (_ankles(a)[0] + _ankles(a)[1]) * 0.5
	check(Vector2(hips.x - mid.x, hips.z - mid.z).length() < 0.25 * a.gait.leg, "%s: stopped, the hips stand over the feet (%.3f m off)" % [what, Vector2(hips.x - mid.x, hips.z - mid.z).length()])
	check(_float(a) < 0.01, "%s: stopped on the slope, the feet stand on it (%.4f m off)" % [what, _float(a)])
	a.free()


## A teleport sets both feet down at the far end at once; floating high over the floor, the legs hang as they rest.
func _teleport_and_float(scene: PackedScene, what: String) -> void:
	var a := _open(scene)
	var h := a.eye_height
	_pose(a, _eyes(Vector3(0, h, 0)))
	_pose(a, _eyes(Vector3(20, h + _floor(Vector3(20, 0, 0)), 0)))
	check(a.gait.feet.all(func(f: Gait.Foot) -> bool: return f.down and f.t < 0.0 and f.at.x > 19.0) and _float(a) < 0.01, "%s: a teleport sets the feet down where it lands" % what)
	_pose(a, _eyes(Vector3(20, h + 5.0, 0)))
	check(not a.gait.feet.any(func(f: Gait.Foot) -> bool: return f.down), "%s: floating 5 m up, the feet hang" % what)
	var hips := a.bone("hips")
	var foot := a.bone("leftFoot")
	var rest: float = a._joints.hips.rest.origin.y - a._joints.leftFoot.rest.origin.y
	check(absf(hips.origin.y - foot.origin.y - rest) < 0.01, "%s: hanging, a leg is its rest length below the hips" % what)
	_pose(a, _eyes(Vector3(20, h + _floor(Vector3(20, 0, 0)), 0)))
	check(a.gait.feet.all(func(f: Gait.Foot) -> bool: return f.down) and _float(a) < 0.01, "%s: back down, the feet stand again" % what)
	a.free()


## Two players given the same streamed head and hands see the same legs: the pose is solved from them alone.
func _two_players_see_one_pose(scene: PackedScene, what: String) -> void:
	var here := _open(scene)
	var there := _open(scene)
	var h := here.eye_height
	var worst := 0.0
	for i in 240:
		var t := i * STEP
		var at := _eyes(Vector3(0.6 * t, h - 0.3 * sin(t * 3.0) ** 2 + _floor(Vector3(0.6 * t, 0, 0)), 0.1 * sin(t * 5.0)), 1.5 * sin(t), 0.4 * sin(t * 2.0))
		_pose(here, at)
		_pose(there, at)
		for b in ["leftFoot", "rightFoot", "leftLowerLeg", "rightLowerLeg", "hips"]:
			worst = maxf(worst, here.bone(b).origin.distance_to(there.bone(b).origin))
	check(worst < 1e-5, "%s: two players solve the same legs from the same stream (%.6f m apart)" % [what, worst])
	here.free()
	there.free()


func _sample(name: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join("../tests/avatars").path_join(name)
