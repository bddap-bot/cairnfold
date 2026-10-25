class_name Grazers
extends Node3D

## Animals that walk in from out of sight in bands, graze where their band keeps to, stand and look about, walk on
## to fresh grass, run from a fright and settle, eat food held out to them, and leave, out of sight, as a band:
## the sheep at fences (`Herds`) and the deer and fox at the meadow's rim (`Roamers`). Each keeps out of water,
## off paths and paving, clear of walls, houses, towers and trunks, and never walks through a wall or into water.
## Part of `Wildlife`, which decides when they come and where nobody is looking.

enum State { ENTER, GRAZE, STAND, WALK, LIE, WARY, FLEE, LEAVE, FEED }
## How an animal shows what it does; each kind poses these its own way.
enum Motion { IDLE, GRAZE, STEP, WALK, RUN, LIE }

const TURN := 3.0
## The pace, in metres a second, an animal keeps while it turns to face the way it goes, so it shuffles a step back
## or aside to food without stopping to wheel round; it gets up to any faster pace only once it faces the way.
const SIDLE := 0.3
## A grazing animal steps on this far every so often.
const NIBBLE_STEP := Vector2(0.2, 0.6)
## Seconds before a cornered animal looks again for a way to run.
const RETRY := 1.0

var wildlife: Wildlife
var bands: Array[Band] = []
var rng := RandomNumberGenerator.new()
## How long a spell of grazing lasts, and how long a band rests where it is once one ends.
var graze_for := Vector2(6.0, 16.0)
var stand_for := Vector2(3.0, 8.0)
## Chances, once a spell of grazing ends, of lying down and of walking on rather than looking up.
var lie_chance := 0.0
var walk_chance := 0.45
## Fresh grass lies this far from where an animal is.
var roam := Vector2(1.5, 4.5)
## How far a fright sends one.
var flee_reach := Vector2(2.5, 4.0)


class Band:
	var animals: Array[Node3D] = []


func _init(home: Wildlife, seed: int) -> void:
	wildlife = home
	rng.seed = seed


func all() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for b in bands:
		out.append_array(b.animals)
	return out


func count() -> int:
	var n := 0
	for b in bands:
		n += b.animals.size()
	return n


func tick(delta: float) -> void:
	for i in range(bands.size() - 1, -1, -1):
		var b := bands[i]
		if not _leaving(b):
			_keep(b, delta)
		for a in b.animals:
			_think(b, a, delta)
		_part(b, delta)
		if _leaving(b) and _gone(b):
			for a in b.animals:
				wildlife.release(a)
				a.queue_free()
			bands.remove_at(i)


## Sends any animal whose ground or way has been built on, dug out or reshaped since it chose it to ground it can
## reach.
func look() -> void:
	for b in bands:
		if _leaving(b):
			continue
		for a in b.animals:
			var moving: bool = a.state in [State.ENTER, State.WALK, State.FLEE] or (a.state == State.GRAZE and _off_goal(a))
			if moving and not (wildlife.standable(a.goal) and wildlife.clear_way(a.position, a.goal)) or not moving and not wildlife.standable(a.position):
				_walk_on(b, a)
			if _leaving(b):
				break


## Whether the band stays: once not, it leaves.
func _keep(_b: Band, _delta: float) -> void:
	pass


## Whether `p` is where band `b` keeps to.
func _within(_b: Band, _p: Vector3) -> bool:
	return true


## Somewhere band `b` keeps to, picked at random.
func _anywhere(_b: Band) -> Vector3:
	return Vector3.ZERO


func _speed(_a: Node3D, _state: State) -> float:
	return 0.5


func _appetite(_a: Node3D) -> Wildlife.Appetite:
	return null


## What a fright does.
func _alarm(_b: Band, _a: Node3D, _delta: float) -> void:
	pass


func _lie(_a: Node3D) -> void:
	pass


## The level way off from a fright at `from`.
func _away(a: Node3D, from: Vector3) -> Vector3:
	var off := a.position - from
	off.y = 0.0
	return off.normalized() if off.length() > 0.01 else _forward(a)


## Somewhere a fright may send an animal of band `b`.
func _refuge(_b: Band, _p: Vector3) -> bool:
	return true


## Once a fright is over: stood still a while, or watching.
func _after_flight(a: Node3D) -> void:
	a.state = State.STAND
	a.timer = rng.randf_range(4.0, 8.0)


## What a settled animal does besides, such as a call now and then.
func _settled_tick(_a: Node3D, _delta: float) -> void:
	pass


## A state only some kinds have.
func _other(_b: Band, _a: Node3D, _delta: float) -> void:
	pass


