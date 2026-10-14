class_name Herds
extends Node3D

## Sheep at the fences the player has built: some time after a long enough fence stands, a small flock walks in
## from out of sight and grazes the grass along one side of it. They crop with heads down, drifting a step at a
## time, look about, walk to fresh grass and now and then lie down; a hand close by sends one trotting off a few
## metres before it settles. They keep out of water, off paths and clear of walls, houses, towers and trunks,
## never walk through a wall or into water, and leave, out of sight, once their fence is gone or no grass beside
## it can be reached. Part of `Wildlife`, which decides when they come and where nobody is looking.

enum State { ENTER, GRAZE, STAND, WALK, LIE, FLEE, LEAVE }

const CAP := 8
const FLOCK := Vector2i(2, 4)
## Standing length of fence that makes a pasture.
const MIN_FENCE := 6.0
## How far beside its fence a flock grazes.
const BAND := Vector2(1.0, 7.0)
## Grass nearer a fence's end than this along it is past the end, not beside it.
const END := 0.5
## How far beyond its first grass a flock starts walking in: further, a step at a time, if nearer is in sight
## or has no clear way.
const WALK_FROM := 12.0
const SPEED := {State.ENTER: 0.5, State.WALK: 0.45, State.FLEE: 1.5, State.LEAVE: 0.55, State.GRAZE: 0.12}
const GRAZE_FOR := Vector2(6.0, 16.0)
const STAND_FOR := Vector2(3.0, 8.0)
const LIE_FOR := Vector2(20.0, 45.0)
const CALM_FOR := Vector2(4.0, 8.0)
## Chances, once a spell of grazing ends, of lying down and of walking on rather than looking up.
const LIE_CHANCE := 0.12
const WALK_CHANCE := 0.45
## A grazing sheep steps on this far every so often.
const NIBBLE_STEP := Vector2(0.2, 0.6)
## Fresh grass lies this far from where a sheep is.
const ROAM := Vector2(1.5, 4.5)
## A hand nearer than this to a sheep's back sends it off this far.
const SCARE := 1.0
const FLEE := Vector2(2.5, 4.0)
## Clearance from a wall's centre line beyond its half thickness, and from a trunk.
const WALL_CLEAR := 0.55
const TRUNK_CLEAR := 0.9
## Ground barer than this is a path or paving.
const BARE := 0.4
## How far from the water a sheep stands.
const SHORE := 0.4
const TURN := 3.0

var wildlife: Wildlife
var flocks: Array[Flock] = []
var rng := RandomNumberGenerator.new()
## Fences long enough to graze beside, as of the last look.
var pastures: Array[Wall] = []


class Flock:
	var sheep: Array[Sheep] = []
	var fence: Wall
	## Which side of the fence it grazes: +1 or -1 along the fence's left-hand normal.
	var side := 1.0


func _init(home: Wildlife, seed: int) -> void:
	wildlife = home
	rng.seed = seed


func all() -> Array[Sheep]:
	var out: Array[Sheep] = []
	for f in flocks:
		out.append_array(f.sheep)
	return out


func count() -> int:
	var n := 0
	for f in flocks:
		n += f.sheep.size()
	return n


## Pastures no flock is staying at: where an arrival may be due.
func empty_pastures() -> Array:
	return pastures.filter(func(w: Wall) -> bool: return flocks.all(func(f: Flock) -> bool: return _leaving(f) or f.fence != w))


func tick(delta: float) -> void:
	for i in range(pastures.size() - 1, -1, -1):
		if not is_instance_valid(pastures[i]):
			pastures.remove_at(i)
	for i in range(flocks.size() - 1, -1, -1):
		var f := flocks[i]
		if not _leaving(f) and not _grazing(f):
			_leave(f)
		for s in f.sheep:
			_think(f, s, delta)
		_part(f, delta)
		if _leaving(f) and _gone(f):
			for s in f.sheep:
				s.queue_free()
			flocks.remove_at(i)


## Looks the walls over for pastures, and sends any sheep whose ground or way has been built on, dug out or
## reshaped since to grass it can reach.
func look() -> void:
	pastures.clear()
	var walls := wildlife.walls
	if walls != null:
		for w in walls.walls:
			if is_instance_valid(w) and w.finished and w.layout.fence and standing_length(w.layout) >= MIN_FENCE:
				pastures.append(w)
	for f in flocks:
		if _leaving(f) or not _grazing(f):
			continue
		for s in f.sheep:
			var moving := s.state in [State.ENTER, State.WALK, State.FLEE] or (s.state == State.GRAZE and _off_goal(s))
			if moving and not (allowed(s.goal) and _clear_way(s.position, s.goal)) or not moving and not allowed(s.position):
				_walk_on(f, s)
			if _leaving(f):
				break


