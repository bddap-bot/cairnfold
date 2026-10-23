extends "res://../tests/support/suite.gd"

## Headless checks of the deer and the fox: godot4 --headless --path game --script ../tests/test_roamers.gd

const STEP := 1.0 / 30.0
const AWAY := Vector3(0, -50, 0)


func _initialize() -> void:
	seed(1)
	Terrain.install()
	Ground.install()
	await process_frame
	_no_tool_places_a_deer_or_a_fox()
	_each_is_one_draw_call()
	await _a_fox_and_a_doe_stand_true_to_life()
	await _deer_then_a_fox_come_out_of_sight()
	await _a_sudden_move_sends_a_deer_off_and_stillness_lets_it_near()
	await _food_held_still_draws_one_to_eat()
	await _a_wall_drawn_under_one_moves_it()
	await _thrown_seeds_draw_them_to_eat()
	await _they_leave_out_of_sight_and_come_again()
	finish()


class Glade:
	var rig: Rig
	var world: World
	var walls: WallTool
	var water: Water
	var flora: Flora
	var paths: Paths
	var terrain: GroundGrab
	var wildlife: Wildlife
	var feed: FeedTool

	func beasts(kind: Beast.Kind) -> Array[Beast]:
		var out: Array[Beast] = []
		out.assign(wildlife.roamers.all().filter(func(b: Beast) -> bool: return b.kind == kind))
		return out


func _glade(seed: int) -> Glade:
	var g := Glade.new()
	g.rig = Rig.new()
	root.add_child(g.rig)
	g.world = World.new()
	root.add_child(g.world)
	g.paths = Paths.new()
	root.add_child(g.paths)
	g.flora = Flora.new()
	root.add_child(g.flora)
	g.flora.keep()
	g.walls = WallTool.new(g.rig, g.world, g.flora, g.paths)
	root.add_child(g.walls)
	g.walls.set_process(false)
	g.terrain = GroundGrab.new(g.rig, g.world)
	g.terrain.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(g.terrain)
	g.water = Water.new([])
	root.add_child(g.water)
	g.world.attach(g.walls, g.flora, g.paths, g.terrain, g.water)
	var hands: Array[Node3D] = []
	hands.assign(g.rig.hands)
	await process_frame
	g.wildlife = Wildlife.new(g.water, g.flora, g.walls, Palette.new(), g.rig.head, hands, seed)
	root.add_child(g.wildlife)
	g.wildlife.set_process(false)
	g.feed = FeedTool.new(g.rig, g.water)
	root.add_child(g.feed)
	g.feed.set_process(false)
	g.feed.rng.seed = seed
	g.wildlife.handfuls = g.feed.handfuls
	for h in g.rig.hands:
		h.global_position = AWAY
	return g


func _teardown(g: Glade) -> void:
	g.wildlife.free()
	for w in g.walls.walls:
		w.free()
	for n: Node in [g.feed, g.terrain, g.water, g.walls, g.flora, g.paths, g.world, g.rig]:
		n.queue_free()
	await process_frame


func _run(g: Glade, seconds: float, each := Callable()) -> void:
	for i in int(seconds / STEP):
		g.wildlife.tick(STEP)
		g.feed.tick(STEP)
		for a in g.wildlife.roamers.all():
			if Wildlife.in_hand(a.hand):
				a.player.advance(STEP)
				a._process(STEP)
				a.neck._process_modification()
		if each.is_valid():
			each.call()


## Every animal that disappears was out of the viewer's sight in its last frame, and none stands where it may not.
func _watch(g: Glade, seen: Dictionary) -> Callable:
	return func() -> void:
		var now := {}
		for b in g.wildlife.roamers.all():
			now[b] = g.wildlife._in_sight(b.position)
			if b.state != Grazers.State.ENTER and b.state != Grazers.State.LEAVE and not g.wildlife.roamers.allowed(b.position):
				check(false, "a %s stands where it may not, %s" % [Beast.Kind.keys()[b.kind], b.position])
		for b in seen:
			if not now.has(b) and seen[b]:
				check(false, "an animal vanished in sight")
		seen.clear()
		seen.merge(now)


