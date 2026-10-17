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

## Clearance from a wall's centre line beyond its half thickness, and from a trunk.
const WALL_CLEAR := 0.55
const TRUNK_CLEAR := 0.9
## Ground barer than this is a path or paving.
const BARE := 0.4
const SHORE := 0.4
const TURN := 3.0
## How readily one that sees food held out goes for it, per second.
const DRAWN := 0.4
## A grazing animal steps on this far every so often.
const NIBBLE_STEP := Vector2(0.2, 0.6)
## Seconds before a cornered animal looks again for a way to run.
const RETRY := 1.0

var wildlife: Wildlife
var bands: Array[Band] = []
var rng := RandomNumberGenerator.new()


class Band:
	var animals: Array[Node3D] = []


func _init(home: Wildlife, seed: int) -> void:
	wildlife = home
	rng.seed = seed


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
			if moving and not (allowed(a.goal) and clear_way(a.position, a.goal)) or not moving and not allowed(a.position):
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


## What a fright does: false unless it took the animal over this tick.
func _alarm(_b: Band, _a: Node3D, _delta: float) -> bool:
	return false


## How long a band rests where it is once a spell of grazing ends, and how readily it lies down.
func _stand_for() -> Vector2:
	return Vector2(3.0, 8.0)


func _graze_for() -> Vector2:
	return Vector2(6.0, 16.0)


func _lie_chance() -> float:
	return 0.0


func _lie(_a: Node3D) -> void:
	pass


func _walk_chance() -> float:
	return 0.45


## Fresh grass lies this far from where an animal is.
func _roam() -> Vector2:
	return Vector2(1.5, 4.5)


## How far a fright sends one.
func _flee_reach() -> Vector2:
	return Vector2(2.5, 4.0)


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
		a.position = Terrain.ground(at.x, at.z)
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
		if not clear_way(at, first):
			return false
	return true


func _think(b: Band, a: Node3D, delta: float) -> void:
	a.position.y = Terrain.height_at(a.position.x, a.position.z)
	if a.state == State.LEAVE:
		var way := Vector3(a.goal.x - a.position.x, 0, a.goal.z - a.position.z)
		if way.length() < 1e-3:
			a.pose(Motion.IDLE, delta)
		elif _go(a, a.goal, _speed(a, State.LEAVE), delta):
			_head_off(a, way.normalized())
		return
	if a.hand != null and a.state != State.FEED:
		_fed(a)
	a.full = maxf(a.full - delta, 0.0)
	a.retry = maxf(a.retry - delta, 0.0)
	if _alarm(b, a, delta):
		return
	if a.state in [State.GRAZE, State.STAND, State.WALK] and a.full <= 0.0 and rng.randf() < delta * DRAWN:
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
		var spot := wildlife.eat_spot(appetite, o, a.position)
		return allowed(spot) and clear_way(a.position, spot)
	var h := wildlife.offer_for(appetite, a.position, reaches)
	if h == null:
		return
	wildlife.claim(h, a)
	a.hand = h
	a.goal = wildlife.eat_spot(appetite, h, a.position)
	a.state = State.FEED
	a.timer = rng.randf_range(appetite.eats_for.x, appetite.eats_for.y)


## Up to the food, held out calmly or thrown, and eating it with the mouth at it. Food put away or eaten, or a
## hand that leads where it may not go, leave it standing.
func _eat(a: Node3D, delta: float) -> void:
	if not wildlife.feeds(a.hand, a):
		_fed(a)
		return
	var hand: Vector3 = a.hand.global_position
	var spot := wildlife.eat_spot(_appetite(a), a.hand, a.position)
	if Vector2(spot.x - a.goal.x, spot.z - a.goal.z).length() > 0.15:
		if not allowed(spot) or not clear_way(a.position, spot):
			_fed(a)
			return
		a.goal = spot
	if _off_goal(a) and not _go(a, a.goal, _speed(a, State.WALK), delta):
		return
	a.eat(hand.y - a.position.y, delta)
	Wildlife._face(a, hand - a.position, delta * TURN)
	wildlife.nibble(a.hand, delta)
	a.timer -= delta
	if a.timer <= 0.0:
		_fed(a)


func _fed(a: Node3D) -> void:
	wildlife.release(a)
	a.hand = null
	var appetite := _appetite(a)
	a.full = rng.randf_range(appetite.full_for.x, appetite.full_for.y)
	if a.state == State.FEED:
		a.state = State.STAND
		a.timer = rng.randf_range(_stand_for().x, _stand_for().y)


## Whether a grazing animal is still stepping to the grass it chose.
func _off_goal(a: Node3D) -> bool:
	return Vector2(a.goal.x - a.position.x, a.goal.z - a.position.z).length() > 1e-3


func _next(b: Band, a: Node3D) -> void:
	var roll := rng.randf()
	if roll < _lie_chance():
		_lie(a)
	elif roll < _lie_chance() + _walk_chance():
		_walk_on(b, a)
	else:
		a.state = State.STAND
		a.timer = rng.randf_range(_stand_for().x, _stand_for().y)


func _graze(a: Node3D) -> void:
	a.state = State.GRAZE
	a.timer = rng.randf_range(_graze_for().x, _graze_for().y)
	a.goal = a.position


## Off to fresh grass nearby, else anywhere its band keeps to that it can walk to; else, if it stands on grass it
## may, it grazes there, and if not, its band leaves. False unless it walks off.
func _walk_on(b: Band, a: Node3D) -> bool:
	var to: Variant = _spot(b, a, a.position, _roam().y, _roam().x)
	if to == null:
		to = _spot(b, a)
	if to != null:
		a.state = State.WALK
		a.goal = to
		return true
	if allowed(a.position) and _within(b, a.position):
		_graze(a)
	else:
		_leave(b)
	return false


