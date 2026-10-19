extends SceneTree

## Headless checks of wildlife: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_wildlife.gd

const STEP := 1.0 / 30.0

var failures := 0
var feed: FeedTool


func _initialize() -> void:
	_no_tool_places_an_animal()
	await _teleport_is_no_motion()
	await _ducks_come_only_to_ponds()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


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
	_check(f.state == Wildlife.State.FEED and absf(off - Wildlife.duck_appetite.mouth) < 0.05, "a duck comes under the hand, its bill %.2f m from under it" % off)
	_check(f.ducks.all(func(d: Duck) -> bool: return d.pecking > 0.5), "and pecks there, the ducklings with it")
	var steps := 4
	for i in steps:
		hand.global_position = at + Vector3(0, 0.12 * (i + 1), 0)
		_run(wildlife, STEP)
	_check(f.state != Wildlife.State.FEED and f.full > 0.0, "a jerk of the hand sends them back to swimming")
	_run(wildlife, 2.0)
	_check(f.state != Wildlife.State.FEED, "fed, they come back only later")
	hand.tool = Hand.Tool.WALLS
	hand.held_still = false
	wildlife.hands.clear()


## A handful thrown out over the pond scatters on the water, and the ducks come and peck it up grain by grain.
func _seeds_thrown_on_the_pond_are_eaten(wildlife: Wildlife, pond: PondWater) -> void:
	var f: Wildlife.Family = wildlife.families[0]
	f.full = 0.0
	var mid := Terrain.grid_xz(pond.pond.bottom)
	var s := feed.throw(Vector3(mid.x, pond.surface_y() + 1.2, mid.y), Vector3(0.3, 0.5, 0))
	_run(wildlife, 1.5)
	_check(s.landed() and absf(s.position.y - pond.surface_y()) < 0.01, "thrown seeds come down on the water")
	_check(_spread(s) > 0.1, "and scatter, %.2f m across" % _spread(s))
	var ate := [false]
	_run(wildlife, 40.0, func() -> void: ate[0] = ate[0] or (f.state == Wildlife.State.FEED and f.hand == s and s.left() < Handful.GRAINS))
	_check(ate[0], "a duck comes and pecks them up, %d grains left" % s.left())
	_run(wildlife, Handful.LASTS.y + 2.0)
	_check(s.left() == 0 and not wildlife.offers().has(s) and f.state != Wildlife.State.FEED, "eaten or faded, they are gone and the ducks swim again")


## Seeds thrown on grass nothing eats sink away after a while.
func _seeds_thrown_on_the_grass_fade(wildlife: Wildlife) -> void:
	var at := Terrain.ground(14.0, -14.0)
	var s := feed.throw(at + Vector3(0, 1.0, 0), Vector3(1.5, 1.0, 0))
	_run(wildlife, 1.5)
	_check(s.landed() and absf(s.position.y - Terrain.height_at(s.position.x, s.position.z)) < 0.01, "seeds thrown on grass lie on the ground")
	_check(s.position.x > at.x + 0.5, "carried the way they were thrown, %.2f m" % (s.position.x - at.x))
	_run(wildlife, s.lasts - 3.5)
	_check(wildlife.offers().has(s) and s.left() == Handful.GRAINS, "uneaten, they lie a while")
	_run(wildlife, 4.0)
	_check(not wildlife.offers().has(s) and not s.visible, "then sink away")
	var many: Array[Handful] = []
	for i in FeedTool.HANDFULS + 1:
		many.append(feed.throw(at + Vector3(0, 1.0, 0), Vector3.ZERO))
	_run(wildlife, 1.5)
	_check(wildlife.offers().size() == FeedTool.HANDFULS and many[0] == many[-1], "only the latest %d handfuls lie about" % FeedTool.HANDFULS)
	_run(wildlife, Handful.LASTS.y + 2.0)
	_check(wildlife.offers().is_empty(), "and they all sink away")


func _spread(s: Handful) -> float:
	var lo := Vector2.INF
	var hi := -Vector2.INF
	for p in s._at:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	return (hi - lo).length()


## No hand tool, no scripted step and nothing but the game's root reaches an animal; Wildlife offers no way
## to add one.
func _no_tool_places_an_animal() -> void:
	for key in Hand.Tool.keys():
		_check(not key in ["DUCK", "DUCKS", "ANIMAL", "ANIMALS", "WILDLIFE"], "no hand tool %s" % key)
	for f in DirAccess.get_files_at("res://src"):
		if f.ends_with("_tool.gd") or f in ["hand.gd", "driver.gd", "buttons.gd"]:
			var code := FileAccess.get_file_as_string("res://src/" + f)
			_check(not code.contains("Duck") and not code.contains("ildlife"), "%s reaches no animal" % f)
	_check(FileAccess.get_file_as_string("res://src/main.gd").count("Wildlife.new(") == 1, "main makes one Wildlife")
	for m in (load("res://src/wildlife.gd") as Script).get_script_method_list():
		_check(m.name.begins_with("_") or m.name in ["tick", "ducks", "sudden", "still", "approaching", "offers", "offer_for", "claim", "release", "feeds", "eat_spot", "nibble"], "Wildlife exposes no way to add an animal, found %s" % m.name)