func _arrived(g: Glade) -> void:
	for i in int(Roamers.FIRST[Beast.Kind.FOX].y / STEP) + 1:
		g.wildlife.tick(STEP)
		if not g.beasts(Beast.Kind.FOX).is_empty() and not g.beasts(Beast.Kind.DEER).is_empty():
			break
	_settle(g.wildlife.roamers.all())


func _settle(beasts: Array) -> void:
	for b in beasts:
		b.goal = b.position
		b.state = Grazers.State.GRAZE
		b.timer = 30.0


## Walks the head toward `to` at `speed` until within `stop` of it, ticking as it goes; false if `a` ran meanwhile.
func _walk_up(g: Glade, a: Beast, speed: float, stop: float) -> bool:
	var head := g.rig.head
	while Vector2(head.global_position.x - a.position.x, head.global_position.z - a.position.z).length() > stop:
		var to := Vector3(a.position.x - head.global_position.x, 0, a.position.z - head.global_position.z).normalized()
		head.global_position += to * speed * STEP
		head.global_position.y = Terrain.height_at(head.global_position.x, head.global_position.z) + 1.6
		_run(g, STEP)
		if a.state == Grazers.State.FLEE:
			return false
	return true


func _no_tool_places_a_deer_or_a_fox() -> void:
	for f in DirAccess.get_files_at("res://src"):
		if f.ends_with("_tool.gd") or f in ["hand.gd", "buttons.gd"]:
			var code := FileAccess.get_file_as_string("res://src/" + f)
			check(not code.contains("Beast") and not code.contains("Roamers"), "%s reaches no deer or fox" % f)
	check(FileAccess.get_file_as_string("res://src/wildlife.gd").count("Roamers.new(") == 1, "Wildlife alone makes them")


## A grown red fox stands about 0.4 m at the shoulder and 1.1 m nose to tail tip; a doe about 1 m at the shoulder.
func _a_fox_and_a_doe_stand_true_to_life() -> void:
	for want in [[Beast.Kind.FOX, 0.40, 1.1], [Beast.Kind.DEER, 0.99, 1.41]]:
		var b := Beast.new(want[0], 1.0, 0.0)
		root.add_child(b)
		await process_frame
		var mi: MeshInstance3D = b.find_children("*", "MeshInstance3D", true, false)[0]
		var skeleton: Skeleton3D = b.find_children("*", "Skeleton3D", true, false)[0]
		var shoulder := (skeleton.global_transform * skeleton.get_bone_global_rest(skeleton.find_bone("FrontShoulder.L"))).origin
		var bounds: AABB = mi.global_transform * mi.mesh.get_aabb()
		var withers := 0.0
		for v in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			var at: Vector3 = mi.global_transform * v
			if absf(at.z - shoulder.z) < 0.03 * bounds.size.z:
				withers = maxf(withers, at.y)
		var kind: String = Beast.Kind.keys()[want[0]]
		check(absf(withers - want[1]) < 0.04, "a %s stands %.2f m at the shoulder" % [kind, withers])
		check(absf(bounds.size.z - want[2]) < 0.06, "a %s is %.2f m nose to tail" % [kind, bounds.size.z])
		b.free()


func _each_is_one_draw_call() -> void:
	for kind in [Beast.Kind.DEER, Beast.Kind.FOX]:
		var a := Beast.new(kind, 1.0, 0.0)
		var b := Beast.new(kind, 0.9, 0.5)
		var ma: MeshInstance3D = a.find_children("*", "MeshInstance3D", true, false)[0]
		var mb: MeshInstance3D = b.find_children("*", "MeshInstance3D", true, false)[0]
		var tris := ma.mesh.get_faces().size() / 3
		check(ma.mesh.get_surface_count() == 1, "a %s is one surface" % Beast.Kind.keys()[kind])
		check(tris > 1000 and tris < 2500, "of a couple of thousand triangles, %d" % tris)
		check(ma.mesh == mb.mesh and ma.material_override == mb.material_override, "sharing one mesh and material")
		check(ma.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "casting no shadow")
		check(a.find_children("*", "BoneAttachment3D", true, false).is_empty(), "with nothing riding its bones")
		a.free()
		b.free()


