extends "res://../tests/support/suite.gd"

## Headless checks of bridges: where a stroke hangs, the sag of its deck, each railing style, the single rope at the
## least width, a bridge drawn between two wall tops and across a pond's banks, and demo/bridges.json and the stress
## scene's bridges/* phases: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_bridges.gd


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_hangs()
	_sag()
	_railings()
	_single_rope()
	_commands()
	boot_main()
	await process_frame
	main.world.limit = INF
	await _drawn()
	await _demo()
	await _stress()
	finish()


func _bridge(sag: float, rail := "rope", width := 1.2) -> Dictionary:
	return {"a": Vector3(0, 3, 0), "b": Vector3(10, 3.5, 0), "width": width, "sag": sag, "rail": rail, "seed": 4, "paint": Palette.plain(), "on": PackedInt32Array()}


func _hangs() -> void:
	var flat := func(_p: Vector3) -> float: return 0.0
	var dry := func(_x: float, _z: float) -> float: return -10.0
	var a := Vector3(0, 3, 0)
	check(StairLayout.sag_over(a, Vector3(10, 3, 0), 1.2, flat, dry) > 0.0, "a level span three metres over the meadow hangs")
	check(StairLayout.sag_over(a, Vector3(10, 5, 0), 1.2, flat, dry) > 0.0, "a span rising gently between two heights hangs")
	check(StairLayout.sag_over(a, Vector3(4, 5, 0), 1.2, flat, dry) == 0.0, "a steep span is stairs, not a bridge")
	check(StairLayout.sag_over(Vector3(0, 0.3, 0), Vector3(10, 0.3, 0), 1.2, flat, dry) == 0.0, "a span along the ground is a landing")
	check(StairLayout.sag_over(a, Vector3(1.5, 3, 0), 1.2, flat, dry) == 0.0, "a step's length is no bridge")
	var hill := func(p: Vector3) -> float: return 4.0 if absf(p.x - 5.0) < 1.0 else 0.0
	check(StairLayout.sag_over(a, Vector3(10, 3, 0), 1.2, hill, dry) == 0.0, "a span through a hill does not hang")
	var bed := func(p: Vector3) -> float: return -0.8 if absf(p.x - 5.0) < 3.5 else 0.0
	var pond := func(_x: float, _z: float) -> float: return -0.05
	var banks := StairLayout.sag_over(Vector3(0, 0.1, 0), Vector3(10, 0.1, 0), 1.2, bed, pond)
	check(banks > 0.0, "a span from bank to bank over a pond hangs")
	var deck := StairLayout.new()
	deck.build({"a": Vector3(0, 0.1, 0), "b": Vector3(10, 0.1, 0), "width": 1.2, "sag": banks, "rail": "rope", "seed": 1, "paint": Palette.plain()})
	check(deck.deck(0.5).y >= -0.05 + StairLayout.HANG_KEEP - 0.001 or is_equal_approx(banks, StairLayout.SAG_LEAST), "over the pond the deck keeps over the water: %.3f" % deck.deck(0.5).y)
	var high := StairLayout.sag_over(Vector3(0, 2.5, 0), Vector3(10, 2.5, 0), 1.2, bed, pond)
	check(is_equal_approx(high, 10.0 * StairLayout.SAG), "with room under it, a ten-metre bridge hangs %.2f m: %.3f" % [10.0 * StairLayout.SAG, high])
	var low := StairLayout.sag_over(Vector3(0, 1.0, 0), Vector3(20, 1.0, 0), 1.2, flat, pond)
	check(low > 0.0 and low < 20.0 * StairLayout.SAG and 1.0 - low >= StairLayout.HANG_KEEP - 0.001, "a bridge low over the ground hangs only as far as it keeps over it: %.3f" % low)


