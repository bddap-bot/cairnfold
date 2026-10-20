class_name Birds
extends Node3D

## Conures: once ducks have come to the garden and a planted tree or a finished wall stands, a pair or a
## trio flies in from out of sight and lands on a crown or a wall top. Perched, they look about, preen,
## hop along, now and then flutter to another perch or swoop down to peck in the grass. One the player comes
## up to slowly turns to watch and stays, shuffling aside only from a face about to touch it; a sudden
## move startles it a short way to a perch still in view. One that sees seeds held out looks at whoever holds them
## and at the hand a while, and then flies to it, or thinks better of it; on the hand it eats as long as the seeds are
## held out, and each hand holding seeds has its own. They leave, out of sight, once no perch stands. Part of `Wildlife`, which decides when they come
## and knows where nobody is looking.

enum State { ARRIVE, PERCH, HOP, FLY, PECK, LEAVE, DECIDE, FEED }

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
## A hand or the head moving suddenly within this startles a bird.
const STARTLE := 0.8
## Smoothed controller speed in m/s; carrying a bird tolerates more motion than approaching one.
const HAND_FLICK := 2.0
## A startled bird makes for a perch this far off, out of reach of what startled it.
const STARTLE_TO := Vector2(0.6, 3.0)
## A hand or the head within this has a bird turn to watch it, and keep to its perch.
const WATCH := 1.5
## A face this near a bird has it shuffle aside, so no eye ever ends up inside one; a slow hand may touch it.
const SHUFFLE := 0.12
## How readily a perched bird that sees seeds held out goes for them, per second.
const DRAWN := 0.6
## How long one looks over seeds held out before it goes for them or not, how likely it goes, and how long one that
## did not waits before looking again.
const DECIDE_FOR := Vector2(1.5, 5.0)
const TAKES := 0.75
const PUT_OFF := Vector2(2.0, 6.0)
## A conure flies to seeds held out anywhere near and eats them standing on the hand.
static var appetite := Wildlife.Appetite.new(Wildlife.Eat.ON_HAND, 6.0, INF, 0.0, Vector2(8.0, 16.0), Vector2(10.0, 25.0))
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
## What one bird says while doing each thing, by its `State`, or PREEN or WATCH while perched: calls, each with the
## seconds on average between two of them. Murmurs and beak sounds near, grumbles and chirps further off, and contact
## calls only on the wing.
const VOICE := {
	"PERCH": [["murmur", 20.0], ["chatter", 40.0], ["chirp", 80.0]],
	"PREEN": [["grind", 8.0], ["murmur", 20.0]],
	"WATCH": [["murmur", 9.0], ["grind", 30.0]],
	"HOP": [["chirp", 8.0]],
	"PECK": [["click", 12.0], ["chatter", 25.0]],
	"DECIDE": [["murmur", 4.0]],
	"FEED": [["murmur", 10.0], ["grind", 30.0]],
	"FLY": [["contact", 20.0]],
	"ARRIVE": [["contact", 8.0]],
	"LEAVE": [["contact", 12.0]],
}

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
	## How long until it goes for seeds again; the hand it flies to or eats on is its node's.
	var full := 0.0


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
		b.node.look(delta)
		b.node.animate(delta)
		if b.state == State.LEAVE and wildlife._let_go(b.node.position, LET_GO):
			wildlife.release(b)
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
		b.node = Conure.new(rng.randf() * 10.0, rng.randi() % Conure.PLUMAGES.size())
		b.node.animation_event.connect(_animation_event.bind(b))
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
	for parts: Array in wildlife.flora.placed("tree"):
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
		elif b.state in [State.PERCH, State.HOP, State.DECIDE] and b.site != null:
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
	b.full = maxf(b.full - delta, 0.0)
	if b.node.hand != null:
		_voice(b, State.keys()[b.state], delta)
		_to_hand(b, delta)
		return
	if b.state == State.LEAVE or b.state == State.ARRIVE or b.state == State.FLY:
		_voice(b, State.keys()[b.state], delta)
		return
	var at := b.node.position
	var fright := wildlife._startled(at, STARTLE)
	if fright != null:
		_startle(b, fright.global_position)
		return
	if b.state == State.HOP:
		_voice(b, "HOP", delta)
		return
	if b.full <= 0.0 and rng.randf() < delta * DRAWN:
		var h := wildlife.offer_for(appetite, at)
		if h != null:
			wildlife.claim(h, b)
			b.node.hand = h
			b.then = b.state
			b.state = State.DECIDE
			b.duration = rng.randf_range(DECIDE_FOR.x, DECIDE_FOR.y)
			b.timer = b.duration
			return
	var near := wildlife._nearest(at, WATCH) if b.state == State.PERCH else null
	if near != null:
		_voice(b, "WATCH", delta)
		_watch(b, near, delta)
		return
	b.timer -= delta
	if b.state == State.PECK:
		_voice(b, "PECK", delta)
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
	_voice(b, "PREEN" if b.preening > 0.0 else "PERCH", delta)
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


