class_name Wildlife
extends Node3D

## Animals arrive drawn by what is built, never placed by the player, and come and go only out of the
## viewer's sight or past FAR, so nothing pops in or out of being.

## Seconds from a habitat appearing to an arrival there.
const ARRIVE_AFTER := Vector2(20.0, 60.0)
const BUTTERFLIES_AFTER := Vector2(8.0, 25.0)
const SHEEP_AFTER := Vector2(25.0, 60.0)
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
## Metres bill to tail of a grown duck; ducklings in line keep that spacing scaled to their size.
const LENGTH := 0.38
## Fraction of a duck's size; water deeper than this floats it.
const FLOAT_DEPTH := 0.1
const SINK := 0.06
const SWIM_FOR := Vector2(25.0, 50.0)
const REST_FOR := Vector2(15.0, 35.0)
const BANK := Vector2(0.5, 1.4)
## Metres an animal stands clear of a wall beyond its half thickness, and of a trunk.
const WALL_CLEAR := 0.55
const TRUNK_CLEAR := 0.9
## Ground barer than this is a path or paving.
const BARE := 0.4
const SHORE := 0.4
const RIPPLE_EVERY := 1.6
## Cosine of the widest angle off the gaze a headset still shows.
const SIGHT := 0.5
## Narrower than SIGHT so one frame's step of a leaving animal never crosses the edge of sight.
const LEAVE_SIGHT := SIGHT - 0.1
const GONE := 8.0
const FAR := 60.0
const EDGE := Terrain.SIZE * 0.5 - 1.0
const LOOK_EVERY := 0.5
## Mean seconds between a family's quacks, and between its ducklings' peeps.
const QUACK_EVERY := 20.0
const PEEP_EVERY := 30.0
## Metres per second; a hand or the head faster than this startles an animal near it.
const CALM := 0.7
## Metres per second.
const STILL := 0.25
## Eases the speed an animal sees so tracking jitter startles none.
const SPEED_EASE := 12.0
## Controller space: on top of the hand, behind the seeds the seed tool shows at `Hand.TOP`, facing them.
const ON_HAND := Vector3(0, 0.0075, 0.088)

enum State { FLY_IN, ENTER, SWIM, ASHORE, REST, FLY_OUT, WALK_OUT, FEED }
enum Eat { ON_HAND, UNDER_HAND }

class Appetite:
	var eat: Eat
	## Metres.
	var notice: float
	## Metres a hand may be above the ground or water under it.
	var reach: float
	## Metres forward from where it stands to its mouth.
	var mouth: float
	var eats_for: Vector2
	## Seconds before it comes back for more.
	var full_for: Vector2
	## Chance per second of going for seeds it sees; INF goes at once.
	var drawn: float

	func _init(how: Eat, sees: float, up: float, to_mouth: float, eating: Vector2, full: Vector2, draw: float) -> void:
		eat = how
		notice = sees
		reach = up
		mouth = to_mouth
		eats_for = eating
		full_for = full
		drawn = draw

	func tempted(full: float, delta: float, random: RandomNumberGenerator) -> bool:
		return full <= 0.0 and (drawn == INF or random.randf() < delta * drawn)


