extends "res://../tests/support/suite.gd"

## Headless checks of moving and copying builds: a grip carries and turns a wall, a fence, a house and a tower, each one
## reshape that takes its fittings and ivy along and one undo puts back; a tap of the colour tool takes one build's look
## and a tap on another lays it there as far as that build takes it, one undo step; `demo/move.json` and the stress
## scene's `move/*` phase do both: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_move.gd

var world: World
var tool: WallTool
var palette: PaletteTool


func _initialize() -> void:
	boot_main()
	_run.call_deferred()


func _run() -> void:
	await process_frame
	world = main.world
	tool = main.tool
	palette = main.palette_tool
	await play([
		{"op": "budget", "bounded": false},
		{"op": "place", "x": 0, "z": 14},
		{"op": "wall", "points": [[-12, 0], [-4, 0]], "seconds": 0.3},
		{"op": "lift_wall", "index": -1, "height": 3.0},
		{"op": "fit", "what": "opening", "index": -1, "s": 2.0, "y": 1.0},
		{"op": "fit", "what": "lantern", "index": -1, "s": 5.0, "y": 1.7, "side": 1.0},
		{"op": "fit", "what": "flag", "index": -1, "s": 6.5},
		{"op": "fence", "points": [[-12, 6], [-6, 6]], "seconds": 0.3},
		{"op": "house", "at": [4, 0], "size": [6, 4], "seconds": 0.3},
		{"op": "fit", "what": "opening", "index": -1, "s": 13.0, "y": 1.0},
		{"op": "fit", "what": "lantern", "index": -1, "s": 14.8, "y": 1.7, "side": 1.0},
		{"op": "fit", "what": "chimney", "index": -1, "at": [1.5, 0.6]},
		{"op": "house", "round": true, "at": [14, 0], "size": [3.4, 3.4], "seconds": 0.3},
		{"op": "house", "at": [4, 10], "size": [5, 4], "seconds": 0.3},
	])
	await _settled()
	await _a_wall_carries_its_fittings_and_ivy()
	await _a_fence_is_carried_and_turned()
	await _a_house_carries_its_roof_fittings_and_ivy()
	await _a_tower_turns_about_its_middle()
	await _a_tap_copies_a_look()
	await _a_look_goes_as_far_as_a_build_takes_it()
	await _the_demo_and_the_stress_scene_carry_and_copy()
	finish()


func _settled() -> void:
	await until(func() -> bool: return not tool.walls.any(func(w: Wall) -> bool: return w.laying()), "every wall laid")


func _wall(i: int) -> Wall:
	return tool.walls[i]


## Carries build `w` as a grip does, its hand moved `move` along the ground and turned `degrees`, and lets it go.
func _carry(w: Wall, move: Vector3, degrees: float) -> void:
	tool.take_build(w)
	var start: Dictionary = tool.held_at.duplicate()
	var from := Transform3D(Basis(), start.center + Vector3(0, 1.2, 2.0))
	var to := Transform3D(Basis(Vector3.UP, deg_to_rad(degrees)), from.origin + move)
	tool.stand_build(WallTool.carry(start, from, to, 1.0))
	tool.end_build()
	await _settled()


## Where `p` stands once carried by `move` and turned `degrees` about `middle`, across the ground.
static func _moved(p: Vector3, middle: Vector3, move: Vector3, degrees: float) -> Vector2:
	var q := middle + move + Basis(Vector3.UP, deg_to_rad(degrees)) * Vector3(p.x - middle.x, 0.0, p.z - middle.z)
	return Vector2(q.x, q.z)


static func _all_moved(was: PackedVector3Array, now: PackedVector3Array, middle: Vector3, move: Vector3, degrees: float) -> bool:
	if was.size() != now.size():
		return false
	for i in was.size():
		if _moved(was[i], middle, move, degrees).distance_to(Vector2(now[i].x, now[i].z)) > 1e-3:
			return false
	return true


## Where ivy roots and climbs along a wall's faces, which the ground under it does not change.
static func _ivy(w: Wall) -> Array:
	return IvyLayout.grow(w.layout).map(func(l: Dictionary) -> Vector2: return Vector2(snappedf(l.s, 0.001), l.side))


## Whether two growths of ivy have the same leaves on the same faces, each within 0.1 m along of the other.
static func _alike(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i].y != b[i].y or absf(a[i].x - b[i].x) > 0.1:
			return false
	return true


## The fields a carry keeps: everything but where the build stands.
static func _kept(d: Dictionary) -> Dictionary:
	var out := d.duplicate(true)
	out.erase("points")
	if out.has("roof"):
		out.roof.erase("center")
	return out


