class_name Herds
extends Grazers

## Sheep at the fences the player has built: some time after a long enough fence stands, a small flock walks in
## from out of sight and grazes the grass along one side of it. They crop with heads down, drifting a step at a
## time, look about, walk to fresh grass and now and then lie down; a sudden move close by sends one trotting off a
## few metres before it settles, and one that sees seeds held out low walks up and nibbles them from the hand. They
## leave, out of sight, once their fence is gone or no grass beside it can be reached.

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
const LIE_FOR := Vector2(20.0, 45.0)
## A sudden move nearer than this to a sheep's back sends it off.
const SCARE := 1.0
## A sheep walks up to seeds held out below its head and nibbles them, its muzzle at the hand.
static var appetite := Wildlife.Appetite.new(Wildlife.Eat.UNDER_HAND, 4.0, 0.9, 0.55, Vector2(6.0, 12.0), Vector2(10.0, 25.0), 0.4)
## Seconds, on average, between one settled sheep's bleats.
const BLEAT_EVERY := 75.0

## Fences long enough to graze beside, as of the last look.
var pastures: Array[Wall] = []


class Flock extends Band:
	var fence: Wall
	## Which side of the fence it grazes: +1 or -1 along the fence's left-hand normal.
	var side := 1.0


func _init(home: Wildlife, seed: int) -> void:
	super(home, seed)
	lie_chance = 0.12


## Pastures no flock is staying at: where an arrival may be due.
func empty_pastures() -> Array:
	return pastures.filter(func(w: Wall) -> bool: return bands.all(func(f: Flock) -> bool: return _leaving(f) or f.fence != w))


func tick(delta: float) -> void:
	for i in range(pastures.size() - 1, -1, -1):
		if not is_instance_valid(pastures[i]):
			pastures.remove_at(i)
	super(delta)


func _keep(b: Band, _delta: float) -> void:
	if not _grazing(b):
		_leave(b)


## Looks the walls over for pastures, then sends sheep whose ground or way has changed to grass they can reach.
func look() -> void:
	pastures.clear()
	var walls := wildlife.walls
	if walls != null:
		for w in walls.walls:
			if is_instance_valid(w) and w.finished and w.layout.fence and standing_length(w.layout) >= MIN_FENCE:
				pastures.append(w)
	for b in bands:
		if not _leaving(b) and not _grazing(b):
			_leave(b)
	super()


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
	var first: Variant = _spot(f, null)
	if first == null:
		f.side = -f.side
		first = _spot(f, null)
	var n := mini(rng.randi_range(FLOCK.x, FLOCK.y), CAP - count())
	if first == null or n <= 0:
		return
	_walk_in(f, first, n, WALK_FROM, 1.1, func() -> Sheep:
		return Sheep.new(rng.randf() * 10.0, rng.randf_range(Sheep.SIZE.x, Sheep.SIZE.y), Color.WHITE.lerp(Sheep.TINTS[rng.randi() % Sheep.TINTS.size()], rng.randf())))


func _speed(_a: Node3D, state: State) -> float:
	return SPEED.get(state, SPEED[State.WALK])


func _appetite(_a: Node3D) -> Wildlife.Appetite:
	return appetite


func _alarm(b: Band, a: Node3D, _delta: float) -> void:
	if a.state == State.ENTER or a.state == State.FLEE:
		return
	var fright: Node3D = wildlife._startled(a.position + Vector3.UP * 0.55 * a.size, SCARE)
	if fright != null:
		if a.hand != null:
			_fed(a)
		_flee(b, a, fright.global_position)


func _settled_tick(a: Node3D, delta: float) -> void:
	wildlife.calls.now_and_then("bleat", a.position, BLEAT_EVERY, delta)


func _other(_b: Band, a: Node3D, delta: float) -> void:
	if a.state != State.LIE:
		return
	a.pose(Motion.LIE, delta)
	a.timer -= delta
	if a.timer <= 0.0:
		a.state = State.STAND
		a.timer = rng.randf_range(stand_for.x, stand_for.y)


func _lie(a: Node3D) -> void:
	a.state = State.LIE
	a.timer = rng.randf_range(LIE_FOR.x, LIE_FOR.y)


## Whether the flock's fence still stands as a pasture.
func _grazing(f: Flock) -> bool:
	return is_instance_valid(f.fence) and pastures.has(f.fence)


func _anywhere(b: Band) -> Vector3:
	var f := b as Flock
	var layout := f.fence.layout
	var total := layout.length()
	var at := layout.frame_at(rng.randf_range(END, maxf(total - END, END)))
	var normal: Vector3 = (at.tangent as Vector3).cross(Vector3.UP) * f.side
	return at.point + normal * rng.randf_range(BAND.x, BAND.y)


## Whether `p` lies in the flock's band on its side of the fence, alongside it rather than beyond an end.
func _within(b: Band, p: Vector3) -> bool:
	var f := b as Flock
	var layout := f.fence.layout
	var s := layout.closest_s(p)
	if s < END or s > layout.length() - END:
		return false
	var at := layout.frame_at(s)
	var off := Vector3(p.x - at.point.x, 0, p.z - at.point.z)
	var d := off.length()
	return d >= BAND.x and d <= BAND.y and off.dot((at.tangent as Vector3).cross(Vector3.UP)) * f.side > 0.0