var terrain: Terrain
var marks: Ground
var water: Water
var flora: Flora
var walls: WallTool
## The wall tool's walls by grid cell, as of frame `_walls_frame`.
var _walls_at := {}
var _walls_frame := -1
## Per pond: [walls_at_rev, its layout, its `_pond_area`, whether any wall's cells come within swim reach of
## that area]; a pond no wall comes near asks no wall about a step inside it.
var _walled := {}
var palette: Palette
var viewer: Node3D
var hands: Array[Node3D] = []
## Other players' seed dishes (`Session`); one held out is an offer as a hand here is.
var dishes: Array[Dish] = []
var families: Array[Family] = []
var butterflies: Butterflies
var fireflies: Fireflies
var snails: Snails
var fish: Fish
var birds: Birds
var herds: Herds
var roamers: Roamers
var frogs: Frogs
var snakes: Snakes
var squirrels: Squirrels
var owls: Owls
var calls: Calls
## Null is always day.
var light: Look
var rng := RandomNumberGenerator.new()
## Conures come only once a duck has.
var ducks_came := false
var _due := {}
var _due_butterflies := {}
var _due_birds := {}
var _due_sheep := {}
var _since_look := INF
## Index into birds, herds, roamers, squirrels: each looks every LOOK_EVERY, a quarter of it after the one
## before, so no frame pays for them all.
var _looker := 0
var _asleep := false
## Keyed by hand or head: last position and eased speed. A teleport or snap turn clears `_was`, so the cut is
## no motion to an animal: a player in a small room cannot help teleporting.
var _was := {}
var _speed := {}
var _calm := true
var _velocity := {}
## Offer -> whatever eats from it or is on its way to.
var _eaters := {}
var handfuls: Array[Handful] = []
static var duck_appetite := Appetite.new(Eat.UNDER_HAND, 3.5, 0.6, 0.16, Vector2(6.0, 12.0), Vector2(8.0, 20.0), INF)


class Family:
	var ducks: Array[Duck] = []
	var pond: PondWater
	var state := State.ENTER
	var timer := 0.0
	var goal := Vector3.ZERO
	## A wet point of the pond, to find it again if its surface is rebuilt.
	var home := Vector3.ZERO
	## `flight` runs from 0 here to 1 on the water.
	var sky := Vector3.ZERO
	var flight := 0.0
	var ripple := 0.0
	## Level way out once leaving; Vector3.ZERO for a family walled in.
	var heading := Vector3.ZERO
	var hand: Node3D
	var full := 0.0

	func _init(first: Duck) -> void:
		ducks.append(first)

	func leader() -> Duck:
		return ducks[0]


func _init(land: Terrain, wear: Ground, ponds: Water, plants: Flora, builds: WallTool, season: Palette, eyes: Node3D, near: Array[Node3D], seed: int, sky: Look = null) -> void:
	terrain = land
	marks = wear
	water = ponds
	flora = plants
	walls = builds
	palette = season
	viewer = eyes
	hands = near
	light = sky
	if eyes != null and eyes.get_parent() is Rig:
		eyes.get_parent().jumped.connect(func() -> void: _was.clear())
	Duck.prepare()
	Sheep.prepare()
	Conure.prepare()
	Beast.prepare()
	rng.seed = seed
	butterflies = Butterflies.new(self, rng.seed + 1)
	add_child(butterflies)
	fireflies = Fireflies.new(self, rng.seed + 3)
	add_child(fireflies)
	fish = Fish.new(self, rng.seed + 6)
	add_child(fish)
	birds = Birds.new(self, rng.seed + 2)
	add_child(birds)
	herds = Herds.new(self, rng.seed + 4)
	add_child(herds)
	roamers = Roamers.new(self, rng.seed + 7)
	add_child(roamers)
	frogs = Frogs.new(self, rng.seed + 9)
	snakes = Snakes.new(self, rng.seed + 10)
	squirrels = Squirrels.new(self, rng.seed + 11)
	owls = Owls.new(self, rng.seed + 12)
	snails = Snails.new(self, rng.seed + 8)
	for kind in shy():
		add_child(kind)
	calls = Calls.new(eyes, rng.seed + 5)
	add_child(calls)


func ducks() -> Array[Duck]:
	var out: Array[Duck] = []
	for f in families:
		out.append_array(f.ducks)
	return out


func shy() -> Array[Shy]:
	return [frogs, snakes, squirrels, owls, snails]


## Each as Flora.placed lists it, trunk first.
func dry_trees() -> Array:
	return flora.placed("tree").filter(func(parts: Array) -> bool: return parts.size() > 1 and water.pond_at(parts[0].anchor.x, parts[0].anchor.z) == null)


func _process(delta: float) -> void:
	tick(delta)


## 0 by day to 1 at night.
func night() -> float:
	return 0.0 if light == null else Daylight.night(Daylight.elevation(light.time))


