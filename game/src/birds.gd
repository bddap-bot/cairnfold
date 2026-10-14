class_name Birds
extends Node3D

## Conures: once ducks have come to the garden and a planted tree or a finished wall stands, a pair or a
## trio flies in from out of sight and lands on a crown or a wall top. Perched, they look about, preen,
## hop along, now and then flutter to another perch or swoop down to peck in the grass, and flush up to
## another perch when a hand comes near. They leave, out of sight, once no perch stands. Part of
## `Wildlife`, which knows where nobody is looking.

enum State { ARRIVE, PERCH, HOP, FLY, PECK, LEAVE }

const CAP := 3
const FLOCK := Vector2i(2, 3)
const ARRIVE_AFTER := Vector2(20.0, 60.0)
## How often the perches are looked over; between times the birds use what was found.
const REFRESH := 0.5
const FROM_DISTANCE := 22.0
const FROM_HEIGHT := 9.0
const LEAVE_TO := 40.0
const LET_GO := 6.0
const SPEED := 4.0
const HOP_TIME := 0.32
## A hop along a wall top reaches the next few perch points; a crown's points stand further apart.
const HOP := Vector2(0.12, 0.5)
const HOP_TREE := 0.9
## A hand closer than this sends a bird up to another perch.
const FLUSH := 0.8
const PAUSE := Vector2(1.5, 5.0)
const PREEN_FOR := Vector2(3.0, 7.0)
const PECK_FOR := Vector2(5.0, 11.0)
const PECK_REACH := Vector2(1.5, 4.0)
## Birds keep this far apart on their perches.
const SPACING := 0.22
## How deep inside a neighbouring foliage blob a crown point may lie, as a fraction of its radius, and still
## show: blobs bulge by noise beyond their round shape.
const INSIDE := 0.85
const CROWN_POINTS := 12
## How far below the top of its crown a bird may stand on a tree.
const CROWN_DEPTH := 1.2

var wildlife: Wildlife
var rng := RandomNumberGenerator.new()
var birds: Array[Bird] = []
var ducks_came := false
## Each perch site by its wall or its trunk.
var sites := {}
var _due := -1.0
var _since_refresh := INF

static var _crown_points := PackedVector3Array()


class Bird:
	var node: Conure
	var state := State.ARRIVE
	var site: Site
	var spot := Vector3.ZERO
	var from := Vector3.ZERO
	var to := Vector3.ZERO
	var lift := 0.0
	var flight := 0.0
	var duration := 1.0
	var timer := 0.0
	var preening := 0.0
	## Where the next leg goes once a hop or a flight down to the grass ends.
	var then := State.PERCH


## A wall or a planted tree, with the points a bird may stand on, worked out again only when its shape changed.
class Site:
	var wall: Wall
	var tree: Array[Flora.Plant] = []
	var points := PackedVector3Array()
	var shape := []


func _init(home: Wildlife, seed: int) -> void:
	wildlife = home
	rng.seed = seed


func tick(delta: float) -> void:
	ducks_came = ducks_came or not wildlife.families.is_empty()
	_since_refresh += delta
	if _since_refresh >= REFRESH:
		_since_refresh = 0.0
		_refresh()
	_schedule(delta)
	for i in range(birds.size() - 1, -1, -1):
		var b := birds[i]
		_think(b, delta)
		_move(b, delta)
		if b.state == State.LEAVE and _gone(b):
			b.node.queue_free()
			birds.remove_at(i)


func _schedule(delta: float) -> void:
	if sites.is_empty() or not ducks_came or not birds.is_empty():
		_due = -1.0
		return
	if _due < 0.0:
		_due = rng.randf_range(ARRIVE_AFTER.x, ARRIVE_AFTER.y)
		return
	_due -= delta
	if _due <= 0.0:
		_due = -1.0
		_arrive()


