extends "res://../tests/support/suite.gd"

## Headless checks of hands that stop at what is solid and pulse when they touch:
## godot4 --headless --fixed-fps 60 --path game --script ../tests/test_hand_stop.gd


func _initialize() -> void:
	_a_sweep_stops_at_the_surface_and_slides_along_it()
	_a_ball_started_inside_is_let_go()
	_a_touch_pulses_with_its_speed_and_sliding_ticks_softly()
	_water_is_soft_and_still_water_is_quiet()
	boot_main()
	_run.call_deferred()


func _run() -> void:
	await play([
		{"op": "wall", "points": [[-3, -6], [3, -6]], "seconds": 0.2},
	])
	var wall: Wall = main.tool.walls[0]
	await _the_ground_stops_a_hand()
	await _a_wall_stops_a_hand_that_catches_up_when_it_comes_back(wall)
	await _a_hand_reaches_through_an_arch(wall)
	_a_trunk_is_solid_and_its_leaves_are_brushed()
	_surfaces_come_from_what_is_touched(wall)
	_animals_are_solid_in_their_coats()
	await _a_wall_laid_elsewhere_keeps_what_was_gathered()
	await _a_hand_does_not_stop_against_the_bird_it_carries()
	await _an_eye_inside_a_wall_or_hill_sees_dark()
	finish()


## The view darkens while the eye is inside a wall or under the ground, and clears once it is out; nothing moves it.
func _an_eye_inside_a_wall_or_hill_sees_dark() -> void:
	var rig: Rig = main.rig
	var dim := func() -> float: return rig._fade_mat.albedo_color.a if rig._fade.visible else 0.0
	for case: Array in [["in a wall", main.world.terrain.ground(-2, -6), 0.0], ["under a hill", main.world.terrain.ground(0, 10), -3.0]]:
		rig.place(main.world.terrain.ground(0, 0), 0.0)
		await frames(30)
		var clear: float = dim.call()
		rig.place(case[1], 0.0)
		rig.global_position.y += case[2]
		var at := rig.global_position
		await frames(30)
		var inside: float = dim.call()
		check(clear == 0.0 and inside >= Rig.INSIDE_DIM - 0.01 and rig.global_position == at, "an eye %s sees dark, %.2f from %.2f, unmoved" % [case[0], inside, clear])
		rig.place(main.world.terrain.ground(0, 0), 0.0)
		await frames(30)
		check(dim.call() == 0.0, "and clear once out of it")


static func _past_one(p: Vector3) -> bool:
	return p.x > 1.0


static func _facing_back(p: Vector3) -> Vector3:
	return Vector3.LEFT if p.x > 1.0 else Vector3.ZERO


func _a_sweep_stops_at_the_surface_and_slides_along_it() -> void:
	var at := HandStop.resolve(Vector3.ZERO, Vector3(2, 0, 0), _past_one, _facing_back)
	check(at.x <= 1.0 and at.x > 0.99, "a ball pushed into a face stops at it, %.4f" % at.x)
	at = HandStop.resolve(Vector3(0.9, 0, 0), Vector3(1.5, 0.2, 0.4), _past_one, _facing_back)
	check(at.x <= 1.0 and at.x > 0.99 and is_equal_approx(at.y, 0.2) and is_equal_approx(at.z, 0.4), "pushed in at a slant it slides along the face to %s" % at)
	at = HandStop.resolve(Vector3(0.5, 0, 0), Vector3(-0.2, 0.1, 0), _past_one, _facing_back)
	check(at.is_equal_approx(Vector3(-0.2, 0.1, 0)), "a clear way goes all the way")


func _a_ball_started_inside_is_let_go() -> void:
	var at := HandStop.resolve(Vector3(1.5, 0, 0), Vector3(1.7, 0, 0), _past_one, _facing_back)
	check(at.is_equal_approx(Vector3(1.7, 0, 0)), "a ball already inside follows its controller")