func asleep() -> bool:
	return _asleep


func tick(delta: float) -> void:
	calls.tick(delta)
	_watch(delta)
	_asleep = night() >= 0.5
	var day := not _asleep
	_schedule(delta, day)
	var room := day and butterflies.butterflies.size() < Butterflies.CAP
	for key in _ripe(_due_butterflies, butterflies.empty_patches(), BUTTERFLIES_AFTER, delta, room):
		if butterflies.butterflies.size() >= Butterflies.CAP:
			break
		_due_butterflies.erase(key)
		var from := _unseen_direction(butterflies.centre(key), Butterflies.FROM_DISTANCE, Butterflies.FROM_HEIGHT, SIGHT, butterflies.rng)
		butterflies.arrive(key, from)
	butterflies.tick(delta)
	fireflies.tick(delta)
	fish.tick(delta)
	_since_look += delta
	if is_inf(_since_look):
		_since_look = 0.0
		birds.look()
		herds.look()
		roamers.look()
		squirrels.look()
	elif _since_look >= LOOK_EVERY / 4.0:
		_since_look = 0.0
		[birds.look, herds.look, roamers.look, squirrels.look][_looker].call()
		_looker = (_looker + 1) % 4
	ducks_came = ducks_came or not families.is_empty()
	var perches := [birds] if ducks_came and birds.birds.is_empty() and not birds.sites.is_empty() else []
	if not _ripe(_due_birds, perches, ARRIVE_AFTER, delta, day, birds.rng).is_empty():
		_due_birds.clear()
		birds.arrive()
	birds.tick(delta)
	herds.tick(delta)
	for fence in _ripe(_due_sheep, herds.empty_pastures(), SHEEP_AFTER, delta, day and herds.all().size() < Herds.CAP):
		_due_sheep.erase(fence)
		if herds.all().size() < Herds.CAP:
			herds.arrive(fence)
	roamers.tick(delta)
	for kind in shy():
		kind.tick(delta)
	for i in range(families.size() - 1, -1, -1):
		var f := families[i]
		_think(f, delta)
		for j in range(1, f.ducks.size()):
			_follow(f.ducks[j], f.ducks[j - 1], delta)
		if _gone(f):
			release(f)
			for d in f.ducks:
				d.queue_free()
			families.remove_at(i)


func _schedule(delta: float, day: bool) -> void:
	var ponds := water.ponds.filter(func(p: PondWater) -> bool: return p.pond.cells.size() >= MIN_POND and _family_at(p) == null)
	var ripe := _ripe(_due, ponds, ARRIVE_AFTER, delta, day and families.size() < FAMILIES)
	if not ripe.is_empty():
		_due.erase(ripe[0])
		_arrive(ripe[0])


func _ripe(due: Dictionary, habitats: Array, after: Vector2, delta: float, counting := true, random := rng) -> Array:
	var present := {}
	for h in habitats:
		present[h] = true
	for h in due.keys():
		if not present.has(h):
			due.erase(h)
	var out := []
	if not counting:
		return out
	for h in habitats:
		if not due.has(h):
			due[h] = random.randf_range(after.x, after.y)
			continue
		due[h] -= delta
		if due[h] <= 0.0:
			out.append(h)
	return out


func _family_at(p: PondWater) -> Family:
	for f in families:
		if f.pond == p:
			return f
	return null


func _arrive(p: PondWater) -> void:
	var land := _deep_point(p)
	var chicks := 0
	if rng.randf() < FAMILY_CHANCE:
		chicks = rng.randi_range(DUCKLINGS.x, DUCKLINGS.y)
	var reach := sqrt(p.pond.cells.size() / PI) + WALK_FROM
	var away := _way_in(land, reach, chicks + 1) if chicks > 0 else Vector3.ZERO
	var f := Family.new(_spawn(false))
	f.pond = p
	f.home = land
	f.goal = land
	families.append(f)
	if away != Vector3.ZERO:
		for i in chicks:
			f.ducks.append(_spawn(true))
		for i in f.ducks.size():
			var at := land + away * (reach + LENGTH * 1.5 * i)
			f.ducks[i].position = terrain.ground(at.x, at.z)
			_face(f.ducks[i], -away, 1.0)
	else:
		f.goal.y = p.surface_y() - SINK
		f.sky = _unseen_point(land, FLY_DISTANCE, FLY_HEIGHT)
		f.leader().position = f.sky
		_face(f.leader(), land - f.sky, 1.0)
		f.state = State.FLY_IN