## A teleport or a snap turn moves the head and hands across the garden in a frame; no animal takes that for a
## sudden move or an approach. A hand swung out, or a flat player walking up, still is one.
func _teleport_is_no_motion() -> void:
	Terrain.install()
	var rig := Rig.new()
	root.add_child(rig)
	var water := Water.new([])
	root.add_child(water)
	var flora := Flora.new()
	root.add_child(flora)
	var watched: Array[Node3D] = []
	watched.assign(rig.hands)
	var wildlife := Wildlife.new(water, flora, null, Palette.new(), rig.head, watched, 1)
	root.add_child(wildlife)
	wildlife.set_process(false)
	await process_frame
	rig.right.position = Vector3(0.3, 1.2, -0.4)
	_run(wildlife, 1.0)
	var ahead := Vector3(0, 0, -12)
	rig.teleport(Terrain.ground(0, -6), 0.0)
	rig._fade_step(Rig.FADE)
	wildlife.tick(STEP)
	rig.snap_turn(Rig.SNAP)
	wildlife.tick(STEP)
	for n: Node3D in [rig.head, rig.right]:
		_check(not wildlife.sudden(n) and not wildlife.approaching(n, ahead), "a teleport and a snap turn startle nothing, %s at %.2f m/s" % [n.name, wildlife._speed[n]])
	for i in 4:
		rig.right.position += Vector3(0, 0, -0.12)
		wildlife.tick(STEP)
	var toward := rig.right.global_position + rig.global_basis * Vector3(0, 0, -5)
	_check(wildlife.sudden(rig.right) and wildlife.approaching(rig.right, toward), "a hand swung out still does, at %.2f m/s" % wildlife._speed[rig.right])
	_run(wildlife, 1.0)
	var flat := Flat.new(rig)
	var deer := rig.head.global_position + Vector3(0, 0, -8)
	for i in int(1.0 / STEP):
		var to := deer - rig.head.global_position
		flat._walk(Vector3(to.x, 0, to.z).normalized() * Flat.WALK * STEP)
		wildlife.tick(STEP)
	_check(wildlife.approaching(rig.head, deer) and wildlife.sudden(rig.head), "a flat player walking up to a deer still comes at it, at %.2f m/s" % wildlife._speed[rig.head])
	for n: Node in [flat, wildlife, flora, water, rig]:
		n.free()


## Presses a hollow at x, z as a grip does, then fills it to the brim with the pond tool pointed at its rim.
func _dig(tool: WaterTool, x: float, z: float, frames: int) -> void:
	var depth := clampf(0.7 * frames / 60.0, 0.45, 1.3)
	var hand := tool.world.ground_grab.rig.right
	tool.world.ground_grab.begin(hand, Terrain.ground(x, z), 2.8)
	tool.world.ground_grab.pull(hand, -depth)
	tool.world.ground_grab.end_stroke(hand)
	tool.fill(hand, Terrain.ground(x + maxf(2.8, depth * GroundGrab.SPREAD), z))
	await process_frame
	await process_frame


func _from_shore(p: PondWater, at: Vector3) -> float:
	var best := INF
	for g in p.pond.shore:
		best = minf(best, Terrain.grid_xz(g).distance_to(Vector2(at.x, at.z)))
	return best


## Every duck that disappears was out of the viewer's sight in its last frame.
func _watch_vanishing(wildlife: Wildlife, seen: Dictionary) -> Callable:
	return func() -> void:
		var now := {}
		for d in wildlife.ducks():
			now[d] = wildlife._in_sight(d.position)
		for d in seen:
			if not now.has(d) and seen[d]:
				_check(false, "a duck vanished in sight")
		seen.clear()
		seen.merge(now)


