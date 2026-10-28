class_name Snakes
extends Shy

## Grass snakes in the grass beside the ponds: one to a pond, slithering from one spot in the grass to another a few
## metres from the water and lying still a while between, its tongue flicking. One a person comes toward slips off
## quickly the other way through the grass. They come by day; at night they lie still.

enum State { SLITHER, BASK, FLEE, LEAVE }

const CAP := 3
const SPEED := {State.SLITHER: 0.2, State.FLEE: 0.65, State.LEAVE: 0.35}
const TURN := 1.6
## How far out from the shore its grass reaches.
const RING := Vector2(0.8, 4.5)
const BASK_FOR := Vector2(6.0, 20.0)
const FLEE_TO := Vector2(2.5, 4.5)
const FLIGHT := 2.2
const STARTLE := 3.2
const LEAVE_TO := 25.0
## Seconds, on average, between flicks of its tongue, and how long one lasts.
const FLICK_EVERY := 3.0
const FLICK_FOR := 0.35
const RUSTLE_EVERY := 9.0


class Snake extends Shy.One:
	## How far it has slid, which sets the waves along its body so they stay put on the ground as it goes.
	var travel := 0.0
	var bend := 0.0
	var flick := INF


func _init(home: Wildlife, seed: int) -> void:
	super(home, seed, body(), "res://src/snake.gdshader", CAP, "snakes")


## Head at the origin facing -Z, the body trailing back along +Z.
static func body() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length := 0.78
	var rings := 40
	var around := 7
	var olive := Color("67733c")
	var bar := Color("2f3420")
	var belly := Color("c9c39a")
	var collar := Color("e2cf6a")
	var grid := []
	for i in rings + 1:
		var u := float(i) / rings
		var z := u * length - 0.02
		var r := 0.017 * clampf(u / 0.12, 0.55, 1.0) * (1.0 - smoothstep(0.55, 1.0, u) * 0.92)
		if u < 0.07:
			r = lerpf(0.009, 0.0135, u / 0.07)
		var row := []
		for j in around:
			var a := TAU * j / around
			var n := Vector3(cos(a), sin(a) * 0.85, 0)
			var p := Vector3(n.x * r * 1.15, r + n.y * r, z)
			var c := olive
			if n.y < -0.3:
				c = belly
			elif u > 0.075 and u < 0.105:
				c = collar
			elif (u > 0.105 and u < 0.12) or (u > 0.13 and absf(n.x) > 0.6 and fmod(u * 37.0, 1.0) < 0.3):
				c = bar
			row.append([p, n.normalized(), c])
		grid.append(row)
	for i in rings:
		for j in around:
			var k := (j + 1) % around
			for v in [grid[i][j], grid[i + 1][j], grid[i + 1][k], grid[i][j], grid[i + 1][k], grid[i][k]]:
				st.set_color(v[2])
				st.set_uv2(Vector2.ZERO)
				st.set_normal(v[1])
				st.add_vertex(v[0])
	Meshes.ellipsoid(st, 0, Vector3(0, 0.011, -0.022), Vector3(0.0115, 0.0085, 0.015), olive, 4, 8)
	for side in [-1.0, 1.0]:
		Meshes.ellipsoid(st, 0, Vector3(side * 0.0095, 0.0145, -0.026), Vector3.ONE * 0.0032, Color("120f0c"), 3, 6)
		Meshes.ellipsoid(st, 1, Vector3(side * 0.002, 0.008, -0.046), Vector3(0.0012, 0.0008, 0.007), Color("5a2228"), 2, 4, Callable(), Basis(Vector3.UP, side * 0.25))
	Meshes.ellipsoid(st, 1, Vector3(0, 0.008, -0.039), Vector3(0.0014, 0.0009, 0.006), Color("5a2228"), 2, 4)
	return st.commit()


func habitats() -> Dictionary:
	var out := {}
	for p: PondWater in wildlife.water.ponds:
		if p.pond.cells.size() >= Wildlife.MIN_POND and out.size() < CAP:
			out[p] = 1
	return out


func active() -> bool:
	return not wildlife.asleep()


## One slips in at a spot in its pond's grass out of sight.
func arrive(home: Object) -> One:
	for attempt in 12:
		var at := _grass(home)
		if at != Vector3.INF and not wildlife._in_sight(at):
			var s := Snake.new()
			s.position = at
			s.yaw = rng.randf() * TAU
			s.state = State.SLITHER
			s.goal = _grass(home)
			s.goal = s.position if s.goal == Vector3.INF else s.goal
			s.clock = rng.randf() * 100.0
			return s
	return null


