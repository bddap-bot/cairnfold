extends "res://../tests/support/suite.gd"

## Headless checks of wildlife: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_wildlife.gd

const GladeBase = preload("res://../tests/support/glade.gd")
const STEP := 1.0 / 30.0
## What no tool may place: [the animal, what no hand tool's name begins with, what no tool's source may name, whether the
## driver's source is held to that too, the one file that makes it, how it makes it].
const UNPLACEABLE := [
	["animal", ["DUCK", "ANIMAL", "WILDLIFE"], ["Duck", "ildlife"], false, "main.gd", "Wildlife.new("],
	["bird", ["BIRD", "CONURE"], ["Birds", "onure"], false, "wildlife.gd", "Birds.new("],
	["sheep", ["SHEEP", "HERD"], ["Sheep", "Herds"], true, "wildlife.gd", "Herds.new("],
	["butterfly", ["BUTTERFL"], ["utterfl"], true, "wildlife.gd", "Butterflies.new("],
	["firefly", ["FIREFL"], ["irefl"], true, "wildlife.gd", "Fireflies.new("],
	["fish", [], ["Fish"], true, "wildlife.gd", "Fish.new("],
	["deer or fox", [], ["Beast", "Roamers"], false, "wildlife.gd", "Roamers.new("],
]

var feed: FeedTool


func _initialize() -> void:
	_no_tool_places_an_animal()
	await _teleport_is_no_motion()
	await _ducks_come_only_to_ponds()
	await _ducks_keep_out_of_walls()
	finish()


func _run(wildlife: Wildlife, seconds: float, each := Callable()) -> void:
	var t := 0.0
	while t < seconds:
		wildlife.tick(STEP)
		if feed != null:
			feed.tick(STEP)
		if each.is_valid():
			each.call()
		t += STEP


## Seeds held low over the pond: the mother swims over and pecks under the hand, the ducklings pecking with her;
## a jerk of the hand sends them back to swimming, and nobody comes again for a while.
func _seeds_held_low_draw_the_ducks(wildlife: Wildlife, hand: Hand, pond: PondWater) -> void:
	var f: Wildlife.Family = wildlife.families[0]
	var mid := Terrain.grid_xz(pond.pond.bottom)
	var at := Vector3(mid.x, pond.surface_y() + 0.3, mid.y)
	hand.global_position = at
	hand.held_still = true
	hand.tool = Hand.Tool.SEEDS
	wildlife.hands.assign([hand])
	var pecked := [0.0]
	for i in int(40.0 / STEP):
		_run(wildlife, STEP)
		pecked[0] = maxf(pecked[0], f.leader().pecking)
		if f.leader().pecking >= 1.0:
			break
	var lead := f.leader()
	var off := Vector2(lead.position.x - at.x, lead.position.z - at.z).length()
	check(f.state == Wildlife.State.FEED and absf(off - Wildlife.duck_appetite.mouth) < 0.05, "a duck comes under the hand, its bill %.2f m from under it" % off)
	check(f.ducks.all(func(d: Duck) -> bool: return d.pecking > 0.5), "and pecks there, the ducklings with it")
	var steps := 4
	for i in steps:
		hand.global_position = at + Vector3(0, 0.12 * (i + 1), 0)
		_run(wildlife, STEP)
	check(f.state != Wildlife.State.FEED and f.full > 0.0, "a jerk of the hand sends them back to swimming")
	_run(wildlife, 2.0)
	check(f.state != Wildlife.State.FEED, "fed, they come back only later")
	hand.tool = Hand.Tool.WALLS
	hand.held_still = false
	wildlife.hands.clear()


