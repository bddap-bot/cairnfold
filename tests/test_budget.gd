extends "res://../tests/support/suite.gd"

## Headless checks of the frame budget: what the garden counts follows every placement and deletion, an edit that
## would take it past the budget is turned down whole, and deleting makes room again:
## godot4 --headless --fixed-fps 60 --path game --script ../tests/test_budget.gd

var world: World


func _initialize() -> void:
	boot_main()
	_run.call_deferred()


func _run() -> void:
	await process_frame
	world = main.world
	await _joining_does_not_change_the_budget()
	await _a_fresh_meadow_has_room_for_small_stone_houses()
	_every_step_keeps_the_same_fill()
	await _counts_follow_placements_and_deletions()
	await _arches_reserve_room_until_removed()
	await _an_edit_past_the_budget_is_turned_down_and_deleting_makes_room()
	await _a_capped_edit_is_heard_felt_and_shown()
	await _painting_stops_at_the_budget()
	_water_costs_at_most_a_view_full()
	_masonry_near_one_eye_is_charged_once()
	_stone_ground_counts_its_square_metres()
	_a_boulder_costs_no_more_once_it_fills_the_view()
	finish()


func _every_step_keeps_the_same_fill() -> void:
	var garden := {"wall_m2": 20.0, "flower": 100, "fitting": 2}
	var expected := Budget.fill(garden)
	var pin: int = main.quality.pin
	for step in Quality.ladder.size():
		main.quality.pin = step
		check(is_equal_approx(Budget.fill(garden), expected), "quality %d keeps the same fill" % step)
		check(not Budget.fits(garden, {"wall_m2": Budget.CAPACITY_MS * 1000.0 / Budget.COSTS.wall_m2 + 1.0}), "quality %d refuses an over-capacity edit" % step)
	main.quality.pin = pin


static func _near(cells: Dictionary) -> Dictionary:
	var near := Budget.Near.new()
	near.add(cells)
	return near.units()


func _masonry_near_one_eye_is_charged_once() -> void:
	var house := _wall(Vector2(0, 0), Vector2(4, 0), 2.5)
	var units := Budget.wall(house)
	var near := _near(World._spread("walls", house))
	check(is_equal_approx(near.get("wall_m2_near", 0.0), units.wall_m2), "a lone wall stands wholly near one eye: %s" % near)
	var span := (Budget.near_span() * 2 + 1) * Masonry.FINE
	var apart := {}
	for i in 3:
		World._add_cells(apart, World._spread("walls", _wall(Vector2(i * span * 2.0, 0), Vector2(i * span * 2.0 + 4, 0), 2.5)))
	check(is_equal_approx(_near(apart).get("wall_m2_near", 0.0), units.wall_m2), "walls too far apart to stand near one eye count near once")
	var close := {}
	for i in 3:
		World._add_cells(close, World._spread("walls", _wall(Vector2(0, i * 2.0), Vector2(4, i * 2.0), 2.5)))
	check(is_equal_approx(_near(close).get("wall_m2_near", 0.0), 3.0 * units.wall_m2), "walls side by side all count near")
	var long := _wall(Vector2(-60, 0), Vector2(60, 0), 2.5)
	var spread := World._spread("walls", long)
	var total := 0.0
	for c in spread:
		total += spread[c].wall_m2
	check(is_equal_approx(total, Budget.wall(long).wall_m2) and spread.size() >= 15, "a long wall's face spreads along the chunks it crosses: %d" % spread.size())
	check(_near(spread).wall_m2_near < Budget.wall(long).wall_m2 * 0.3, "and only the stretch near one eye counts near")


func _water_costs_at_most_a_view_full() -> void:
	var q: Dictionary = Budget.COSTS
	var pond := {"pond_m2": 20.0}
	check(is_equal_approx(Budget.cost_ms(pond), 20.0 * q.pond_m2 / 1000.0), "a small pond costs its square metres")
	var lake := {"pond_m2": 13158.0}
	check(is_equal_approx(Budget.cost_ms(lake), q.water / 1000.0), "the meadow's whole bowl costs a view full of water")
	check(Budget.fits({}, lake) == (q.water / 1000.0 <= Budget.CAPACITY_MS), "and fits an empty garden exactly when that view fits the room")
	check(Budget.fits(lake, {"pond_m2": 500.0}), "more water beside a full view's worth costs nothing more")