## A second at 72 Hz of a hand held at `held` (or passing through `passing`) moving `speed` m/s along it: the
## pulses after the first touch's.
static func _slide(held: HandStop.Surface, passing: HandStop.Surface, speed: float) -> Array[Vector2]:
	var f := HandStop.Feel.new()
	var out: Array[Vector2] = []
	for k in 73:
		var p := f.step(k / 72.0, 1.0 / 72.0, held, passing, speed / 72.0, speed / 72.0)
		if p.x > 0.0 and k > 0:
			out.append(p)
	return out


func _a_touch_pulses_with_its_speed_and_sliding_ticks_softly() -> void:
	var stone := HandStop.Surface.STONE
	var soft := HandStop.Feel.new().step(0.0, 1.0 / 72.0, stone, HandStop.Surface.NONE, 0.1 / 72.0, 0.0)
	var hard := HandStop.Feel.new().step(0.0, 1.0 / 72.0, stone, HandStop.Surface.NONE, 2.0 / 72.0, 0.0)
	check(soft.x > 0.0 and hard.x > soft.x and hard.x <= 0.5, "a touch pulses harder the faster it comes in: %.2f, %.2f" % [soft.x, hard.x])
	var wool := HandStop.Feel.new().step(0.0, 1.0 / 72.0, HandStop.Surface.WOOL, HandStop.Surface.NONE, 2.0 / 72.0, 0.0)
	check(wool.x < hard.x * 0.5, "touching wool is gentler than stone: %.2f, %.2f" % [wool.x, hard.x])
	var ticks := _slide(stone, HandStop.Surface.NONE, 0.5)
	var strongest := 0.0
	for t in ticks:
		strongest = maxf(strongest, t.x)
	check(ticks.size() > 3 and ticks.size() <= 40 and strongest <= 0.15, "a second of sliding along stone ticks %d times, at most %.2f" % [ticks.size(), strongest])
	check(_slide(stone, HandStop.Surface.NONE, 0.02).is_empty(), "a hand held still against stone plays no grain")
	var rows := _slide(HandStop.Surface.TILE, HandStop.Surface.NONE, 0.5)
	check(rows.size() < ticks.size() and rows.size() >= 2, "roof tiles tick in rows, fewer than stone's grain: %d to %d" % [rows.size(), ticks.size()])
	var spread := func(ts: Array[Vector2]) -> float:
		var lo := INF
		var hi := 0.0
		for t in ts:
			lo = minf(lo, t.x)
			hi = maxf(hi, t.x)
		return hi - lo
	check(spread.call(ticks) > spread.call(rows) * 2.0, "stone is rough, tiles are even")
	check(not _slide(HandStop.Surface.NONE, HandStop.Surface.LEAVES, 0.5).is_empty(), "brushing leaves ticks")
	for s in HandStop.Surface.values():
		check(s == HandStop.Surface.NONE or HandStop.FEEL.has(s), "every surface has a feel: %s" % HandStop.Surface.keys()[s])
	var f := HandStop.Feel.new()
	var pulses := 0
	for k in 72:
		if f.step(k / 72.0, 1.0 / 72.0, stone if k % 2 == 0 else HandStop.Surface.NONE, HandStop.Surface.NONE, 0.0001, 0.0).x > 0.0:
			pulses += 1
	check(pulses == 1, "a hand resting at a surface pulses once, not %d times" % pulses)
	f = HandStop.Feel.new()
	f.step(0.0, 1.0 / 72.0, stone, HandStop.Surface.NONE, 0.01, 0.0)
	f.step(0.05, 1.0 / 72.0, HandStop.Surface.NONE, HandStop.Surface.NONE, 0.0, 0.0)
	check(f.step(0.3, 1.0 / 72.0, stone, HandStop.Surface.NONE, 0.01, 0.0).x > 0.0, "a touch after a clear moment pulses again")


## The strongest a hand in water ever feels: a fast plunge, a fast stroke or pulling out.
const WATER_CEILING := 0.06