## A family at its pond quacks about once a minute or more, and goes on quacking while it eats
## from a hand held over the water by someone kneeling at the bank.
func _ducks_are_heard(wildlife: Wildlife, rig: Rig, pond: PondWater) -> void:
	var f: Wildlife.Family = wildlife.families[0]
	var quacks := func() -> int: return wildlife.calls.played.get("quack", [0])[0]
	var before: int = quacks.call()
	_run(wildlife, 1800.0)
	var heard: int = quacks.call() - before
	check(heard >= 1800.0 / 60.0, "a family at its pond quacked %d times in half an hour" % heard)
	var mid := Terrain.grid_xz(pond.pond.bottom)
	var at := Vector3(mid.x, pond.surface_y() + 0.3, mid.y)
	var eyes := rig.head.global_position
	rig.head.global_position = at + Vector3(0.6, 0.6, 0)
	f.full = 0.0
	rig.right.global_position = at
	rig.right.held_still = true
	rig.right.tool = Hand.Tool.SEEDS
	wildlife.hands.assign([rig.right])
	var near := [0, 0.0]
	for i in int(240.0 / STEP):
		var was: int = quacks.call()
		_run(wildlife, STEP)
		if f.state == Wildlife.State.FEED:
			near[1] += STEP
			near[0] += quacks.call() - was
		elif f.full <= 0.0:
			continue
		else:
			f.full = 0.0
	check(near[1] > 60.0 and wildlife.calls.calm(f.leader().position), "the family ate from the hand beside the head for %.0f s" % near[1])
	check(near[0] >= 1, "and quacked %d times while eating there" % near[0])
	rig.right.tool = Hand.Tool.WALLS
	rig.right.held_still = false
	wildlife.hands.clear()
	rig.head.global_position = eyes
	_run(wildlife, 2.0)


## A handful thrown out over the pond plunges in, spreads apart under the water, rises slowly and bobs on the surface,
## and the ducks come and peck it up grain by grain.
func _seeds_thrown_on_the_pond_are_eaten(wildlife: Wildlife, pond: PondWater) -> void:
	var f: Wildlife.Family = wildlife.families[0]
	f.full = 0.0
	var mid := Terrain.grid_xz(pond.pond.bottom)
	var s := feed.throw(Vector3(mid.x, pond.surface_y() + 1.2, mid.y), Vector3(0.3, 0.5, 0))
	var deep := [0.0, 0.0]
	_run(wildlife, 1.0, func() -> void:
		var now := s.grains()
		for i in now.size():
			deep[0] = maxf(deep[0], pond.surface_y() - now[i].y)
			if now[i].y < pond.surface_y() - 0.02:
				deep[1] = maxf(deep[1], s._vel[i].y))
	var under := _spread(s)
	check(deep[0] > 0.1 and not s.landed(), "thrown seeds plunge into the water, %.2f m under" % deep[0])
	_run(wildlife, 8.0, func() -> void:
		var now := s.grains()
		for i in now.size():
			if now[i].y < pond.surface_y() - 0.02:
				deep[1] = maxf(deep[1], s._vel[i].y))
	check(deep[1] > 0.0 and deep[1] < Handful.RISE * 1.1, "rising slowly, %.2f m/s at most" % deep[1])
	var off := 0.0
	for p in s.grains():
		off = maxf(off, absf(p.y - pond.surface_y()))
	check(s.landed() and s.left() > 0 and off < 0.01, "to float on the surface, %d still under, %.3f m off it at most" % [s.flying, off])
	check(under > 0.3 and _spread(s) >= under, "spread apart under it, %.2f m across" % under)
	var heights := range(s.left()).map(func(i: int) -> float: return s.drawn(i).y)
	_run(wildlife, 0.5)
	var bob := 0.0
	for i in s.left():
		bob = maxf(bob, absf(s.drawn(i).y - heights[i]))
	check(bob > 1e-4 and bob <= 2.0 * Handful.BOB, "bobbing there, %.4f m in half a second" % bob)
	var ate := [false]
	_run(wildlife, 40.0, func() -> void: ate[0] = ate[0] or (f.state == Wildlife.State.FEED and f.hand == s and s.left() < Handful.GRAINS))
	check(ate[0], "a duck comes and pecks them up, %d grains left" % s.left())
	_run(wildlife, Handful.LASTS.y + 2.0)
	check(s.left() == 0 and not wildlife.offers().has(s) and f.state != Wildlife.State.FEED, "eaten or faded, they are gone and the ducks swim again")