func _stone_ground_counts_its_square_metres() -> void:
	var before: Dictionary = world.units.duplicate()
	var r := FloraTool.MAX_RADIUS * 0.4
	var disc := PackedVector4Array([Vector4(40, -40, r, r * 2.0)])
	var meadow := {"op": "ground", "kind": int(Ground.Kind.MEADOW), "stamps": disc}
	check(Budget.ground(meadow).is_empty(), "painting meadow back counts nothing")
	var stone := {"op": "ground", "kind": int(Ground.Kind.STONE), "stamps": disc, "style": 0}
	var area: float = Budget.ground(stone).get("stone_m2", 0.0)
	check(absf(area - PI * 9.0 * r * r) < PI * 9.0 * r * r * 0.1, "a stone disc counts the ground it reaches, fade included: %.1f m²" % area)
	var twice := {"op": "ground", "kind": int(Ground.Kind.STONE), "stamps": PackedVector4Array([disc[0], disc[0] + Vector4(0.5, 0, 0, 0)]), "style": 0}
	check(Budget.ground(twice).stone_m2 < area * 1.5, "a stroke counts the ground its discs share once")
	var bounded := world.bounded
	world.bounded = false
	world._order(stone, world.me())
	var id := world.seq
	check(world.state.grounds.has(id), "the stone stroke goes into the garden")
	check(is_equal_approx(world.units.get("stone_m2", 0.0) - before.get("stone_m2", 0.0), area), "laying stone counts it")
	check(_same(world.units, _recount()), "stone's count matches a recount")
	world._order({"op": "take", "of": "grounds", "ids": PackedInt32Array([id])}, world.me())
	check(_same(world.units, before), "taking the stone away frees it")
	world.bounded = bounded
	var q: Dictionary = Budget.COSTS
	check(is_equal_approx(Budget.cost_ms({"stone_m2": 100.0}), 100.0 * q.stone_m2 / 1000.0), "a little stone costs its square metres")
	check(is_equal_approx(Budget.cost_ms({"stone_m2": 25600.0}), q.stone / 1000.0), "the whole meadow in stone costs a view full of it")


func _settled() -> void:
	main.water_tool.settle()
	for i in 3:
		await process_frame
	main.flora_tool.flora.grow_now()


## What the garden holds, counted afresh from its state rather than kept command by command.
func _recount() -> Dictionary:
	var out := {}
	var cells := {}
	for of in ["walls", "stairs", "paths", "grounds"]:
		for d: Dictionary in world.state[of].values():
			Budget.add(out, World._units(of, d))
			World._add_cells(cells, World._spread(of, d))
	Budget.add(out, _near(cells))
	for g in world.state.groups:
		for p: Flora.Plant in world.flora.groups[g]:
			if p != null and not world.state.groups[g].hidden.has(p.index):
				var u := world.flora.unit_of(p)
				if u != "" and (g != 0 or u in Flora.PLACED):
					Budget.add(out, {u: 1})
	var wet := 0
	for w: PondWater in world.water.ponds:
		wet += w.pond.cells.size()
	if wet > 0:
		out.pond_m2 = wet
	return out


func _same(a: Dictionary, b: Dictionary) -> bool:
	for k in Budget.UNITS:
		if not is_equal_approx(snappedf(a.get(k, 0.0), 0.001), snappedf(b.get(k, 0.0), 0.001)):
			return false
	return true


func _wall(from: Vector2, to: Vector2, height: float) -> Dictionary:
	var points := PackedVector3Array()
	for i in 9:
		var p := from.lerp(to, i / 8.0)
		points.append(main.world.terrain.ground(p.x, p.y))
	return wall_data({"points": points, "height": height, "seed": 7})


## Submits a wall command and waits for it to settle; whether it went into the garden.
func _build(walls: Array) -> bool:
	var before: int = world.state.walls.size()
	var settled := [false]
	world.submit({"op": "wall", "walls": walls}, func() -> void: settled[0] = true, main.rig.right)
	check(settled[0], "a wall command settles at once on the host")
	await _settled()
	return world.state.walls.size() > before


## A Quest once priced its fresh meadow's own trees and flowers at 141% of the bar and turned down the first house.
func _a_fresh_meadow_has_room_for_small_stone_houses() -> void:
	var meadow := world.units.duplicate()
	var walls: int = world.state.walls.size()
	await play([{"op": "place", "x": 0, "z": 14}, {"op": "house", "at": [0, 0], "size": [2.4, 2.4], "seconds": 0.3},
		{"op": "house", "at": [6, 0], "size": [2.4, 2.4], "seconds": 0.3}])
	await _settled()
	check(world.state.walls.size() == walls + 2, "a fresh meadow takes two small stone houses: %d walls" % (world.state.walls.size() - walls))
	print("budget-houses: meadow %.6f, two houses %.6f of the bar" % [Budget.fill(meadow), world.fill()])
	check(Budget.fill(meadow) < 1.0 and world.fill() < 1.0, "the meadow and both houses fit: %.3f, %.3f" % [Budget.fill(meadow), world.fill()])
	world.undo()
	world.undo()
	await _settled()
	check(_same(world.units, meadow), "undoing the houses gives back the meadow's count: %s" % world.units)