## Level, out from `land`; Vector3.ZERO where none is found.
func _way_in(land: Vector3, reach: float, n: int) -> Vector3:
	for attempt in 6:
		var away := _unseen_direction(land, reach, 0.0)
		var starts := range(n).map(func(i: int) -> Vector3: return land + away * (reach + LENGTH * 1.5 * i))
		if starts.all(standable) and clear_way(land, starts[-1]):
			return away
	return Vector3.ZERO


func _spawn(chick: bool) -> Duck:
	var d := Duck.new(chick, rng.randf() * 10.0)
	add_child(d)
	return d


func _think(f: Family, delta: float) -> void:
	var lead := f.leader()
	if f.state != State.FLY_OUT and f.state != State.WALK_OUT and (not is_instance_valid(f.pond) or not water.ponds.has(f.pond)):
		f.pond = _pond_near(f.home)
		if f.pond == null:
			_leave(f)
	var resting := asleep()
	if f.state in [State.SWIM, State.ASHORE, State.REST, State.FEED] and not resting:
		calls.now_and_then("quack", lead.position, QUACK_EVERY, delta)
		if f.ducks.size() > 1:
			calls.now_and_then("peep", f.ducks[1 + calls.rng.randi() % (f.ducks.size() - 1)].position, PEEP_EVERY, delta)
	f.full = maxf(f.full - delta, 0.0)
	if f.state in [State.SWIM, State.ASHORE, State.REST] and duck_appetite.tempted(f.full, delta, rng):
		_come_for_seeds(f)
	var eating := false
	match f.state:
		State.FLY_IN, State.FLY_OUT:
			_fly(f, delta)
		State.ENTER, State.ASHORE:
			if _go(lead, f.goal, delta):
				if f.state == State.ENTER:
					if not resting:
						calls.call_out("quack", lead.position)
					_swim(f)
				else:
					f.state = State.REST
					f.timer = rng.randf_range(REST_FOR.x, REST_FOR.y)
		State.SWIM:
			f.timer = 0.0 if resting else f.timer - delta
			f.ripple -= delta
			if f.ripple <= 0.0 and lead.afloat:
				f.ripple = RIPPLE_EVERY
				f.pond.ripple(Vector3(lead.position.x, f.pond.surface_y(), lead.position.z), 0.3)
			if _go(lead, f.goal, delta):
				var bank := _bank_point(f.pond, lead.position) if f.timer <= 0.0 else Vector3.INF
				if bank != Vector3.INF:
					f.state = State.ASHORE
					f.goal = bank
				elif resting:
					f.state = State.REST
					f.timer = rng.randf_range(REST_FOR.x, REST_FOR.y)
				else:
					f.goal = _deep_point(f.pond, lead.position)
		State.REST:
			_step(lead, Vector3.ZERO, delta)
			if not resting:
				f.timer -= delta
			if f.timer <= 0.0:
				_swim(f)
		State.WALK_OUT:
			if _go(lead, f.goal, delta) and f.heading != Vector3.ZERO:
				_walk_away(f, f.goal, f.heading)
		State.FEED:
			eating = _eat(f, delta)
	for d in f.ducks:
		d.peck(1.0 if eating else 0.0, delta)


