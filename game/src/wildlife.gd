class_name Wildlife
extends Node3D

## Animals that come on their own, drawn by what is built; nothing the player holds can place one.
## Some time after a pond appears a duck arrives: alone it flies in and splashes down, a mother with
## ducklings walks in from the meadow with them in a line. They paddle about, now and then waddle up
## the bank to rest on the grass, and leave when their pond is gone. Arrivals and departures happen
## out of the viewer's sight, so nothing pops in or out of being. Butterflies come the same way to the flower
## patches painted (`Butterflies`), fireflies at dusk over ponds and flower patches (`Fireflies`), fish to the ponds (`Fish`), conures,
## after the ducks, to planted trees and wall tops (`Birds`), and sheep to the fences built (`Herds`); deer
## and a fox come out of the trees round the meadow (`Roamers`).
## A hand or the head coming near slowly startles none of them; a sudden one does. A hand holding seeds draws
## those that eat from it, each kind as its `Appetite` says.

## How long after its habitat appears a duck, a pond's fish, or a flock of conures, comes.
const ARRIVE_AFTER := Vector2(20.0, 60.0)
const BUTTERFLIES_AFTER := Vector2(8.0, 25.0)
const SHEEP_AFTER := Vector2(25.0, 60.0)
## In wet grid points.
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
## Bill to tail of a grown duck; a line of ducklings keeps that spacing scaled to their size.
const LENGTH := 0.38
## Water deeper than this, as a fraction of a duck's size, floats it.
const FLOAT_DEPTH := 0.1
const SINK := 0.06
const SWIM_FOR := Vector2(25.0, 50.0)
const REST_FOR := Vector2(15.0, 35.0)
const BANK := Vector2(0.5, 1.4)
const RIPPLE_EVERY := 1.6
## Cosine of the widest angle from the gaze a headset still shows.
const SIGHT := 0.5
## A leaving duck is let go once outside this narrower cone, so one frame's step never crosses the edge of
## sight, and at least GONE from the viewer, or once FAR.
const LEAVE_SIGHT := SIGHT - 0.1
const GONE := 8.0
const FAR := 60.0
const EDGE := Terrain.SIZE * 0.5 - 1.0
## Seconds between looks over the walls and trees for where conures may perch and sheep graze.
const LOOK_EVERY := 0.5
## Seconds, on average, between a family's quacks and its ducklings' peeps while it is at its pond.
const QUACK_EVERY := 20.0
const PEEP_EVERY := 30.0
## A hand or the head moving faster than this, in metres a second, startles an animal near it; slower, it may
## come right up.
const CALM := 0.7
## Slower than this, in metres per second, a hand or the head is still.
const STILL := 0.25
## Per second: how quickly the speed an animal sees follows a hand's or the head's, so tracking jitter startles none.
const SPEED_EASE := 12.0
## Where an animal eating from a hand stands on it, in the controller's space: on its top, behind the seeds
## the seed tool shows at `Hand.TOP`, facing them.
const ON_HAND := Vector3(0, 0.0075, 0.088)

enum State { FLY_IN, ENTER, SWIM, ASHORE, REST, FLY_OUT, WALK_OUT, FEED }
## Where an animal eats seeds held out to it: standing on the hand, or under it on the ground or water.
enum Eat { ON_HAND, UNDER_HAND }

## How a kind of animal eats from a hand holding seeds. Every kind that does declares one; `Wildlife` finds the
## hand, keeps one animal to a hand and says where it eats.
class Appetite:
	var eat: Eat
	## How far off it sees the seeds.
	var notice: float
	## How high over the ground or water under it a hand may be for it to reach.
	var reach: float
	## From where it stands to its mouth, along the way it faces.
	var mouth: float
	var eats_for: Vector2
	## How long after eating it comes back for more.
	var full_for: Vector2

	func _init(how: Eat, sees: float, up: float, to_mouth: float, eating: Vector2, full: Vector2) -> void:
		eat = how
		notice = sees
		reach = up
		mouth = to_mouth
		eats_for = eating
		full_for = full


