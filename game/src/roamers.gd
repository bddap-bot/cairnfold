class_name Roamers
extends Grazers

## Deer and a fox at the meadow's rim. A while after the garden opens a few deer walk out of the trees, and later a
## fox; they graze, or nose the grass, along the rim. A person coming near has them stop and watch; one coming too
## close, or moving suddenly, sends them galloping off toward the trees. A person standing still lets them settle,
## and each calm spell lets one come a little nearer before it runs. After a long stay they walk back into the
## trees, and others come some minutes later.

## How long after the garden opens the first deer, and the first fox, come; once a band has gone, how long until
## the next of its kind; and how long a band stays.
const FIRST := {Beast.Kind.DEER: Vector2(30.0, 70.0), Beast.Kind.FOX: Vector2(60.0, 120.0)}
const AGAIN := Vector2(90.0, 240.0)
const STAY := Vector2(240.0, 480.0)
const HERD := {Beast.Kind.DEER: Vector2i(2, 3), Beast.Kind.FOX: Vector2i(1, 1)}
## How far from the middle of the garden they keep: the meadow's rim, inside the trees' ring.
const RING := Vector2(9.0, 40.0)
const WALK_FROM := 22.0
const SPEED := {
	Beast.Kind.DEER: {State.ENTER: 0.9, State.WALK: 0.8, State.GRAZE: 0.5, State.FLEE: 6.0, State.LEAVE: 0.9},
	Beast.Kind.FOX: {State.ENTER: 0.9, State.WALK: 0.85, State.GRAZE: 0.45, State.FLEE: 4.5, State.LEAVE: 0.9},
}
const GRAZE_FOR := Vector2(8.0, 20.0)
const STAND_FOR := Vector2(3.0, 9.0)
const ROAM := Vector2(3.0, 9.0)
const FLEE := Vector2(12.0, 20.0)
## Within WATCH of a person who comes nearer than FLIGHT * NOTICE, or moves suddenly, it stops to watch; within
## FLIGHT of one coming toward it, or STARTLE of a sudden move, it runs.
const WATCH := {Beast.Kind.DEER: 12.0, Beast.Kind.FOX: 9.0}
const FLIGHT := {Beast.Kind.DEER: 5.0, Beast.Kind.FOX: 3.5}
const NOTICE := 1.8
const STARTLE := {Beast.Kind.DEER: 10.0, Beast.Kind.FOX: 7.0}
## Eating from a hand, a sudden move startles it only this much nearer.
const EATING_STARTLE := 0.4
## A watched person keeping still for CALM_FOR lets it settle, and each such spell lets one come CLOSER nearer
## before it runs, down to NEAREST of FLIGHT.
const CALM_FOR := 6.0
## A settled deer mews, and a fox yips, about once in this many seconds.
const CALLS := {Beast.Kind.DEER: ["mew", 90.0], Beast.Kind.FOX: ["yip", 150.0]}
const CLOSER := 0.12
const NEAREST := 0.35
static var appetite := {
	Beast.Kind.DEER: _appetite_of(Beast.Kind.DEER, 12.0, 3.4375, 2.34375, Vector2(6.0, 12.0)),
	Beast.Kind.FOX: _appetite_of(Beast.Kind.FOX, 10.0, 4.6, 2.5, Vector2(4.0, 8.0)),
}

## Per kind with no band here: seconds until one comes.
var due := {}


class Visit extends Band:
	var stay := 0.0


## Eating from under a hand, its reach and mouth in the model's units (`Beast.SCALE`).
static func _appetite_of(kind: Beast.Kind, sees: float, up: float, to_mouth: float, eating: Vector2) -> Wildlife.Appetite:
	return Wildlife.Appetite.new(Wildlife.Eat.UNDER_HAND, sees, Beast.metres(kind, up), Beast.metres(kind, to_mouth), eating, Vector2(15.0, 30.0))


func _init(home: Wildlife, seed: int) -> void:
	super(home, seed)
	for kind in FIRST:
		due[kind] = rng.randf_range(FIRST[kind].x, FIRST[kind].y)


func all() -> Array[Beast]:
	var out: Array[Beast] = []
	for b in bands:
		out.append_array(b.animals)
	return out


func tick(delta: float) -> void:
	super(delta)
	for kind in FIRST:
		if bands.any(func(b: Band) -> bool: return b.animals[0].kind == kind):
			continue
		if not due.has(kind):
			due[kind] = rng.randf_range(AGAIN.x, AGAIN.y)
		due[kind] -= delta
		if due[kind] <= 0.0:
			due.erase(kind)
			arrive(kind)