func _sag() -> void:
	var d := _bridge(0.7)
	var b := StairLayout.new()
	b.build(d)
	check(b.kind == StairLayout.Kind.BRIDGE, "a hanging span is a bridge")
	check(b.deck(0.0).is_equal_approx(d.a) and b.deck(1.0).is_equal_approx(d.b), "the deck meets both ends")
	var lowest := INF
	var at := 0.0
	for i in 101:
		var y := b.deck(i / 100.0).y - lerpf(d.a.y, d.b.y, i / 100.0)
		if y < lowest:
			lowest = y
			at = i / 100.0
	check(is_equal_approx(at, 0.5) and is_equal_approx(lowest, -0.7), "it hangs its sag below the line at the middle: %.2f at %.2f" % [lowest, at])
	var planks := b.stones.filter(func(p: Dictionary) -> bool: return p.kind == "rail" and p.xform.basis.x.length() > 1.0)
	check(planks.size() == ceili(10.0 / StairLayout.PLANK_PITCH), "a plank every %.2f m: %d" % [StairLayout.PLANK_PITCH, planks.size()])
	var off := 0.0
	var tilted := 0
	for i in planks.size():
		var p: Dictionary = planks[i]
		var top: Vector3 = p.xform.origin + p.xform.basis.y * 0.5
		off = maxf(off, absf(top.y - b.surface(top)))
		if absf(p.xform.basis.z.normalized().y) > 0.05:
			tilted += 1
	check(off < 0.02, "the planks lie along the deck: off by %.3f" % off)
	check(tilted > planks.size() / 2, "the planks tilt with the hang toward the ends: %d of %d" % [tilted, planks.size()])
	var ropes := b.stones.filter(func(p: Dictionary) -> bool: return p.kind == "rope")
	check(ropes.any(func(p: Dictionary) -> bool: return p.xform.origin.y < b.deck(0.5).y and absf(p.xform.origin.x - 5.0) < 0.6), "ropes hang under the planks")
	check(ropes.all(func(p: Dictionary) -> bool: return p.color.is_equal_approx(StairLayout.HEMP * (p.color.r / StairLayout.HEMP.r))), "ropes are hemp")
	check(is_equal_approx(b.surface(Vector3(5, 9, 0)), b.deck(0.5).y) and is_nan(b.surface(Vector3(5, 3, 2))), "the deck is stood on over it, not beside it")
	var again := StairLayout.new()
	again.build(d)
	check(again.stones == b.stones, "the same bridge lays the same pieces")
	var swap := d.duplicate()
	swap.a = d.b
	swap.b = d.a
	again.build(swap)
	check(again.stones == b.stones, "drawn from either end, the same bridge")
	var deeper := StairLayout.new()
	deeper.build(_bridge(1.4))
	check(deeper.deck(0.5).y < b.deck(0.5).y - 0.6, "a deeper sag hangs lower")


func _railings() -> void:
	var looks := {}
	for rail: String in StairLayout.RAILS:
		var b := StairLayout.new()
		b.build(_bridge(0.6, rail))
		var top := func(p: Dictionary) -> float: return p.xform.origin.y + absf(p.xform.basis.y.y) * 0.5
		var high := b.stones.filter(func(p: Dictionary) -> bool: return top.call(p) > b.surface(p.xform.origin) + StairLayout.RAIL_HEIGHT * 0.7)
		var kinds := {}
		for p in high:
			kinds[p.kind] = kinds.get(p.kind, 0) + 1
		looks[rail] = kinds
		check(b.stones.filter(func(p: Dictionary) -> bool: return p.kind == "rope" and p.xform.origin.y < b.deck(0.5).y + 0.05).size() > 0, "%s: the deck hangs on its ropes" % rail)
		if rail == "none":
			check(high.is_empty(), "no railing stands over an unrailed bridge")
			continue
		for side in [-1.0, 1.0]:
			var mid := high.filter(func(p: Dictionary) -> bool: return absf(p.xform.origin.x - 5.0) < 1.5 and signf(p.xform.origin.z) == side)
			check(not mid.is_empty(), "%s: a handrail runs along the %s side at its middle" % [rail, "right" if side > 0 else "left"])
		var hand := high.filter(func(p: Dictionary) -> bool: return absf(p.xform.basis.y.normalized().y) < 0.5)
		var follows := hand.all(func(p: Dictionary) -> bool: return absf(p.xform.origin.y - b.surface(p.xform.origin) - StairLayout.RAIL_HEIGHT) < 0.08)
		check(not hand.is_empty() and follows, "%s: the handrail follows the deck's hang" % rail)
	check(looks.wood.has("rail") and not looks.wood.has("rope"), "wooden railings: posts and rails of wood: %s" % looks.wood)
	check(looks.rope.has("rope") and looks.rope.has("rail"), "rope railings: rope handrails on wooden posts: %s" % looks.rope)
	check(looks.stone.has("rope") and looks.stone.has("block"), "stone railings: rope handrails from stone pillars: %s" % looks.stone)
	var hangers := func(rail: String) -> int:
		var b := StairLayout.new()
		b.build(_bridge(0.6, rail))
		return b.stones.filter(func(p: Dictionary) -> bool: return p.kind == "rope" and absf(p.xform.basis.y.normalized().y) > 0.9).size()
	check(hangers.call("rope") > 10, "rope railings tie down to the deck's ropes")
	var budget := func(rail: String) -> float: return Budget.stairs(_bridge(0.6, rail)).wall_m2
	check(budget.call("rope") > budget.call("none"), "railings are charged on a bridge")