## A spot in the grass round `p`, on ground an animal may stand on, or Vector3.INF.
func _grass(p: PondWater, near := Vector3.INF, reach := INF) -> Vector3:
	var mid := Terrain.grid_xz(p.pond.bottom)
	var shore := p.pond.shore
	for attempt in 8:
		var s := Terrain.grid_xz(shore[rng.randi() % shore.size()])
		var out := (s - mid).normalized() if s != mid else Vector2.RIGHT
		out = out.rotated(rng.randf_range(-0.7, 0.7))
		var q := s + out * rng.randf_range(RING.x, RING.y)
		var at := wildlife.terrain.ground(q.x, q.y)
		if near != Vector3.INF and at.distance_to(near) > reach:
			continue
		if wildlife.standable(at) and (near == Vector3.INF or wildlife.clear_way(near, at)):
			return at
	return Vector3.INF


func think(a: One, delta: float) -> void:
	var s: Snake = a
	var p: PondWater = s.home if is_instance_valid(s.home) else null
	s.flick += delta
	if s.state != State.LEAVE and s.state != State.FLEE:
		var n := wary(s.position, FLIGHT, STARTLE)
		if n != null:
			_flee(s, n)
	match s.state:
		State.BASK:
			if not wildlife.asleep():
				s.timer -= delta
			if s.timer <= 0.0:
				var to := _grass(p, s.position, 3.0) if p != null else Vector3.INF
				if to != Vector3.INF:
					s.goal = to
					s.state = State.SLITHER
				else:
					s.timer = rng.randf_range(BASK_FOR.x, BASK_FOR.y)
		State.SLITHER, State.FLEE, State.LEAVE:
			if _slide(s, delta):
				if s.state == State.LEAVE:
					s.goal = s.position + Basis(Vector3.UP, s.yaw).z * -LEAVE_TO
				else:
					s.state = State.BASK
					s.timer = rng.randf_range(BASK_FOR.x, BASK_FOR.y)
	if s.state != State.BASK and s.state != State.LEAVE:
		wildlife.calls.now_and_then("rustle", s.position, RUSTLE_EVERY, delta)
	if rng.randf() < delta / FLICK_EVERY:
		s.flick = 0.0
	var tongue := sin(PI * s.flick / FLICK_FOR) if s.flick < FLICK_FOR else 0.0
	s.basis = standing(s.position, s.yaw)
	s.pose = Color(s.travel, s.shown, s.bend, tongue)


func leave(a: One) -> void:
	var s: Snake = a
	s.state = State.LEAVE
	var dir := wildlife._unseen_direction(s.position, LEAVE_TO, 0.0, Wildlife.LEAVE_SIGHT, rng)
	s.goal = wildlife._head_off(s.position, dir, rng)


func _flee(s: Snake, n: Node3D) -> void:
	var off := away(s.position, n)
	for attempt in 8:
		var to := s.position + off.rotated(Vector3.UP, rng.randf_range(-0.8, 0.8)) * rng.randf_range(FLEE_TO.x, FLEE_TO.y)
		to = wildlife.terrain.ground(to.x, to.z)
		if wildlife.standable(to) and wildlife.clear_way(s.position, to):
			s.goal = to
			s.state = State.FLEE
			wildlife.calls.call_out("rustle", s.position)
			return


## Turns toward its goal as a snake can and slides on along the way it faces, its body curving with the turn; true once
## there. A way into water or a wall turns it back to lie still.
func _slide(s: Snake, delta: float) -> bool:
	var to := Vector3(s.goal.x - s.position.x, 0, s.goal.z - s.position.z)
	var speed: float = SPEED[s.state]
	if to.length() < 0.12:
		s.bend = move_toward(s.bend, 0.0, delta * 2.0)
		return true
	var want := wrapf(heading(to) - s.yaw, -PI, PI)
	var turn := clampf(want, -TURN * delta, TURN * delta)
	s.yaw += turn
	s.bend = lerpf(s.bend, turn / maxf(delta, 1e-4) / TURN, minf(delta * 3.0, 1.0))
	var step := Basis(Vector3.UP, s.yaw).z * -speed * delta * clampf(1.0 - absf(want) / PI, 0.35, 1.0)
	var next := s.position + step
	if wildlife.water.pond_at(next.x, next.z) != null or not wildlife.clear_way(s.position, next):
		if s.state == State.LEAVE:
			leave(s)
		else:
			s.goal = s.position
		return s.state != State.LEAVE
	s.position = wildlife.terrain.ground(next.x, next.z)
	s.travel += step.length()
	return false