func _water_is_soft_and_still_water_is_quiet() -> void:
	var water := HandStop.Surface.WATER
	var none := HandStop.Surface.NONE
	var dt := 1.0 / 72.0
	var f := HandStop.Feel.new()
	var plunge := f.step(0.0, dt, none, water, 4.0 * dt, 4.0 * dt)
	check(plunge.x > 0.0 and plunge.x <= WATER_CEILING, "a hand plunged into water splashes softly: %.3f" % plunge.x)
	var quiet := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in range(1, 72 * 5):
		var jitter := rng.randf_range(0.0, 0.003)
		if f.step(k * dt, dt, none, water, jitter, jitter).x > 0.0:
			quiet += 1
	check(quiet == 0, "a hand held still under water, tracking jitter and all, feels nothing for five seconds: %d pulses" % quiet)
	var leave := f.step(5.0, dt, none, none, 0.0, 0.0)
	check(leave.x > 0.0 and leave.x <= WATER_CEILING, "pulling the hand out pulses once, gently: %.3f" % leave.x)
	var g := HandStop.Feel.new()
	g.step(0.0, dt, none, water, 0.0, 0.0)
	var bobs := 0
	for k in range(1, 144):
		if g.step(k * dt, dt, none, water if k % 2 == 0 else none, 0.001, 0.001).x > 0.0:
			bobs += 1
	check(bobs == 1, "a hand bobbing at the surface pulses on leaving once, not %d times" % bobs)
	for speed in [0.1, 0.3, 0.45]:
		var drift := _slide(none, water, speed)
		check(drift.is_empty(), "moving slowly under water, %.2f m/s, feels nothing: %d pulses" % [speed, drift.size()])
	var stroke := _slide(none, water, 1.0)
	var swipe := _slide(none, water, 3.0)
	var top := 0.0
	var mean := func(ts: Array[Vector2]) -> float:
		var sum := 0.0
		for t in ts:
			sum += t.x
		return sum / maxf(ts.size(), 1)
	for t in stroke + swipe:
		top = maxf(top, t.x)
	check(stroke.size() >= 3 and top <= WATER_CEILING * 0.5, "a quick stroke through water is a faint texture: %d ticks, at most %.3f" % [stroke.size(), top])
	check(mean.call(_slide(none, water, 0.7)) < mean.call(swipe), "quicker strokes feel a little stronger")


## Holds the right hand so its ball sits at `ball`, as tracking would put it.
func _hold(ball: Vector3) -> void:
	var hand: Hand = main.rig.right
	hand.held_still = true
	hand.global_transform = Transform3D(Basis.IDENTITY, ball - HandStop.CENTRE)
	await process_frame


func _seen() -> Vector3:
	return main.rig.right.body.global_transform * HandStop.CENTRE


func _the_ground_stops_a_hand() -> void:
	var g := main.world.terrain.height_at(4.0, 4.0)
	await _hold(Vector3(4, g + 0.3, 4))
	await _hold(Vector3(4, g + 0.1, 4))
	for k in 5:
		await _hold(Vector3(4, g + 0.1 - 0.1 * (k + 1), 4))
	var rest := _seen()
	check(absf(rest.y - (g + HandStop.RADIUS)) < 0.02, "a hand pushed 0.4 m into the ground stays on it: %.3f over %.3f" % [rest.y, g])
	await _hold(Vector3(4.2, g - 0.4, 4))
	var seen := _seen()
	var on := main.world.terrain.height_at(seen.x, seen.z) + HandStop.RADIUS
	check(Vector2(seen.x - 4.2, seen.z - 4.0).length() < 0.04 and absf(seen.y - on) < 0.01, "pushed into the ground it slides across it, to the nearest point on it %s" % seen)
	await _hold(Vector3(4.2, g + 0.5, 4))
	check(_seen().is_equal_approx(Vector3(4.2, g + 0.5, 4)), "lifted clear, it is back on its controller")