func _voice(b: Bird, doing: String, delta: float) -> void:
	for call: Array in VOICE[doing]:
		wildlife.calls.now_and_then(call[0], b.node.position, call[1], delta)


## Someone close and calm: the bird turns to them and looks about, and stays, stepping aside only from a face
## about to touch it: a hop along its perch, or a short flight where its neighbours leave no room for one.
func _watch(b: Bird, near: Node3D, delta: float) -> void:
	var at := near.global_position
	b.preening = 0.0
	b.node.blend(Conure.IDLE, delta)
	Wildlife._face(b.node, at - b.node.position, delta * 3.0)
	b.node.looking = at
	if near != wildlife.viewer or (b.node.position + Conure.BODY).distance_to(at) >= SHUFFLE:
		return
	var best := Vector3.INF
	for p in b.site.points():
		var d := p.distance_to(b.spot)
		if d > HOP.x and d < b.site.hop() and p.distance_to(at) > SHUFFLE * 2.0 and _clear(p, b) and d < best.distance_to(b.spot):
			best = p
	if best != Vector3.INF:
		_hop(b, best, State.PERCH)
	else:
		_startle(b, at)


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


## Off a short way from something sudden at `from`, and never away: see `_short_flight`, else up and back down
## where it was.
func _startle(b: Bird, from: Vector3) -> void:
	Cues.play(Cues.Act.BIRDS_STARTLE, b.node.global_position)
	var was := b.state
	if not _short_flight(b, from):
		_fly_to(b, b.site, b.node.position, State.FLY)
		if was == State.PECK:
			b.then = State.PECK


## To the nearest free perch point a short way off and out of reach of `from`, one in the viewer's sight if
## any is; false if none is.
func _short_flight(b: Bird, from: Vector3) -> bool:
	var at := b.node.position
	var best := Vector3.INF
	var best_site: Site = null
	var best_score := INF
	for site in sites:
		for p in site.points():
			var d := p.distance_to(at)
			if d < STARTLE_TO.x or d > STARTLE_TO.y or p.distance_to(from) < STARTLE * 1.5 or not _clear(p, b):
				continue
			var score := d + (0.0 if wildlife._in_sight(p) else STARTLE_TO.y)
			if score < best_score:
				best_score = score
				best = p
				best_site = site
	if best == Vector3.INF:
		return false
	_fly_to(b, best_site, best, State.FLY)
	return true


## Looking the seeds over, flying to them, then standing on the hand eating for as long as it is held out calmly
## with them. A sudden move of it startles the bird off; seeds put away send it back to a perch nearby, and thrown
## seeds keep it only until it has had its fill.
func _to_hand(b: Bird, delta: float) -> void:
	var h := b.node.hand
	if b.state == State.DECIDE:
		_decide(b, h, delta)
		return
	if not wildlife.feeds(h, b) or wildlife._speed.get(h, 0.0) > HAND_FLICK:
		_off_hand(b)
		return
	b.spot = wildlife.eat_spot(appetite, h, b.node.position)
	if b.state != State.FEED:
		b.to = b.spot
		return
	b.node.position = b.spot
	if h is Hand:
		Wildlife._face(b.node, -h.global_basis.z, delta * 6.0)
	wildlife.nibble(h, delta)
	b.timer -= delta
	b.node.blend(Conure.PECK if fposmod(b.timer, 3.0) < 1.8 else Conure.IDLE, delta)
	if h is Handful and b.timer <= 0.0:
		_off_hand(b)