## Seeds thrown on grass nothing eats sink away after a while: the deer and sheep about are kept full meanwhile.
func _seeds_thrown_on_the_grass_fade(wildlife: Wildlife) -> void:
	var grazing := wildlife.roamers.all() + wildlife.herds.all()
	for a in grazing:
		a.full = INF
	var at := wildlife.terrain.ground(14.0, -14.0)
	var s := feed.throw(at + Vector3(0, 1.0, 0), Vector3(1.5, 1.0, 0))
	_run(wildlife, 1.5)
	check(s.landed() and absf(s.position.y - wildlife.terrain.height_at(s.position.x, s.position.z)) < 0.01, "seeds thrown on grass lie on the ground")
	check(s.position.x > at.x + 0.5, "carried the way they were thrown, %.2f m" % (s.position.x - at.x))
	_run(wildlife, s.lasts - 3.5)
	check(wildlife.offers().has(s) and s.left() == Handful.GRAINS, "uneaten, they lie a while")
	_run(wildlife, 4.0)
	check(not wildlife.offers().has(s) and not s.visible, "then sink away")
	for a in grazing:
		a.full = 0.0
	var many: Array[Handful] = []
	for i in FeedTool.HANDFULS + 1:
		many.append(feed.throw(at + Vector3(0, 1.0, 0), Vector3.ZERO))
	_run(wildlife, 1.5)
	check(wildlife.offers().size() == FeedTool.HANDFULS and many[0] == many[-1], "only the latest %d handfuls lie about" % FeedTool.HANDFULS)
	_run(wildlife, Handful.LASTS.y + 2.0)
	check(wildlife.offers().is_empty(), "and they all sink away")


func _spread(s: Handful) -> float:
	var lo := Vector2.INF
	var hi := -Vector2.INF
	for p in s._at:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	return (hi - lo).length()


## Tools do not place animals; Wildlife offers no public spawning entry point.
func _no_tool_places_an_animal() -> void:
	for row: Array in UNPLACEABLE:
		var what: String = row[0]
		for key: String in Hand.Tool.keys():
			for prefix: String in row[1]:
				check(not key.begins_with(prefix), "no hand tool %s" % key)
		for f in DirAccess.get_files_at("res://src"):
			if f.ends_with("_tool.gd") or f in ["hand.gd", "buttons.gd"] or (row[3] and f == "driver.gd"):
				var code := FileAccess.get_file_as_string("res://src/" + f)
				for part: String in row[2]:
					check(not code.contains(part), "%s reaches no %s" % [f, what])
		check(FileAccess.get_file_as_string("res://src/" + row[4]).count(row[5]) == 1, "%s alone makes the %s" % [row[4], what])
	for m in (load("res://src/wildlife.gd") as Script).get_script_method_list():
		check(m.name.begins_with("_") or m.name in ["tick", "ducks", "sudden", "still", "approaching", "offers", "offer_for", "claim", "release", "feeds", "eat_spot", "nibble", "in_hand", "feeding", "standable", "clear_way", "night", "asleep"], "Wildlife exposes no way to add an animal, found %s" % m.name)


