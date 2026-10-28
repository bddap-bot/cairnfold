class_name Frogs
extends Shy

## Frogs at the ponds' edges: a few to a pond, sitting at the waterline, hopping along the bank now and then or into the
## water for a swim with only their eyes above it, and croaking softly at night. One a person comes toward hops for the
## water and plops in, stays under a while, and comes up to swim back to the bank.

enum State { SIT, HOP, SWIM, UNDER }

const CAP := 12
const PER_POND := 4
const CELLS_EACH := 8
const HOP := 0.32
const HOP_HEIGHT := 0.09
const HOP_TIME := 0.34
const SWIM_SPEED := 0.12
const SIT_FOR := Vector2(4.0, 14.0)
const SWIM_FOR := Vector2(6.0, 16.0)
const UNDER_FOR := Vector2(8.0, 20.0)
## A person coming toward one within FLIGHT, or moving suddenly within STARTLE, sends it into the water.
const FLIGHT := 1.3
const STARTLE := 2.2
## How far below the surface a swimming frog's origin rides, its eyes just out, and a dived one's, out of sight.
const FLOAT := 0.045
const DIVE := 0.25
## Seconds, on average, between one frog's croaks at night, and how long its throat swells for one.
const CROAK_EVERY := 14.0
const CROAK_FOR := 0.9


class Frog extends Shy.One:
	## Where a run of hops ends, the state it takes there, and whether it flees.
	var dest := Vector3.ZERO
	var then := State.SIT
	var fleeing := false
	var croaked := INF
	## Its spot on the bank, and the point in the water off it that it swims back to.
	var bank := Vector3.ZERO
	var launch := Vector3.ZERO


func _init(home: Wildlife, seed: int) -> void:
	super(home, seed, body(), "res://src/frog.gdshader", CAP, "frogs")


static func body() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var green := Color("7aa04e")
	var dark := Color("52713a")
	var pale := Color("dcd8a4")
	var sit := Basis(Vector3.RIGHT, 0.3)
	Meshes.ellipsoid(st, 0, Vector3(0, 0.03, 0.006), Vector3(0.031, 0.023, 0.043), green, 6, 10, Callable(), sit)
	Meshes.ellipsoid(st, 0, Vector3(0, 0.022, -0.002), Vector3(0.027, 0.017, 0.036), pale, 5, 8, Callable(), sit)
	for spot: Vector3 in [Vector3(0.012, 0.049, 0.012), Vector3(-0.014, 0.046, 0.022), Vector3(0.0, 0.052, -0.004)]:
		Meshes.ellipsoid(st, 0, spot, Vector3(0.007, 0.003, 0.009), dark, 3, 6)
	Meshes.ellipsoid(st, 1, Vector3(0, 0.044, -0.034), Vector3(0.027, 0.017, 0.024), green, 5, 10)
	Meshes.ellipsoid(st, 2, Vector3(0, 0.032, -0.046), Vector3(0.017, 0.009, 0.012), pale, 4, 8)
	for side in [-1.0, 1.0]:
		Meshes.ellipsoid(st, 1, Vector3(side * 0.016, 0.058, -0.041), Vector3.ONE * 0.0095, Color("b9a548"), 5, 8)
		Meshes.ellipsoid(st, 1, Vector3(side * 0.02, 0.061, -0.047), Vector3.ONE * 0.0055, Color("15140f"), 4, 6)
		Meshes.ellipsoid(st, 1, Vector3(side * 0.021, 0.064, -0.051), Vector3.ONE * 0.0016, Color.WHITE, 2, 4)
		var hind := 3 if side < 0 else 4
		Meshes.ellipsoid(st, hind, Vector3(side * 0.031, 0.018, 0.022), Vector3(0.012, 0.012, 0.027), green, 4, 8)
		Meshes.ellipsoid(st, hind, Vector3(side * 0.036, 0.005, 0.0), Vector3(0.011, 0.004, 0.024), dark, 3, 6)
		Meshes.ellipsoid(st, 5, Vector3(side * 0.019, 0.011, -0.031), Vector3(0.006, 0.012, 0.006), green, 3, 6)
	return st.commit()


func habitats() -> Dictionary:
	var ponds := wildlife.water.ponds
	var out := {}
	for p: PondWater in ponds:
		if p.pond.cells.size() >= Wildlife.MIN_POND and p.surface_y() >= p.pond.level - 0.001:
			out[p] = Wildlife._pond_quota(p, ponds.size(), CAP, CELLS_EACH, PER_POND)
	return out