var water: Water
var flora: Flora
var walls: WallTool
var palette: Palette
var viewer: Node3D
var hands: Array[Node3D] = []
## Other players' seed dishes as this game shows them (`Session`): one held out is an offer as a hand here is.
var dishes: Array[Dish] = []
var families: Array[Family] = []
var butterflies: Butterflies
var fireflies: Fireflies
var snails: Snails
var fish: Fish
var birds: Birds
var herds: Herds
var roamers: Roamers
var calls: Calls
var rng := RandomNumberGenerator.new()
## Whether a duck has ever come: conures come only after.
var ducks_came := false
var _due := {}
var _due_butterflies := {}
var _due_birds := {}
var _due_sheep := {}
var _since_look := INF
## Per hand and the head: where it was last tick and how fast it has been moving. A teleport or a snap turn forgets
## where each was, so the cut is no motion to an animal: a player in a small room cannot help teleporting.
var _was := {}
var _speed := {}
var _velocity := {}
## Per hand holding seeds or seeds scattered: whatever is eating from it or on its way to.
var _eaters := {}
var handfuls: Array[Handful] = []
## A duck paddles or waddles over to peck seeds held low over its pond or the bank.
static var duck_appetite := Appetite.new(Eat.UNDER_HAND, 3.5, 0.6, 0.16, Vector2(6.0, 12.0), Vector2(8.0, 20.0))


class Family:
	var ducks: Array[Duck] = []
	var pond: PondWater
	var state := State.ENTER
	var timer := 0.0
	var goal := Vector3.ZERO
	## A wet point of the family's pond, to find it again if the pond's surface is rebuilt.
	var home := Vector3.ZERO
	## Where a flight meets the sky; `flight` runs from 0 there to 1 on the water.
	var sky := Vector3.ZERO
	var flight := 0.0
	var ripple := 0.0
	## The level way out, once leaving.
	var heading := Vector3.ZERO
	## The hand it feeds from, and how long until it eats again.
	var hand: Node3D
	var full := 0.0

	func _init(first: Duck) -> void:
		ducks.append(first)

	func leader() -> Duck:
		return ducks[0]


func _init(ponds: Water, plants: Flora, builds: WallTool, season: Palette, eyes: Node3D, near: Array[Node3D], seed := -1, sky: Look = null) -> void:
	water = ponds
	flora = plants
	walls = builds
	palette = season
	viewer = eyes
	hands = near
	if eyes != null and eyes.get_parent() is Rig:
		eyes.get_parent().jumped.connect(func() -> void: _was.clear())
	Duck.prepare()
	Sheep.prepare()
	Conure.prepare()
	Beast.prepare()
	if seed >= 0:
		rng.seed = seed
	else:
		rng.randomize()
	butterflies = Butterflies.new(self, rng.seed + 1)
	add_child(butterflies)
	fireflies = Fireflies.new(self, sky, rng.seed + 3)
	add_child(fireflies)
	snails = Snails.new(self, rng.seed + 8)
	add_child(snails)
	fish = Fish.new(self, rng.seed + 6)
	add_child(fish)
	birds = Birds.new(self, rng.seed + 2)
	add_child(birds)
	herds = Herds.new(self, rng.seed + 4)
	add_child(herds)
	roamers = Roamers.new(self, rng.seed + 7)
	add_child(roamers)
	calls = Calls.new(eyes, rng.seed + 5)
	add_child(calls)


func ducks() -> Array[Duck]:
	var out: Array[Duck] = []
	for f in families:
		out.append_array(f.ducks)
	return out


func _process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	calls.tick(delta)
	_watch(delta)
	_schedule(delta)
	var room := butterflies.butterflies.size() < Butterflies.CAP
	for key in _ripe(_due_butterflies, butterflies.empty_patches(), BUTTERFLIES_AFTER, delta, room):
		if butterflies.butterflies.size() >= Butterflies.CAP:
			break
		_due_butterflies.erase(key)
		var from := _unseen_direction(butterflies.centre(key), Butterflies.FROM_DISTANCE, Butterflies.FROM_HEIGHT, SIGHT, butterflies.rng)
		butterflies.arrive(key, from)
	butterflies.tick(delta)
	fireflies.tick(delta)
	fish.tick(delta)
	snails.tick(delta)
	_since_look += delta
	if _since_look >= LOOK_EVERY:
		_since_look = 0.0
		birds.look()
		herds.look()
		roamers.look()
	ducks_came = ducks_came or not families.is_empty()
	var perches := [birds] if ducks_came and birds.birds.is_empty() and not birds.sites.is_empty() else []
	if not _ripe(_due_birds, perches, ARRIVE_AFTER, delta, true, birds.rng).is_empty():
		_due_birds.clear()
		birds.arrive()
	birds.tick(delta)
	herds.tick(delta)
	for fence in _ripe(_due_sheep, herds.empty_pastures(), SHEEP_AFTER, delta, herds.count() < Herds.CAP):
		_due_sheep.erase(fence)
		if herds.count() < Herds.CAP:
			herds.arrive(fence)
	roamers.tick(delta)
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