## Where it stands, turned to the seeds: it looks at whoever holds them out, then at the hand, and goes or does not.
## A sudden move near it startles it as on its perch; seeds put away or held out suddenly leave it where it is.
func _decide(b: Bird, h: Node3D, delta: float) -> void:
	var fright := wildlife._startled(b.node.position, STARTLE)
	if fright != null:
		_put_off(b)
		_startle(b, fright.global_position)
		return
	if not wildlife.feeds(h, b) or wildlife.sudden(h):
		_put_off(b)
		return
	var seeds := h.global_position
	var you := wildlife.viewer
	var at := you.global_position if you != null and you.is_inside_tree() and b.timer > b.duration * 0.5 else seeds
	b.preening = 0.0
	b.node.blend(Conure.IDLE, delta)
	Wildlife._face(b.node, seeds - b.node.position, delta * 3.0)
	b.node.looking = at
	b.timer -= delta
	if b.timer > 0.0:
		return
	if rng.randf() < TAKES:
		_fly_to(b, null, wildlife.eat_spot(appetite, h, b.node.position), State.FLY)
		b.then = State.FEED
	else:
		_put_off(b)
		b.full = rng.randf_range(PUT_OFF.x, PUT_OFF.y)


## Back to what it was doing before it saw the seeds, the hand let go.
func _put_off(b: Bird) -> void:
	wildlife.release(b)
	b.node.hand = null
	b.state = b.then
	b.then = State.PERCH
	b.timer = rng.randf_range(PAUSE.x, PAUSE.y)


func _off_hand(b: Bird) -> void:
	var from := b.node.hand.global_position
	wildlife.release(b)
	b.node.hand = null
	b.full = rng.randf_range(appetite.full_for.x, appetite.full_for.y)
	if not _short_flight(b, from):
		_flutter(b)


## Flies to a perch elsewhere: another site now and then, else further along this one. With no free point
## there, a perched bird whose site still stands stays put, and any other leaves.
func _flutter(b: Bird) -> void:
	if b.state == State.DECIDE:
		_put_off(b)
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
	elif best != b.spot and b.state in [State.PERCH, State.DECIDE]:
		b.spot = best
		b.node.position = best


func _leave(b: Bird) -> void:
	wildlife.release(b)
	b.node.hand = null
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
		State.PERCH, State.DECIDE:
			if not n.is_in_group(&"perched"):
				n.add_to_group(&"perched")
			return
		State.PECK:
			n.position.y = Terrain.height_at(n.position.x, n.position.z)
			n.blend(Conure.PECK, delta)
			return
	if n.is_in_group(&"perched"):
		n.remove_from_group(&"perched")
	if b.state == State.FEED:
		return
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
	if b.state == State.FEED:
		b.timer = rng.randf_range(appetite.eats_for.x, appetite.eats_for.y)
	elif b.state == State.PECK:
		if flew:
			b.timer = rng.randf_range(PECK_FOR.x, PECK_FOR.y)
	else:
		b.timer = rng.randf_range(PAUSE.x, PAUSE.y)
		if flew:
			b.node.rotation.y += rng.randf_range(-1.2, 1.2)
	b.node.event(Cues.Act.HAND_PERCH if flew else Cues.Act.HAND_HOP)


func _animation_event(act: Cues.Act, b: Bird) -> void:
	if b.state == State.FEED and b.node.hand is Hand:
		Cues.play(act, b.node.global_position, b.node.hand)
		if act == Cues.Act.HAND_PECK:
			wildlife.calls.call_out("click", b.node.position)
	if act == Cues.Act.HAND_PERCH and b.state == State.PERCH:
		if wildlife.calls.rng.randf() < 0.5 and not wildlife.calls.calm(b.to):
			wildlife.calls.call_out("chirp", b.to)