## One comes to a spot on the bank out of sight where there is one.
func arrive(home: Object) -> One:
	var spot := []
	for attempt in 6:
		spot = _bank(home)
		if spot.is_empty() or not wildlife._in_sight(spot[0]):
			break
	if spot.is_empty():
		return null
	var f := Frog.new()
	f.position = spot[0]
	f.bank = spot[0]
	f.launch = spot[1]
	f.yaw = heading(spot[1] - spot[0]) + rng.randf_range(-1.2, 1.2)
	f.timer = rng.randf_range(SIT_FOR.x, SIT_FOR.y)
	f.clock = rng.randf() * 100.0
	return f


## A spot at the waterline of `p` and one a little out in the water off it, near `near` where given; empty where none
## is found.
func _bank(p: PondWater, near := Vector3.INF, reach := 1.2) -> Array:
	var shore := p.pond.shore
	var surface := p.surface_y()
	var t := wildlife.terrain
	for attempt in 12:
		var s := Terrain.grid_xz(shore[rng.randi() % shore.size()])
		if near != Vector3.INF and s.distance_to(Vector2(near.x, near.z)) > reach + Terrain.STEP:
			continue
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)].slice(rng.randi() % 4) + [Vector2i(1, 0), Vector2i(-1, 0)]:
			var w := s + Vector2(d) * Terrain.STEP
			if wildlife.water.pond_at(w.x, w.y) != p:
				continue
			var edge := -1.0
			for i in 21:
				var q := s.lerp(w, i / 20.0)
				if t.height_at(q.x, q.y) < surface:
					edge = (i - 1) / 20.0
					break
			if edge < 0.0:
				continue
			var dry := s.lerp(w, maxf(edge - 0.02, 0.0))
			var wet := s.lerp(w, minf(edge + 0.3, 1.0))
			if surface - t.height_at(wet.x, wet.y) < 0.06:
				wet = w
			var bank := t.ground(dry.x, dry.y)
			if near != Vector3.INF and Vector2(bank.x - near.x, bank.z - near.z).length() > reach:
				continue
			if not wildlife._swims_clear(Vector3(wet.x, 0, wet.y), dry, p):
				continue
			return [bank, Vector3(wet.x, surface - FLOAT, wet.y)]
	return []


func _pond(f: Frog) -> PondWater:
	if not is_instance_valid(f.home) or not wildlife.water.ponds.has(f.home):
		return null
	return f.home


func think(a: One, delta: float) -> void:
	var f: Frog = a
	var p := _pond(f)
	if p == null:
		f.fading = true
		_settle(f, delta)
		return
	var surface := p.surface_y()
	f.croaked += delta
	if not f.leaving and not f.fleeing and f.state in [State.SIT, State.SWIM, State.HOP]:
		if wary(f.position, FLIGHT, STARTLE) != null:
			_flee(f, p)
	match f.state:
		State.SIT:
			f.timer -= delta
			if wildlife.asleep() and wildlife.calls.now_and_then("croak", f.position, CROAK_EVERY, delta):
				f.croaked = 0.0
			if f.timer <= 0.0 and not f.leaving:
				if rng.randf() < 0.65:
					var spot := _bank(p, f.position)
					if not spot.is_empty():
						f.bank = spot[0]
						f.launch = spot[1]
						_hop_to(f, spot[0], State.SIT)
					else:
						f.timer = rng.randf_range(SIT_FOR.x, SIT_FOR.y)
				else:
					_hop_to(f, f.launch, State.SWIM)
		State.HOP:
			f.t = minf(f.t + delta / f.span, 1.0)
			var at := f.from.lerp(f.goal, f.t)
			at.y += 4.0 * HOP_HEIGHT * f.t * (1.0 - f.t)
			f.position = at
			if f.t >= 1.0:
				f.position = f.goal
				if f.goal.distance_to(f.dest) > 0.01:
					_next_hop(f)
				else:
					_landed(f, p)
		State.SWIM:
			f.timer -= delta
			var to := Vector3(f.goal.x - f.position.x, 0, f.goal.z - f.position.z)
			if to.length() <= SWIM_SPEED * delta:
				if f.goal == f.launch and f.timer <= 0.0:
					_hop_to(f, f.bank, State.SIT)
				else:
					f.goal = f.launch if f.timer <= 0.0 else _wet(p, f.position)
			else:
				f.yaw = lerp_angle(f.yaw, heading(to), minf(delta * 3.0, 1.0))
				var next := f.position + to.normalized() * SWIM_SPEED * delta
				if wildlife.water.pond_at(next.x, next.z) == p and wildlife._swims_clear(f.position, Vector2(next.x, next.z), p):
					f.position = Vector3(next.x, surface - FLOAT, next.z)
				else:
					f.goal = f.launch
		State.UNDER:
			f.timer -= delta
			f.position.y = surface - DIVE
			if f.timer <= 0.0 and not f.leaving:
				f.fleeing = false
				f.position = _wet(p, f.position)
				f.state = State.SWIM
				f.timer = 0.0
				f.goal = f.launch
	_settle(f, delta)