func _schedule(delta: float) -> void:
	var ponds := water.ponds.filter(func(p: PondWater) -> bool: return p.pond.cells.size() >= MIN_POND and _family_at(p) == null)
	var ripe := _ripe(_due, ponds, ARRIVE_AFTER, delta, families.size() < FAMILIES)
	if not ripe.is_empty():
		_due.erase(ripe[0])
		_arrive(ripe[0])


## Starts a wait in `after` for each habitat when it first appears and counts it down; the habitats whose
## wait is over. A habitat that is gone, or taken, forgets its wait; while not `counting`, waits hold still.
## Waits are drawn from `random`.
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
	var chicks := rng.randf() < FAMILY_CHANCE
	var f := Family.new(_spawn(false))
	f.pond = p
	f.home = land
	f.goal = land
	families.append(f)
	if chicks:
		for i in rng.randi_range(DUCKLINGS.x, DUCKLINGS.y):
			f.ducks.append(_spawn(true))
		var reach := sqrt(p.pond.cells.size() / PI) + WALK_FROM
		var away := _unseen_direction(land, reach, 0.0)
		for i in f.ducks.size():
			var at := land + away * (reach + LENGTH * 1.5 * i)
			f.ducks[i].position = Terrain.ground(at.x, at.z)
			_face(f.ducks[i], -away, 1.0)
		f.state = State.ENTER
	else:
		f.goal.y = p.surface_y() - SINK
		f.sky = _unseen_point(land, FLY_DISTANCE, FLY_HEIGHT)
		f.leader().position = f.sky
		_face(f.leader(), land - f.sky, 1.0)
		f.state = State.FLY_IN


func _spawn(chick: bool) -> Duck:
	var d := Duck.new(chick, rng.randf() * 10.0)
	add_child(d)
	return d


func _think(f: Family, delta: float) -> void:
	var lead := f.leader()
	if f.state != State.FLY_OUT and f.state != State.WALK_OUT and not water.ponds.has(f.pond):
		f.pond = _pond_near(f.home)
		if f.pond == null:
			_leave(f)
	if f.state in [State.SWIM, State.ASHORE, State.REST, State.FEED]:
		calls.now_and_then("quack", lead.position, QUACK_EVERY, delta)
		if f.ducks.size() > 1:
			calls.now_and_then("peep", f.ducks[1 + calls.rng.randi() % (f.ducks.size() - 1)].position, PEEP_EVERY, delta)
	f.full = maxf(f.full - delta, 0.0)
	if f.state in [State.SWIM, State.ASHORE, State.REST] and f.full <= 0.0:
		_come_for_seeds(f)
	var eating := false
	match f.state:
		State.FLY_IN, State.FLY_OUT:
			_fly(f, delta)
		State.ENTER, State.ASHORE:
			if _go(lead, f.goal, delta):
				if f.state == State.ENTER:
					calls.call_out("quack", lead.position)
					_swim(f)
				else:
					f.state = State.REST
					f.timer = rng.randf_range(REST_FOR.x, REST_FOR.y)
		State.SWIM:
			f.timer -= delta
			f.ripple -= delta
			if f.ripple <= 0.0 and lead.afloat:
				f.ripple = RIPPLE_EVERY
				f.pond.ripple(Vector3(lead.position.x, f.pond.surface_y(), lead.position.z), 0.3)
			if _go(lead, f.goal, delta):
				var bank := _bank_point(f.pond, lead.position) if f.timer <= 0.0 else Vector3.INF
				if bank != Vector3.INF:
					f.state = State.ASHORE
					f.goal = bank
				else:
					f.goal = _deep_point(f.pond, lead.position)
		State.REST:
			_step(lead, Vector3.ZERO, delta)
			f.timer -= delta
			if f.timer <= 0.0:
				_swim(f)
		State.WALK_OUT:
			if _go(lead, f.goal, delta):
				f.goal = _onward(f.goal, f.heading)
		State.FEED:
			eating = _eat(f, delta)
	for d in f.ducks:
		d.peck(1.0 if eating else 0.0, delta)


## A duck that sees seeds held low over its pond or its bank heads over to them, its ducklings after it.
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