func _a_wall_stops_a_hand_that_catches_up_when_it_comes_back(wall: Wall) -> void:
	var foot := wall.layout.point_at(1.5).y + WallLayout.SINK
	var y := foot + 1.2
	check(wall.layout.opening_at(4.5, 1.2).is_empty(), "the test spot is plain wall")
	await _hold(Vector3(1.5, y, -4.8))
	var z := -4.8
	while z > -6.5:
		z -= 0.03
		await _hold(Vector3(1.5, y, z))
	var face := -6.0 + WallLayout.THICKNESS * 0.5 + HandStop.RADIUS
	check(absf(_seen().z - face) < 0.02, "a hand pushed through a wall stays at its face: %.3f, face at %.3f" % [_seen().z, face])
	check(main.rig.right.global_position.z < -6.4, "while its controller carries on")
	await _hold(Vector3(1.8, y + 0.2, z))
	check(absf(_seen().z - face) < 0.02 and absf(_seen().x - 1.8) < 0.01 and absf(_seen().y - y - 0.2) < 0.01, "moved along the wall, it slides along the face")
	await _hold(Vector3(1.5, y, -4.9))
	check(_seen().is_equal_approx(Vector3(1.5, y, -4.9)), "brought back out, the hand catches up")
	await _hold(Vector3(1.5, y, -5.5))
	await _hold(Vector3(1.5, y, -5.5 - HandStop.BREAK - 0.1))
	check(absf(_seen().z - (-5.6 - HandStop.BREAK)) < 0.01, "pushed further than an arm's reach past it, the hand lets go")


func _a_hand_reaches_through_an_arch(wall: Wall) -> void:
	main.fitting_tool.fit({"what": "opening", "style": WallLayout.Family.ARCHWAY, "y": 0.0, "wall": wall, "s": 3.0})
	await frames(2)
	wall.lay_now()
	await frames(2)
	check(not wall.layout.archways().is_empty(), "the wall opened an arch")
	if wall.layout.archways().is_empty():
		return
	var s: float = wall.layout.archways()[0]
	var p := wall.layout.point_at(s)
	var y := p.y + WallLayout.SINK + 0.6
	await _hold(Vector3(p.x, y, -4.8))
	var z := -4.8
	while z > -7.2:
		z -= 0.03
		await _hold(Vector3(p.x, y, z))
	check(absf(_seen().z - z) < 0.01, "a hand passes through an arch: %.3f to %.3f" % [_seen().z, z])
	await _hold(Vector3(p.x, y, -4.8))


func _flora() -> Flora:
	for n in main.get_children():
		if n is Flora:
			return n
	return null


func _a_trunk_is_solid_and_its_leaves_are_brushed() -> void:
	var flora := _flora()
	var trunk: Flora.Plant = null
	var leaf: Flora.Plant = null
	for parts in flora.solids():
		if parts[0].pool == flora.trunks and parts.size() > 1:
			trunk = parts[0]
			leaf = parts[1]
			break
	check(trunk != null, "the meadow has a tree")
	if trunk == null:
		return
	var base := Vector3(trunk.anchor.x, main.world.terrain.height_at(trunk.anchor.x, trunk.anchor.z), trunk.anchor.z)
	var near := HandStop.Near.gather(main.world, AABB(base, Vector3.ZERO).grow(6.0))
	var mid := base + Vector3.UP * 0.6
	check(near.touch(mid) == HandStop.Surface.BARK, "a trunk is solid bark")
	check(not near.solid(mid + Vector3(1.2, 0, 0)), "beside it is not")
	var at := leaf.xform.translated(Vector3.UP * main.world.terrain.height_at(leaf.anchor.x, leaf.anchor.z))
	var centre := at * leaf.pool.mesh.get_aabb().get_center()
	check(near.passing(centre) == HandStop.Surface.LEAVES and not near.solid(centre), "leaves are brushed, not solid")