## A teleport or a snap turn moves the head and hands across the garden in a frame; no animal takes that for a
## sudden move or an approach. A hand swung out, or a flat player walking up, still is one.
func _teleport_is_no_motion() -> void:
	var terrain := Terrain.new()
	var marks := Ground.new()
	terrain.install()
	var rig := Rig.new(terrain)
	root.add_child(rig)
	var water := Water.new(terrain, [])
	root.add_child(water)
	var flora := Flora.new(terrain, marks)
	root.add_child(flora)
	var watched: Array[Node3D] = []
	watched.assign(rig.hands)
	var wildlife := Wildlife.new(terrain, marks, water, flora, null, Palette.new(), rig.head, watched, 1)
	root.add_child(wildlife)
	wildlife.set_process(false)
	await process_frame
	rig.right.position = Vector3(0.3, 1.2, -0.4)
	_run(wildlife, 1.0)
	var ahead := Vector3(0, 0, -12)
	rig.teleport(terrain.ground(0, -6), 0.0)
	rig._fade_step(Rig.FADE)
	wildlife.tick(STEP)
	rig.snap_turn(Rig.SNAP, rig.right)
	wildlife.tick(STEP)
	for n: Node3D in [rig.head, rig.right]:
		check(not wildlife.sudden(n) and not wildlife.approaching(n, ahead), "a teleport and a snap turn startle nothing, %s at %.2f m/s" % [n.name, wildlife._speed[n]])
	for i in 4:
		rig.right.position += Vector3(0, 0, -0.12)
		wildlife.tick(STEP)
	var toward := rig.right.global_position + rig.global_basis * Vector3(0, 0, -5)
	check(wildlife.sudden(rig.right) and wildlife.approaching(rig.right, toward), "a hand swung out still does, at %.2f m/s" % wildlife._speed[rig.right])
	_run(wildlife, 1.0)
	var flat := Flat.new(rig)
	var deer := rig.head.global_position + Vector3(0, 0, -8)
	for i in int(1.0 / STEP):
		var to := deer - rig.head.global_position
		flat._walk(Vector3(to.x, 0, to.z).normalized() * Flat.WALK * STEP)
		wildlife.tick(STEP)
	check(wildlife.approaching(rig.head, deer) and wildlife.sudden(rig.head), "a flat player walking up to a deer still comes at it, at %.2f m/s" % wildlife._speed[rig.head])
	for n: Node in [flat, wildlife, flora, water, rig]:
		n.free()


func _from_shore(p: PondWater, at: Vector3) -> float:
	var best := INF
	for g in p.pond.shore:
		best = minf(best, Terrain.grid_xz(g).distance_to(Vector2(at.x, at.z)))
	return best