func _counts_follow_placements_and_deletions() -> void:
	var meadow := world.units.duplicate()
	var stand := {"tree": world.flora.meadow_trees().size(), "bush": world.flora.meadow_bushes().size()}
	check(_same(meadow, stand), "the meadow's own trees and bushes count as planted ones, its grass and flowers nothing: %s" % meadow)
	check(Budget.CAPACITY_MS > 0.0 and Budget.fits(meadow, {"wall_m2": 1.0}), "a fresh garden has room to build: %.2f full" % world.fill())
	check(_same(world.units, _recount()), "a fresh garden counts what it holds")
	var oak: int = world.flora.meadow_trees()[0]
	world._order({"op": "tree", "group": 0, "index": oak, "scale": 2.0}, world.me())
	check(_same(world.units, meadow), "a meadow tree counts one tree when resized: %s" % world.units)
	world._order({"op": "undo"}, world.me())
	check(_same(world.units, meadow), "and shrunk back too: %s" % world.units)
	var full := world.fill()
	world._order({"op": "show", "plants": {0: PackedInt32Array([oak])}, "on": false}, world.me())
	check(is_equal_approx(full - world.fill(), Budget.COSTS.tree / 1000.0 / Budget.CAPACITY_MS), "clearing a meadow tree frees one tree's share of the bar: %.4f to %.4f" % [full, world.fill()])
	world._order({"op": "undo"}, world.me())
	check(is_equal_approx(world.fill(), full), "and putting it back takes the share again")
	await play([
		{"op": "place", "x": 0, "z": 8},
		{"op": "wall", "points": [[-6, -2], [-1, -3]], "seconds": 0.3},
		{"op": "tree", "x": -6, "z": 4},
		{"op": "paint", "tool": "flowers", "points": [[6, 4], [7, 4]], "radius": 1.0, "seconds": 0.3},
		{"op": "pave", "points": [[3.5, -6], [3.5, 1]], "radius": 0.8, "seconds": 0.3},
		{"op": "dig", "x": 10, "z": -8, "seconds": 0.5},
	])
	await _settled()
	check(world.units.get("wall_m2", 0.0) > 0.0 and not world.units.has("path_m2") and world.units.get("pond_m2", 0) > 0, "walls, ponds and reserved path steps count: %s" % world.units)
	check(world.units.get("tree", 0) == meadow.tree + 1 and world.units.get("flower", 0) > 0, "a planted tree and painted flowers count: %s" % world.units)
	var planted: int = world.state.groups.keys().filter(func(g: int) -> bool: return world.state.groups[g].kind == "tree")[0]
	var before_resize := world.units.duplicate()
	for scale in [FloraLayout.SCALES.x, 2.0, FloraLayout.SCALES.y]:
		var resize := {"op": "tree", "group": planted, "index": 0, "scale": scale}
		check(world.change_of(resize).is_empty(), "resizing predicts no extra charge")
		world._order(resize, world.me())
		check(is_equal_approx(world.state.groups[planted].scale.get(0, 1.0), scale), "the resize was accepted before undoing it")
		check(_same(world.units, before_resize) and _same(world.units, _recount()), "resizing keeps the planted tree charged once")
		world._order({"op": "undo"}, world.me())
		check(_same(world.units, before_resize), "undoing a resize preserves its charge")
	check(_same(world.units, _recount()), "what the garden counts matches what it holds: %s against %s" % [world.units, _recount()])
	var wall_id: int = world.state.walls.keys()[0]
	var wall_units := Budget.wall(world.state.walls[wall_id])
	var with_wall := world.units.duplicate()
	world.submit({"op": "take", "of": "walls", "ids": PackedInt32Array([wall_id])})
	await _settled()
	check(is_equal_approx(world.units.get("wall_m2", 0.0), with_wall.wall_m2 - wall_units.wall_m2), "deleting a wall frees what it counted")
	await play([{"op": "delete", "x": -6, "z": 4, "height": 3.0}])
	await _settled()
	check(world.units.get("tree", 0) == meadow.tree, "deleting the tree frees it: %s" % world.units)
	check(_same(world.units, _recount()), "after deletions the count still matches the garden")
	for i in 8:
		world.undo()
		await _settled()
	check(_same(world.units, _recount()), "undo and redo keep the count matching the garden")
	await play([{"op": "bare"}])
	await _settled()
	check(_same(world.units, _recount()) and not world.units.has("wall_m2") and not world.units.has("flower"), "a wipe leaves nothing counted but the meadow: %s" % world.units)
	world.undo()
	await _settled()
	check(_same(world.units, _recount()), "undoing the wipe counts the garden it brings back")
	await play([{"op": "bare"}])
	await _settled()


