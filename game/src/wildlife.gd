class_name Wildlife
extends Node3D

## Animals that come on their own, drawn by what is built; nothing the player holds can place one.
## Some time after a pond appears a duck arrives: alone it flies in and splashes down, a mother with
## ducklings walks in from the meadow with them in a line. They paddle about, now and then waddle up
## the bank to rest on the grass, and leave when their pond is gone. Arrivals and departures happen
## out of the viewer's sight, so nothing pops in or out of being.

const ARRIVE_AFTER := Vector2(20.0, 60.0)
## In wet grid points.
const MIN_POND := 6
const FAMILIES := 2
const DUCKLINGS := Vector2i(2, 4)
const FAMILY_CHANCE := 0.6
const SWIM_SPEED := 0.16
const FLY_SPEED := 5.5
const FLY_DISTANCE := 24.0
const FLY_HEIGHT := 8.0
const WALK_FROM := 5.0
const WALK_AWAY := 30.0
## Bill to tail of a grown duck; a line of ducklings keeps that spacing scaled to their size.
const LENGTH := 0.38
## Water deeper than this, as a fraction of a duck's size, floats it.
const FLOAT_DEPTH := 0.1
const SINK := 0.06
const SWIM_FOR := Vector2(25.0, 50.0)
const REST_FOR := Vector2(15.0, 35.0)
const BANK := Vector2(0.5, 1.4)
const RIPPLE_EVERY := 1.6
## Cosine of the widest angle from the gaze a headset still shows.
const SIGHT := 0.5
## A leaving duck is let go once outside this narrower cone, so one frame's step never crosses the edge of
## sight, and at least GONE from the viewer, or once FAR.
const LEAVE_SIGHT := SIGHT - 0.1
const GONE := 8.0
const FAR := 60.0
const EDGE := Terrain.SIZE * 0.5 - 1.0

enum State { FLY_IN, ENTER, SWIM, ASHORE, REST, FLY_OUT, WALK_OUT }

var water: Water
var viewer: Node3D
var families: Array[Family] = []
var rng := RandomNumberGenerator.new()
var _due := {}


class Family:
	var ducks: Array[Duck] = []
	var pond: PondWater
	var state := State.ENTER
	var timer := 0.0
	var goal := Vector3.ZERO
	## A wet point of the family's pond, to find it again if the pond's surface is rebuilt.
	var home := Vector3.ZERO
	## Where a flight meets the sky; `flight` runs from 0 there to 1 on the water.
	var sky := Vector3.ZERO
	var flight := 0.0
	var ripple := 0.0
	## The level way out, once leaving.
	var heading := Vector3.ZERO

	func _init(first: Duck) -> void:
		ducks.append(first)

	func leader() -> Duck:
		return ducks[0]


func _init(ponds: Water, eyes: Node3D, seed := -1) -> void:
	water = ponds
	viewer = eyes
	if seed >= 0:
		rng.seed = seed
	else:
		rng.randomize()


func ducks() -> Array[Duck]:
	var out: Array[Duck] = []
	for f in families:
		out.append_array(f.ducks)
	return out


func _process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	_schedule(delta)
	for i in range(families.size() - 1, -1, -1):
		var f := families[i]
		_think(f, delta)
		for j in range(1, f.ducks.size()):
			_follow(f.ducks[j], f.ducks[j - 1], delta)
		if _gone(f):
			for d in f.ducks:
				d.queue_free()
			families.remove_at(i)


func _schedule(delta: float) -> void:
	for p in _due.keys():
		if not water.ponds.has(p):
			_due.erase(p)
	if families.size() >= FAMILIES:
		return
	for p in water.ponds:
		if p.pond.cells.size() < MIN_POND or _family_at(p) != null:
			continue
		if not _due.has(p):
			_due[p] = rng.randf_range(ARRIVE_AFTER.x, ARRIVE_AFTER.y)
			continue
		_due[p] -= delta
		if _due[p] <= 0.0:
			_due.erase(p)
			_arrive(p)
			return


func _family_at(p: PondWater) -> Family:
	for f in families:
		if f.pond == p:
			return f
	return null


func _arrive(p: PondWater) -> void:
	var land := _deep_point(p)
	var chicks := rng.randf() < FAMILY_CHANCE
	var f := Family.new(_spawn(false))
	f.pond = p
	f.home = land
	f.goal = land
	families.append(f)
	if chicks:
		for i in rng.randi_range(DUCKLINGS.x, DUCKLINGS.y):
			f.ducks.append(_spawn(true))
		var reach := sqrt(p.pond.cells.size() / PI) + WALK_FROM
		var away := _unseen_direction(land, reach, 0.0)
		for i in f.ducks.size():
			var at := land + away * (reach + LENGTH * 1.5 * i)
			f.ducks[i].position = Terrain.ground(at.x, at.z)
			_face(f.ducks[i], -away, 1.0)
		f.state = State.ENTER
	else:
		f.goal.y = p.surface_y() - SINK
		f.sky = land + _unseen_direction(land, FLY_DISTANCE, FLY_HEIGHT) * FLY_DISTANCE + Vector3.UP * FLY_HEIGHT
		f.leader().position = f.sky
		_face(f.leader(), land - f.sky, 1.0)
		f.state = State.FLY_IN