func _deer_then_a_fox_come_out_of_sight() -> void:
	var g := await _glade(7)
	var seen := {}
	var each := _watch(g, seen)
	var first := {}
	var t := 0.0
	for i in int((Roamers.FIRST[Beast.Kind.FOX].y + 10.0) / STEP):
		g.wildlife.tick(STEP)
		each.call()
		t += STEP
		for kind in [Beast.Kind.DEER, Beast.Kind.FOX]:
			var now := g.beasts(kind)
			if not first.has(kind) and not now.is_empty():
				first[kind] = t
				for b in now:
					check(not g.wildlife._in_sight(b.position), "a %s comes in out of sight" % Beast.Kind.keys()[kind])
	for kind in [Beast.Kind.DEER, Beast.Kind.FOX]:
		check(first.has(kind) and first[kind] >= Roamers.FIRST[kind].x - STEP, "a %s comes a while after the garden opens, %s" % [Beast.Kind.keys()[kind], first.get(kind)])
	var deer := g.beasts(Beast.Kind.DEER)
	check(deer.size() >= Roamers.HERD[Beast.Kind.DEER].x and deer.size() <= Roamers.HERD[Beast.Kind.DEER].y, "a few deer, %d" % deer.size())
	check(g.beasts(Beast.Kind.FOX).size() == 1, "and one fox")
	_run(g, 60.0, each)
	var rim := 0
	for b in g.wildlife.roamers.all():
		var r := Vector2(b.position.x, b.position.z).length()
		if r >= Roamers.RING.x - 0.5 and r <= Roamers.RING.y + 0.5:
			rim += 1
	check(rim == g.wildlife.roamers.all().size(), "out on the meadow's rim, %d of %d" % [rim, g.wildlife.roamers.all().size()])
	await _teardown(g)


func _a_sudden_move_sends_a_deer_off_and_stillness_lets_it_near() -> void:
	var g := await _glade(11)
	await _arrived(g)
	var deer := g.beasts(Beast.Kind.DEER)[0]
	var head := g.rig.head
	head.global_position = deer.position + Vector3(2.0, 1.6, 6.0)
	_run(g, 0.2)
	check(deer.state == Grazers.State.FLEE, "a person appearing 6 m off sends it running, %s" % Grazers.State.keys()[deer.state])
	var from := head.global_position
	_run(g, 1.0)
	check(deer._clip == "Gallop", "at a gallop, %s" % deer._clip)
	_run(g, 3.0)
	var off := Vector2(deer.position.x - from.x, deer.position.z - from.z).length()
	check(off > 10.0, "a long way off, %.1f m" % off)
	var back := Vector3(head.global_position.x - deer.position.x, 0, head.global_position.z - deer.position.z).normalized()
	head.global_position = deer.position + back * 16.0 + Vector3.UP * 1.6
	_run(g, 10.0)
	check(_walk_up(g, deer, 0.5, 6.0), "a person walking up to 6 m does not send it running")
	check(deer.state == Grazers.State.WARY, "but it stops to watch, %s" % Grazers.State.keys()[deer.state])
	_run(g, Roamers.CALM_FOR * 4.0 + 1.0)
	check(deer.calm >= 3.0, "a person standing still calms it, %.0f calm spells" % deer.calm)
	check(_walk_up(g, deer, 0.5, Roamers.FLIGHT[Beast.Kind.DEER] - 1.0), "and may then walk nearer than it first let them before it runs")
	check(not _walk_up(g, deer, 0.5, 0.8), "though not right up to it")
	await _teardown(g)