func _ducks_come_only_to_ponds() -> void:
	var world := World.new()
	world.terrain.install()
	var rig := Rig.new(world.terrain)
	root.add_child(rig)
	root.add_child(world)
	var grab := GroundGrab.new(rig, world)
	root.add_child(grab)
	var water := Water.new(world.terrain, [])
	root.add_child(water)
	var tool := WaterTool.new(rig, world)
	root.add_child(tool)
	world.attach(null, null, null, grab, water)
	var flora := Flora.new(world.terrain, world.marks)
	root.add_child(flora)
	var no_hands: Array[Node3D] = []
	await process_frame
	var wildlife := Wildlife.new(world.terrain, world.marks, water, flora, null, Palette.new(), rig.head, no_hands, 1)
	root.add_child(wildlife)
	wildlife.set_process(false)

	_run(wildlife, 600.0)
	check(wildlife.ducks().is_empty(), "a meadow without a pond draws no ducks")

	await GladeBase.dig(tool, 3, -4, 90)
	await GladeBase.dig(tool, 4.5, -4, 90)
	check(water.ponds.size() == 1 and water.ponds[0].pond.cells.size() >= Wildlife.MIN_POND, "a dug pond, %d wet points" % (water.ponds[0].pond.cells.size() if water.ponds.size() else 0))
	var pond := water.ponds[0]
	pond._process(PondWater.FILL)
	check(rig.head.global_position.direction_to(Vector3(3.75, pond.surface_y(), -4)).dot(-rig.head.global_basis.z) > Wildlife.SIGHT, "the viewer looks at the pond")
	var vanishing := GladeBase.watch_vanishing(self, wildlife, wildlife.ducks, "duck")
	var arrived := [false]
	var first_sight := func() -> void:
		vanishing.call()
		for d in wildlife.ducks():
			if not arrived[0]:
				check(not wildlife._in_sight(d.position), "a duck first appears out of sight")
		arrived[0] = arrived[0] or not wildlife.ducks().is_empty()
	_run(wildlife, Wildlife.ARRIVE_AFTER.x - 1.0, first_sight)
	check(wildlife.ducks().is_empty(), "no duck before its time")
	_run(wildlife, Wildlife.ARRIVE_AFTER.y - Wildlife.ARRIVE_AFTER.x + 2.0, first_sight)
	check(wildlife.families.size() == 1, "a duck comes to the pond some time after it appears")

	var states := {}
	var worst := [0.0, 0.0, 0]
	var watch := func() -> void:
		vanishing.call()
		for f in wildlife.families:
			states[f.state] = true
			if f.state == Wildlife.State.REST:
				var at := f.leader().position
				worst[0] = maxf(worst[0], _from_shore(pond, at))
				worst[2] += int(water.pond_at(at.x, at.z) != null)
		for d in wildlife.ducks():
			if d.afloat:
				worst[1] = maxf(worst[1], absf(d.position.y - (pond.surface_y() - Wildlife.SINK * d.size)))
	_run(wildlife, 240.0, watch)
	check(wildlife.families.size() == 1 and states.has(Wildlife.State.SWIM) and states.has(Wildlife.State.REST), "it swims, then rests on the bank, states %s" % [states.keys()])
	check(worst[2] == 0 and worst[0] <= Wildlife.BANK.y + 0.75, "it rests on dry grass near the water, at most %.2f m from the shore" % worst[0])
	check(worst[1] < 0.02, "afloat, each duck sits at the waterline, off by %.3f" % worst[1])

	_night_rests_the_day_animals(world, wildlife, water, flora, rig)

	var flier := Wildlife.new(world.terrain, world.marks, water, flora, null, Palette.new(), rig.head, no_hands, 0)
	root.add_child(flier)
	flier.set_process(false)
	var lone: Duck = null
	var lone_seed := 0
	for seed in 40:
		flier.rng.seed = seed
		lone_seed = seed
		flier._arrive(pond)
		if flier.families[-1].ducks.size() == 1:
			lone = flier.families[-1].leader()
			break
		for d in flier.families[-1].ducks:
			d.free()
		flier.families.pop_back()
	check(lone != null, "a lone duck flies in")
	var high := lone.position.y - pond.surface_y()
	_run(flier, 10.0)
	check(high > 5.0 and flier.families[-1].state == Wildlife.State.SWIM and lone.afloat, "it comes down from %.1f m and settles on the water" % high)
	_seeds_held_low_draw_the_ducks(flier, rig.right, pond)
	flier.families.clear()
	lone.free()
	flier.rng.seed = lone_seed
	flier._arrive(pond)
	var midair := flier.families[-1]
	check(midair.state == Wildlife.State.FLY_IN, "the same seed flies in again")
	_run(flier, 1.0)
	var low := [midair.leader().position.y, 0.0]
	var walker := Wildlife.new(world.terrain, world.marks, water, flora, null, Palette.new(), rig.head, no_hands, 0)
	root.add_child(walker)
	walker.set_process(false)
	for seed in 40:
		walker.rng.seed = seed
		walker._arrive(pond)
		if walker.families[-1].ducks.size() > 1:
			break
		walker.families[-1].leader().free()
		walker.families.pop_back()
	check(walker.families.size() == 1 and walker.families[0].ducks.size() > 2, "a mother walks in with ducklings")
	var entered := [Wildlife.State.ENTER, false]
	_run(walker, 90.0, func() -> void:
		var now: Wildlife.State = walker.families[0].state
		entered[1] = entered[1] or (entered[0] == Wildlife.State.ENTER and now == Wildlife.State.SWIM and walker.calls._since["quack"] == 0.0)
		entered[0] = now)
	check(walker.families[0].state in [Wildlife.State.SWIM, Wildlife.State.ASHORE, Wildlife.State.REST], "and they reach the water")
	check(entered[1], "the mother quacks as she takes to the water")
	_seeds_held_low_draw_the_ducks(walker, rig.right, pond)
	feed = FeedTool.new(rig, water, world.terrain)
	root.add_child(feed)
	feed.set_process(false)
	walker.handfuls = feed.handfuls
	_seeds_thrown_on_the_pond_are_eaten(walker, pond)
	_seeds_thrown_on_the_grass_fade(walker)
	_ducks_are_heard(walker, rig, pond)

	for step in 4:
		world.undo()
	await process_frame
	await process_frame
	check(water.ponds.is_empty(), "the pond drains")
	var flying := GladeBase.watch_vanishing(self, flier, flier.ducks, "duck")
	flying.call()
	var climbing := func() -> void:
		flying.call()
		if not flier.families.is_empty():
			low[1] = minf(low[1], flier.families[0].leader().position.y - low[0])
			low[0] = flier.families[0].leader().position.y
	_run(flier, 30.0, climbing)
	check(flier.families.is_empty() and low[1] >= 0.0, "a duck flying in to a drained pond turns back up and away")
	flier.queue_free()
	var walking := GladeBase.watch_vanishing(self, walker, walker.ducks, "duck")
	walking.call()
	_run(walker, 400.0, walking)
	check(walker.families.is_empty(), "a family walks away from a drained pond")
	walker.queue_free()

	_run(wildlife, 400.0, vanishing)
	check(wildlife.families.is_empty(), "the ducks leave a drained pond")
	_run(wildlife, 300.0)
	check(wildlife.ducks().is_empty(), "and none come back without water")