## Walks band `b`'s animals in toward `first` from out of sight, `n` of them made by `make` and spaced `gap` apart
## along a clear way, each to a spot of its own near `first`. False, with none made, if there is no such way.
func _walk_in(b: Band, first: Vector3, n: int, walk_from: float, gap: float, make: Callable) -> bool:
	var starts := PackedVector3Array()
	for attempt in 12:
		var reach := walk_from * (1 + attempt / 4)
		var away := wildlife._unseen_direction(first, reach, 0.0, Wildlife.SIGHT, rng)
		var across := away.cross(Vector3.UP)
		starts.clear()
		for i in n:
			starts.append(first + away * (reach + gap * i) + across * rng.randf_range(-0.5, 0.5))
		if _starts_ok(first, starts):
			break
		starts.clear()
	for at in starts:
		var a: Node3D = make.call()
		a.position = wildlife.terrain.ground(at.x, at.z)
		Wildlife._face(a, first - at, 1.0)
		var spot: Variant = _spot(b, a, first, 3.5)
		if spot == null:
			spot = _spot(b, a)
		if spot == null and not b.animals.is_empty():
			a.free()
			continue
		a.goal = spot if spot != null else first
		add_child(a)
		b.animals.append(a)
	if b.animals.is_empty():
		return false
	bands.append(b)
	return true


## Whether animals walking in from `starts` begin out of sight, inside the garden, and meet no wall or water on
## their way to `first`.
func _starts_ok(first: Vector3, starts: PackedVector3Array) -> bool:
	for at in starts:
		if maxf(absf(at.x), absf(at.z)) > Wildlife.EDGE or wildlife._in_sight(at):
			return false
	for at in starts:
		if not wildlife.clear_way(at, first):
			return false
	return true


func _think(b: Band, a: Node3D, delta: float) -> void:
	a.position.y = wildlife.terrain.height_at(a.position.x, a.position.z)
	if a.state == State.LEAVE:
		var way := Vector3(a.goal.x - a.position.x, 0, a.goal.z - a.position.z)
		if way.length() < 1e-3:
			a.pose(Motion.IDLE, delta)
		elif _go(a, a.goal, _speed(a, State.LEAVE), delta):
			a.goal = wildlife._head_off(a.position, way.normalized(), rng)
		return
	if a.hand != null and a.state != State.FEED:
		_fed(a)
	a.full = maxf(a.full - delta, 0.0)
	a.retry = maxf(a.retry - delta, 0.0)
	_alarm(b, a, delta)
	if a.state in [State.GRAZE, State.STAND, State.WALK] and _appetite(a).tempted(a.full, delta, rng):
		_come_for_food(a)
	if _settled(a):
		_settled_tick(a, delta)
	match a.state:
		State.ENTER, State.WALK:
			if _go(a, a.goal, _speed(a, a.state), delta):
				_graze(a)
		State.FLEE:
			if _go(a, a.goal, _speed(a, State.FLEE), delta, Motion.RUN):
				_after_flight(a)
		State.GRAZE:
			a.timer -= delta
			if _off_goal(a):
				_go(a, a.goal, _speed(a, State.GRAZE), delta, Motion.STEP)
			elif a.timer <= 0.0:
				_next(b, a)
			else:
				a.pose(Motion.GRAZE, delta)
				if rng.randf() < delta * 0.25:
					var step: Variant = _spot(b, a, a.position + _forward(a) * rng.randf_range(NIBBLE_STEP.x, NIBBLE_STEP.y), 0.25)
					if step != null:
						a.goal = step
		State.STAND:
			a.pose(Motion.IDLE, delta)
			a.timer -= delta
			if a.timer <= 0.0:
				if rng.randf() < 0.5 and _within(b, a.position):
					_graze(a)
				else:
					_walk_on(b, a)
		State.FEED:
			_eat(a, delta)
		_:
			_other(b, a, delta)


func _come_for_food(a: Node3D) -> void:
	var appetite := _appetite(a)
	var reaches := func(o: Node3D) -> bool:
		var spot := _eat_spot(a, o)
		if a is Beast and Wildlife.in_hand(o) and not a.neck.reachable(a, o, spot.y):
			return false
		return wildlife.standable(spot) and wildlife.clear_way(a.position, spot)
	var h := wildlife.offer_for(appetite, a.position, reaches)
	if h == null:
		return
	wildlife.claim(h, a)
	a.hand = h
	a.goal = _eat_spot(a, h)
	a.state = State.FEED
	a.timer = rng.randf_range(appetite.eats_for.x, appetite.eats_for.y)