func _food_held_still_draws_one_to_eat() -> void:
	var g := await _glade(13)
	await _arrived(g)
	for kind in [Beast.Kind.DEER, Beast.Kind.FOX]:
		var near := g.beasts(kind)[0]
		var hand: Hand = g.rig.right
		var off: float = Roamers.STARTLE[kind] + 1.0
		var at := Vector3.INF
		for k in 12:
			var p := near.position + Vector3.RIGHT.rotated(Vector3.UP, TAU * k / 12.0) * off
			if g.wildlife.roamers.allowed(p) and g.wildlife.roamers.clear_way(near.position, p):
				at = Terrain.ground(p.x, p.z)
				break
		check(at != Vector3.INF, "open grass to hold food over")
		if at == Vector3.INF:
			continue
		g.rig.head.global_position = at + Vector3(0, 1.6, 0)
		hand.global_position = at + Vector3.UP * 0.4
		hand.held_still = true
		hand.tool = Hand.Tool.SEEDS
		_run(g, 0.1)
		for b in g.wildlife.roamers.all():
			b.full = 0.0
		var eater: Beast = null
		for i in int(60.0 / STEP):
			g.wildlife.tick(STEP)
			for b in g.wildlife.roamers.all():
				if b.state == Grazers.State.FEED and b.kind == kind and Vector2(b.goal.x - b.position.x, b.goal.z - b.position.z).length() < 1e-3:
					eater = b
			if eater != null:
				break
		check(eater != null, "a %s comes to food held still" % Beast.Kind.keys()[kind])
		if eater != null:
			_run(g, 1.0)
			var reach := Vector2(at.x - eater.position.x, at.z - eater.position.z).length()
			check(eater.state == Grazers.State.FEED and absf(reach - eater.neck.stand_off(eater, hand)) < 0.15, "and eats with its mouth at the hand, %.2f m off" % reach)
			check(eater._clip == Beast.EAT_CLIP, "head down, eating, %s" % eater._clip)
			var ran := [false]
			_run(g, Roamers.appetite[kind].eats_for.y + 3.0, func() -> void: ran[0] = ran[0] or eater.state == Grazers.State.FLEE)
			check(eater.state != Grazers.State.FEED and not ran[0], "once fed it stays by the still person, %s" % Grazers.State.keys()[eater.state])
			var back := Vector3(hand.global_position.x - eater.position.x, 0, hand.global_position.z - eater.position.z).normalized()
			_run(g, 1.5, func() -> void:
				hand.global_position += back * 0.3 * STEP
				ran[0] = ran[0] or eater.state == Grazers.State.FLEE)
			check(not ran[0], "nor runs as the hand is drawn back")
			g.wildlife.claim(hand, eater)
			eater.hand = hand
			eater.state = Grazers.State.FEED
			hand.global_position.y += 3.0
			g.wildlife.roamers._eat(eater, STEP)
			check(eater.hand == null and eater.state != Grazers.State.FEED, "a hand raised beyond the neck reach releases contact and backs off")
		hand.tool = Hand.Tool.WALLS
		hand.held_still = false
		hand.global_position = AWAY
		g.rig.head.global_position = Vector3(0, 1.6, 0)
		_run(g, 1.0)
	await _teardown(g)


func _a_wall_drawn_under_one_moves_it() -> void:
	var g := await _glade(19)
	await _arrived(g)
	var deer := g.beasts(Beast.Kind.DEER)[0]
	var p := deer.position
	var across := Vector3(p.z, 0, -p.x).normalized()
	var m: WallTool.Mason = g.walls.masons[0]
	m.hand.tool = Hand.Tool.WALLS
	g.walls.begin_stroke(m, Terrain.ground(p.x - across.x * 3.0, p.z - across.z * 3.0))
	for i in 41:
		var q := p + across * lerpf(-3.0, 3.0, i / 40.0)
		g.walls.extend_stroke(m, Terrain.ground(q.x, q.z))
	g.walls.end_stroke(m)
	check(not g.wildlife.roamers.allowed(deer.position), "a wall is drawn under a grazing deer")
	_run(g, 1.0 + Wildlife.LOOK_EVERY)
	check(deer.state == Grazers.State.WALK or deer.state == Grazers.State.LEAVE, "it walks off within a second, %s" % Grazers.State.keys()[deer.state])
	_run(g, 15.0)
	check(g.wildlife.roamers.allowed(deer.position) or deer.state == Grazers.State.LEAVE, "to ground it may stand on")
	await _teardown(g)