func _come_for_seeds(f: Family) -> void:
	var lead := f.leader()
	var h := offer_for(duck_appetite, lead.position, func(o: Node3D) -> bool: return _reaches(f, eat_spot(duck_appetite, o, lead.position)))
	if h == null:
		return
	claim(h, f)
	f.hand = h
	f.goal = eat_spot(duck_appetite, h, lead.position)
	f.state = State.FEED
	f.timer = rng.randf_range(duck_appetite.eats_for.x, duck_appetite.eats_for.y)


func _reaches(f: Family, spot: Vector3) -> bool:
	return _pond_near(spot) == f.pond and _swims_clear(f.leader().position, Vector2(spot.x, spot.z))


## True while pecking.
func _eat(f: Family, delta: float) -> bool:
	var lead := f.leader()
	if not feeds(f.hand, f) or sudden(f.hand):
		_fed(f)
		return false
	var spot := eat_spot(duck_appetite, f.hand, lead.position)
	if Vector2(spot.x - f.goal.x, spot.z - f.goal.z).length() > 0.15:
		if not _reaches(f, spot):
			_fed(f)
			return false
		f.goal = spot
	if not _go(lead, f.goal, delta):
		return false
	_face(lead, f.hand.global_position - lead.position, delta * 4.0)
	nibble(f.hand, delta)
	f.timer -= delta
	if f.timer <= 0.0:
		_fed(f)
	return true


func _fed(f: Family) -> void:
	release(f)
	f.hand = null
	f.full = rng.randf_range(duck_appetite.full_for.x, duck_appetite.full_for.y)
	_swim(f)


func _swim(f: Family) -> void:
	f.state = State.SWIM
	f.timer = rng.randf_range(SWIM_FOR.x, SWIM_FOR.y)
	f.goal = _deep_point(f.pond, f.leader().position)
	f.home = f.goal


func _leave(f: Family) -> void:
	release(f)
	var at := f.leader().position
	if f.ducks.size() == 1:
		if f.state != State.FLY_IN:
			f.goal = at
			f.flight = 1.0
			f.sky = _unseen_point(at, FLY_DISTANCE, FLY_HEIGHT, LEAVE_SIGHT)
		f.heading = Vector3(f.sky.x - f.goal.x, 0, f.sky.z - f.goal.z).normalized()
		f.state = State.FLY_OUT
	else:
		f.state = State.WALK_OUT
		_walk_away(f, at, _unseen_direction(at, WALK_AWAY, 0.0, LEAVE_SIGHT))


func _walk_away(f: Family, at: Vector3, heading: Vector3) -> void:
	f.goal = _head_off(at, heading)
	f.heading = Vector3(f.goal.x - at.x, 0, f.goal.z - at.z).normalized()


## `at` itself when no way is clear.
func _head_off(at: Vector3, heading: Vector3, random := rng) -> Vector3:
	for attempt in 6:
		var to := at + heading * WALK_AWAY
		to = terrain.ground(clampf(to.x, -EDGE, EDGE), clampf(to.z, -EDGE, EDGE))
		if clear_way(at, to):
			return to
		heading = _unseen_direction(at, WALK_AWAY, 0.0, LEAVE_SIGHT, random)
	return at


func _gone(f: Family) -> bool:
	if f.state != State.WALK_OUT and (f.state != State.FLY_OUT or f.flight > 0.0):
		return false
	return f.ducks.all(func(d: Duck) -> bool: return _let_go(d.position, 0.0 if f.heading == Vector3.ZERO or _at_edge(d.position) else GONE))


func _let_go(at: Vector3, near: float) -> bool:
	if viewer == null or not viewer.is_inside_tree():
		return true
	var off := at.distance_to(viewer.global_position)
	return off >= FAR or (off >= near and not _in_sight(at, LEAVE_SIGHT))


func _at_edge(at: Vector3) -> bool:
	return maxf(absf(at.x), absf(at.z)) >= EDGE - 0.5