func _spawn(chick: bool) -> Duck:
	var d := Duck.new(chick, rng.randf() * 10.0)
	add_child(d)
	return d


func _think(f: Family, delta: float) -> void:
	var lead := f.leader()
	if f.state != State.FLY_OUT and f.state != State.WALK_OUT and not water.ponds.has(f.pond):
		f.pond = _pond_near(f.home)
		if f.pond == null:
			_leave(f)
	match f.state:
		State.FLY_IN, State.FLY_OUT:
			_fly(f, delta)
		State.ENTER, State.ASHORE:
			if _go(lead, f.goal, delta):
				if f.state == State.ENTER:
					_swim(f)
				else:
					f.state = State.REST
					f.timer = rng.randf_range(REST_FOR.x, REST_FOR.y)
		State.SWIM:
			f.timer -= delta
			f.ripple -= delta
			if f.ripple <= 0.0 and lead.afloat:
				f.ripple = RIPPLE_EVERY
				f.pond.ripple(Vector3(lead.position.x, f.pond.surface_y(), lead.position.z), 0.3)
			if _go(lead, f.goal, delta):
				if f.timer <= 0.0:
					f.state = State.ASHORE
					f.goal = _bank_point(f.pond)
				else:
					f.goal = _deep_point(f.pond)
		State.REST:
			_step(lead, Vector3.ZERO, delta)
			f.timer -= delta
			if f.timer <= 0.0:
				_swim(f)
		State.WALK_OUT:
			if _go(lead, f.goal, delta):
				f.goal = _onward(f.goal, f.heading)


func _swim(f: Family) -> void:
	f.state = State.SWIM
	f.timer = rng.randf_range(SWIM_FOR.x, SWIM_FOR.y)
	f.goal = _deep_point(f.pond)
	f.home = f.goal


## A lone duck flies off, back along its way in if it had not yet landed; a family walks away.
func _leave(f: Family) -> void:
	var at := f.leader().position
	if f.ducks.size() == 1:
		if f.state != State.FLY_IN:
			f.goal = at
			f.flight = 1.0
			f.sky = at + _unseen_direction(at, FLY_DISTANCE, FLY_HEIGHT, LEAVE_SIGHT) * FLY_DISTANCE + Vector3.UP * FLY_HEIGHT
		f.heading = Vector3(f.sky.x - f.goal.x, 0, f.sky.z - f.goal.z).normalized()
		f.state = State.FLY_OUT
	else:
		f.state = State.WALK_OUT
		f.heading = _unseen_direction(at, WALK_AWAY, 0.0, LEAVE_SIGHT)
		f.goal = _onward(at, f.heading)


## A leaving duck keeps on its way until it is out of sight and some way off.
func _gone(f: Family) -> bool:
	if f.state != State.WALK_OUT and (f.state != State.FLY_OUT or f.flight > 0.0):
		return false
	if viewer == null or not viewer.is_inside_tree():
		return true
	for d in f.ducks:
		var off := d.position.distance_to(viewer.global_position)
		var edge := maxf(absf(d.position.x), absf(d.position.z)) >= EDGE - 0.5
		if off < FAR and (_in_sight(d.position, LEAVE_SIGHT) or (off < GONE and not edge)):
			return false
	return true


## WALK_AWAY further along `heading`, kept on the terrain.
func _onward(at: Vector3, heading: Vector3) -> Vector3:
	var to := at + heading * WALK_AWAY
	return Terrain.ground(clampf(to.x, -EDGE, EDGE), clampf(to.z, -EDGE, EDGE))


## Along an arc between `sky` and the water, steep near the sky and flattening to a glide.
func _fly(f: Family, delta: float) -> void:
	var lead := f.leader()
	var arriving := f.state == State.FLY_IN
	if not arriving and f.flight <= 0.0:
		lead.position += f.heading * FLY_SPEED * delta
		return
	var flat := Vector2(f.goal.x - f.sky.x, f.goal.z - f.sky.z).length()
	f.flight = clampf(f.flight + (1.0 if arriving else -1.0) * delta * FLY_SPEED / flat, 0.0, 1.0)
	var at := f.sky.lerp(f.goal, f.flight)
	at.y = lerpf(f.goal.y, f.sky.y, pow(1.0 - f.flight, 2.0))
	_face(lead, (f.goal - f.sky) * (1.0 if arriving else -1.0), delta * 4.0)
	lead.position = at
	lead.blend(Duck.FLY if f.flight < 0.85 else Duck.FLY * 0.3, delta * 4.0)
	if arriving and f.flight >= 1.0:
		var splash := Vector3(at.x, f.pond.surface_y(), at.z)
		f.pond.ripple(splash, 1.0)
		water.splashed.emit(&"dip", splash)
		_swim(f)