static func standing_length(layout: WallLayout) -> float:
	var out := layout.length()
	for r in layout.ruins:
		out -= r.y - r.x
	return out


## A few sheep walk in toward `fence` from WALK_FROM beyond their grass, along a clear way that starts out of
## sight; if there is no such way or no grass beside it will do, none come this time.
func arrive(fence: Wall) -> void:
	var f := Flock.new()
	f.fence = fence
	f.side = 1.0 if rng.randf() < 0.5 else -1.0
	var first: Variant = _pasture_point(f, null)
	if first == null:
		f.side = -f.side
		first = _pasture_point(f, null)
	var n := mini(rng.randi_range(FLOCK.x, FLOCK.y), CAP - count())
	if first == null or n <= 0:
		return
	var starts := PackedVector3Array()
	for attempt in 12:
		var reach := WALK_FROM * (1 + attempt / 4)
		var away := wildlife._unseen_direction(first, reach, 0.0, Wildlife.SIGHT, rng)
		var across := away.cross(Vector3.UP)
		starts.clear()
		for i in n:
			starts.append(first + away * (reach + 1.1 * i) + across * rng.randf_range(-0.5, 0.5))
		if _starts_ok(first, starts):
			break
		starts.clear()
	for at in starts:
		var s := Sheep.new(rng.randf() * 10.0, rng.randf_range(Sheep.SIZE.x, Sheep.SIZE.y), Color.WHITE.lerp(Sheep.TINTS[rng.randi() % Sheep.TINTS.size()], rng.randf()))
		s.position = Terrain.ground(at.x, at.z)
		Wildlife._face(s, first - at, 1.0)
		var spot: Variant = _pasture_point(f, s, first, 3.5)
		if spot == null:
			spot = _pasture_point(f, s)
		if spot == null and not f.sheep.is_empty():
			s.free()
			continue
		s.goal = spot if spot != null else first
		add_child(s)
		f.sheep.append(s)
	if not f.sheep.is_empty():
		flocks.append(f)


## Whether sheep walking in from `starts` begin out of sight, inside the garden, and meet no wall or water on
## their way to `first`.
func _starts_ok(first: Vector3, starts: PackedVector3Array) -> bool:
	for at in starts:
		if maxf(absf(at.x), absf(at.z)) > Wildlife.EDGE or wildlife._in_sight(at):
			return false
	for at in starts:
		if not _clear_way(at, first):
			return false
	return true


func _think(f: Flock, s: Sheep, delta: float) -> void:
	s.position.y = Terrain.height_at(s.position.x, s.position.z)
	if s.state == State.LEAVE:
		var way := Vector3(s.goal.x - s.position.x, 0, s.goal.z - s.position.z)
		if way.length() < 1e-3:
			s.blend(Sheep.IDLE, delta)
		elif _go(s, s.goal, SPEED[State.LEAVE], delta):
			_head_off(s, way.normalized())
		return
	var hand: Node3D = wildlife._hand_within(s.position + Vector3.UP * 0.55 * s.size, SCARE) if s.state != State.ENTER and s.state != State.FLEE else null
	if hand != null:
		_flee(s, hand.global_position)
	match s.state:
		State.ENTER, State.WALK:
			if _go(s, s.goal, SPEED[s.state], delta):
				_graze(s)
		State.FLEE:
			if _go(s, s.goal, SPEED[State.FLEE], delta):
				s.state = State.STAND
				s.timer = rng.randf_range(CALM_FOR.x, CALM_FOR.y)
		State.GRAZE:
			s.timer -= delta
			if _off_goal(s):
				_go(s, s.goal, SPEED[State.GRAZE], delta, Sheep.GRAZE + Sheep.WALK * 0.5)
			elif s.timer <= 0.0:
				_next(f, s)
			else:
				s.blend(Sheep.GRAZE, delta)
				if rng.randf() < delta * 0.25:
					var step: Variant = _pasture_point(f, s, s.position + _forward(s) * rng.randf_range(NIBBLE_STEP.x, NIBBLE_STEP.y), 0.25)
					if step != null:
						s.goal = step
		State.STAND:
			s.blend(Sheep.IDLE, delta)
			s.timer -= delta
			if s.timer <= 0.0:
				if rng.randf() < 0.5 and _beside(f, s.position):
					_graze(s)
				else:
					_walk_on(f, s)
		State.LIE:
			s.blend(Sheep.LIE, delta)
			s.timer -= delta
			if s.timer <= 0.0:
				s.state = State.STAND
				s.timer = rng.randf_range(STAND_FOR.x, STAND_FOR.y)