func _watch(delta: float) -> void:
	if delta <= 0.0:
		return
	var watched := _watched()
	for n in _was.keys():
		if not watched.has(n):
			_was.erase(n)
			_speed.erase(n)
			_velocity.erase(n)
	for n in watched:
		var at := n.global_position
		var moved: Vector3 = (at - _was.get(n, at)) / delta
		var ease := 1.0 - exp(-delta * SPEED_EASE)
		_was[n] = at
		_speed[n] = lerpf(_speed.get(n, 0.0), moved.length(), ease)
		_velocity[n] = _velocity.get(n, Vector3.ZERO).lerp(moved, ease)
	_calm = _speed.values().all(func(v: float) -> bool: return v <= CALM)
	var held := offers()
	for h in _eaters.keys():
		if not held.has(h):
			_eaters.erase(h)


## A dish put away is forgotten, so held out again it is no sudden move.
func _watched() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n: Node3D in hands + dishes + [viewer]:
		if n != null and n.is_inside_tree() and (n is not Dish or n.is_visible_in_tree()):
			out.append(n)
	return out


func sudden(n: Node3D) -> bool:
	return _speed.get(n, 0.0) > CALM


func still(n: Node3D) -> bool:
	return _speed.get(n, 0.0) < STILL


func approaching(n: Node3D, p: Vector3) -> bool:
	var to := Vector3(p.x - n.global_position.x, 0, p.z - n.global_position.z)
	var v: Vector3 = _velocity.get(n, Vector3.ZERO)
	return to.length() > 1e-3 and Vector3(v.x, 0, v.z).dot(to.normalized()) > STILL


func _startled(p: Vector3, reach: float) -> Node3D:
	if _calm:
		return null
	for n in _watched():
		if p.distance_to(n.global_position) < reach and sudden(n):
			return n
	return null


func _nearest(p: Vector3, reach: float, across_ground := false) -> Node3D:
	var best: Node3D = null
	for n in _watched():
		var at := n.global_position
		var d := Vector2(at.x - p.x, at.z - p.z).length() if across_ground else p.distance_to(at)
		if d < reach:
			reach = d
			best = n
	return best


func offers() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for h in hands:
		if h is Hand and h.is_inside_tree() and h.holds_seeds():
			out.append(h)
	for d in dishes:
		if d.is_visible_in_tree():
			out.append(d)
	for s in handfuls:
		if s.landed():
			out.append(s)
	return out


static func in_hand(offer: Node3D) -> bool:
	return offer is Hand or offer is Dish


## `dish`: count those on other players' dishes instead of this player's hands.
func feeding(dish: bool) -> int:
	return birds.birds.filter(func(b: Birds.Bird) -> bool: return b.state == Birds.State.FEED and (b.node.hand is Dish if dish else b.node.hand is Hand)).size()


func nibble(offer: Node3D, delta: float) -> void:
	if offer is Handful:
		offer.peck(delta)


func offer_for(appetite: Appetite, at: Vector3, fits := Callable()) -> Node3D:
	for h in offers():
		var p := h.global_position
		if _eaters.has(h) or sudden(h) or p.distance_to(at) > appetite.notice:
			continue
		if in_hand(h) and appetite.eat == Eat.UNDER_HAND and p.y - water.floor_at(p) > appetite.reach:
			continue
		if h is Handful and appetite.eat == Eat.ON_HAND and water.pond_at(p.x, p.z) != null:
			continue
		if fits.is_valid() and not fits.call(h):
			continue
		return h
	return null


func claim(h: Node3D, eater: Object) -> void:
	_eaters[h] = eater


func release(eater: Object) -> void:
	for h in _eaters.keys():
		if _eaters[h] == eater:
			_eaters.erase(h)


func feeds(h: Node3D, eater: Object) -> bool:
	return h != null and _eaters.get(h) == eater and offers().has(h)


func eat_spot(appetite: Appetite, h: Node3D, from: Vector3) -> Vector3:
	var seen := Hand.seen(h)
	if appetite.eat == Eat.ON_HAND and in_hand(h):
		return seen.global_transform * ON_HAND
	var at := seen.global_position
	var off := Vector3(from.x - at.x, 0, from.z - at.z)
	at += off.normalized() * appetite.mouth if off.length() > 1e-3 else Vector3.ZERO
	return Vector3(at.x, water.floor_at(at), at.z)


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
		Cues.play(Cues.Act.DIP, splash)
		if not _asleep:
			calls.call_out("quack", splash)
		_swim(f)


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