func _single_rope() -> void:
	var b := StairLayout.new()
	var least := _bridge(0.6, "wood", StairLayout.WIDTH.x)
	b.build(least)
	check(StairLayout.single(least) and not StairLayout.railed(least), "at its least width a bridge is a single rope with no railing")
	var ropes := b.stones.filter(func(p: Dictionary) -> bool: return p.kind == "rope")
	check(ropes.size() >= 10 and ropes.all(func(p: Dictionary) -> bool: return absf(p.xform.origin.z) < 0.01), "one rope down the middle")
	check(not b.stones.any(func(p: Dictionary) -> bool: return p.kind == "rail" and p.xform.basis.x.length() > 0.3), "no planks")
	check(ropes.all(func(p: Dictionary) -> bool: return absf(p.xform.origin.y - b.surface(p.xform.origin)) < 0.02), "the rope hangs as the deck would")
	var wider := StairLayout.new()
	wider.build(_bridge(0.6, "wood", StairLayout.WIDTH.x + 0.1))
	check(wider.stones.any(func(p: Dictionary) -> bool: return p.kind == "rail" and p.xform.basis.x.length() > 0.3), "any wider, it is planks again")


func _commands() -> void:
	check(Commands._stairs(_bridge(0.7)) != null, "a bridge is a valid command")
	for bad in [-0.1, StairLayout.SAG_MOST + 0.1, NAN]:
		check(Commands._stairs(_bridge(bad)) == null, "a sag of %s is refused" % bad)
	var bare := _bridge(0.7)
	bare.erase("sag")
	check(Commands._stairs(bare) == null, "stairs without a sag are refused")
	var steep := _bridge(0.7)
	steep.b = Vector3(3, 5, 0)
	check(Commands._stairs(steep) == null, "a steep flight cannot hang")
	check(Commands._stairs(_bridge(10.0 * StairLayout.SAG + 0.1)) == null, "no bridge hangs deeper than its span lets it")
	check(Commands._stairs(_bridge(StairLayout.SAG_LEAST * 0.5)) == null, "nor shallower than the least sag")


## The stairs tool, drawn from one wall's top to another's, hangs a bridge; at a sixth of its height it lays a landing.
func _drawn() -> void:
	var world: World = main.world
	await play([{"op": "wall", "points": [[-5, -4], [-5, 4]], "seconds": 0.3}, {"op": "top", "index": 0, "style": "cap"}, {"op": "wall", "points": [[5, -4], [5, 4]], "seconds": 0.3}, {"op": "top", "index": 1, "style": "cap"}])
	await play([{"op": "stairs", "a": [-5, 0, 0], "b": [5, 0, 0], "on": true, "rail": "rope", "seconds": 0.3}])
	check(world.state.stairs.size() == 1, "the tool lays a bridge")
	var d: Dictionary = world.state.stairs.values()[0]
	check(d.sag > 0.3 and d.on.size() == 2, "drawn between two wall tops, it hangs, tied to both walls: sag %.2f on %s" % [d.sag, d.on])
	var id: int = world.state.stairs.keys()[0]
	check(world.stairs.layouts[id].kind == StairLayout.Kind.BRIDGE, "and is laid as a bridge")
	var span: StairLayout = world.stairs.layouts[id]
	var rope: Dictionary = span.stones.filter(func(p: Dictionary) -> bool: return p.kind == "rope" and p.xform.origin.y > span.surface(p.xform.origin) + 0.5 and p.xform.origin.z > 0.0)[0]
	var at: Vector3 = rope.xform.origin
	var from := at + Vector3(0, 0.6, 0.6)
	check(world.stairs.pick(from, (at - from).normalized(), 5.0).get("kind") == "rope", "a ray meets the bridge's handrail rope")
	var colour := main.palette_tool.aim(from, (at - from).normalized())
	check(colour.get("of") == "stairs" and colour.get("element") == Palette.Element.WOOD, "the colour tool on a bridge's rope paints its woodwork: %s" % colour)
	await play([{"op": "stairs", "a": [-5, 0, -3.5], "b": [-5, 0, 3.5], "on": true, "seconds": 0.3}])
	var along: Array = world.state.stairs.values().filter(func(s: Dictionary) -> bool: return s.a.x == s.b.x)
	check(along.size() == 1 and along[0].sag == 0.0, "drawn along a wall's walk it is a landing on the walk, not a bridge sagging into it: %s" % [along])
	await play([{"op": "bare"}])
	await play([{"op": "stairs", "a": [-5, 0, 0], "b": [5, 0, 0], "ground": true, "seconds": 0.3}])
	check(world.state.stairs.size() == 1 and world.state.stairs.values()[0].sag == 0.0, "drawn along the meadow it is a landing")
	await play([{"op": "bare"}])


