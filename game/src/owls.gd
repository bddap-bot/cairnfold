class_name Owls
extends Shy

## Tawny owls at night, on the perches conures use: once it is dark and a planted tree or a finished wall stands, one or
## two glide in from out of sight and settle on a crown or a wall top. Perched, an owl turns its head about, a long way
## round as owls do, watches a person near it, blinks, and hoots softly now and then; now and then it glides to another
## perch or drops to the grass after something and flies back up. One a person comes toward flies off to the perch
## furthest from them, or away if none is far enough. They leave, out of sight, when the light comes back.

enum State { FLY, PERCH, GROUND }

const CAP := 2
const AFTER := Vector2(15.0, 45.0)
const FROM_DISTANCE := 22.0
const FROM_HEIGHT := 8.0
const SPEED := 3.2
const LIFT := 0.8
const PERCH_FOR := Vector2(25.0, 70.0)
const LOOK_FOR := Vector2(1.5, 5.0)
## How far round an owl turns its head from the way it faces.
const LOOK_ROUND := 2.3
const WATCH := 7.0
const DROP_TO := Vector2(2.0, 7.0)
const GROUND_FOR := Vector2(1.5, 3.5)
const FLIGHT := 2.6
const STARTLE := 3.6
## A perch nearer than this to a person is no refuge; an owl finding none flies away.
const REFUGE := 4.5
## Owls keep this far from each other and from conures on their perches.
const SPACING := 0.5
const HOOT_EVERY := 24.0
const HOOT_FOR := 1.1


class Owl extends Shy.One:
	var site: Birds.Site
	## Where its head looks round to, and where it is now, from the way it faces.
	var look := 0.0
	var head := 0.0
	var next_look := 0.0
	var flying := 0.0
	var hooted := INF
	## Where a drop to the grass goes back up to.
	var back := Vector3.ZERO
	var back_site: Birds.Site


func _init(home: Wildlife, seed: int) -> void:
	super(home, seed, body(), "res://src/owl.gdshader", CAP, "owls")
	after = AFTER


## Standing on its perch facing -Z; its head is part 1 and turns about the neck, its wings parts 2 and 3.
static func body() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var brown := Color("84613f")
	var chest := Color("c4a47c")
	var disc := Color("d6bd96")
	var wing := Color("6c4e31")
	var dark := Color("120e0b")
	Meshes.ellipsoid(st, 0, Vector3(0, 0.125, 0.005), Vector3(0.082, 0.115, 0.076), brown, 7, 12, Callable(), Basis(), 0.04)
	Meshes.ellipsoid(st, 0, Vector3(0, 0.115, -0.028), Vector3(0.066, 0.095, 0.054), chest, 6, 10, Callable(), Basis(), 0.04)
	Meshes.ellipsoid(st, 0, Vector3(0, 0.035, 0.065), Vector3(0.038, 0.012, 0.05), wing, 3, 8, Callable(), Basis(Vector3.RIGHT, -0.5))
	Meshes.ellipsoid(st, 1, Vector3(0, 0.25, 0), Vector3(0.074, 0.064, 0.068), brown, 6, 12, Callable(), Basis(), 0.03)
	Meshes.ellipsoid(st, 1, Vector3(0, 0.245, -0.045), Vector3(0.06, 0.053, 0.026), disc, 5, 12)
	Meshes.ellipsoid(st, 1, Vector3(0, 0.232, -0.072), Vector3(0.007, 0.012, 0.008), Color("cdbb8c"), 3, 6)
	for side in [-1.0, 1.0]:
		Meshes.ellipsoid(st, 1, Vector3(side * 0.026, 0.282, -0.06), Vector3(0.026, 0.008, 0.012), Color("5b4129"), 3, 6, Callable(), Basis(Vector3.FORWARD, side * 0.35))
		Meshes.ellipsoid(st, 5, Vector3(side * 0.026, 0.255, -0.066), Vector3.ONE * 0.0165, dark, 5, 8)
		Meshes.ellipsoid(st, 5, Vector3(side * 0.031, 0.262, -0.08), Vector3.ONE * 0.0035, Color.WHITE, 2, 4)
		Meshes.ellipsoid(st, 2 if side < 0 else 3, Vector3(side * 0.072, 0.135, 0.012), Vector3(0.026, 0.098, 0.07), wing, 5, 8, Callable(), Basis(), 0.06)
		Meshes.ellipsoid(st, 4, Vector3(side * 0.024, 0.008, -0.022), Vector3(0.013, 0.008, 0.02), Color("b39d6e"), 3, 6)
	return st.commit()


func habitats() -> Dictionary:
	var sites := wildlife.birds.sites
	if not wildlife.asleep() or sites.is_empty():
		return {}
	return {wildlife.birds: mini(CAP, sites.size())}


func active() -> bool:
	return wildlife.asleep()


## One glides in from out of sight to a free perch.
func arrive(_home: Object) -> One:
	var o := Owl.new()
	var to := _perch(o, Vector3.INF)
	if to.is_empty():
		return null
	o.position = wildlife._unseen_point(to[1], FROM_DISTANCE, FROM_HEIGHT, Wildlife.SIGHT, rng)
	o.clock = rng.randf() * 100.0
	_fly(o, to[0], to[1])
	return o


## A free perch point, [its site, the point], nearest `near` or anywhere where Vector3.INF, kept REFUGE from `from` when
## given; empty where none is.
func _perch(o: Owl, near: Vector3, from := Vector3.INF) -> Array:
	var best := []
	var best_d := INF
	for s: Birds.Site in wildlife.birds.sites:
		var points := s.points()
		for attempt in mini(points.size(), 6):
			var p := points[rng.randi() % points.size()]
			if from != Vector3.INF and Vector2(p.x - from.x, p.z - from.z).length() < REFUGE:
				continue
			if not _free(p, o):
				continue
			var d := rng.randf() if near == Vector3.INF else -p.distance_to(from) if from != Vector3.INF else p.distance_to(near)
			if d < best_d:
				best_d = d
				best = [s, p]
	return best