## A fence drawn three quarters of the way round a pond, close along its bank: no duck rests on it or beyond it, a family
## never walks in through it, and one inside never walks out through it; all of them use the open quarter.
func _ducks_keep_out_of_walls() -> void:
	seed(1)
	var g := GladeBase.new()
	await g.build(self, 1)
	g.world.terrain.install()
	var walls := g.walls
	var water := g.water
	var wildlife := g.wildlife
	await GladeBase.dig(g.add_tool(WaterTool.new(g.rig, g.world)), 3, -4, 90)
	var pond := water.ponds[0]
	pond._process(PondWater.FILL)
	var mid := Terrain.grid_xz(pond.pond.bottom)
	var far := 0.0
	for c in pond.pond.shore:
		far = maxf(far, Terrain.grid_xz(c).distance_to(mid))
	var ring := walls._new_wall()
	ring.layout.fence = true
	for i in 37:
		var a := 1.5 * PI * i / 36.0
		ring.layout.points.append(g.world.terrain.ground(mid.x + cos(a) * (far + 0.3), mid.y + sin(a) * (far + 0.3)))
	walls.build([ring])
	await process_frame
	walls.walls[-1].lay_now()
	var line := PackedVector2Array()
	for q in walls.walls[-1].layout.samples:
		line.append(Vector2(q.x, q.z))
	var on_wall := func(at: Vector3) -> bool:
		for i in line.size() - 1:
			if Geometry2D.get_closest_point_to_segment(Vector2(at.x, at.z), line[i], line[i + 1]).distance_to(Vector2(at.x, at.z)) < 0.2:
				return true
		return false
	var through := func(a: Vector3, b: Vector3) -> bool:
		for i in line.size() - 1:
			if Geometry2D.segment_intersects_segment(Vector2(a.x, a.z), Vector2(b.x, b.z), line[i], line[i + 1]) != null:
				return true
		return false
	check(walls.walls.size() == 1 and walls.walls[0].layout.fence, "a fence curves round the pond")
	var from := Vector3(mid.x, pond.surface_y(), mid.y)
	var banks := 0
	var walled := 0
	for i in 200:
		var at := wildlife._bank_point(pond, from)
		if at != Vector3.INF:
			banks += 1
			walled += int(on_wall.call(at) or through.call(from, at))
	check(walled == 0 and banks > 0, "no duck rests on the fence or beyond it, %d of %d bank points" % [walled, banks])
	var crossed := 0
	var families := 0
	for seed in 60:
		wildlife.rng.seed = seed
		var before := wildlife.families.size()
		wildlife._arrive(pond)
		if wildlife.families.size() == before:
			continue
		var f: Wildlife.Family = wildlife.families[-1]
		if f.ducks.size() > 1:
			families += 1
			crossed += int(f.ducks.any(func(d: Duck) -> bool: return through.call(d.position, f.goal)))
		for d in f.ducks:
			d.free()
		wildlife.families.pop_back()
	check(crossed == 0 and families > 0, "no family walks in through the fence, %d of %d" % [crossed, families])
	var out := 0
	var moved := 0
	for seed in 20:
		wildlife.rng.seed = seed
		var f := Wildlife.Family.new(wildlife._spawn(false))
		f.ducks.append(wildlife._spawn(true))
		f.pond = pond
		f.leader().position = g.world.terrain.ground(mid.x, mid.y)
		wildlife.families.append(f)
		wildlife._leave(f)
		out += int(through.call(f.leader().position, f.goal))
		moved += int(f.goal.distance_to(f.leader().position) > 1.0)
		for d in f.ducks:
			d.free()
		wildlife.families.clear()
	check(out == 0 and moved > 0, "nor walks out through it, %d of %d" % [out, moved])
	await g.teardown()