func _arrive() -> void:
	var count := rng.randi_range(FLOCK.x, FLOCK.y)
	var site: Site
	var land := Vector3.INF
	for attempt in 4:
		site = sites.values()[rng.randi() % sites.size()]
		land = _free_spot(site, Vector3.INF)
		if land != Vector3.INF:
			break
	if land == Vector3.INF:
		return
	var away := wildlife._unseen_direction(land, FROM_DISTANCE, FROM_HEIGHT, Wildlife.SIGHT, rng)
	var start := land + away * FROM_DISTANCE + Vector3.UP * FROM_HEIGHT
	for i in mini(count, CAP - birds.size()):
		var b := Bird.new()
		b.node = Conure.new(rng.randf() * 10.0)
		add_child(b.node)
		b.node.position = start + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.5, 0.5), rng.randf_range(-1, 1))
		b.node.blend(Conure.FLY, 1.0)
		birds.append(b)
		var spot := land if i == 0 else _free_spot(site, land)
		if spot == Vector3.INF:
			spot = land
		_fly_to(b, site, spot, State.ARRIVE)
		b.flight = -rng.randf_range(0.0, 0.25)


## Walls standing finished without a roof and planted trees out of the water. Their points are only worked
## out once a bird makes for one, so a garden full of them costs nothing until then.
func _refresh() -> void:
	var now := {}
	var walls := wildlife.walls
	if walls != null:
		for w in walls.walls:
			if w.finished and w.roof == null:
				if sites.has(w):
					now[w] = sites[w]
				else:
					now[w] = Site.new()
					now[w].wall = w
	for parts: Array in wildlife.flora.planted_trees():
		var trunk: Flora.Plant = parts[0]
		if wildlife.water.pond_at(trunk.anchor.x, trunk.anchor.z) != null:
			continue
		if sites.has(trunk):
			now[trunk] = sites[trunk]
		else:
			var s := Site.new()
			s.tree.assign(parts)
			now[trunk] = s
	sites = now
	for b in birds:
		if b.state == State.LEAVE:
			continue
		if sites.is_empty():
			_leave(b)
		elif b.site != null and not sites.values().has(b.site):
			_flutter(b)
		elif b.state in [State.PERCH, State.HOP] and b.site != null:
			_resettle(b)


## The site's points, laid out again when its wall or the ground under it changed.
func _points(s: Site) -> PackedVector3Array:
	var shape := [Terrain.revision]
	if s.wall != null:
		var l := s.wall.layout
		shape.append_array([l.stones.size(), l.length(), l.height, l.top, l.flags.size(), l.lanterns.size(), l.ruins.size(), l.roofed])
	if shape == s.shape:
		return s.points
	s.shape = shape
	s.points = s.wall.layout.perches() if s.wall != null else _crown(s.tree)
	return s.points


## Points on top of a tree's crown: upward-facing points of its foliage blobs that no other blob hides, a
## little apart, highest first.
func _crown(parts: Array[Flora.Plant]) -> PackedVector3Array:
	if _crown_points.is_empty():
		var arrays := wildlife.flora.foliage.mm.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in verts.size():
			if normals[i].y > 0.55:
				_crown_points.append(verts[i])
	var blobs: Array[Transform3D] = []
	var into: Array[Transform3D] = []
	for p: Flora.Plant in parts.slice(1):
		if p.shown():
			var x := p.xform
			x.origin.y += Terrain.height_at(p.anchor.x, p.anchor.z)
			blobs.append(x)
			into.append(x.affine_inverse())
	var found: Array[Vector3] = []
	for i in blobs.size():
		for v in _crown_points:
			var at := blobs[i] * v
			var hidden := false
			for j in blobs.size():
				if j != i and (into[j] * at).length() < INSIDE:
					hidden = true
					break
			if not hidden:
				found.append(at)
	found.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y > b.y)
	var out := PackedVector3Array()
	for p in found:
		if out.size() >= CROWN_POINTS or not out.is_empty() and p.y < out[0].y - CROWN_DEPTH:
			break
		if Array(out).all(func(q: Vector3) -> bool: return q.distance_to(p) > SPACING * 1.5):
			out.append(p)
	return out


