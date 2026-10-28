extends "res://../tests/support/suite.gd"

## Headless checks of the animals that keep their distance: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_shy.gd

const GladeBase = preload("res://../tests/support/glade.gd")
const STEP := GladeBase.STEP

var g: GladeBase
var look: Look


func _initialize() -> void:
	seed(1)
	await process_frame
	g = GladeBase.new()
	await g.build(self, 4)
	g.world.terrain.install()
	look = Look.build(root, g.world.terrain)
	look.set_time(Daylight.DEFAULT)
	g.wildlife.light = look
	g.run(200.0)
	check(g.wildlife.shy().all(func(k: Shy) -> bool: return k.animals.is_empty()), "a bare meadow draws none of them")
	var tool := WaterTool.new(g.rig, g.world)
	g.add_tool(tool)
	await GladeBase.dig(tool, 3, -4, 90)
	await GladeBase.dig(tool, 4.5, -4, 90)
	for p in g.water.ponds:
		p._process(PondWater.FILL)
	g.world.submit({"op": "plant", "kind": "tree", "seed": 7, "at": g.world.terrain.ground(-3, -7)})
	await process_frame
	_frogs()
	_snakes()
	_squirrels()
	await _owls()
	_cost()
	await _they_go_with_their_habitats()
	look.queue_free()
	await g.teardown()
	finish()


## Holds a hand at `from` and walks it toward `at` at a calm pace, as a person stepping up, for `seconds`.
func _approach(hand: Node3D, from: Vector3, at: Vector3, seconds: float, each := Callable()) -> void:
	hand.global_position = from
	g.wildlife.tick(STEP)
	var dir := Vector3(at.x - from.x, 0, at.z - from.z).normalized()
	for i in int(seconds / STEP):
		hand.global_position += dir * 0.45 * STEP
		g.wildlife.tick(STEP)
		if each.is_valid():
			each.call()


func _rest_hands() -> void:
	for h in g.rig.hands:
		h.global_position = GladeBase.AWAY
	g.wildlife._was.clear()


## Frogs sit at the waterline, hop along it and swim; one walked up to hops in and plops under; at night they croak.
func _frogs() -> void:
	var frogs := g.wildlife.frogs
	var pond := g.water.ponds[0]
	var want := Wildlife._pond_quota(pond, 1, Frogs.CAP, Frogs.CELLS_EACH, Frogs.PER_POND)
	var states := {}
	var off_bank := [0]
	var watch := func() -> void:
		for a in frogs.animals:
			states[a.state] = true
			if a.state == Frogs.State.SIT:
				var dry := g.water.pond_at(a.position.x, a.position.z) == null or pond.surface_y() - g.world.terrain.height_at(a.position.x, a.position.z) < 0.01
				var near := false
				for o in [Vector2(0.4, 0), Vector2(-0.4, 0), Vector2(0, 0.4), Vector2(0, -0.4)]:
					near = near or g.water.pond_at(a.position.x + o.x, a.position.z + o.y) != null
				if not dry or not near or absf(a.position.y - g.world.terrain.height_at(a.position.x, a.position.z)) > 0.01:
					off_bank[0] += 1
	g.run(Wildlife.ARRIVE_AFTER.y * want + 20.0, watch)
	check(frogs.animals.size() == want, "a pond of %d wet points draws %d frogs: %d" % [pond.pond.cells.size(), want, frogs.animals.size()])
	g.run(240.0, watch)
	check(off_bank[0] == 0, "a sitting frog sits on the bank at the waterline, %d ticks off it" % off_bank[0])
	check(states.has(Frogs.State.HOP) and states.has(Frogs.State.SWIM), "they hop and swim: %s" % [states.keys()])
	var sitting: Array = frogs.animals.filter(func(a: Shy.One) -> bool: return a.state == Frogs.State.SIT)
	for i in 600:
		if not sitting.is_empty():
			break
		g.run(STEP)
		sitting = frogs.animals.filter(func(a: Shy.One) -> bool: return a.state == Frogs.State.SIT)
	check(not sitting.is_empty(), "one sits")
	var f: Frogs.Frog = sitting[0]
	var plops: int = Cues.asked.get(Cues.Act.PLOP, 0)
	var hand := g.rig.hands[0]
	var under := [false]
	var start := f.position + (f.position - f.launch).normalized() * 2.0 + Vector3.UP * 1.0
	_approach(hand, start, f.position, 4.0, func() -> void: under[0] = under[0] or f.state == Frogs.State.UNDER)
	check(under[0], "one walked up to hops in and goes under")
	check(Cues.asked.get(Cues.Act.PLOP, 0) > plops, "with a plop")
	check(f.position.y < g.water.ponds[0].surface_y() - Frogs.DIVE * 0.5, "out of sight under the water")
	_rest_hands()
	g.run(Frogs.UNDER_FOR.y + 30.0)
	check(f.state != Frogs.State.UNDER, "and comes up again")
	var croaks: int = g.wildlife.calls.played.get("croak", [0])[0]
	check(croaks == 0, "no croaks by day")
	look.set_time(0.0)
	g.run(180.0)
	check(g.wildlife.calls.played.get("croak", [0])[0] > 3, "they croak at night: %d" % g.wildlife.calls.played.get("croak", [0])[0])
	look.set_time(Daylight.DEFAULT)
	g.run(STEP)