## At night the day's animals rest: a family on the bank stays there and quacks no more, a new pond draws no duck
## until morning, a butterfly stays on its flower and a conure only murmurs.
func _night_rests_the_day_animals(world: World, wildlife: Wildlife, water: Water, flora: Flora, rig: Rig) -> void:
	var look := Look.build(root, world.terrain)
	look.set_time(0.0)
	wildlife.light = look
	_run(wildlife, STEP)
	look.set_time(Daylight.DEFAULT)
	_run(wildlife, STEP)
	check(wildlife.night() == 0.0 and not wildlife.asleep(), "late morning is day")
	look.set_time(0.0)
	_run(wildlife, STEP)
	check(wildlife.night() > 0.99 and wildlife.asleep(), "midnight is night")

	var f: Wildlife.Family = wildlife.families[0]
	var quacks := func() -> int: return wildlife.calls.played.get("quack", [0])[0] + wildlife.calls.played.get("peep", [0])[0]
	_run(wildlife, 120.0)
	var before: int = quacks.call()
	var states := {}
	_run(wildlife, 600.0, func() -> void: states[f.state] = true)
	check(states.keys() == [Wildlife.State.REST], "at night the family rests on the bank, states %s" % [states.keys()])
	check(quacks.call() == before, "and is quiet, %d calls in ten minutes" % (quacks.call() - before))

	var late := Wildlife.new(world.terrain, world.marks, water, flora, null, Palette.new(), rig.head, [] as Array[Node3D], 5, look)
	root.add_child(late)
	late.set_process(false)
	_run(late, Wildlife.ARRIVE_AFTER.y + 5.0)
	check(late.families.is_empty(), "no duck comes to a pond at night")
	look.set_time(Daylight.DEFAULT)
	_run(late, Wildlife.ARRIVE_AFTER.y + 5.0)
	check(late.families.size() == 1, "one comes after morning")
	look.set_time(0.0)
	_run(late, STEP)

	var b := Butterflies.Butterfly.new()
	b.patch = Vector2i(99, 99)
	b.at = Vector3(50, 0, 50)
	b.state = Butterflies.State.PERCH
	b.timer = 1.0
	late.butterflies.patches[b.patch] = PackedVector3Array([b.at])
	late.butterflies._think(b, 5.0)
	check(b.state == Butterflies.State.PERCH and b.timer == 1.0, "a butterfly stays settled at night")
	late.butterflies.patches.erase(b.patch)

	var bird := Birds.Bird.new()
	bird.node = Conure.new(0.0, 0)
	bird.node.position = Vector3(40, 0, 40)
	var heard := {}
	late.calls.played.clear()
	for i in 3000:
		late.calls.tick(1.0)
		late.birds._voice(bird, "PERCH", 1.0)
	for kind in late.calls.played:
		heard[kind] = true
	check(heard.keys() == ["murmur"], "a roosting conure only murmurs, heard %s" % [heard.keys()])
	bird.state = Birds.State.PERCH
	bird.full = INF
	var roost := bird.node.position
	var stirred := [false]
	for i in 3000:
		late.birds._think(bird, 0.2)
		stirred[0] = stirred[0] or bird.state != Birds.State.PERCH or bird.preening > 0.0 or bird.node.position != roost
	check(not stirred[0], "and stays on its roost, neither hopping, preening nor flying")
	bird.node.free()
	late.queue_free()
	wildlife.light = null
	look.queue_free()