## Whether a duck of `f` can get to `spot` from where it is: on its pond or the bank, by water no wall cuts off.
func _reaches(f: Family, spot: Vector3) -> bool:
	return _pond_near(spot) == f.pond and _swims_clear(f.leader().position, Vector2(spot.x, spot.z))


## Over to the hand and pecking under it while it is held out calmly; true while pecking. A hand snatched
## away or put down, or the seeds eaten, sends the family back to swimming.
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


## A lone duck flies off, back along its way in if it had not yet landed; a family walks away.
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
		f.heading = _unseen_direction(at, WALK_AWAY, 0.0, LEAVE_SIGHT)
		f.goal = _onward(at, f.heading)


## A leaving duck keeps on its way until it is out of sight and some way off.
func _gone(f: Family) -> bool:
	if f.state != State.WALK_OUT and (f.state != State.FLY_OUT or f.flight > 0.0):
		return false
	return f.ducks.all(func(d: Duck) -> bool: return _let_go(d.position, 0.0 if _at_edge(d.position) else GONE))


## Whether a leaving animal at `at` may be let go: FAR off, or out of sight and at least `near` off.
func _let_go(at: Vector3, near: float) -> bool:
	if viewer == null or not viewer.is_inside_tree():
		return true
	var off := at.distance_to(viewer.global_position)
	return off >= FAR or (off >= near and not _in_sight(at, LEAVE_SIGHT))


func _at_edge(at: Vector3) -> bool:
	return maxf(absf(at.x), absf(at.z)) >= EDGE - 0.5


## The first of `hands` within `reach` of `p`, or null.
func _hand_within(p: Vector3, reach: float) -> Node3D:
	for h in hands:
		if h.is_inside_tree() and p.distance_to(h.global_position) < reach:
			return h
	return null


## Eases how fast each hand and the head is moving, and lets go of hands no longer holding seeds out.
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
	var held := offers()
	for h in _eaters.keys():
		if not held.has(h):
			_eaters.erase(h)


## This player's hands and head, and other players' dishes while held out: a dish put away is forgotten, so held out
## again it is no sudden move.
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


## Whether `n` is coming toward `p` faster than a still hand or head drifts.
func approaching(n: Node3D, p: Vector3) -> bool:
	var to := Vector3(p.x - n.global_position.x, 0, p.z - n.global_position.z)
	var v: Vector3 = _velocity.get(n, Vector3.ZERO)
	return to.length() > 1e-3 and Vector3(v.x, 0, v.z).dot(to.normalized()) > STILL


## The first hand, or the head, within `reach` of `p` and moving suddenly, or null.
func _startled(p: Vector3, reach: float) -> Node3D:
	for n in _watched():
		if p.distance_to(n.global_position) < reach and sudden(n):
			return n
	return null


## The nearest hand or head within `reach` of `p`, however it moves, or null.
func _nearest(p: Vector3, reach: float) -> Node3D:
	var best: Node3D = null
	for n in _watched():
		var d := p.distance_to(n.global_position)
		if d < reach:
			reach = d
			best = n
	return best


## The hands holding seeds out, this player's and others', and the seeds lying where they were thrown.
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


## Whether `offer` is seeds held in a hand, this player's or another's, rather than thrown.
static func in_hand(offer: Node3D) -> bool:
	return offer is Hand or offer is Dish


## Conures eating from a dish held out in this player's hand, or with `dish` in another player's.
func feeding(dish: bool) -> int:
	return birds.birds.filter(func(b: Birds.Bird) -> bool: return b.state == Birds.State.FEED and (b.node.hand is Dish if dish else b.node.hand is Hand)).size()


func nibble(offer: Node3D, delta: float) -> void:
	if offer is Handful:
		offer.peck(delta)


## A calm hand holding seeds, or seeds thrown, that an animal at `at` sees and can reach (`fits`, given the offer,
## where the animal has more to say) and that nothing else eats from, or null. A bird eats thrown seeds only off dry
## ground.
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


## Whether hand `h` is still held out with seeds for `eater`.
func feeds(h: Node3D, eater: Object) -> bool:
	return h != null and _eaters.get(h) == eater and offers().has(h)