func _think(b: Bird, delta: float) -> void:
	if b.state == State.LEAVE or b.state == State.ARRIVE or b.state == State.FLY:
		return
	if _hand_within(b.node.position) != null:
		_flush(b)
		return
	if b.state == State.HOP:
		return
	b.timer -= delta
	if b.state == State.PECK:
		if b.timer <= 0.0:
			_flutter(b)
		elif rng.randf() < delta * 0.4:
			var to := b.node.position + Vector3.FORWARD.rotated(Vector3.UP, rng.randf() * TAU) * rng.randf_range(0.08, 0.2)
			_hop(b, Terrain.ground(to.x, to.z), State.PECK)
		return
	b.preening = maxf(b.preening - delta, 0.0)
	b.node.blend(Conure.PREEN if b.preening > 0.0 else Conure.IDLE, delta)
	if b.timer > 0.0:
		return
	b.timer = rng.randf_range(PAUSE.x, PAUSE.y)
	var roll := rng.randf()
	if roll < 0.4:
		var next := _hop_spot(b)
		if next != Vector3.INF:
			_hop(b, next, State.PERCH)
	elif roll < 0.6:
		b.preening = rng.randf_range(PREEN_FOR.x, PREEN_FOR.y)
		b.timer = b.preening + 0.5
	elif roll < 0.72:
		_flutter(b)
	elif roll < 0.84:
		_swoop(b)


func _hop_spot(b: Bird) -> Vector3:
	var reach := HOP.y if b.site.wall != null else HOP_TREE
	var near: Array[Vector3] = []
	for p in _points(b.site):
		var d := p.distance_to(b.spot)
		if d > HOP.x and d < reach and _clear(p, b):
			near.append(p)
	return near[rng.randi() % near.size()] if not near.is_empty() else Vector3.INF


func _hop(b: Bird, to: Vector3, then: State) -> void:
	b.from = b.node.position
	b.to = to
	b.flight = 0.0
	b.duration = HOP_TIME
	b.lift = 0.06 + maxf(to.y - b.from.y, 0.0) * 0.5
	b.state = State.HOP
	b.then = then
	if then == State.PERCH:
		b.spot = to


## Up and away from a hand to a perch out of its reach: on another site if there is one.
func _flush(b: Bird) -> void:
	var hand := _hand_within(b.node.position).global_position
	var others := sites.values().filter(func(s: Site) -> bool: return s != b.site)
	var first := rng.randi()
	var order := []
	for k in others.size():
		order.append(others[(first + k) % others.size()])
	if sites.values().has(b.site):
		order.append(b.site)
	for site: Site in order:
		var best := Vector3.INF
		for i in 8:
			var p := _free_spot(site, Vector3.INF, b)
			if p != Vector3.INF and p.distance_to(hand) > FLUSH * 2.0 and (best == Vector3.INF or p.distance_to(hand) > best.distance_to(hand)):
				best = p
		if best != Vector3.INF:
			_fly_to(b, site, best, State.FLY)
			return
	_leave(b)


## Flies to a perch elsewhere: another site now and then, else further along this one.
func _flutter(b: Bird) -> void:
	if sites.is_empty():
		_leave(b)
		return
	var site: Site = b.site
	if site == null or not sites.values().has(site) or rng.randf() < 0.5:
		site = sites.values()[rng.randi() % sites.size()]
	var spot := _free_spot(site, Vector3.INF, b)
	if spot == Vector3.INF:
		return
	_fly_to(b, site, spot, State.FLY)


## Down to the grass near the perch, to peck about there and come back up.
func _swoop(b: Bird) -> void:
	for attempt in 6:
		var off := Vector3.FORWARD.rotated(Vector3.UP, rng.randf() * TAU) * rng.randf_range(PECK_REACH.x, PECK_REACH.y)
		var at := Terrain.ground(b.spot.x + off.x, b.spot.z + off.z)
		if _open_ground(at):
			_fly_to(b, null, at, State.FLY)
			b.then = State.PECK
			return


func _open_ground(at: Vector3) -> bool:
	if absf(at.x) > Wildlife.EDGE or absf(at.z) > Wildlife.EDGE or wildlife.water.pond_at(at.x, at.z) != null:
		return false
	if wildlife.walls != null:
		for w in wildlife.walls.walls:
			if w.pick_bounds.grow(0.3).has_point(at + Vector3.UP * 0.05):
				return false
	return true


func _fly_to(b: Bird, site: Site, to: Vector3, state: State) -> void:
	b.from = b.node.position
	b.to = to
	b.site = site
	b.spot = to
	b.flight = 0.0
	b.duration = maxf(b.from.distance_to(to) / SPEED, 0.5)
	b.lift = 0.0 if state == State.ARRIVE else minf(0.3 + b.from.distance_to(to) * 0.15, 1.5)
	b.state = state
	b.then = State.PERCH