func _step(d: Duck, velocity: Vector3, delta: float) -> void:
	d.position += velocity * delta
	var ground := terrain.height_at(d.position.x, d.position.z)
	var p := water.pond_at(d.position.x, d.position.z)
	var surface := p.surface_y() if p != null else -INF
	d.position.y = maxf(ground, surface - SINK * d.size)
	d.afloat = surface - ground > FLOAT_DEPTH * d.size
	var moving := velocity.length() > 0.01
	if moving:
		_face(d, velocity, delta * 4.0)
	d.blend(Duck.PADDLE if d.afloat else Duck.WADDLE if moving else Duck.IDLE, delta)


static func _face(d: Node3D, dir: Vector3, weight: float) -> void:
	if Vector2(dir.x, dir.z).length() < 1e-4:
		return
	d.rotation.y = lerp_angle(d.rotation.y, Shy.heading(dir), clampf(weight, 0.0, 1.0))


## Failing 12 tries, the pond's bottom, or `from` itself when given.
func _deep_point(p: PondWater, from := Vector3.INF) -> Vector3:
	var cells := p.pond.cells
	for attempt in 12:
		var xz := Terrain.grid_xz(cells[rng.randi() % cells.size()])
		if p.pond.level - terrain.height_at(xz.x, xz.y) > FLOAT_DEPTH * 2.0 and _swims_clear(from, xz):
			return Vector3(xz.x, p.pond.level, xz.y)
	var b := Terrain.grid_xz(p.pond.bottom) if from == Vector3.INF else Vector2(from.x, from.z)
	return Vector3(b.x, p.pond.level, b.y)


static func _pond_quota(p: PondWater, ponds: int, cap: int, each: int, most: int) -> int:
	var share := cap / maxi(1, ponds)
	return clampi(p.pond.cells.size() / each, mini(1, share), mini(most, share))


## Counts into `have`, per habitat their `key` names, the staying `animals` up to `want`'s count; returns the rest.
static func _surplus(animals: Array, key: StringName, want: Dictionary, have: Dictionary) -> Array:
	var over := []
	for a in animals:
		# Untyped: a gone habitat is a freed object, which a typed variable refuses.
		var h: Variant = a.get(key)
		if not a.leaving and have.get(h, 0) < want.get(h, 0):
			have[h] = have.get(h, 0) + 1
		elif not a.leaving:
			over.append(a)
	return over


func _swims_clear(from: Vector3, to: Vector2, pond: PondWater = null) -> bool:
	if walls == null or from == Vector3.INF:
		return true
	var a := Vector2(from.x, from.z)
	var frame := Engine.get_process_frames()
	if frame != _walls_frame:
		_walls_frame = frame
		_walls_at = walls.walls_by_cell()
	# Only a wall with samples in cells within SWIM_REACH of the step can turn it back.
	var reach := Vector2.ONE * WallLayout.SWIM_REACH
	var step := Rect2(a, Vector2.ZERO).expand(to)
	if pond != null:
		var near: Array = _walled.get(pond, [])
		if near.is_empty() or near[0] != walls.walls_at_rev or near[1] != pond.pond:
			for gone in _walled.keys().filter(func(k: Object) -> bool: return not is_instance_valid(k)):
				_walled.erase(gone)
			near = [walls.walls_at_rev, pond.pond, _pond_area(pond.pond), false]
			for c in PathLayout.cells_along(near[2].position - reach, near[2].end + reach):
				if _walls_at.has(c):
					near[3] = true
					break
			_walled[pond] = near
		if not near[3] and near[2].encloses(step):
			return true
	var asked := {}
	for c in PathLayout.cells_along(step.position - reach, step.end + reach):
		for w: Wall in _walls_at.get(c, []):
			if not asked.has(w):
				asked[w] = true
				if w.layout.blocks_swim(a, to):
					return false
	return true