## Where an animal coming from `from` stands to eat from hand `h`: on the hand as seen, behind the seeds (`ON_HAND`
## in the hand's space), or on the ground or water with its mouth under it.
func eat_spot(appetite: Appetite, h: Node3D, from: Vector3) -> Vector3:
	var seen: Node3D = h.body if h is Hand else h
	if appetite.eat == Eat.ON_HAND and in_hand(h):
		return seen.global_transform * ON_HAND
	var at := seen.global_position
	var off := Vector3(from.x - at.x, 0, from.z - at.z)
	at += off.normalized() * appetite.mouth if off.length() > 1e-3 else Vector3.ZERO
	return Vector3(at.x, water.floor_at(at), at.z)


## WALK_AWAY further along `heading`, kept on the terrain.
func _onward(at: Vector3, heading: Vector3) -> Vector3:
	var to := at + heading * WALK_AWAY
	return Terrain.ground(clampf(to.x, -EDGE, EDGE), clampf(to.z, -EDGE, EDGE))


## Along an arc between `sky` and the water, steep near the sky and flattening to a glide.
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
		calls.call_out("quack", splash)
		_swim(f)


## True once the duck is there.
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


## Moves a duck by `velocity`, stands it on the ground or floats it, and picks its motion from where it is.
func _step(d: Duck, velocity: Vector3, delta: float) -> void:
	d.position += velocity * delta
	var ground := Terrain.height_at(d.position.x, d.position.z)
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
	d.rotation.y = lerp_angle(d.rotation.y, atan2(-dir.x, -dir.z), clampf(weight, 0.0, 1.0))


## Deep enough to float a grown duck, and with `from` reached without paddling into a wall; else the pond's
## bottom, or with `from` where it is.
func _deep_point(p: PondWater, from := Vector3.INF) -> Vector3:
	var cells := p.pond.cells
	for attempt in 12:
		var xz := Terrain.grid_xz(cells[rng.randi() % cells.size()])
		if p.pond.level - Terrain.height_at(xz.x, xz.y) > FLOAT_DEPTH * 2.0 and _swims_clear(from, xz):
			return Vector3(xz.x, p.pond.level, xz.y)
	var b := Terrain.grid_xz(p.pond.bottom) if from == Vector3.INF else Vector2(from.x, from.z)
	return Vector3(b.x, p.pond.level, b.y)


func _swims_clear(from: Vector3, to: Vector2) -> bool:
	if walls == null or from == Vector3.INF:
		return true
	var a := Vector2(from.x, from.z)
	return not walls.walls.any(func(w: Wall) -> bool: return w.layout.blocks_swim(a, to))


## On the grass a little way up the bank from a shore point, reached from `from` without paddling into a wall;
## Vector3.INF where none is, as on a stretch of water a wall cuts off from the banks.
func _bank_point(p: PondWater, from: Vector3) -> Vector3:
	var mid := Terrain.grid_xz(p.pond.bottom)
	for attempt in 12:
		var s := Terrain.grid_xz(p.pond.shore[rng.randi() % p.pond.shore.size()])
		var out := (s - mid).normalized() if s != mid else Vector2.RIGHT
		var at := s + out * rng.randf_range(BANK.x, BANK.y)
		if water.pond_at(at.x, at.y) == null and _swims_clear(from, at):
			return Terrain.ground(at.x, at.y)
	var s := Terrain.grid_xz(p.pond.shore[0])
	return Terrain.ground(s.x, s.y) if _swims_clear(from, s) else Vector3.INF


## Whichever pond is over `at` or within a couple of metres of it.
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
	if viewer == null or not viewer.is_inside_tree():
		return false
	return (at - viewer.global_position).normalized().dot(-viewer.global_basis.z) > cone


## The point `reach` away from `at` along `_unseen_direction`, and `height` up.
func _unseen_point(at: Vector3, reach: float, height: float, cone := SIGHT, random := rng) -> Vector3:
	return at + _unseen_direction(at, reach, height, cone, random) * reach + Vector3.UP * height


## A level direction from `at` along which the point `reach` away and `height` up is outside `cone`, else
## the one of those tried furthest from the gaze.
func _unseen_direction(at: Vector3, reach: float, height: float, cone := SIGHT, random := rng) -> Vector3:
	var best := Vector3.FORWARD
	var best_dot := INF
	for attempt in 12:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, random.randf() * TAU)
		var to := at + dir * reach + Vector3.UP * height
		if not _in_sight(to, cone):
			return dir
		var dot := (to - viewer.global_position).normalized().dot(-viewer.global_basis.z)
		if dot < best_dot:
			best_dot = dot
			best = dir
	return best