func _surfaces_come_from_what_is_touched(wall: Wall) -> void:
	var p := wall.layout.point_at(1.0) + Vector3.UP * (WallLayout.SINK + 1.0)
	var near := HandStop.Near.gather(main.world, AABB(p, Vector3.ZERO).grow(1.0))
	check(near.touch(p) == HandStop.Surface.STONE, "a stone wall feels of stone")
	var g := main.world.terrain.ground(10.0, 10.0)
	check(near.touch(g) == HandStop.Surface.GROUND, "the meadow feels of ground")


## A wall laid away from a hand leaves what was gathered round it standing; one laid through it is gathered.
func _a_wall_laid_elsewhere_keeps_what_was_gathered() -> void:
	var p := main.world.terrain.ground(0.0, 12.0) + Vector3.UP * 1.0
	var box := AABB(p, Vector3.ZERO).grow(0.3)
	var stop := HandStop.new(main.world, main.rig)
	var near := stop._near_for(0, box)
	await play([{"op": "wall", "points": [[-3, 20], [3, 20]], "seconds": 0.2}])
	check(stop._near_for(0, box) == near, "a wall laid elsewhere costs no gathering")
	await play([{"op": "wall", "points": [[-3, 12], [3, 12]], "seconds": 0.2}])
	var again := stop._near_for(0, box)
	check(again != near and again.solid(p), "a wall laid through the hand is gathered, and stops it")
	stop.free()


func _animals_are_solid_in_their_coats() -> void:
	var g := main.world.terrain.ground(-6.0, 6.0)
	var conure := Conure.new(0.0, 0)
	conure.terrain = main.world.terrain
	var critters: Array[Critter] = [Sheep.new(0.0, 1.0, Color.WHITE), Duck.new(false, 0.0), conure]
	var coats := [HandStop.Surface.WOOL, HandStop.Surface.DOWN, HandStop.Surface.FEATHERS]
	for k in critters.size():
		var c := critters[k]
		main.add_child(c)
		c.global_position = g + Vector3(k * 2.0, 0.5, 0.0)
		var centre := c.global_transform * c.mesh.get_aabb().get_center()
		var box := AABB(centre, Vector3.ZERO).grow(0.5)
		var near := HandStop.Near.gather(main.world, box)
		near.focus(box, main.get_tree().get_nodes_in_group(HandStop.CRITTERS))
		check(near.touch(centre) == coats[k], "a %s is solid, in its coat" % HandStop.Surface.keys()[coats[k]])
		var above := centre + Vector3.UP * 0.6
		check(HandStop.resolve(above, centre, near.solid, near.normal).y > centre.y + 0.01, "a hand coming down on a %s stops on its back" % HandStop.Surface.keys()[coats[k]])
		c.queue_free()


func _a_hand_does_not_stop_against_the_bird_it_carries() -> void:
	var g := main.world.terrain.ground(-8.0, -2.0)
	var bird := Conure.new(0.0, 0)
	bird.terrain = main.world.terrain
	main.add_child(bird)
	bird.global_position = g + Vector3.UP * 1.0
	var centre := bird.global_transform * bird.mesh.get_aabb().get_center()
	bird.hand = main.rig.right
	await _hold(centre + Vector3.UP * 0.3)
	for k in 10:
		await _hold(centre + Vector3.UP * (0.3 - 0.06 * (k + 1)))
	check(_seen().distance_to(centre - Vector3.UP * 0.3) < 0.01, "a hand passes the bird standing on it")
	var hand: Hand = main.rig.right
	hand.body.position = Vector3(0, 0.1, 0)
	var spot: Vector3 = main.wildlife.eat_spot(Birds.appetite, hand, Vector3.ZERO)
	check(spot.is_equal_approx(hand.body.global_transform * Wildlife.ON_HAND), "a bird eats on the hand as seen")
	bird.hand = null
	await _hold(centre + Vector3.UP * 1.5)
	await _hold(centre + Vector3.UP * 0.3)
	for k in 10:
		await _hold(centre + Vector3.UP * (0.3 - 0.06 * (k + 1)))
	check(_seen().y > centre.y, "another's bird stops it")
	bird.queue_free()