## A point of `p` deep enough to swim in, near `from`, at swimming depth.
func _wet(p: PondWater, from: Vector3) -> Vector3:
	var surface := p.surface_y()
	for attempt in 10:
		var q := from + Vector3(rng.randf_range(-1.0, 1.0), 0, rng.randf_range(-1.0, 1.0))
		if wildlife.water.pond_at(q.x, q.z) == p and surface - wildlife.terrain.height_at(q.x, q.z) > 0.08 and wildlife._swims_clear(from, Vector2(q.x, q.z), p):
			return Vector3(q.x, surface - FLOAT, q.z)
	return Vector3(from.x, surface - FLOAT, from.z)


func _flee(f: Frog, p: PondWater) -> void:
	f.fleeing = true
	if f.state == State.SWIM:
		_plop(f, p)
		return
	var spot := f.launch
	if Vector2(spot.x - f.position.x, spot.z - f.position.z).length() > 1.5:
		var near := _bank(p, f.position)
		if not near.is_empty():
			f.bank = near[0]
			f.launch = near[1]
			spot = f.launch
	f.yaw = heading(spot - f.position)
	_hop_to(f, spot, State.UNDER)


## Hops from where it is to `to`, HOP at a time, taking `then` there.
func _hop_to(f: Frog, to: Vector3, then: State) -> void:
	f.dest = to
	f.then = then
	_next_hop(f)


func _next_hop(f: Frog) -> void:
	var to := f.dest - f.position
	to.y = 0.0
	var reach := HOP * (1.4 if f.fleeing else 1.0)
	var step := f.dest if to.length() <= reach else f.position + to.normalized() * reach
	if step != f.dest:
		step.y = wildlife.water.floor_at(step)
	f.from = f.position
	f.goal = step
	f.t = 0.0
	f.span = HOP_TIME * (0.8 if f.fleeing else 1.0)
	f.state = State.HOP
	if to.length() > 1e-3:
		f.yaw = heading(to)


func _landed(f: Frog, p: PondWater) -> void:
	var wet := wildlife.water.pond_at(f.position.x, f.position.z) == p
	if f.then == State.UNDER or (f.then == State.SWIM and wet):
		if f.then == State.UNDER:
			_plop(f, p)
			return
		p.ripple(Vector3(f.position.x, p.surface_y(), f.position.z), 0.25)
		Cues.play(Cues.Act.PLOP, f.position)
		f.state = State.SWIM
		f.timer = rng.randf_range(SWIM_FOR.x, SWIM_FOR.y)
		f.goal = _wet(p, f.position)
		return
	f.state = State.SIT
	f.fleeing = false
	f.timer = rng.randf_range(SIT_FOR.x, SIT_FOR.y)


func _plop(f: Frog, p: PondWater) -> void:
	var at := Vector3(f.position.x, p.surface_y(), f.position.z)
	p.ripple(at, 0.45)
	Cues.play(Cues.Act.PLOP, at)
	f.state = State.UNDER
	f.timer = rng.randf_range(UNDER_FOR.x, UNDER_FOR.y)


## Its pose: on the ground or in the water, legs out through a hop or kicking as it swims, its throat swelling as it
## croaks.
func _settle(f: Frog, _delta: float) -> void:
	var legs := 0.0
	match f.state:
		State.HOP:
			legs = sin(PI * f.t)
		State.SWIM:
			legs = 0.35 + 0.35 * sin(f.clock * 5.0)
	var throat := sin(PI * clampf(f.croaked / CROAK_FOR, 0.0, 1.0)) if f.croaked < CROAK_FOR else 0.0
	f.basis = Basis(Vector3.UP, f.yaw) if f.state != State.SIT else standing(f.position, f.yaw)
	f.pose = Color(f.clock, f.shown, legs, throat)