## Whether a grazing sheep is still stepping to the grass it chose.
func _off_goal(s: Sheep) -> bool:
	return Vector2(s.goal.x - s.position.x, s.goal.z - s.position.z).length() > 1e-3


func _next(f: Flock, s: Sheep) -> void:
	var roll := rng.randf()
	if roll < LIE_CHANCE:
		s.state = State.LIE
		s.timer = rng.randf_range(LIE_FOR.x, LIE_FOR.y)
	elif roll < LIE_CHANCE + WALK_CHANCE:
		_walk_on(f, s)
	else:
		s.state = State.STAND
		s.timer = rng.randf_range(STAND_FOR.x, STAND_FOR.y)


func _graze(s: Sheep) -> void:
	s.state = State.GRAZE
	s.timer = rng.randf_range(GRAZE_FOR.x, GRAZE_FOR.y)
	s.goal = s.position


## Off to fresh grass nearby, else anywhere beside the fence it can walk to; else, if it stands on grass it may,
## it grazes there, and if not, its flock leaves. False unless it walks off.
func _walk_on(f: Flock, s: Sheep) -> bool:
	var to: Variant = _pasture_point(f, s, s.position, ROAM.y, ROAM.x)
	if to == null:
		to = _pasture_point(f, s)
	if to != null:
		s.state = State.WALK
		s.goal = to
		return true
	if allowed(s.position) and _beside(f, s.position):
		_graze(s)
	else:
		_leave(f)
	return false


func _flee(s: Sheep, from: Vector3) -> void:
	var off := s.position - from
	off.y = 0.0
	var away := off.normalized() if off.length() > 0.01 else _forward(s)
	for attempt in 10:
		var dir := away.rotated(Vector3.UP, rng.randf_range(-0.7, 0.7) * (1.0 + attempt * 0.25))
		var to := s.position + dir * rng.randf_range(FLEE.x, FLEE.y)
		if allowed(to) and _clear_way(s.position, to):
			s.state = State.FLEE
			s.goal = Terrain.ground(to.x, to.z)
			return


## Whether the flock's fence still stands as a pasture.
func _grazing(f: Flock) -> bool:
	return is_instance_valid(f.fence) and pastures.has(f.fence)


func _leaving(f: Flock) -> bool:
	return f.sheep[0].state == State.LEAVE


## The flock sets off away from the viewer's gaze, all one way where that way is clear for each sheep.
func _leave(f: Flock) -> void:
	var heading := wildlife._unseen_direction(f.sheep[0].position, Wildlife.WALK_AWAY, 0.0, Wildlife.LEAVE_SIGHT, rng)
	for s in f.sheep:
		s.state = State.LEAVE
		_head_off(s, heading)


## Sends a leaving sheep WALK_AWAY on along `heading`, or, if a wall or water is in that way, along another way
## out of sight; with none clear it stands where it is until it can be let go.
func _head_off(s: Sheep, heading: Vector3) -> void:
	for attempt in 6:
		var to := wildlife._onward(s.position, heading)
		if _clear_way(s.position, to):
			s.goal = to
			return
		heading = wildlife._unseen_direction(s.position, Wildlife.WALK_AWAY, 0.0, Wildlife.LEAVE_SIGHT, rng)
	s.goal = s.position


## A leaving flock is let go once every sheep is out of sight and some way off, as a duck family is; one that
## has stopped, walled in or at the edge of the garden, once out of sight.
func _gone(f: Flock) -> bool:
	for s in f.sheep:
		var stopped := Vector2(s.goal.x - s.position.x, s.goal.z - s.position.z).length() < 1e-3
		if not wildlife._let_go(s.position, 0.0 if stopped or wildlife._at_edge(s.position) else Wildlife.GONE):
			return false
	return true