## A grip carries a wall 6 m and turns it 90° about its middle: one reshape carries its line, its window, lantern and
## flag keep their places along it, its ivy climbs as it did and stays grown; one undo puts it back, a redo carries it
## again.
func _a_wall_carries_its_fittings_and_ivy() -> void:
	var w := _wall(0)
	var was: Dictionary = world.state.walls[w.id].duplicate(true)
	check(not was.openings.is_empty() and not was.lanterns.is_empty() and not was.flags.is_empty(), "the wall has a window, a lantern and a flag")
	var ivy := _ivy(w)
	check(ivy.size() > 10, "and ivy: %d leaves" % ivy.size())
	w.ivy_age = 1000.0
	var seq := world.seq
	var middle: Vector3 = WallTool.line_of(was).center
	var move := Vector3(0, 0, -6)
	await _carry(w, move, 90.0)
	var now: Dictionary = world.state.walls[w.id]
	check(world.seq == seq + 1, "one carry is one command")
	check(_all_moved(was.points, now.points, middle, move, 90.0), "its line is carried 6 m and turned 90° about its middle: %s" % now.points)
	check(_kept(now) == _kept(was), "its window, lantern, flag, seed and paint go along unchanged")
	check(_ivy(w) == ivy and w.ivy_age >= 1000.0, "its ivy climbs where it did along it and stays grown")
	world._order({"op": "undo"}, world.me())
	await _settled()
	check(world.state.walls[w.id].points == was.points and _ivy(w) == ivy, "one undo puts it back where it stood")
	world._order({"op": "redo"}, world.me())
	await _settled()
	check(world.state.walls[w.id].points == now.points, "a redo carries it again")


## A fence carries and turns as a wall does, rails and all.
func _a_fence_is_carried_and_turned() -> void:
	var w := _wall(1)
	var was: Dictionary = world.state.walls[w.id].duplicate(true)
	check(was.fence, "the second build is a fence")
	var middle: Vector3 = WallTool.line_of(was).center
	var move := Vector3(4, 0, 2)
	await _carry(w, move, -45.0)
	check(_all_moved(was.points, world.state.walls[w.id].points, middle, move, -45.0) and _kept(world.state.walls[w.id]) == _kept(was), "a fence is carried and turned 45° as a wall is")
	world._order({"op": "undo"}, world.me())
	await _settled()
	check(world.state.walls[w.id].points == was.points, "one undo puts it back")


## A grip carries a house 5 m and turns it 90°: its walls and roof go together, its window, lantern and chimney keep
## their places on it, its ivy climbs as it did, steering round its window as the ground under it lets; one undo puts it
## back.
func _a_house_carries_its_roof_fittings_and_ivy() -> void:
	var w := _wall(2)
	var was: Dictionary = world.state.walls[w.id].duplicate(true)
	check(was.has("roof") and not was.openings.is_empty() and not was.lanterns.is_empty() and not was.roof.chimneys.is_empty(), "the house has a window, a lantern and a chimney")
	var ivy := _ivy(w)
	var middle: Vector3 = was.roof.center
	var move := Vector3(-2, 0, 4.5)
	await _carry(w, move, 90.0)
	var now: Dictionary = world.state.walls[w.id]
	check(_all_moved(was.points, now.points, middle, move, 90.0), "its walls are carried and turned 90°: %s" % now.points)
	check(_kept(now) == _kept(was), "its window, lantern and chimney keep their places on it, its roof its shape")
	check(_alike(_ivy(w), ivy), "its ivy climbs where it did on its walls")
	world._order({"op": "undo"}, world.me())
	await _settled()
	check(world.state.walls[w.id] == was, "one undo puts it back")


## A round tower carries and turns about its middle, its cone with it.
func _a_tower_turns_about_its_middle() -> void:
	var w := _wall(3)
	var was: Dictionary = world.state.walls[w.id].duplicate(true)
	check(was.roof.kind == RoofLayout.Kind.CONE, "the fourth build is a tower")
	var middle: Vector3 = was.roof.center
	var move := Vector3(1, 0, -3)
	await _carry(w, move, 30.0)
	var now: Dictionary = world.state.walls[w.id]
	var centre := Vector3.ZERO
	for p: Vector3 in now.points:
		centre += p / now.points.size()
	var to := _moved(middle, middle, move, 30.0)
	check(Vector2(centre.x, centre.z).distance_to(to) < 1e-3 and Vector2(now.roof.center.x, now.roof.center.z).distance_to(to) < 1e-3 and is_equal_approx(now.roof.radius, was.roof.radius), "a tower is carried and turned, its cone with it: %s from %s, %s from %s" % [now.points, was.points, now.roof.center, was.roof.center])
	world._order({"op": "undo"}, world.me())
	await _settled()
	check(world.state.walls[w.id] == was, "one undo puts it back")