func _arches_reserve_room_until_removed() -> void:
	await play([
		{"op": "wall", "points": [[-6, -20], [6, -20]], "seconds": 0.1},
	])
	var plain := world.units.duplicate()
	await play([{"op": "fit", "what": "opening", "index": 0, "s": 6.0, "style": 1}])
	await _settled()
	check(world.fill() > Budget.fill(plain), "an arch reserves GPU room beyond its intact stone wall")
	var arched := world.units.duplicate()
	world.undo()
	await _settled()
	check(_same(world.units, plain), "undoing an arch frees its reserved room")
	world.redo()
	await _settled()
	check(_same(world.units, arched), "redoing an arch reserves its room again")
	await play([{"op": "fit", "what": "opening", "index": 0, "s": 6.0, "style": 1}])
	await _settled()
	check(_same(world.units, plain), "removing an arch frees its room")
	await play([{"op": "bare"}])
	await _settled()


func _an_edit_past_the_budget_is_turned_down_and_deleting_makes_room() -> void:
	var piece := _wall(Vector2(-6, -20), Vector2(6, -20), 4.5)
	var share := Budget.fill(Budget.wall(piece))
	check(share > 0.02 and share < 1.0, "one test wall takes a measurable share: %.3f" % share)
	var too_big := [_wall(Vector2(-40, 30), Vector2(40, 30), 9.0), _wall(Vector2(-40, 34), Vector2(40, 34), 9.0), _wall(Vector2(-40, 38), Vector2(40, 38), 9.0)]
	var before := world.units.duplicate()
	check(not await _build(too_big), "a build past the whole budget is turned down")
	check(_same(world.units, before), "a turned-down build counts nothing")
	var built := 0
	for i in 40:
		var at := -30.0 + i * 3.0
		if not await _build([_wall(Vector2(-6, at), Vector2(6, at), 4.5)]):
			break
		built += 1
	check(built > 0 and built < 40, "walls go up until the budget is full: %d" % built)
	check(world.fill() <= 1.0, "the garden never passes its budget: %.3f" % world.fill())
	check(world.fill() + share > 1.0, "the wall turned down would have passed it: %.3f + %.3f" % [world.fill(), share])
	var full := world.units.duplicate()
	var last: int = world.state.walls.keys().max()
	world.submit({"op": "take", "of": "walls", "ids": PackedInt32Array([last])})
	await _settled()
	check(world.fill() < Budget.fill(full), "deleting a wall frees its share")
	check(await _build([_wall(Vector2(-6, -50), Vector2(6, -50), 4.5)]), "the room it freed takes another wall")
	var ids: Array = world.state.walls.keys()
	ids.sort()
	var tall_id: int = ids[ids.size() / 2 - 1]
	world.submit({"op": "reshape", "of": "walls", "id": tall_id, "data": {"height": 9.0}})
	await _settled()
	check(world.state.walls[tall_id].height == 4.5, "pulling a wall among the others taller than the budget allows is turned down")
	await play([{"op": "bare"}])
	await _settled()


## Directive (verbatim): "When something doesn't work because of the frame cap, I think it should be obvious to the
## player. I think maybe we can do that by embiggening the little bar that represents frame cap and shaking it around
## and making a little sound, like a [grunt ]sound". The bar has since gone from the hand; the grunt, the knocks and
## the sight turning red stay.
func _a_capped_edit_is_heard_felt_and_shown() -> void:
	var hand: Hand = main.rig.right
	hand.tool = Hand.Tool.WALLS
	var capped := [null]
	world.capped.connect(func(h: XRController3D) -> void: capped[0] = h, CONNECT_ONE_SHOT)
	var grunts: int = Cues.asked.get(Cues.Act.CAPPED, 0)
	var too_big := [_wall(Vector2(-40, 30), Vector2(40, 30), 9.0), _wall(Vector2(-40, 34), Vector2(40, 34), 9.0), _wall(Vector2(-40, 38), Vector2(40, 38), 9.0)]
	check(not await _build(too_big), "a build past the whole budget is turned down")
	check(capped[0] == hand, "the hand that tried it is the one capped")
	check(Cues.asked.get(Cues.Act.CAPPED, 0) == grunts + 1, "the frame cap grunts once")
	var change := {}
	for w: Dictionary in too_big:
		Budget.add(change, Budget.wall(w))
	for i in 3:
		world.preview(hand, change)
		await process_frame
	check(hand.capped, "a preview that will not fit shows refused before it is let go")
	for i in 3:
		await process_frame
	check(not hand.capped, "and stops once nothing over is shown")