## A band of `kind` walks in toward a spot on the meadow's rim from out of sight among the trees; with no clear
## way in, none come this time.
func arrive(kind: Beast.Kind) -> void:
	var v := Visit.new()
	v.stay = rng.randf_range(STAY.x, STAY.y)
	var first: Variant = _spot(v, null)
	if first == null:
		return
	_walk_in(v, first, rng.randi_range(HERD[kind].x, HERD[kind].y), WALK_FROM, 1.6, func() -> Beast:
		return Beast.new(kind, rng.randf_range(0.9, 1.08), rng.randf()))


func _keep(b: Band, delta: float) -> void:
	var v := b as Visit
	v.stay -= delta
	if v.stay <= 0.0:
		_leave(b)


## How near a person who is moving may come before it runs.
static func flight(a: Beast) -> float:
	return FLIGHT[a.kind] * maxf(NEAREST, 1.0 - CLOSER * a.calm)


func _alarm(b: Band, a: Node3D, _delta: float) -> bool:
	if a.state == State.ENTER or a.state == State.FLEE:
		return false
	var eating: bool = a.state == State.FEED and Wildlife.in_hand(a.hand)
	var runs_at := flight(a)
	for n in wildlife._watched():
		var at := n.global_position
		var d := Vector2(at.x - a.position.x, at.z - a.position.z).length()
		var sudden := wildlife.sudden(n)
		var startled: bool = sudden and d < STARTLE[a.kind] * (EATING_STARTLE if eating else 1.0)
		var pressed := not eating and wildlife.approaching(n, a.position) and d < runs_at
		if startled or pressed:
			if a.hand != null:
				_fed(a)
			a.calm = 0.0
			_flee(b, a, at)
			if a.state != State.FLEE:
				_watch(a)
			return false
		if eating or d >= WATCH[a.kind]:
			continue
		if a.state == State.WARY:
			if not wildlife.still(n):
				a.timer = CALM_FOR
		elif sudden or d < runs_at * NOTICE:
			_watch(a)
	return false


func _watch(a: Beast) -> void:
	a.state = State.WARY
	a.timer = CALM_FOR


## Watching, it faces the nearest person; once they have kept still a while it is calmer of them, and it grazes again
## once they are far enough off.
func _other(_b: Band, a: Node3D, delta: float) -> void:
	a.pose(Motion.IDLE, delta)
	var near: Node3D = null
	var d: float = WATCH[a.kind]
	for n in wildlife._watched():
		var off := Vector2(n.global_position.x - a.position.x, n.global_position.z - a.position.z).length()
		if off < d:
			d = off
			near = n
	if near != null:
		Wildlife._face(a, near.global_position - a.position, delta * TURN)
	a.timer -= delta
	if a.timer > 0.0:
		return
	if near == null:
		_graze(a)
		return
	a.calm += 1.0
	if d < flight(a) * NOTICE:
		a.timer = CALM_FOR
	else:
		_graze(a)


func _settled_tick(a: Node3D, delta: float) -> void:
	wildlife.calls.now_and_then(CALLS[a.kind][0], a.position, CALLS[a.kind][1], delta)


func _after_flight(a: Node3D) -> void:
	_watch(a)


## Away from the fright and out toward the trees.
func _away(a: Node3D, from: Vector3) -> Vector3:
	var out := Vector3(a.position.x, 0, a.position.z)
	return (super(a, from) + (out.normalized() if out.length() > 0.01 else Vector3.ZERO) * 0.6).normalized()


func _refuge(_b: Band, p: Vector3) -> bool:
	return Vector2(p.x, p.z).length() >= RING.x


func _speed(a: Node3D, state: State) -> float:
	return SPEED[a.kind].get(state, SPEED[a.kind][State.WALK]) * a.size


func _appetite(a: Node3D) -> Wildlife.Appetite:
	return appetite[a.kind]


func _stand_for() -> Vector2:
	return STAND_FOR


func _graze_for() -> Vector2:
	return GRAZE_FOR


func _roam() -> Vector2:
	return ROAM


func _flee_reach() -> Vector2:
	return FLEE


func _within(_b: Band, p: Vector3) -> bool:
	var r := Vector2(p.x, p.z).length()
	return r >= RING.x and r <= RING.y


## Often at a tree's foot, on the meadow side of it; else anywhere on the rim.
func _anywhere(_b: Band) -> Vector3:
	var trunks := wildlife.flora.trunks if wildlife.flora != null else null
	if trunks != null and trunks.size() > 0 and rng.randf() < 0.6:
		var t := trunks.anchors[rng.randi() % trunks.size()]
		var inward := -Vector3(t.x, 0, t.z).normalized()
		return t + inward.rotated(Vector3.UP, rng.randf_range(-1.2, 1.2)) * rng.randf_range(2.0, 7.0)
	return Vector3.FORWARD.rotated(Vector3.UP, rng.randf() * TAU) * rng.randf_range(RING.x, RING.y)