## A perched bird whose wall or crown was laid again steps to the nearest point now there, or flies to one.
func _resettle(b: Bird) -> void:
	var best := Vector3.INF
	for p in _points(b.site):
		if p.distance_to(b.spot) < best.distance_to(b.spot):
			best = p
	if best == Vector3.INF or best.distance_to(b.spot) > 0.4:
		_flutter(b)
	elif best != b.spot and b.state == State.PERCH:
		b.spot = best
		b.node.position = best


func _leave(b: Bird) -> void:
	var at := b.node.position
	b.from = at
	b.to = at + wildlife._unseen_direction(at, LEAVE_TO, FROM_HEIGHT, Wildlife.LEAVE_SIGHT, rng) * LEAVE_TO + Vector3.UP * FROM_HEIGHT
	b.flight = 0.0
	b.duration = at.distance_to(b.to) / SPEED
	b.lift = 0.0
	b.site = null
	b.state = State.LEAVE


## A point of `site` no other bird stands on or makes for, away from `near` when given, else at random.
func _free_spot(site: Site, near: Vector3, me: Bird = null) -> Vector3:
	var points := _points(site)
	if points.is_empty():
		return Vector3.INF
	for attempt in 10:
		var p := points[rng.randi() % points.size()]
		if near != Vector3.INF and p.distance_to(near) > 1.5 and attempt < 6:
			continue
		if _clear(p, me) and (near == Vector3.INF or p.distance_to(near) > SPACING):
			return p
	return Vector3.INF


func _clear(p: Vector3, me: Bird) -> bool:
	for o in birds:
		if o != me and o.state != State.LEAVE and o.spot.distance_to(p) < SPACING:
			return false
	return true


func _gone(b: Bird) -> bool:
	var eye := wildlife.viewer
	if eye == null or not eye.is_inside_tree():
		return true
	var off := b.node.position.distance_to(eye.global_position)
	return off > Wildlife.FAR or (off > LET_GO and not wildlife._in_sight(b.node.position, Wildlife.LEAVE_SIGHT))


func _hand_within(p: Vector3) -> Node3D:
	for h in wildlife.hands:
		if h.is_inside_tree() and p.distance_to(h.global_position) < FLUSH:
			return h
	return null


## Along an arc from `from` to `to`, slowing to land; a leaving bird speeds up and keeps going.
func _move(b: Bird, delta: float) -> void:
	var n := b.node
	match b.state:
		State.PERCH:
			if not n.is_in_group(&"perched"):
				n.add_to_group(&"perched")
			return
		State.PECK:
			n.position.y = Terrain.height_at(n.position.x, n.position.z)
			n.blend(Conure.PECK, delta)
			return
	if n.is_in_group(&"perched"):
		n.remove_from_group(&"perched")
	b.flight = minf(b.flight + delta / b.duration, 1.0)
	if b.flight < 0.0:
		return
	var leaving := b.state == State.LEAVE
	var s := b.flight * b.flight if leaving else b.flight * (2.0 - b.flight)
	var at := b.from.lerp(b.to, s) + Vector3.UP * b.lift * sin(PI * s)
	if leaving and b.flight >= 1.0:
		at = n.position + (b.to - b.from).normalized() * SPEED * delta
	_face(n, at - n.position, delta * (14.0 if b.state == State.HOP else 6.0))
	n.position = at
	if b.state == State.HOP:
		n.blend(Conure.FLY * 0.35, delta * 3.0)
	else:
		n.blend(Conure.FLY, delta * 2.0)
	if b.flight >= 1.0 and not leaving:
		_land(b)


func _land(b: Bird) -> void:
	var flew := b.state != State.HOP
	b.node.position = b.to
	b.state = b.then
	b.then = State.PERCH
	if b.state == State.PECK:
		if flew:
			b.timer = rng.randf_range(PECK_FOR.x, PECK_FOR.y)
	else:
		b.timer = rng.randf_range(PAUSE.x, PAUSE.y)
		if flew:
			b.node.rotation.y += rng.randf_range(-1.2, 1.2)


func _face(n: Node3D, dir: Vector3, weight: float) -> void:
	if Vector2(dir.x, dir.z).length() < 1e-4:
		return
	n.rotation.y = lerp_angle(n.rotation.y, atan2(-dir.x, -dir.z), clampf(weight, 0.0, 1.0))
