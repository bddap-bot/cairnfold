class_name Birds
extends Node3D

## Conures: once ducks have come to the garden and a planted tree or a finished wall stands, a pair or a
## trio flies in from out of sight and lands on a crown or a wall top. Perched, they look about, preen,
## hop along, now and then flutter to another perch or swoop down to peck in the grass, and flush up to
## another perch when a hand comes near. They leave, out of sight, once no perch stands. Part of
## `Wildlife`, which decides when they come and knows where nobody is looking.

enum State { ARRIVE, PERCH, HOP, FLY, PECK, LEAVE }

const CAP := 3
const FLOCK := Vector2i(2, 3)
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
## Seconds, on average, between one bird's chatter and its chirps while perched, and its chatter while pecking.
const CHATTER_EVERY := 75.0
const CHIRP_EVERY := 110.0
const PECK_CHATTER_EVERY := 40.0

var wildlife: Wildlife
var rng := RandomNumberGenerator.new()
var birds: Array[Bird] = []
## Every perch site standing at the last look.
var sites: Array[Site] = []
## The same sites by their wall or trunk, so the next look keeps what each has worked out.
var _by_key := {}

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


## Something a bird may stand on, and the points on it where it may.
class Site:
	## Whether the last look over the garden found it.
	var listed := true

	func standing() -> bool:
		return false

	func points() -> PackedVector3Array:
		return PackedVector3Array()

	## How far one hop along it may reach.
	func hop() -> float:
		return Birds.HOP.y


class WallSite extends Site:
	var wall: Wall

	func _init(w: Wall) -> void:
		wall = w

	func standing() -> bool:
		return is_instance_valid(wall) and not wall.is_queued_for_deletion()

	func points() -> PackedVector3Array:
		return wall.perches() if standing() else PackedVector3Array()


## A planted tree's crown; its points are worked out again only when a blob of it is taken or put back, and
## stand on whatever ground is under the trunk now.
class TreeSite extends Site:
	var parts: Array[Flora.Plant] = []
	var _crown := PackedVector3Array()
	var _shown := -1

	func _init(tree: Array) -> void:
		parts.assign(tree)

	func standing() -> bool:
		return parts[0].shown()

	func points() -> PackedVector3Array:
		if not standing():
			return PackedVector3Array()
		var shown := 0
		for p in parts:
			shown += int(p.shown())
		if shown != _shown:
			_shown = shown
			_crown = Birds._crown(parts)
		var out := _crown.duplicate()
		var ground := Vector3.UP * Terrain.height_at(parts[0].anchor.x, parts[0].anchor.z)
		for i in out.size():
			out[i] += ground
		return out

	func hop() -> float:
		return Birds.HOP_TREE


func _init(home: Wildlife, seed: int) -> void:
	wildlife = home
	rng.seed = seed


func tick(delta: float) -> void:
	if birds.any(func(b: Bird) -> bool: return b.site != null and not b.site.standing()):
		look()
	for i in range(birds.size() - 1, -1, -1):
		var b := birds[i]
		_think(b, delta)
		_move(b, delta)
		if b.state == State.LEAVE and wildlife._let_go(b.node.position, LET_GO):
			b.node.queue_free()
			birds.remove_at(i)


## A pair or a trio flies in from out of sight to a perch site, as many as find a free point there.
func arrive() -> void:
	var count := rng.randi_range(FLOCK.x, FLOCK.y)
	var site: Site
	var land := Vector3.INF
	for attempt in 4:
		site = sites[rng.randi() % sites.size()]
		land = _free_spot(site, Vector3.INF)
		if land != Vector3.INF:
			break
	if land == Vector3.INF:
		return
	var start := wildlife._unseen_point(land, FROM_DISTANCE, FROM_HEIGHT, Wildlife.SIGHT, rng)
	for i in count:
		var spot := land if i == 0 else _free_spot(site, land)
		if spot == Vector3.INF:
			break
		var b := Bird.new()
		b.node = Conure.new(rng.randf() * 10.0)
		add_child(b.node)
		b.node.position = start + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.5, 0.5), rng.randf_range(-1, 1))
		b.node.blend(Conure.FLY, 1.0)
		birds.append(b)
		_fly_to(b, site, spot, State.ARRIVE)
		b.flight = -rng.randf_range(0.0, 0.25)


## Looks the garden over for perch sites: finished walls with a top to stand on and planted trees out of the
## water. A bird whose site is gone flies elsewhere, and one whose site was laid again steps onto it as it is now.
func look() -> void:
	var old := _by_key
	_by_key = {}
	for s in sites:
		s.listed = false
	sites.clear()
	var walls := wildlife.walls
	if walls != null:
		for w in walls.walls:
			if w.finished and not w.perches().is_empty():
				var s: Site = old.get(w)
				_list(w, s if s != null else WallSite.new(w))
	for parts: Array in wildlife.flora.planted_trees():
		var trunk: Flora.Plant = parts[0]
		if parts.size() > 1 and wildlife.water.pond_at(trunk.anchor.x, trunk.anchor.z) == null:
			var s: Site = old.get(trunk)
			_list(trunk, s if s != null else TreeSite.new(parts))
	for s in sites:
		s.listed = true
	for b in birds:
		if b.state == State.LEAVE:
			continue
		if sites.is_empty():
			_leave(b)
		elif b.site != null and not b.site.listed:
			_flutter(b)
		elif b.state in [State.PERCH, State.HOP] and b.site != null:
			_resettle(b)