## A grass snake slides through the grass by the pond and lies still between; walked up to, it slips off away.
func _snakes() -> void:
	var snakes := g.wildlife.snakes
	g.run(Wildlife.ARRIVE_AFTER.y + 5.0)
	check(snakes.animals.size() == 1, "one snake to the pond: %d" % snakes.animals.size())
	var s: Snakes.Snake = snakes.animals[0]
	var bad := [0]
	var moved := [0.0]
	var was := [s.position]
	var watch := func() -> void:
		if not g.wildlife.standable(s.position) and g.water.pond_at(s.position.x, s.position.z) != null:
			bad[0] += 1
		moved[0] += s.position.distance_to(was[0])
		was[0] = s.position
	g.run(120.0, watch)
	check(bad[0] == 0, "it keeps out of the water")
	check(moved[0] > 2.0, "it slides about: %.1f m" % moved[0])
	var hand := g.rig.hands[0]
	var from := s.position + Vector3(1.8, 1.0, 0.3)
	var fled := [false]
	_approach(hand, from, s.position, 2.0, func() -> void: fled[0] = fled[0] or s.state == Snakes.State.FLEE)
	check(fled[0], "walked up to, it slips off")
	var before := Vector2(s.position.x - hand.global_position.x, s.position.z - hand.global_position.z).length()
	g.run(3.0)
	check(Vector2(s.position.x - hand.global_position.x, s.position.z - hand.global_position.z).length() > before, "away from the hand")
	_rest_hands()


## A squirrel comes down its tree, climbs about the trunk and forages under it; walked up to, it races up the trunk.
func _squirrels() -> void:
	var squirrels := g.wildlife.squirrels
	g.run(Wildlife.ARRIVE_AFTER.y + 5.0)
	check(squirrels.animals.size() == 1, "one squirrel to the planted tree: %d" % squirrels.animals.size())
	var q: Squirrels.Squirrel = squirrels.animals[0]
	var trunk: Flora.Plant = q.home
	var states := {}
	var off_bark := [0.0]
	var watch := func() -> void:
		states[q.state] = true
		if q.state in [Squirrels.State.CLIMB, Squirrels.State.CLING]:
			var foot := trunk.foot()
			var off := Vector2(q.position.x - foot.x, q.position.z - foot.z).length() - Squirrels.radius(trunk, q.up)
			off_bark[0] = maxf(off_bark[0], absf(off - Squirrels.GRIP))
	g.run(240.0, watch)
	check(states.size() == Squirrels.State.size(), "it climbs, clings, runs and forages: %s" % [states.keys()])
	check(off_bark[0] < 0.01, "on the trunk it keeps to the bark: %.3f m off" % off_bark[0])
	while q.state != Squirrels.State.FORAGE:
		g.run(STEP)
	var hand := g.rig.hands[0]
	var high := [0.0]
	_approach(hand, q.position + Vector3(2.4, 1.0, 1.0), q.position, 6.0, func() -> void: high[0] = maxf(high[0], q.up if q.state in [Squirrels.State.CLIMB, Squirrels.State.CLING] else 0.0))
	check(high[0] > Squirrels.height(trunk) * 0.5, "walked up to, it races up its trunk: %.2f m" % high[0])
	_rest_hands()
	look.set_time(0.0)
	g.run(60.0)
	check(q.state == Squirrels.State.CLING and q.up > Squirrels.height(trunk) * 0.85, "at night it keeps up in its crown")
	look.set_time(Daylight.DEFAULT)
	g.run(STEP)