## True once the sheep is there. `look` is the motion it walks with.
func _go(s: Sheep, goal: Vector3, speed: float, delta: float, look := Sheep.WALK) -> bool:
	var to := Vector3(goal.x - s.position.x, 0, goal.z - s.position.z)
	var d := to.length()
	var step := minf(d, speed * delta)
	if d > 1e-4:
		s.position += to / d * step
		Wildlife._face(s, to, delta * TURN)
	s.position.y = Terrain.height_at(s.position.x, s.position.z)
	s.walked(step)
	s.blend(look, delta)
	return d <= speed * delta


func _forward(s: Sheep) -> Vector3:
	var ahead := -s.basis.z
	ahead.y = 0.0
	return ahead.normalized()


## Sheep of a flock nudge apart where they overlap, never into anything they keep out of; of two settled ones
## crowding each other, one soon walks on.
func _part(f: Flock, delta: float) -> void:
	if _leaving(f):
		return
	for i in f.sheep.size():
		for j in range(i + 1, f.sheep.size()):
			var a := f.sheep[i]
			var b := f.sheep[j]
			var off := Vector3(b.position.x - a.position.x, 0, b.position.z - a.position.z)
			var room := Sheep.RADIUS * (a.size + b.size)
			var d := off.length()
			if d >= room:
				continue
			if d < room * 0.75 and _settled(a) and _settled(b) and rng.randf() < delta:
				if not _walk_on(f, b) and not _leaving(f):
					_walk_on(f, a)
				if _leaving(f):
					return
				continue
			var push := (off / d if d > 1e-4 else Vector3.RIGHT) * minf(room - d, delta * 0.6) * 0.5
			_nudge(f, a, -push)
			_nudge(f, b, push)


## Moves `s` by `by` unless it is walking in or lying, or that would take it onto ground it keeps off or out of
## its flock's grass.
func _nudge(f: Flock, s: Sheep, by: Vector3) -> void:
	if s.state == State.ENTER or s.state == State.LIE:
		return
	var to := s.position + by
	if not allowed(to) or (s.state != State.FLEE and not _beside(f, to)):
		return
	s.position = Terrain.ground(to.x, to.z)
	if s.state == State.GRAZE:
		s.goal = s.position


func _settled(s: Sheep) -> bool:
	return s.state == State.GRAZE or s.state == State.STAND or s.state == State.LIE


## Grass beside `f`'s fence on its side: near `near` (within `reach`, at least `least` off) if given, else
## anywhere along it; a sheep `s` must be able to walk there in a straight line. Null when none is found.
func _pasture_point(f: Flock, s: Sheep, near: Variant = null, reach := 0.0, least := 0.0) -> Variant:
	var layout := f.fence.layout
	var total := layout.length()
	if total <= 0.0:
		return null
	for attempt in 16:
		var p: Vector3
		if near == null:
			var at := layout.frame_at(rng.randf_range(END, maxf(total - END, END)))
			var normal: Vector3 = (at.tangent as Vector3).cross(Vector3.UP) * f.side
			p = at.point + normal * rng.randf_range(BAND.x, BAND.y)
		else:
			p = near + Vector3.FORWARD.rotated(Vector3.UP, rng.randf() * TAU) * rng.randf_range(least, reach)
		if not _beside(f, p) or not allowed(p) or _crowded(f, s, p):
			continue
		if s != null and not _clear_way(s.position, p):
			continue
		return Terrain.ground(p.x, p.z)
	return null


## Whether another sheep of the flock stands, or is headed, too near `p` for `s` to stand there too.
func _crowded(f: Flock, s: Sheep, p: Vector3) -> bool:
	for o in f.sheep:
		if o == s:
			continue
		var room := Sheep.RADIUS * (o.size + (s.size if s != null else 1.0)) * 1.2
		if Vector2(o.goal.x - p.x, o.goal.z - p.z).length() < room or Vector2(o.position.x - p.x, o.position.z - p.z).length() < room:
			return true
	return false


## Whether `p` lies in the flock's band on its side of the fence, alongside it rather than beyond an end.
func _beside(f: Flock, p: Vector3) -> bool:
	var layout := f.fence.layout
	var s := layout.closest_s(p)
	if s < END or s > layout.length() - END:
		return false
	var at := layout.frame_at(s)
	var off := Vector3(p.x - at.point.x, 0, p.z - at.point.z)
	var d := off.length()
	return d >= BAND.x and d <= BAND.y and off.dot((at.tangent as Vector3).cross(Vector3.UP)) * f.side > 0.0


## Where a sheep may stand: on unpaved grass in the garden, back from the water, clear of every wall, inside no
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
func _clear_way(a: Vector3, b: Vector3) -> bool:
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