func _list(key: Object, s: Site) -> void:
	_by_key[key] = s
	sites.append(s)


## Points on top of a tree's crown, over the ground under its trunk: upward-facing points of its foliage
## blobs that no other blob hides, a little apart, highest first.
static func _crown(parts: Array[Flora.Plant]) -> PackedVector3Array:
	if _crown_points.is_empty():
		var arrays := parts[1].pool.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in verts.size():
			if normals[i].y > 0.55:
				_crown_points.append(verts[i])
	var blobs: Array[Transform3D] = []
	var into: Array[Transform3D] = []
	for p: Flora.Plant in parts.slice(1):
		if p.shown():
			blobs.append(p.xform)
			into.append(p.xform.affine_inverse())
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
	var hand := wildlife._hand_within(b.node.position, FLUSH)
	if hand != null:
		_flush(b, hand.global_position)
		return
	if b.state == State.HOP:
		return
	b.timer -= delta
	if b.state == State.PECK:
		wildlife.calls.now_and_then("chatter", b.node.position, PECK_CHATTER_EVERY, delta)
		if b.timer <= 0.0:
			_flutter(b)
		elif rng.randf() < delta * 0.4:
			var to := b.node.position + Vector3.FORWARD.rotated(Vector3.UP, rng.randf() * TAU) * rng.randf_range(0.08, 0.2)
			to = Terrain.ground(to.x, to.z)
			if _open_ground(to):
				_hop(b, to, State.PECK)
		return
	b.preening = maxf(b.preening - delta, 0.0)
	b.node.blend(Conure.PREEN if b.preening > 0.0 else Conure.IDLE, delta)
	wildlife.calls.now_and_then("chatter", b.node.position, CHATTER_EVERY, delta)
	wildlife.calls.now_and_then("chirp", b.node.position, CHIRP_EVERY, delta)
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
	var near: Array[Vector3] = []
	for p in b.site.points():
		var d := p.distance_to(b.spot)
		if d > HOP.x and d < b.site.hop() and _clear(p, b):
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


## Whether a site is there to land on: found at the last look and not taken away since.
func _open(site: Site) -> bool:
	return site != null and site.listed and site.standing()


## Up and away from a hand at `hand` to a perch out of its reach: on another site if one has room, else on
## this one, else away.
func _flush(b: Bird, hand: Vector3) -> void:
	var order: Array[Site] = []
	if not sites.is_empty():
		var i := rng.randi() % sites.size()
		if sites[i] == b.site and sites.size() > 1:
			i = (i + 1) % sites.size()
		order.append(sites[i])
	if _open(b.site) and not order.has(b.site):
		order.append(b.site)
	for site in order:
		var best := Vector3.INF
		for i in 8:
			var p := _free_spot(site, Vector3.INF, b)
			if p != Vector3.INF and p.distance_to(hand) > FLUSH * 2.0 and (best == Vector3.INF or p.distance_to(hand) > best.distance_to(hand)):
				best = p
		if best != Vector3.INF:
			_fly_to(b, site, best, State.FLY)
			return
	_leave(b)


## Flies to a perch elsewhere: another site now and then, else further along this one. With no free point
## there, a perched bird whose site still stands stays put, and any other leaves.
func _flutter(b: Bird) -> void:
	if sites.is_empty():
		_leave(b)
		return
	var site: Site = b.site
	if not _open(site) or rng.randf() < 0.5:
		site = sites[rng.randi() % sites.size()]
	var spot := _free_spot(site, Vector3.INF, b)
	if spot != Vector3.INF:
		_fly_to(b, site, spot, State.FLY)
	elif b.state != State.PERCH or not _open(b.site):
		_leave(b)


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
	for p in b.site.points():
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
	b.to = wildlife._unseen_point(at, LEAVE_TO, FROM_HEIGHT, Wildlife.LEAVE_SIGHT, rng)
	b.flight = 0.0
	b.duration = at.distance_to(b.to) / SPEED
	b.lift = 0.0
	b.site = null
	b.state = State.LEAVE


## A point of `site` no other bird stands on or makes for, away from `near` when given, else at random.
func _free_spot(site: Site, near: Vector3, me: Bird = null) -> Vector3:
	var points := site.points()
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
	Wildlife._face(n, at - n.position, delta * (14.0 if b.state == State.HOP else 6.0))
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
			if wildlife.calls.rng.randf() < 0.5 and not wildlife.calls.calm(b.to):
				wildlife.calls.call_out("chirp", b.to)
