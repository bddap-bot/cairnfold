class_name Squirrels
extends Shy

## Red squirrels at the planted trees, one to a tree: each comes down out of its crown, clings and climbs about the trunk,
## and runs down to forage on the ground near it, sitting up to nibble. One a person comes toward races back up its
## trunk round the far side, and comes down again once all is quiet. They come by day; at night they go up into the
## crown and keep still there.

enum State { CLIMB, CLING, RUN, FORAGE }

const CAP := 4
const CLIMB_SPEED := 0.55
const ROUND_SPEED := 1.6
const RUN_SPEED := 1.4
const DASH_SPEED := 2.4
## Ground covered in one bound at the shader's bounding pace.
const STRIDE := 0.3
const CLING_FOR := Vector2(2.0, 7.0)
const FORAGE_FOR := Vector2(3.0, 9.0)
const FORAGE := Vector2(0.7, 3.0)
## How far out from its bark it clings.
const GRIP := 0.025
const FLIGHT := 2.6
const STARTLE := 4.0
## After a fright it keeps up its trunk this long once nobody comes near.
const WARY_FOR := Vector2(6.0, 14.0)
const CHITTER_EVERY := 22.0

var _trees := {}


class Squirrel extends Shy.One:
	## On its trunk: how high it is up the trunk and where round it, and where it climbs to.
	var up := 0.0
	var round := 0.0
	var to_up := 0.0
	var to_round := 0.0
	var stride := 0.0
	var sit := 0.0
	var wary := 0.0
	var dashing := false


func _init(home: Wildlife, seed: int) -> void:
	super(home, seed, body(), "res://src/squirrel.gdshader", CAP, "squirrels")


## Standing on the ground facing -Z, its back up +Y; the tail curls up over its back.
static func body() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var coat := Color("b0552a")
	var deep := Color("8c3f1f")
	var cream := Color("eadcbc")
	var dark := Color("140f0c")
	var hunch := Basis(Vector3.RIGHT, 0.25)
	Meshes.ellipsoid(st, 0, Vector3(0, 0.055, 0.012), Vector3(0.034, 0.034, 0.06), coat, 6, 10, Callable(), hunch)
	Meshes.ellipsoid(st, 0, Vector3(0, 0.047, -0.008), Vector3(0.027, 0.028, 0.044), cream, 5, 8, Callable(), hunch)
	Meshes.ellipsoid(st, 1, Vector3(0, 0.08, -0.062), Vector3(0.027, 0.025, 0.031), coat, 6, 10)
	Meshes.ellipsoid(st, 1, Vector3(0, 0.071, -0.072), Vector3(0.02, 0.016, 0.022), cream, 4, 8)
	Meshes.ellipsoid(st, 1, Vector3(0, 0.077, -0.094), Vector3.ONE * 0.0045, Color("4a2e26"), 3, 6)
	for side in [-1.0, 1.0]:
		Meshes.ellipsoid(st, 1, Vector3(side * 0.018, 0.088, -0.081), Vector3.ONE * 0.0062, dark, 4, 6)
		Meshes.ellipsoid(st, 1, Vector3(side * 0.0205, 0.0905, -0.0855), Vector3.ONE * 0.0016, Color.WHITE, 2, 4)
		Meshes.ellipsoid(st, 1, Vector3(side * 0.015, 0.106, -0.055), Vector3(0.0065, 0.015, 0.005), coat, 3, 6, Callable(), Basis(Vector3.FORWARD, side * 0.2))
		Meshes.ellipsoid(st, 1, Vector3(side * 0.016, 0.121, -0.055), Vector3(0.003, 0.008, 0.003), deep, 2, 4)
		var hind := 3
		Meshes.ellipsoid(st, hind, Vector3(side * 0.027, 0.03, 0.04), Vector3(0.015, 0.025, 0.03), coat, 4, 8)
		Meshes.ellipsoid(st, hind, Vector3(side * 0.024, 0.006, 0.02), Vector3(0.01, 0.006, 0.03), deep, 3, 6)
		Meshes.ellipsoid(st, 4, Vector3(side * 0.017, 0.02, -0.038), Vector3(0.008, 0.021, 0.008), coat, 3, 6)
	var curl := [Vector3(0, 0.05, 0.075), Vector3(0, 0.075, 0.105), Vector3(0, 0.115, 0.12), Vector3(0, 0.155, 0.115), Vector3(0, 0.185, 0.095), Vector3(0, 0.198, 0.07)]
	for i in curl.size():
		var r := 0.024 + 0.012 * sin(PI * (i + 0.5) / curl.size())
		Meshes.ellipsoid(st, 2, curl[i], Vector3(r * 0.9, r, r), deep if i == curl.size() - 1 else coat, 4, 8, Callable(), Basis(), 0.12)
	return st.commit()