func _free(p: Vector3, me: Owl) -> bool:
	for b in wildlife.birds.birds:
		if b.node.position.distance_to(p) < SPACING:
			return false
	for a in animals:
		if a != me and ((a as Owl).goal.distance_to(p) < SPACING or a.position.distance_to(p) < SPACING):
			return false
	return true


func _fly(o: Owl, site: Birds.Site, to: Vector3) -> void:
	o.state = State.FLY
	o.site = site
	o.from = o.position
	o.goal = to
	o.t = 0.0
	o.span = maxf(o.from.distance_to(to) / SPEED, 0.6)


func think(a: One, delta: float) -> void:
	var o: Owl = a
	o.hooted += delta
	if o.state == State.PERCH and not o.leaving:
		if o.site == null or not o.site.listed or (int(o.clock) != int(o.clock - delta) and not o.site.points().has(o.goal)):
			var to := _perch(o, o.position)
			if to.is_empty():
				leave(o)
				o.leaving = true
			else:
				_fly(o, to[0], to[1])
		var n := wary(o.position, FLIGHT, STARTLE)
		if n != null:
			var to := _perch(o, o.position, n.global_position)
			if to.is_empty():
				leave(o)
				o.leaving = true
			else:
				_fly(o, to[0], to[1])
	match o.state:
		State.FLY:
			o.t = minf(o.t + delta / o.span, 1.0)
			var at := o.from.lerp(o.goal, smoothstep(0.0, 1.0, o.t))
			at.y += LIFT * sin(PI * o.t) * minf(o.span, 3.0) / 3.0
			var dir := at - o.position
			if Vector2(dir.x, dir.z).length() > 1e-4:
				o.yaw = lerp_angle(o.yaw, heading(dir), minf(delta * 6.0, 1.0))
			o.position = at
			o.flying = move_toward(o.flying, 0.0 if o.t > 0.9 else 1.0, delta * 3.0)
			if o.t >= 1.0:
				if o.leaving:
					o.from = o.position
					o.goal = o.position + Basis(Vector3.UP, o.yaw).z * -FROM_DISTANCE + Vector3.UP * 2.0
					o.t = 0.0
				elif o.site == null:
					o.state = State.GROUND
					o.timer = rng.randf_range(GROUND_FOR.x, GROUND_FOR.y)
				else:
					o.state = State.PERCH
					o.timer = rng.randf_range(PERCH_FOR.x, PERCH_FOR.y)
		State.PERCH:
			o.timer -= delta
			_look(o, delta)
			if wildlife.calls.now_and_then("hoot", o.position, HOOT_EVERY, delta):
				o.hooted = 0.0
			if o.timer <= 0.0 and not o.leaving:
				if rng.randf() < 0.5:
					_drop(o)
				else:
					var to := _perch(o, Vector3.INF)
					if not to.is_empty():
						_fly(o, to[0], to[1])
					else:
						o.timer = rng.randf_range(PERCH_FOR.x, PERCH_FOR.y)
		State.GROUND:
			o.timer -= delta
			if o.timer <= 0.0 or wary(o.position, FLIGHT, STARTLE) != null:
				var to := _perch(o, o.back)
				if to.is_empty():
					leave(o)
					o.leaving = true
				else:
					_fly(o, to[0], to[1])
	o.head = lerp_angle(o.head, o.look, minf(delta * 5.0, 1.0)) if o.state == State.PERCH else move_toward(o.head, 0.0, delta * 3.0)
	var hoot := sin(PI * o.hooted / HOOT_FOR) if o.hooted < HOOT_FOR else 0.0
	o.basis = Basis(Vector3.UP, o.yaw) * Basis(Vector3.RIGHT, -0.9 * o.flying)
	o.pose = Color(o.clock, o.shown, o.flying - hoot * (1.0 - o.flying), o.head)


## Turns its head about now and then, or toward a person near.
func _look(o: Owl, delta: float) -> void:
	var n := nearest(o.position, WATCH)
	if n != null:
		var to := n.global_position - o.position
		o.look = clampf(wrapf(heading(to) - o.yaw, -PI, PI), -LOOK_ROUND, LOOK_ROUND)
		return
	o.next_look -= delta
	if o.next_look <= 0.0:
		o.next_look = rng.randf_range(LOOK_FOR.x, LOOK_FOR.y)
		o.look = rng.randf_range(-LOOK_ROUND, LOOK_ROUND) * (0.4 if rng.randf() < 0.6 else 1.0)


## Down to the grass a little way off, after something there.
func _drop(o: Owl) -> void:
	for attempt in 6:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, rng.randf() * TAU)
		var at := o.position + dir * rng.randf_range(DROP_TO.x, DROP_TO.y)
		at = wildlife.terrain.ground(at.x, at.z)
		if wildlife.standable(at):
			o.back = o.position
			_fly(o, null, at)
			return
	o.timer = rng.randf_range(PERCH_FOR.x, PERCH_FOR.y)


func leave(a: One) -> void:
	var o: Owl = a
	o.site = null
	o.from = o.position
	o.goal = wildlife._unseen_point(o.position, FROM_DISTANCE, FROM_HEIGHT, Wildlife.LEAVE_SIGHT, rng)
	o.t = 0.0
	o.span = o.from.distance_to(o.goal) / SPEED
	o.state = State.FLY