## The look `look_of` reads, as a build has it.
static func _look(d: Dictionary) -> Dictionary:
	var look := PaletteTool.look_of(d)
	look.erase("foundation")
	return look


## A tap of the colour tool's trigger on a house takes its paint, face, top, gable ends, floor and roof covering; a tap
## on another house lays them all there, one reshape and one undo step, and leaves the first as it was. The look stays
## in the hand for the next tap, a long press turns the wheel instead, and a tap on the meadow lets the look go.
func _a_tap_copies_a_look() -> void:
	var a := _wall(2)
	var b := _wall(4)
	world._order({"op": "reshape", "of": "walls", "id": a.id, "data": {"finish": WallLayout.Finish.PLASTER, "wear": 0.25, "gable_end": WallLayout.GableEnd.STEPS, "top": WallLayout.Top.COPE, "planks": true, "paint": {Palette.Element.PLASTER: 2, Palette.Element.ROOF: 3, Palette.Element.THATCH: 4, Palette.Element.STONE: 5}, "roof": {"thatch": true}}}, world.me())
	await _settled()
	var source: Dictionary = world.state.walls[a.id].duplicate(true)
	var target: Dictionary = world.state.walls[b.id].duplicate(true)
	check(_look(source) != _look(target), "two houses of different looks")
	var hand := main.rig.right
	await play([{"op": "tap", "hand": "right", "from": [4, 1.5, 6], "at": [4, 1.2, 2]}])
	check(palette.looks.has(hand) and palette.looks[hand] == PaletteTool.look_of(source), "a tap on the first house takes its look into the hand")
	check(world.state.walls[a.id] == source, "and changes nothing")
	var seq := world.seq
	await play([{"op": "tap", "hand": "right", "from": [4, 1.5, 14], "at": [4, 1.2, 12]}])
	await _settled()
	var copied: Dictionary = world.state.walls[b.id]
	check(world.seq == seq + 1, "a tap on the second lays it as one command")
	check(_look(copied) == _look(source), "the second house takes the first's paint, face, top, gable ends, floor and thatch: %s" % _look(copied))
	check(copied.points == target.points and copied.openings == target.openings and copied.roof.pitch == target.roof.pitch, "and keeps its own place, size, fittings and roof's shape")
	check(world.state.walls[a.id] == source and palette.looks.has(hand), "the first is as it was, and the look stays in the hand")
	world._order({"op": "undo"}, world.me())
	await _settled()
	check(world.state.walls[b.id] == target, "one undo gives the second its own look back")
	world._order({"op": "redo"}, world.me())
	await _settled()
	check(_look(world.state.walls[b.id]) == _look(source), "a redo lays it again")
	seq = world.seq
	await play([{"op": "tap", "hand": "right", "from": [4, 1.5, 14], "at": [4, 1.2, 12]}])
	check(world.seq == seq, "a tap on a build that has the look already sends nothing")
	palette.open(hand, palette.aim(Vector3(4, 1.5, 6), (Vector3(4, 1.2, 2) - Vector3(4, 1.5, 6)).normalized()))
	palette.wheels[hand].dial.held = PaletteTool.TAP
	palette.close(hand)
	check(world.seq == seq and palette.looks[hand] == PaletteTool.look_of(source), "a press held past a tap is the wheel's, and changes nothing")
	palette.open(hand, palette.aim(Vector3(4, 1.5, 6), (Vector3(4, 1.2, 2) - Vector3(4, 1.5, 6)).normalized()))
	palette.close(hand, false)
	check(world.seq == seq and palette.looks[hand] == PaletteTool.look_of(source), "a wheel closed by putting the tool down taps nothing")
	await play([{"op": "tap", "hand": "right", "from": [0, 1.5, 20], "at": [0, 0, 16]}])
	check(not palette.looks.has(hand), "a tap on the meadow lets the look go")
	await play([{"op": "tap", "hand": "right", "from": [4, 1.5, 14], "at": [4, 1.2, 12]}])
	hand.tool = Hand.Tool.WALLS
	await process_frame
	check(not palette.looks.has(hand), "and so does putting the colour tool down")
	world._order({"op": "undo"}, world.me())
	await _settled()