func _arch_over_water(l: WallLayout) -> bool:
	return not l.archways().is_empty() and l.archways().all(func(s: float) -> bool: return main.water.pond_at(l.point_at(s).x, l.point_at(s).z) != null)


func _demo() -> void:
	var steps := Driver.read("res://../demo/bridges.json").filter(func(s: Dictionary) -> bool: return s.op != "capture")
	var aim := steps.find_custom(func(s: Dictionary) -> bool: return s.op == "aim")
	steps[aim].erase("capture")
	await play(steps.slice(0, aim))
	await until(func() -> bool: return main.water.ponds.size() >= 2, "the demo's ponds fill")
	var world: World = main.world
	var kinds := {}
	var rails := {}
	var single := 0
	var banks := 0
	for id: int in world.state.stairs:
		var d: Dictionary = world.state.stairs[id]
		kinds[world.stairs.layouts[id].kind] = true
		if StairLayout.classify(d) != StairLayout.Kind.BRIDGE:
			continue
		rails[d.rail] = true
		if StairLayout.single(d):
			single += 1
		var mid: Vector3 = (d.a + d.b) * 0.5
		if d.on.is_empty() and main.water.pond_at(mid.x, mid.z) != null:
			banks += 1
	check(kinds.has(StairLayout.Kind.BRIDGE), "the demo hangs bridges")
	check(rails.size() == StairLayout.RAILS.size(), "a bridge in every railing style: %s" % [rails.keys()])
	check(single == 1, "and one single rope")
	check(banks >= 1, "a bridge from bank to bank across a pond")
	check(main.tool.walls.any(func(w: Wall) -> bool: return not w.layout.fence and _arch_over_water(w.layout)), "a wall drawn across a pond arches over the water")
	await play([steps[aim]])
	var head := main.rig.head.global_position
	var feet := main.rig.global_position.y
	var deck := main.world.stairs.floor_under(Vector3(head.x, feet + 0.1, head.z))
	check(absf(feet - deck) < 0.05 and feet > 1.5, "the demo's teleport stands on a bridge's deck: %.2f over %.2f at %s" % [feet, deck, head])
	await play([{"op": "bare"}])


## The bridges/* phases follow the last wipe: a bridge over every pond of the stress scene.
func _stress() -> void:
	var steps := Driver.read("res://../demo/stress.json")
	var aerial := steps.find_custom(func(s: Dictionary) -> bool: return s.get("name", "") == "bridges/aerial")
	check(aerial >= 0 and steps.any(func(s: Dictionary) -> bool: return s.get("name", "") == "bridges/ground"), "the stress scene has bridges/aerial and bridges/ground phases")
	if aerial < 0:
		return
	var wiped := aerial
	while steps[wiped].op != "bare":
		wiped -= 1
	await play([steps[0]] + steps.slice(wiped, aerial).filter(func(s: Dictionary) -> bool: return s.op in ["bare", "dig", "wait", "stairs"]))
	var world: World = main.world
	var digs := steps.slice(wiped, aerial).filter(func(s: Dictionary) -> bool: return s.op == "dig")
	check(digs.all(func(s: Dictionary) -> bool: return main.water.pond_at(s.x, s.z) != null), "every stress pond fills")
	for dig: Dictionary in digs:
		var over: Array = world.state.stairs.keys().filter(func(id: int) -> bool:
			var d: Dictionary = world.state.stairs[id]
			var mid: Vector3 = (d.a + d.b) * 0.5
			return world.stairs.layouts[id].kind == StairLayout.Kind.BRIDGE and Vector2(mid.x, mid.z).distance_to(Vector2(dig.x, dig.z)) < 2.0)
		check(over.size() >= 1, "a bridge hangs over the pond at %s, %s" % [dig.x, dig.z])