## Up to the food, held out calmly or thrown, and eating it with the mouth at it. Food put away or eaten, or a
## hand that leads where it may not go, leave it standing.
func _eat(a: Node3D, delta: float) -> void:
	if not wildlife.feeds(a.hand, a):
		_fed(a)
		return
	var hand: Vector3 = NeckAim.food(a.hand) if Wildlife.in_hand(a.hand) else a.hand.global_position
	var spot := _eat_spot(a, a.hand)
	if a is Beast and Wildlife.in_hand(a.hand) and not a.neck.reachable(a, a.hand, spot.y):
		_back_off(a)
		return
	if Vector2(spot.x - a.goal.x, spot.z - a.goal.z).length() > (0.02 if a is Beast and Wildlife.in_hand(a.hand) else 0.15):
		if not wildlife.standable(spot) or not wildlife.clear_way(a.position, spot):
			_fed(a)
			return
		a.goal = spot
	if _off_goal(a) and not _go(a, a.goal, _speed(a, State.WALK), delta):
		return
	a.eat(hand.y - a.position.y, delta)
	Wildlife._face(a, hand - a.position, delta * TURN)
	if a is Beast and Wildlife.in_hand(a.hand):
		if not a.neck.touching(a.hand):
			a.missed_food += delta
			if a.missed_food > 0.75:
				_back_off(a)
			return
		a.missed_food = 0.0
	wildlife.nibble(a.hand, delta)
	a.timer -= delta
	if a.timer <= 0.0:
		_fed(a)


func _back_off(a: Beast) -> void:
	var away := a.position - NeckAim.target(a.hand)
	away.y = 0.0
	var to := a.position + away.normalized() * 0.4
	to.y = wildlife.water.floor_at(to)
	_fed(a)
	if wildlife.standable(to) and wildlife.clear_way(a.position, to):
		a.goal = to
		a.state = State.WALK


func _eat_spot(a: Node3D, h: Node3D) -> Vector3:
	if a is Beast and a.neck != null and Wildlife.in_hand(h):
		var at := NeckAim.target(h)
		var off := Vector3(a.position.x - at.x, 0, a.position.z - at.z)
		at += off.normalized() * a.neck.stand_off(a, h)
		return Vector3(at.x, wildlife.water.floor_at(at), at.z)
	return wildlife.eat_spot(_appetite(a), h, a.position)


func _fed(a: Node3D) -> void:
	wildlife.release(a)
	a.hand = null
	if a is Beast:
		a.missed_food = 0.0
	var appetite := _appetite(a)
	a.full = rng.randf_range(appetite.full_for.x, appetite.full_for.y)
	if a.state == State.FEED:
		a.state = State.STAND
		a.timer = rng.randf_range(stand_for.x, stand_for.y)


## Whether a grazing animal is still stepping to the grass it chose.
func _off_goal(a: Node3D) -> bool:
	return Vector2(a.goal.x - a.position.x, a.goal.z - a.position.z).length() > 1e-3


func _next(b: Band, a: Node3D) -> void:
	var roll := rng.randf()
	if roll < lie_chance:
		_lie(a)
	elif roll < lie_chance + walk_chance:
		_walk_on(b, a)
	else:
		a.state = State.STAND
		a.timer = rng.randf_range(stand_for.x, stand_for.y)


func _graze(a: Node3D) -> void:
	a.state = State.GRAZE
	a.timer = rng.randf_range(graze_for.x, graze_for.y)
	a.goal = a.position


## Off to fresh grass nearby, else anywhere its band keeps to that it can walk to; else, if it stands on grass it
## may, it grazes there, and if not, its band leaves. False unless it walks off.
func _walk_on(b: Band, a: Node3D) -> bool:
	var to: Variant = _spot(b, a, a.position, roam.y, roam.x)
	if to == null:
		to = _spot(b, a)
	if to != null:
		a.state = State.WALK
		a.goal = to
		return true
	if wildlife.standable(a.position) and _within(b, a.position):
		_graze(a)
	else:
		_leave(b)
	return false


## Off from a fright at `from` to ground it may run to; cornered, it stands where it is and looks again in a while.
func _flee(b: Band, a: Node3D, from: Vector3) -> void:
	if a.retry > 0.0:
		return
	var away := _away(a, from)
	for attempt in 10:
		var dir := away.rotated(Vector3.UP, rng.randf_range(-0.7, 0.7) * (1.0 + attempt * 0.25))
		var to: Vector3 = a.position + dir * rng.randf_range(flee_reach.x, flee_reach.y)
		if wildlife.standable(to) and _refuge(b, to) and wildlife.clear_way(a.position, to):
			a.state = State.FLEE
			a.goal = wildlife.terrain.ground(to.x, to.z)
			return
	a.retry = RETRY


func _leaving(b: Band) -> bool:
	return b.animals[0].state == State.LEAVE