## A house's look laid on a wall gives it the house's paint and face, a roofless wall taking no covering; laid on a
## fence it gives its paint alone, a fence keeping a fence's face; a fence's look laid on a house gives its paint and
## leaves its face.
func _a_look_goes_as_far_as_a_build_takes_it() -> void:
	var house: Dictionary = world.state.walls[_wall(2).id]
	var wall: Dictionary = world.state.walls[_wall(0).id]
	var fence: Dictionary = world.state.walls[_wall(1).id]
	var onto_wall := PaletteTool.look_onto(PaletteTool.look_of(house), wall)
	check(onto_wall.finish == WallLayout.Finish.PLASTER and is_equal_approx(onto_wall.wear, 0.25) and onto_wall.paint.get(Palette.Element.PLASTER) == 2 and not onto_wall.has("roof"), "a wall takes a house's face and paint, and no covering: %s" % onto_wall)
	var onto_fence := PaletteTool.look_onto(PaletteTool.look_of(house), fence)
	check(not onto_fence.has("finish") and not onto_fence.has("foundation") and onto_fence.paint.get(Palette.Element.STONE) == 5, "a fence takes a house's paint and keeps a fence's face: %s" % onto_fence)
	var cmd := Commands.clean({"op": "reshape", "of": "walls", "id": _wall(1).id, "data": onto_fence}, world.state, false, world.terrain)
	check(not cmd.is_empty(), "and the garden takes it")
	var fenced := PaletteTool.look_of(fence)
	fenced.paint[Palette.Element.WOOD] = 4
	var onto_house := PaletteTool.look_onto(fenced, house)
	check(not onto_house.has("finish") and onto_house.paint.get(Palette.Element.WOOD) == 4, "a house takes a fence's paint and keeps its face: %s" % onto_house)
	check(PaletteTool.look_onto(PaletteTool.look_of(house), house).is_empty(), "a build's own look lays nothing on it")


## `demo/move.json` carries and turns a house, a wall and a tree and copies a look. The stress scene's `move/carry` phase
## carries the largest house of its densest village a player can build, two storeys and a wing to each house, the
## budget full, across the village and turns it round; played here, the garden takes the carry, its upper storey
## going with it.
func _the_demo_and_the_stress_scene_carry_and_copy() -> void:
	var demo := Driver.read("res://../demo/move.json")
	var ops := demo.map(func(s: Dictionary) -> String: return s.op)
	check(ops.has("resize") and ops.has("carry") and ops.count("tap") >= 2 and ops.has("capture"), "the demo carries, turns and copies, and renders it: %s" % [ops])
	var steps := Driver.read("res://../demo/stress.json")
	var at := steps.find_custom(func(s: Dictionary) -> bool: return s.op == "label" and s.get("name", "") == "move/carry")
	check(at > 0 and not steps[at].get("past_budget", false), "the stress scene has a move/carry phase, held to the frame budget")
	if at < 0:
		return
	var village := village_before(steps, at)
	var bounded := village
	while steps[bounded].op != "budget":
		bounded -= 1
	check(steps[bounded].bounded and steps[village].get("storeys", 1) == 2 and steps[village].get("wings", false), "in a village of two storeys and wings, as dense as the budget lets a player build: %s" % steps[village])
	var carry: Dictionary = steps[at + 1]
	check(carry.op == "resize" and carry.get("largest", false) and Vector2(carry.move[0], carry.move[1]).length() >= 2.0 * steps[village].radius, "it carries the largest house across it: %s" % carry)
	await play([{"op": "bare"}, steps[bounded], steps[village]])
	await _settled()
	var house := Driver.largest(tool)
	var id := house.id
	var was: Dictionary = world.state.walls[id].duplicate(true)
	var upper := tool.walls.filter(func(w: Wall) -> bool: return w.on.has(id)).map(func(w: Wall) -> int: return w.id)
	check(not upper.is_empty(), "the largest house carries an upper storey")
	var seq := world.seq
	var quick := carry.duplicate()
	quick.seconds = 0.5
	await play([quick])
	await _settled()
	var middle: Vector3 = was.roof.center
	var to := Vector3(carry.move[0], 0, carry.move[1])
	check(world.seq == seq + 1 and _all_moved(was.points, world.state.walls[id].points, middle, to, carry.turn), "the garden takes the carry across the village, turned round: %d commands, %s from %s" % [world.seq - seq, world.state.walls[id].points, was.points])
	var along := true
	for u: int in upper:
		var c: Vector3 = WallTool.line_of(world.state.walls[u]).center
		along = along and Vector2(c.x, c.z).distance_to(Vector2(middle.x + to.x, middle.z + to.z)) < 6.0
	check(along, "its upper storey goes with it")
	await play([{"op": "bare"}])