## Planted trees standing out of the water, as conures find them, listed again on `Wildlife`'s looks.
func look() -> void:
	_trees = {}
	for parts: Array in wildlife.flora.placed("tree"):
		var trunk: Flora.Plant = parts[0]
		if parts.size() > 1 and wildlife.water.pond_at(trunk.anchor.x, trunk.anchor.z) == null:
			_trees[trunk] = 1


func habitats() -> Dictionary:
	return _trees


func active() -> bool:
	return not wildlife.asleep()


static func height(trunk: Flora.Plant) -> float:
	return trunk.xform.basis.y.length()


static func radius(trunk: Flora.Plant, up: float) -> float:
	return lerpf(0.3, 0.16, clampf(up / height(trunk), 0.0, 1.0)) * trunk.xform.basis.x.length()


## One comes down out of its crown.
func arrive(home: Object) -> One:
	var trunk: Flora.Plant = home
	var s := Squirrel.new()
	s.up = height(trunk) * 0.95
	s.round = rng.randf() * TAU
	s.clock = rng.randf() * 100.0
	_climb(s, height(trunk) * rng.randf_range(0.3, 0.6), s.round + rng.randf_range(-1.5, 1.5))
	_place(s, trunk)
	return s


func _climb(s: Squirrel, to_up: float, to_round: float) -> void:
	s.state = State.CLIMB
	s.to_up = to_up
	s.to_round = to_round


func think(a: One, delta: float) -> void:
	var s: Squirrel = a
	var trunk: Flora.Plant = s.home
	var rooted := is_instance_valid(trunk) and trunk.shown()
	if not rooted and s.state in [State.CLIMB, State.CLING]:
		s.position = wildlife.terrain.ground(s.position.x, s.position.z)
		s.state = State.RUN
		s.goal = s.position
	var asleep := wildlife.asleep()
	s.wary = maxf(s.wary - delta, 0.0)
	var n := wary(s.position, FLIGHT, STARTLE) if rooted and not s.leaving else null
	if n != null:
		s.wary = rng.randf_range(WARY_FOR.x, WARY_FOR.y)
		if not s.dashing:
			wildlife.calls.call_out("chitter", s.position)
		_dash_up(s, trunk, n)
	elif s.wary > 0.0 and nearest(s.position, STARTLE) != null:
		s.wary = maxf(s.wary, 2.0)
	match s.state:
		State.CLIMB:
			var top := CLIMB_SPEED * (1.8 if s.dashing else 1.0) * delta
			s.up = move_toward(s.up, s.to_up, top)
			var turn := wrapf(s.to_round - s.round, -PI, PI)
			s.round += clampf(turn, -ROUND_SPEED * delta, ROUND_SPEED * delta)
			s.stride += top / STRIDE * 0.5
			if absf(s.up - s.to_up) < 1e-3 and absf(turn) < 0.02:
				s.dashing = false
				if s.up <= 0.02:
					_off_trunk(s, trunk)
				else:
					s.state = State.CLING
					s.timer = rng.randf_range(CLING_FOR.x, CLING_FOR.y)
			_place(s, trunk)
		State.CLING:
			if asleep:
				if s.to_up < height(trunk) * 0.9:
					_climb(s, height(trunk) * 0.95, s.round)
			else:
				s.timer -= delta
				wildlife.calls.now_and_then("chitter", s.position, CHITTER_EVERY, delta)
				if s.timer <= 0.0 and s.wary <= 0.0:
					if rng.randf() < 0.55 and not s.leaving:
						_climb(s, 0.0, s.round)
					else:
						_climb(s, height(trunk) * rng.randf_range(0.15, 0.75), s.round + rng.randf_range(-2.0, 2.0))
			_place(s, trunk)
		State.RUN:
			if _run(s, delta):
				if s.leaving:
					s.goal = wildlife._head_off(s.position, Basis(Vector3.UP, s.yaw).z * -1.0, rng)
				elif rooted and Vector2(s.position.x - trunk.anchor.x, s.position.z - trunk.anchor.z).length() < radius(trunk, 0.0) + 0.2:
					s.up = 0.0
					s.round = atan2(s.position.z - trunk.anchor.z, s.position.x - trunk.anchor.x)
					if s.dashing:
						_climb(s, s.to_up, s.to_round)
					else:
						_climb(s, height(trunk) * (rng.randf_range(0.3, 0.7) if not asleep else 0.95), s.round + rng.randf_range(-1.0, 1.0))
					_place(s, trunk)
				else:
					s.state = State.FORAGE
					s.timer = rng.randf_range(FORAGE_FOR.x, FORAGE_FOR.y)
		State.FORAGE:
			s.timer -= delta
			s.sit = move_toward(s.sit, 1.0, delta * 3.0)
			wildlife.calls.now_and_then("chitter", s.position, CHITTER_EVERY * 1.5, delta)
			if s.timer <= 0.0 or asleep:
				if rng.randf() < 0.6 and not asleep and not s.leaving:
					_forage_spot(s, trunk)
				else:
					_to_trunk(s, trunk)
			s.basis = standing(s.position, s.yaw)
	if s.state != State.FORAGE:
		s.sit = move_toward(s.sit, 0.0, delta * 4.0)
	var gait := 1.0 if s.state in [State.RUN, State.CLIMB] else 0.0
	s.pose = Color(s.stride, s.shown, gait, s.sit)