func _they_leave_out_of_sight_and_come_again() -> void:
	var g := await _glade(17)
	var seen := {}
	var each := _watch(g, seen)
	await _arrived(g)
	for b in g.wildlife.roamers.bands:
		b.stay = 0.0
	var gone := [false]
	_run(g, 120.0, func() -> void:
		each.call()
		gone[0] = gone[0] or g.beasts(Beast.Kind.DEER).is_empty())
	check(gone[0], "the deer leave after their stay")
	_run(g, Roamers.AGAIN.y + 60.0, each)
	check(not g.beasts(Beast.Kind.DEER).is_empty(), "and others come later")
	await _teardown(g)


## Seeds tossed from a still hand land a little way along its aim on the grass, and draw a deer, and the fox, to eat
## them up off the ground.
func _thrown_seeds_draw_them_to_eat() -> void:
	var g := await _glade(23)
	await _arrived(g)
	for kind in [Beast.Kind.DEER, Beast.Kind.FOX]:
		var near := g.beasts(kind)[0]
		var at := Vector3.INF
		for k in 12:
			var p := near.position + Vector3.RIGHT.rotated(Vector3.UP, TAU * k / 12.0) * 5.0
			if g.wildlife.roamers.allowed(p) and g.wildlife.roamers.clear_way(near.position, p):
				at = Terrain.ground(p.x, p.z)
				break
		check(at != Vector3.INF, "open grass to throw seeds onto")
		if at == Vector3.INF:
			continue
		var away := Vector3(at.x - near.position.x, 0, at.z - near.position.z).normalized()
		g.rig.head.global_position = at + away * (Roamers.WATCH[kind] + 2.0) + Vector3.UP * 1.6
		_run(g, 1.0)
		for b in g.wildlife.roamers.all():
			b.full = 0.0
		_settle(g.beasts(kind))
		var hand: Hand = g.rig.right
		var aim := Vector3(near.position.x - at.x, -0.4, near.position.z - at.z).normalized()
		hand.global_transform = Transform3D(Basis.looking_at(aim), at + Vector3.UP * 0.9)
		var launch := g.feed.launch(hand, Vector3.ZERO)
		check(launch.dot(aim) > 0.9 * FeedTool.LAUNCH, "seeds fed from a still hand leave along its aim, %.2f m/s" % launch.dot(aim))
		var seeds := g.feed.throw(g.feed.dish(hand), launch)
		hand.global_position = AWAY
		_run(g, 1.0)
		var out := Vector2(seeds.position.x - at.x, seeds.position.z - at.z)
		check(seeds.landed() and out.dot(Vector2(aim.x, aim.z).normalized()) > 0.4, "and land %.2f m out along it" % out.length())
		var eater: Beast = null
		for i in int(40.0 / STEP):
			_run(g, STEP)
			for b in g.wildlife.roamers.all():
				if b.kind == kind and b.state == Grazers.State.FEED and b.hand == seeds and seeds.left() < Handful.GRAINS:
					eater = b
			if eater != null:
				break
		check(eater != null, "a %s comes to thrown seeds and eats them, %d grains left" % [Beast.Kind.keys()[kind], seeds.left()])
		if eater != null:
			eater.timer = 60.0
			var side := Vector3(g.rig.head.global_position.x - eater.position.x, 0, g.rig.head.global_position.z - eater.position.z).normalized()
			g.rig.head.global_position = eater.position + side * (Roamers.FLIGHT[kind] + 1.5) + Vector3.UP * 1.6
			check(not _walk_up(g, eater, 0.6, 1.0), "but a person coming up to it there still sends it off")
		_run(g, Handful.LASTS.y + 2.0)
	await _teardown(g)