func _ducks_come_only_to_ponds() -> void:
	Terrain.install()
	var rig := Rig.new()
	root.add_child(rig)
	var world := World.new()
	root.add_child(world)
	var terrain := GroundGrab.new(rig, world)
	root.add_child(terrain)
	var water := Water.new([])
	root.add_child(water)
	var tool := WaterTool.new(rig, world)
	root.add_child(tool)
	world.attach(null, null, null, terrain, water)
	var flora := Flora.new()
	root.add_child(flora)
	var no_hands: Array[Node3D] = []
	await process_frame
	var wildlife := Wildlife.new(water, flora, null, Palette.new(), rig.head, no_hands, 1)
	root.add_child(wildlife)
	wildlife.set_process(false)

	_run(wildlife, 600.0)
	_check(wildlife.ducks().is_empty(), "a meadow without a pond draws no ducks")

	await _dig(tool, 3, -4, 90)
	await _dig(tool, 4.5, -4, 90)
	_check(water.ponds.size() == 1 and water.ponds[0].pond.cells.size() >= Wildlife.MIN_POND, "a dug pond, %d wet points" % (water.ponds[0].pond.cells.size() if water.ponds.size() else 0))
	var pond := water.ponds[0]
	pond._process(PondWater.FILL)
	_check(rig.head.global_position.direction_to(Vector3(3.75, pond.surface_y(), -4)).dot(-rig.head.global_basis.z) > Wildlife.SIGHT, "the viewer looks at the pond")
	var seen := {}
	var vanishing := _watch_vanishing(wildlife, seen)
	var arrived := [false]
	var first_sight := func() -> void:
		vanishing.call()
		for d in wildlife.ducks():
			if not arrived[0]:
				_check(not wildlife._in_sight(d.position), "a duck first appears out of sight")
		arrived[0] = arrived[0] or not wildlife.ducks().is_empty()
	_run(wildlife, Wildlife.ARRIVE_AFTER.x - 1.0, first_sight)
	_check(wildlife.ducks().is_empty(), "no duck before its time")
	_run(wildlife, Wildlife.ARRIVE_AFTER.y - Wildlife.ARRIVE_AFTER.x + 2.0, first_sight)
	_check(wildlife.families.size() == 1, "a duck comes to the pond some time after it appears")

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
	_check(wildlife.families.size() == 1 and states.has(Wildlife.State.SWIM) and states.has(Wildlife.State.REST), "it swims, then rests on the bank, states %s" % [states.keys()])
	_check(worst[2] == 0 and worst[0] <= Wildlife.BANK.y + 0.75, "it rests on dry grass near the water, at most %.2f m from the shore" % worst[0])
	_check(worst[1] < 0.02, "afloat, each duck sits at the waterline, off by %.3f" % worst[1])

	var flier := Wildlife.new(water, flora, null, Palette.new(), rig.head, no_hands, 0)
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
	_check(lone != null, "a lone duck flies in")
	var high := lone.position.y - pond.surface_y()
	_run(flier, 10.0)
	_check(high > 5.0 and flier.families[-1].state == Wildlife.State.SWIM and lone.afloat, "it comes down from %.1f m and settles on the water" % high)
	_seeds_held_low_draw_the_ducks(flier, rig.right, pond)
	flier.families.clear()
	lone.free()
	flier.rng.seed = lone_seed
	flier._arrive(pond)
	var midair := flier.families[-1]
	_check(midair.state == Wildlife.State.FLY_IN, "the same seed flies in again")
	_run(flier, 1.0)
	var low := [midair.leader().position.y, 0.0]
	var walker := Wildlife.new(water, flora, null, Palette.new(), rig.head, no_hands, 0)
	root.add_child(walker)
	walker.set_process(false)
	for seed in 40:
		walker.rng.seed = seed
		walker._arrive(pond)
		if walker.families[-1].ducks.size() > 1:
			break
		walker.families[-1].leader().free()
		walker.families.pop_back()
	_check(walker.families.size() == 1 and walker.families[0].ducks.size() > 2, "a mother walks in with ducklings")
	_run(walker, 90.0)
	_check(walker.families[0].state in [Wildlife.State.SWIM, Wildlife.State.ASHORE, Wildlife.State.REST], "and they reach the water")
	_seeds_held_low_draw_the_ducks(walker, rig.right, pond)
	feed = FeedTool.new(rig, water)
	root.add_child(feed)
	feed.set_process(false)
	walker.handfuls = feed.handfuls
	_seeds_thrown_on_the_pond_are_eaten(walker, pond)
	_seeds_thrown_on_the_grass_fade(walker)

	for step in 4:
		world.undo()
	await process_frame
	await process_frame
	_check(water.ponds.is_empty(), "the pond drains")
	var flying := _watch_vanishing(flier, {})
	flying.call()
	var climbing := func() -> void:
		flying.call()
		if not flier.families.is_empty():
			low[1] = minf(low[1], flier.families[0].leader().position.y - low[0])
			low[0] = flier.families[0].leader().position.y
	_run(flier, 30.0, climbing)
	_check(flier.families.is_empty() and low[1] >= 0.0, "a duck flying in to a drained pond turns back up and away")
	flier.queue_free()
	var walking := _watch_vanishing(walker, {})
	walking.call()
	_run(walker, 400.0, walking)
	_check(walker.families.is_empty(), "a family walks away from a drained pond")
	walker.queue_free()

	_run(wildlife, 400.0, vanishing)
	_check(wildlife.families.is_empty(), "the ducks leave a drained pond")
	_run(wildlife, 300.0)
	_check(wildlife.ducks().is_empty(), "and none come back without water")