func leave(a: One) -> void:
	var s: Squirrel = a
	var trunk: Flora.Plant = s.home
	if s.state in [State.CLIMB, State.CLING] and is_instance_valid(trunk) and trunk.shown():
		_climb(s, 0.0, s.round)
	else:
		_run_off(s)


func _run_off(s: Squirrel) -> void:
	s.position = wildlife.terrain.ground(s.position.x, s.position.z)
	s.state = State.RUN
	s.goal = wildlife._head_off(s.position, wildlife._unseen_direction(s.position, Wildlife.WALK_AWAY, 0.0, Wildlife.LEAVE_SIGHT, rng), rng)


func _off_trunk(s: Squirrel, trunk: Flora.Plant) -> void:
	if s.leaving:
		_run_off(s)
	else:
		_forage_spot(s, trunk)


func _forage_spot(s: Squirrel, trunk: Flora.Plant) -> void:
	var foot := trunk.foot()
	for attempt in 8:
		var a := rng.randf() * TAU
		var q := foot + Vector3(cos(a), 0, sin(a)) * (radius(trunk, 0.0) + rng.randf_range(FORAGE.x, FORAGE.y))
		var at := wildlife.terrain.ground(q.x, q.z)
		if wildlife.water.pond_at(at.x, at.z) == null and wildlife.clear_way(s.position, at):
			s.state = State.RUN
			s.goal = at
			s.position = wildlife.terrain.ground(s.position.x, s.position.z)
			return
	_to_trunk(s, trunk)


func _to_trunk(s: Squirrel, trunk: Flora.Plant) -> void:
	var foot := trunk.foot()
	var off := Vector3(s.position.x - foot.x, 0, s.position.z - foot.z)
	off = off.normalized() if off.length() > 1e-3 else Vector3.RIGHT
	s.state = State.RUN
	s.goal = wildlife.terrain.ground(foot.x + off.x * radius(trunk, 0.0), foot.z + off.z * radius(trunk, 0.0))


## Away from `n`: up its trunk round the side from it, running to the trunk first if it is on the ground.
func _dash_up(s: Squirrel, trunk: Flora.Plant, n: Node3D) -> void:
	var off := away(trunk.foot(), n)
	var hide := atan2(off.z, off.x)
	var to_up := maxf(s.up, height(trunk) * rng.randf_range(0.6, 0.85)) if not s.dashing else s.to_up
	s.dashing = true
	if s.state in [State.RUN, State.FORAGE]:
		_to_trunk(s, trunk)
		s.to_up = to_up
		s.to_round = hide
		return
	_climb(s, to_up, hide)


## Bounds over the ground toward its goal; true once there.
func _run(s: Squirrel, delta: float) -> bool:
	var to := Vector3(s.goal.x - s.position.x, 0, s.goal.z - s.position.z)
	var speed := DASH_SPEED if s.dashing or s.leaving else RUN_SPEED
	s.basis = standing(s.position, s.yaw)
	if to.length() <= speed * delta:
		s.position = wildlife.terrain.ground(s.goal.x, s.goal.z)
		return true
	s.yaw = lerp_angle(s.yaw, heading(to), minf(delta * 10.0, 1.0))
	var next := s.position + to.normalized() * speed * delta
	s.position = wildlife.terrain.ground(next.x, next.z)
	s.stride += speed * delta / STRIDE
	return false


## On its trunk, belly to the bark, head up or down the way it climbs.
func _place(s: Squirrel, trunk: Flora.Plant) -> void:
	var foot := trunk.foot()
	var out := Vector3(cos(s.round), 0, sin(s.round))
	s.position = foot + Vector3.UP * s.up + out * (radius(trunk, s.up) + GRIP)
	var dir := Vector3.UP if s.to_up >= s.up or s.state == State.CLING else Vector3.DOWN
	if s.state == State.CLING:
		dir = (Vector3.UP + out.cross(Vector3.UP) * sin(s.clock * 0.3) * 0.4).normalized()
	var back := -dir
	var right := out.cross(back).normalized()
	s.basis = Basis(right, out, right.cross(out))
	s.yaw = heading(out)