static func _pond_area(pond: PondLayout.Pond) -> Rect2:
	var area := Rect2(Terrain.grid_xz(pond.cells[0]), Vector2.ZERO)
	for c in pond.cells:
		area = area.expand(Terrain.grid_xz(c))
	return area.grow(Terrain.STEP)


## Vector3.INF where none is found, as on water a wall cuts off from the banks.
func _bank_point(p: PondWater, from: Vector3) -> Vector3:
	var mid := Terrain.grid_xz(p.pond.bottom)
	for attempt in 12:
		var s := Terrain.grid_xz(p.pond.shore[rng.randi() % p.pond.shore.size()])
		var out := (s - mid).normalized() if s != mid else Vector2.RIGHT
		var at := s + out * rng.randf_range(BANK.x, BANK.y)
		var ground := terrain.ground(at.x, at.y)
		if standable(ground) and clear_way(from, ground):
			return ground
	return Vector3.INF


func standable(p: Vector3) -> bool:
	if maxf(absf(p.x), absf(p.z)) > EDGE - 1.0:
		return false
	if marks.bare(p.x, p.z) > BARE:
		return false
	for o in [Vector2.ZERO, Vector2(SHORE, 0), Vector2(-SHORE, 0), Vector2(0, SHORE), Vector2(0, -SHORE)]:
		if water.pond_at(p.x + o.x, p.z + o.y) != null:
			return false
	if flora != null:
		var trunks := flora.trunks
		for i in trunks.size():
			var t := trunks.anchors[i]
			if Vector2(t.x - p.x, t.z - p.z).length() < TRUNK_CLEAR:
				return false
	var q := Vector2(p.x, p.z)
	for w in _walls():
		var layout := w.layout
		var clear := layout.half_thickness() + WALL_CLEAR
		if not layout.bounds.grow(clear).has_point(q):
			continue
		var pts := WallLayout.ground_line(layout.samples)
		for i in pts.size() - 1:
			if Geometry2D.get_closest_point_to_segment(q, pts[i], pts[i + 1]).distance_to(q) < clear:
				return false
		if layout.closed and Geometry2D.is_point_in_polygon(q, pts):
			return false
	return true


func clear_way(a: Vector3, b: Vector3) -> bool:
	var p := Vector2(a.x, a.z)
	var q := Vector2(b.x, b.z)
	var span := Rect2(p, Vector2.ZERO).expand(q)
	for w in _walls():
		if not w.layout.bounds.grow(0.5).intersects(span.grow(0.01)):
			continue
		var pts := WallLayout.ground_line(w.layout.samples)
		for i in pts.size() - 1:
			if Geometry2D.segment_intersects_segment(p, q, pts[i], pts[i + 1]) != null:
				return false
	return not water.crosses(p, q)


func _walls() -> Array[Wall]:
	return walls.walls if walls != null else ([] as Array[Wall])


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
	return _gaze(at) > cone


## Cosine of the angle between the gaze and `at`; -INF with no viewer.
func _gaze(at: Vector3) -> float:
	if viewer == null or not viewer.is_inside_tree():
		return -INF
	return (at - viewer.global_position).normalized().dot(-viewer.global_basis.z)


func _unseen_point(at: Vector3, reach: float, height: float, cone := SIGHT, random := rng) -> Vector3:
	return at + _unseen_direction(at, reach, height, cone, random) * reach + Vector3.UP * height


## Failing 12 tries, the direction tried furthest from the gaze.
func _unseen_direction(at: Vector3, reach: float, height: float, cone := SIGHT, random := rng) -> Vector3:
	var best := Vector3.FORWARD
	var best_dot := INF
	for attempt in 12:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, random.randf() * TAU)
		var to := at + dir * reach + Vector3.UP * height
		var dot := _gaze(to)
		if dot <= cone:
			return dir
		if dot < best_dot:
			best_dot = dot
			best = dir
	return best