## Owls come only at night, perch on the conures' perches and hoot; walked up to, one flies off; with the day they go.
func _owls() -> void:
	var owls := g.wildlife.owls
	var wall := _draw_wall(Vector3(0, 0, -9), Vector3(5, 0, -10))
	await process_frame
	check(wall.finished, "a finished wall")
	g.run(120.0)
	check(owls.animals.is_empty(), "no owl by day")
	look.set_time(0.0)
	var perched := [0]
	var off := [0]
	var watch := func() -> void:
		for a: Owls.Owl in owls.animals:
			if a.state == Owls.State.PERCH:
				perched[0] += 1
				off[0] += int(not a.site.points().has(a.goal) or a.position.distance_to(a.goal) > 1e-3)
	g.run(Owls.AFTER.y * 2.0 + 20.0)
	check(owls.animals.size() >= 1 and owls.animals.size() <= Owls.CAP, "an owl or two comes at night: %d" % owls.animals.size())
	g.run(240.0, watch)
	check(perched[0] > 0 and off[0] == 0, "an owl perches on a perch point: %d of %d off" % [off[0], perched[0]])
	check(g.wildlife.calls.played.get("hoot", [0])[0] > 3, "they hoot: %d" % g.wildlife.calls.played.get("hoot", [0])[0])
	var o: Owls.Owl
	for i in 3000:
		var on: Array = owls.animals.filter(func(a: Owls.Owl) -> bool: return a.state == Owls.State.PERCH and not a.leaving)
		if not on.is_empty():
			o = on[0]
			break
		g.run(STEP)
	var flew := [false]
	_approach(g.rig.hands[0], o.position + Vector3(2.0, -o.position.y + g.world.terrain.height_at(o.position.x, o.position.z) + 1.5, 1.5), o.position, 3.0, func() -> void: flew[0] = flew[0] or o.state == Owls.State.FLY)
	check(flew[0], "walked up to, an owl flies off")
	_rest_hands()
	look.set_time(Daylight.DEFAULT)
	g.run(120.0)
	check(owls.animals.is_empty(), "with the day they go")


## What the four cost a frame on the CPU at their caps' worth of habitats here, and what each draws.
func _cost() -> void:
	look.set_time(0.0)
	g.run(Owls.AFTER.y * 2.0)
	var elapsed := {}
	for i in 1440:
		for kind in g.wildlife.shy():
			var start := Time.get_ticks_usec()
			kind.tick(1.0 / 72.0)
			elapsed[kind] = elapsed.get(kind, 0) + Time.get_ticks_usec() - start
	for kind in g.wildlife.shy():
		var mesh := kind.crowd.multimesh.mesh
		print("shy_cost: %s: %d animals; %.4f ms/tick; %d triangles each; one draw" % [kind.get_script().get_global_name(), kind.animals.size(), elapsed[kind] / 1440000.0, mesh.surface_get_array_len(0) / 3])
	look.set_time(Daylight.DEFAULT)
	g.run(120.0)


## A pond filled in takes its frogs and snake; a tree taken away sends its squirrel off.
func _they_go_with_their_habitats() -> void:
	g.run(60.0)
	check(not g.wildlife.frogs.animals.is_empty() and not g.wildlife.snakes.animals.is_empty() and not g.wildlife.squirrels.animals.is_empty(), "frogs, a snake and a squirrel")
	for parts in g.flora.placed("tree"):
		for p: Flora.Plant in parts:
			p.set_shown(false)
	g.water.clear()
	await process_frame
	g.run(120.0)
	check(g.wildlife.frogs.animals.is_empty(), "a pond filled in takes its frogs")
	check(g.wildlife.snakes.animals.is_empty(), "and its snake")
	check(g.wildlife.squirrels.animals.is_empty(), "a tree gone sends its squirrel off")


func _draw_wall(a: Vector3, b: Vector3) -> Wall:
	var m: WallTool.Mason = g.walls.masons[0]
	var terrain := g.world.terrain
	g.walls.begin_stroke(m, terrain.ground(a.x, a.z))
	for i in 31:
		var p := a.lerp(b, i / 30.0)
		g.walls.extend_stroke(m, terrain.ground(p.x, p.z))
	g.walls.end_stroke(m)
	return g.walls.walls[-1]