## The band sets off away from the viewer's gaze, all one way where that way is clear for each.
func _leave(b: Band) -> void:
	var heading := wildlife._unseen_direction(b.animals[0].position, Wildlife.WALK_AWAY, 0.0, Wildlife.LEAVE_SIGHT, rng)
	for a in b.animals:
		wildlife.release(a)
		a.hand = null
		a.state = State.LEAVE
		a.goal = wildlife._head_off(a.position, heading, rng)


## A leaving band is let go once every one is out of sight and some way off, as a duck family is; one that has
## stopped, walled in or at the edge of the garden, once out of sight.
func _gone(b: Band) -> bool:
	for a in b.animals:
		var stopped := not _off_goal(a)
		if not wildlife._let_go(a.position, 0.0 if stopped or wildlife._at_edge(a.position) else Wildlife.GONE):
			return false
	return true


## True once it is there; it shows `motion` on the way, paced to the ground covered. It gets to its feet and turns
## to face the way before it goes at `speed`.
func _go(a: Node3D, goal: Vector3, speed: float, delta: float, motion := Motion.WALK) -> bool:
	var to := Vector3(goal.x - a.position.x, 0, goal.z - a.position.z)
	var d := to.length()
	var step := d
	if d > 1e-4:
		Wildlife._face(a, to, delta * TURN)
		var pace: float = lerpf(minf(speed, SIDLE), speed, maxf(_forward(a).dot(to / d), 0.0)) * a.upright()
		step = minf(d, pace * delta)
		a.position += to / d * step
	a.position.y = wildlife.terrain.height_at(a.position.x, a.position.z)
	a.walked(motion, step, delta)
	return step >= d


func _forward(a: Node3D) -> Vector3:
	var ahead := -a.basis.z
	ahead.y = 0.0
	return ahead.normalized()


## Animals of a band nudge apart where they overlap, never into anything they keep out of; of two settled ones
## crowding each other, one soon walks on.
func _part(b: Band, delta: float) -> void:
	if _leaving(b):
		return
	for i in b.animals.size():
		for j in range(i + 1, b.animals.size()):
			var p := b.animals[i]
			var q := b.animals[j]
			var off := Vector3(q.position.x - p.position.x, 0, q.position.z - p.position.z)
			var room: float = p.radius() + q.radius()
			var d := off.length()
			if d >= room:
				continue
			if d < room * 0.75 and _settled(p) and _settled(q) and rng.randf() < delta:
				if not _walk_on(b, q) and not _leaving(b):
					_walk_on(b, p)
				if _leaving(b):
					return
				continue
			var push := (off / d if d > 1e-4 else Vector3.RIGHT) * minf(room - d, delta * 0.6) * 0.5
			_nudge(b, p, -push)
			_nudge(b, q, push)


## Moves `a` by `by` unless it is walking in or lying, or that would take it onto ground it keeps off or out of
## where its band keeps to.
func _nudge(b: Band, a: Node3D, by: Vector3) -> void:
	if a.state == State.ENTER or a.state == State.LIE:
		return
	var to := a.position + by
	if not wildlife.standable(to) or (a.state != State.FLEE and not _within(b, to)):
		return
	a.position = wildlife.terrain.ground(to.x, to.z)
	if a.state == State.GRAZE:
		a.goal = a.position


func _settled(a: Node3D) -> bool:
	return a.state == State.GRAZE or a.state == State.STAND or a.state == State.LIE


## Ground band `b` keeps to: near `near` (within `reach`, at least `least` off) if given, else anywhere it keeps
## to; one `a` can walk to in a straight line. Null when none is found.
func _spot(b: Band, a: Node3D, near: Variant = null, reach := 0.0, least := 0.0) -> Variant:
	for attempt in 16:
		var p: Vector3 = _anywhere(b) if near == null else near + Vector3.FORWARD.rotated(Vector3.UP, rng.randf() * TAU) * rng.randf_range(least, reach)
		if not _within(b, p) or not wildlife.standable(p) or _crowded(b, a, p):
			continue
		if a != null and not wildlife.clear_way(a.position, p):
			continue
		return wildlife.terrain.ground(p.x, p.z)
	return null


## Whether another of the band stands, or is headed, too near `p` for `a` to stand there too.
func _crowded(b: Band, a: Node3D, p: Vector3) -> bool:
	for o in b.animals:
		if o == a:
			continue
		var room: float = (o.radius() + (a.radius() if a != null else o.radius())) * 1.2
		if Vector2(o.goal.x - p.x, o.goal.z - p.z).length() < room or Vector2(o.position.x - p.x, o.position.z - p.z).length() < room:
			return true
	return false