func _painting_stops_at_the_budget() -> void:
	for i in 40:
		var at := -30.0 + i * 3.0
		if not await _build([_wall(Vector2(-6, at), Vector2(6, at), 4.5)]):
			break
	while Budget.CAPACITY_MS - Budget.cost_ms(world.units) <= Budget.COSTS.stone / 1000.0:
		world.submit({"op": "take", "of": "walls", "ids": PackedInt32Array([world.state.walls.keys().max()])})
		await _settled()
	await play([{"op": "paint", "tool": "stone", "points": [[-40, -20], [40, -20], [40, -30], [-40, -30], [-40, -40], [40, -40]], "radius": 3.0, "seconds": 8.0}])
	await _settled()
	check(world.units.get("stone_m2", 0.0) * Budget.COSTS.stone_m2 > Budget.COSTS.stone, "a long stroke of stone lays more than a view full")
	check(is_equal_approx(Budget.cost_ms(world.units) - Budget.cost_ms({"wall_m2": world.units.wall_m2, "wall_m2_near": world.units.wall_m2_near}), Budget.COSTS.stone / 1000.0), "and is charged a view full of it")
	for id: int in world.state.grounds.keys():
		world.submit({"op": "take", "of": "grounds", "ids": PackedInt32Array([id])})
	await _settled()
	check(not world.units.has("stone_m2"), "taking it away frees it")
	await play([{"op": "paint", "tool": "flowers", "points": [[-20, 20], [20, 20]], "radius": 3.0, "seconds": 6.0}])
	await _settled()
	check(world.fill() <= 1.0, "a long paint stroke stops at the budget: %.3f" % world.fill())
	check(world.units.get("flower", 0) > 0, "it painted up to it")
	world.submit({"op": "take", "of": "walls", "ids": PackedInt32Array([world.state.walls.keys().max()])})
	await _settled()
	await play([{"op": "paint", "tool": "stone", "points": [[-40, -20], [40, -20], [40, -30], [-40, -30]], "radius": 3.0, "seconds": 6.0}])
	await _settled()
	check(world.fill() <= 1.0 and world.fill() > 0.97, "where a view full of stone would not fit, a long stroke of it stops at the budget: %.3f" % world.fill())
	check(world.units.get("stone_m2", 0.0) > 0.0, "it painted stone up to it")


func _joining_does_not_change_the_budget() -> void:
	var meadow := world.units.duplicate()
	var bare := world.snapshot()
	await play([{"op": "place", "x": 0, "z": 8}, {"op": "house", "at": [0, 0], "size": [2.4, 2.4], "seconds": 0.3}])
	check(world.state.walls.size() == 1, "the solo host can place a small stone house")
	var house := Budget.add(world.units.duplicate(), meadow, -1.0)
	var solo := world.fill()
	var fits_solo := Budget.fits(world.units, house)
	world._welcome(world.snapshot())
	await _settled()
	check(world.state.walls.size() == 1 and is_equal_approx(world.fill(), solo), "a visitor's garden built from the host's welcome keeps the solo fill: %.3f of %.3f" % [world.fill(), solo])
	check(Budget.fits(world.units, house) == fits_solo, "and agrees on a second house")
	world.restore(bare)
	await _settled()


func _a_boulder_costs_no_more_once_it_fills_the_view() -> void:
	check(is_equal_approx(Budget.boulder(2.0), 4.0), "a small boulder counts its scale squared")
	check(is_equal_approx(Budget.boulder(0.1), Budget.BOULDER_LEAST), "a pebble counts the least")
	var most := Budget.cost_ms({"boulder": Budget.boulder(80.0)})
	check(is_equal_approx(most, Budget.BOULDER_MOST_US / 1000.0), "a boulder 80 metres wide costs the most one does")
	check(Budget.fits({}, {"boulder": Budget.boulder(1000.0)}), "an empty garden takes a boulder of any size")