## True once the duck is there.
func _go(d: Duck, goal: Vector3, delta: float) -> bool:
	var to := Vector3(goal.x - d.position.x, 0, goal.z - d.position.z)
	var speed := SWIM_SPEED if d.afloat else d.walk_speed()
	if to.length() <= speed * delta:
		_step(d, Vector3.ZERO, delta)
		return true
	_step(d, to.normalized() * speed, delta)
	return false


func _follow(d: Duck, ahead: Duck, delta: float) -> void:
	var spot := ahead.position + ahead.global_basis.z.normalized() * LENGTH * 0.5 * (ahead.size + d.size)
	var to := Vector3(spot.x - d.position.x, 0, spot.z - d.position.z)
	var top := (SWIM_SPEED if d.afloat else d.walk_speed()) * 1.3
	if to.length() < 0.03:
		_step(d, Vector3.ZERO, delta)
		_face(d, ahead.position - d.position, delta * 0.5)
	else:
		_step(d, to.normalized() * minf(top, to.length() * 3.0), delta)


## Moves a duck by `velocity`, stands it on the ground or floats it, and picks its motion from where it is.
func _step(d: Duck, velocity: Vector3, delta: float) -> void:
	d.position += velocity * delta
	var ground := Terrain.height_at(d.position.x, d.position.z)
	var p := water.pond_at(d.position.x, d.position.z)
	var surface := p.surface_y() if p != null else -INF
	d.position.y = maxf(ground, surface - SINK * d.size)
	d.afloat = surface - ground > FLOAT_DEPTH * d.size
	var moving := velocity.length() > 0.01
	if moving:
		_face(d, velocity, delta * 4.0)
	d.blend(Duck.PADDLE if d.afloat else Duck.WADDLE if moving else Duck.IDLE, delta)


func _face(d: Duck, dir: Vector3, weight: float) -> void:
	if Vector2(dir.x, dir.z).length() < 1e-4:
		return
	d.rotation.y = lerp_angle(d.rotation.y, atan2(-dir.x, -dir.z), clampf(weight, 0.0, 1.0))


## Deep enough to float a grown duck, else the pond's bottom.
func _deep_point(p: PondWater) -> Vector3:
	var cells := p.pond.cells
	for attempt in 12:
		var xz := Terrain.grid_xz(cells[rng.randi() % cells.size()])
		if p.pond.level - Terrain.height_at(xz.x, xz.y) > FLOAT_DEPTH * 2.0:
			return Vector3(xz.x, p.pond.level, xz.y)
	var b := Terrain.grid_xz(p.pond.bottom)
	return Vector3(b.x, p.pond.level, b.y)


## On the grass a little way up the bank from a shore point.
func _bank_point(p: PondWater) -> Vector3:
	var mid := Terrain.grid_xz(p.pond.bottom)
	for attempt in 12:
		var s := Terrain.grid_xz(p.pond.shore[rng.randi() % p.pond.shore.size()])
		var out := (s - mid).normalized() if s != mid else Vector2.RIGHT
		var at := s + out * rng.randf_range(BANK.x, BANK.y)
		if water.pond_at(at.x, at.y) == null:
			return Terrain.ground(at.x, at.y)
	var s := Terrain.grid_xz(p.pond.shore[0])
	return Terrain.ground(s.x, s.y)


## Whichever pond is over `at` or within a couple of metres of it.
func _pond_near(at: Vector3) -> PondWater:
	var p := water.pond_at(at.x, at.z)
	if p != null:
		return p
	for q in water.ponds:
		for c in q.pond.cells:
			if Terrain.grid_xz(c).distance_to(Vector2(at.x, at.z)) < 2.0:
				return q
	return null


func _in_sight(at: Vector3, cone := SIGHT) -> bool:
	if viewer == null or not viewer.is_inside_tree():
		return false
	return (at - viewer.global_position).normalized().dot(-viewer.global_basis.z) > cone


## A level direction from `at` along which the point `reach` away and `height` up is outside `cone`, else
## the one of those tried furthest from the gaze.
func _unseen_direction(at: Vector3, reach: float, height: float, cone := SIGHT) -> Vector3:
	var best := Vector3.FORWARD
	var best_dot := INF
	for attempt in 12:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, rng.randf() * TAU)
		var to := at + dir * reach + Vector3.UP * height
		if not _in_sight(to, cone):
			return dir
		var dot := (to - viewer.global_position).normalized().dot(-viewer.global_basis.z)
		if dot < best_dot:
			best_dot = dot
			best = dir
	return best