## Off from a fright at `from` to ground it may run to; cornered, it stands where it is and looks again in a while.
func _flee(b: Band, a: Node3D, from: Vector3) -> void:
	if a.retry > 0.0:
		return
	var away := _away(a, from)
	var reach := _flee_reach()
	for attempt in 10:
		var dir := away.rotated(Vector3.UP, rng.randf_range(-0.7, 0.7) * (1.0 + attempt * 0.25))
		var to: Vector3 = a.position + dir * rng.randf_range(reach.x, reach.y)
		if allowed(to) and _refuge(b, to) and clear_way(a.position, to):
			a.state = State.FLEE
			a.goal = Terrain.ground(to.x, to.z)
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
		_head_off(a, heading)


## Sends a leaving animal WALK_AWAY on along `heading`, or, if a wall or water is in that way, along another way
## out of sight; with none clear it stands where it is until it can be let go.
func _head_off(a: Node3D, heading: Vector3) -> void:
	for attempt in 6:
		var to := wildlife._onward(a.position, heading)
		if clear_way(a.position, to):
			a.goal = to
			return
		heading = wildlife._unseen_direction(a.position, Wildlife.WALK_AWAY, 0.0, Wildlife.LEAVE_SIGHT, rng)
	a.goal = a.position


## A leaving band is let go once every one is out of sight and some way off, as a duck family is; one that has
## stopped, walled in or at the edge of the garden, once out of sight.
func _gone(b: Band) -> bool:
	for a in b.animals:
		var stopped := not _off_goal(a)
		if not wildlife._let_go(a.position, 0.0 if stopped or wildlife._at_edge(a.position) else Wildlife.GONE):
			return false
	return true


## True once it is there; it shows `motion` on the way, paced to the ground covered.
func _go(a: Node3D, goal: Vector3, speed: float, delta: float, motion := Motion.WALK) -> bool:
	var to := Vector3(goal.x - a.position.x, 0, goal.z - a.position.z)
	var d := to.length()
	var step := minf(d, speed * delta)
	if d > 1e-4:
		a.position += to / d * step
		Wildlife._face(a, to, delta * TURN)
	a.position.y = Terrain.height_at(a.position.x, a.position.z)
	a.walked(motion, step, delta)
	return d <= speed * delta


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
	if not allowed(to) or (a.state != State.FLEE and not _within(b, to)):
		return
	a.position = Terrain.ground(to.x, to.z)
	if a.state == State.GRAZE:
		a.goal = a.position


func _settled(a: Node3D) -> bool:
	return a.state == State.GRAZE or a.state == State.STAND or a.state == State.LIE


## Ground band `b` keeps to: near `near` (within `reach`, at least `least` off) if given, else anywhere it keeps
## to; one `a` can walk to in a straight line. Null when none is found.
func _spot(b: Band, a: Node3D, near: Variant = null, reach := 0.0, least := 0.0) -> Variant:
	for attempt in 16:
		var p: Vector3 = _anywhere(b) if near == null else near + Vector3.FORWARD.rotated(Vector3.UP, rng.randf() * TAU) * rng.randf_range(least, reach)
		if not _within(b, p) or not allowed(p) or _crowded(b, a, p):
			continue
		if a != null and not clear_way(a.position, p):
			continue
		return Terrain.ground(p.x, p.z)
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


## Where a grazer may stand: on unpaved grass in the garden, back from the water, clear of every wall, inside no
## house or tower, and away from trunks.
func allowed(p: Vector3) -> bool:
	if maxf(absf(p.x), absf(p.z)) > Wildlife.EDGE - 1.0:
		return false
	if Ground.bare(p.x, p.z) > BARE:
		return false
	for o in [Vector2.ZERO, Vector2(SHORE, 0), Vector2(-SHORE, 0), Vector2(0, SHORE), Vector2(0, -SHORE)]:
		if wildlife.water.pond_at(p.x + o.x, p.z + o.y) != null:
			return false
	if wildlife.flora != null:
		var trunks := wildlife.flora.trunks
		for i in trunks.size():
			var t := trunks.anchors[i]
			if Vector2(t.x - p.x, t.z - p.z).length() < TRUNK_CLEAR:
				return false
	var q := Vector2(p.x, p.z)
	for w in _walls():
		var layout := w.layout
		var clear := (0.1 if layout.fence else WallLayout.THICKNESS * 0.5) + WALL_CLEAR
		if not layout.bounds.grow(clear).has_point(q):
			continue
		var pts := _line(layout)
		for i in pts.size() - 1:
			if Geometry2D.get_closest_point_to_segment(q, pts[i], pts[i + 1]).distance_to(q) < clear:
				return false
		if layout.closed and Geometry2D.is_point_in_polygon(q, pts):
			return false
	return true


## Whether a straight walk from `a` to `b` crosses no wall's centre line and goes into no water.
func clear_way(a: Vector3, b: Vector3) -> bool:
	var p := Vector2(a.x, a.z)
	var q := Vector2(b.x, b.z)
	var span := Rect2(p, Vector2.ZERO).expand(q)
	for w in _walls():
		if not w.layout.bounds.grow(0.5).intersects(span.grow(0.01)):
			continue
		var pts := _line(w.layout)
		for i in pts.size() - 1:
			if Geometry2D.segment_intersects_segment(p, q, pts[i], pts[i + 1]) != null:
				return false
	return not wildlife.water.crosses(p, q)


func _walls() -> Array[Wall]:
	return wildlife.walls.walls if wildlife.walls != null else ([] as Array[Wall])


## A wall's centre line on the ground plane as laid, closed round a loop.
static func _line(layout: WallLayout) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in layout.samples:
		out.append(Vector2(p.x, p.z))
	return out
