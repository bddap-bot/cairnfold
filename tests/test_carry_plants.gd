extends "res://../tests/support/suite.gd"

## Headless checks of a grip carrying trees and bushes, planted and the meadow's own: one hand moves one along the
## ground, farther for a far one, and turns it about its foot as the hand turns; let go, it is set as one `tree` command,
## one undo step, which a peer takes and a snapshot keeps; two hands still size a tree and leave a bush as it is:
## godot4 --headless --fixed-fps 60 --path game --script ../tests/test_carry_plants.gd

var world: World
var flora: Flora
var tool: WallTool


func _initialize() -> void:
	boot_main()
	_run.call_deferred()


func _run() -> void:
	await process_frame
	world = main.world
	flora = main.flora_tool.flora
	tool = main.tool
	await _a_planted_tree_is_carried()
	_a_tree_turns_with_the_hand()
	_meadow_plants_are_carried()
	_bushes_are_carried_not_sized()
	_commands_are_checked()
	finish()


## A cleaned command as the host would send it on, checked again as a peer checks it.
func _relayed(cmd: Dictionary, by: int) -> Dictionary:
	var hosted := Commands.clean(cmd, world.state, false, world.terrain)
	hosted.seq = world.seq + 1
	hosted.by = by
	return Commands.clean(hosted, world.state, true, world.terrain)


func _across(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


## Takes `first` in the right hand from 2 m off, a metre over its foot, as a grip does; returns the hand's pose.
func _take(first: Flora.Plant) -> Transform3D:
	var grip := first.foot() + Vector3.UP
	var hand := Transform3D(Basis(), grip + Vector3.BACK * 2.0)
	tool.begin_grow(tool.mason(main.rig.right), first, hand, grip)
	return hand


## Carries `first` by a hand moved `move` from where it took it, and lets go.
func _carry(first: Flora.Plant, move: Vector3) -> void:
	var m := tool.mason(main.rig.right)
	var hand := _take(first)
	m.sizing.follow.call(m, hand.translated(move))
	tool.end_grow(m)


## One hand carries a planted tree along the ground, `reach_gain` times as far as the hand, whole and as tall, shown here
## alone until let go; then the garden sets it there in one step that an undo takes back and a redo puts again, keeping
## its species and moss; what strikes it, what walls arch over and its shade follow it, and a snapshot keeps it there.
func _a_planted_tree_is_carried() -> void:
	var at := world.terrain.ground(-6, 18)
	world._order({"op": "plant", "kind": "tree", "seed": 7, "at": at}, world.me())
	var g := world.seq
	world._order({"op": "tree", "group": g, "index": 0, "species": FloraLayout.Species.FIR, "moss": true}, world.me())
	var parts: Array = flora.groups[g]
	var trunk: Flora.Plant = parts[0]
	var top := flora.top_of(trunk)
	var crown: Vector3 = parts[1].xform.origin - trunk.anchor
	var shade := flora.shade_of(parts).origin - trunk.anchor
	var m := tool.mason(main.rig.right)
	var hand := _take(trunk)
	var move := Vector3(3.0, 0.8, -1.0)
	m.sizing.follow.call(m, hand.translated(move))
	var gain := Hand.reach_gain(2.0)
	var to := _across(at) + _across(move) * gain
	check(_across(trunk.anchor).distance_to(to) < 0.01, "a grip carries a tree along the ground, %.2f times as far as the hand: %s, not %s" % [gain, _across(trunk.anchor), to])
	check(is_equal_approx(trunk.anchor.y, 0.0) and (parts[1].xform.origin - trunk.anchor).is_equal_approx(crown) and is_equal_approx(flora.top_of(trunk), top), "its crown goes with it, as tall, on the ground there")
	check(world.state.groups[g].places.is_empty(), "shown here alone while held")
	tool.end_grow(m)
	var placed: Vector3 = world.state.groups[g].places.get(0, Vector3.INF)
	check(_across(placed).distance_to(to) < 0.01 and _across(trunk.anchor).distance_to(to) < 0.01, "let go, the garden sets it there: %s" % placed)
	check(flora.species_of(trunk) == FloraLayout.Species.FIR and world.state.groups[g].moss.get(0, false) and flora.scale_of(trunk) == 1.0, "a fir still, with its moss, as tall")
	await process_frame
	check(flora.shade_of(parts).origin.is_equal_approx(trunk.anchor + shade), "its shade goes with it")
	var struck := func(over: Vector2) -> bool: return flora.solid_hit(Vector3(over.x, 40.0, over.y), Vector3.DOWN, 60.0).get("plants", []) == parts
	check(struck.call(to), "a ray down onto it where it stands now strikes it")
	check(not struck.call(_across(at)), "and one where it stood does not")
	check(Array(flora.obstacles()).any(func(p: Vector3) -> bool: return _across(p).distance_to(to) < 0.01), "a wall arches over it where it stands now")
	var seq := world.seq
	_carry(trunk, Vector3(0.02, 0.0, 0.0))
	check(world.seq == seq and _across(trunk.anchor).distance_to(to) < 0.01, "let go within a trembling hand's nudge, nothing is sent and it stays")
	world._order({"op": "undo"}, world.me())
	check(_across(trunk.anchor).distance_to(_across(at)) < 0.01 and flora.species_of(trunk) == FloraLayout.Species.FIR, "one undo sets it back where it was planted, still a fir")
	check(struck.call(_across(at)), "and a ray strikes it there again")
	world._order({"op": "redo"}, world.me())
	check(_across(trunk.anchor).distance_to(to) < 0.01, "a redo carries it again")
	var picture := var_to_str(world.digest())
	world.restore(world.snapshot())
	trunk = flora.groups[g][0]
	check(var_to_str(world.digest()) == picture and _across(trunk.anchor).distance_to(to) < 0.01 and flora.species_of(trunk) == FloraLayout.Species.FIR, "a snapshot keeps it there, a fir")
	world.restore({"seq": 0, "cmds": []})


## A hand turned as it carries a tree turns the tree about its foot as far, its crown with it, and its species, size and
## moss stay; let go, its turn is set with its place, one undo step, kept through a restyle and a snapshot. A meadow
## tree turns too, and stands as it grew in a swapped garden.
func _a_tree_turns_with_the_hand() -> void:
	var at := world.terrain.ground(-8, 14)
	world._order({"op": "plant", "kind": "tree", "seed": 11, "at": at}, world.me())
	var g := world.seq
	var parts: Array = flora.groups[g]
	var trunk: Flora.Plant = parts[0]
	var crown := _across(parts[1].xform.origin - trunk.anchor)
	var top := flora.top_of(trunk)
	var m := tool.mason(main.rig.right)
	var hand := _take(trunk)
	var turn := deg_to_rad(70.0)
	m.sizing.follow.call(m, Transform3D(Basis(Vector3.UP, turn), hand.origin + Vector3(1.0, 0.0, 0.0)))
	check(is_equal_approx(flora.turn_of(trunk), turn), "a hand turned 70° turns the tree it carries as far: %.1f°" % rad_to_deg(flora.turn_of(trunk)))
	var turned := _across(parts[1].xform.origin - trunk.anchor)
	check(turned.distance_to(crown.rotated(-turn)) < 0.01 and is_equal_approx(flora.top_of(trunk), top), "its crown turns about its foot with it, as tall: %s from %s" % [turned, crown])
	check(not world.state.groups[g].turns.has(0), "shown here alone while held")
	tool.end_grow(m)
	check(is_equal_approx(world.state.groups[g].turns.get(0, 0.0), turn) and world.state.groups[g].places.has(0), "let go, the garden sets its turn with its place")
	world._order({"op": "tree", "group": g, "index": 0, "species": FloraLayout.Species.BIRCH}, world.me())
	check(is_equal_approx(flora.turn_of(trunk), turn) and trunk.xform.basis.x.is_equal_approx(Basis(Vector3.UP, turn) * FloraLayout.tree(trunk.foot(), flora._solids[Vector2i(0, trunk.slot)].seed, FloraLayout.Species.BIRCH).trunk.basis.x), "restyled, it keeps its turn")
	world._order({"op": "undo"}, world.me())
	world._order({"op": "undo"}, world.me())
	check(is_zero_approx(flora.turn_of(trunk)) and _across(parts[1].xform.origin - trunk.anchor).distance_to(crown) < 0.01 and not world.state.groups[g].turns.has(0), "one undo turns it back as it grew")
	world._order({"op": "redo"}, world.me())
	check(is_equal_approx(flora.turn_of(trunk), turn), "a redo turns it again")
	var picture := var_to_str(world.digest())
	world.restore(world.snapshot())
	trunk = flora.groups[g][0]
	check(var_to_str(world.digest()) == picture and is_equal_approx(flora.turn_of(trunk), turn), "a snapshot keeps its turn")
	world.restore({"seq": 0, "cmds": []})
	var oak: Flora.Plant = flora.groups[0][flora.meadow_trees()[1]]
	m = tool.mason(main.rig.right)
	hand = _take(oak)
	m.sizing.follow.call(m, Transform3D(Basis(Vector3.UP, -turn), hand.origin))
	tool.end_grow(m)
	check(is_equal_approx(world.state.groups[0].turns.get(oak.index, 0.0), -turn) and not world.state.groups[0].places.has(oak.index), "a meadow tree turned where it stands sends its turn alone")
	world.restore({"seq": 0, "cmds": []})
	check(is_zero_approx(flora.turn_of(oak)), "and stands as it grew in an empty garden")
	for bad: Variant in [1, "left", NAN, INF]:
		check(Commands.clean({"op": "tree", "group": 0, "index": oak.index, "turn": bad}, world.state, false, world.terrain).is_empty(), "no turn %s" % [bad])
	check(is_equal_approx(Commands.clean({"op": "tree", "group": 0, "index": oak.index, "turn": TAU + 0.5}, world.state, false, world.terrain).get("turn", 0.0), 0.5), "a turn is kept within a circle")


## The meadow's own trees and bushes carry as planted ones do, and stand where they grew in a swapped garden.
func _meadow_plants_are_carried() -> void:
	for first: Flora.Plant in [flora.groups[0][flora.meadow_trees()[3]], flora.groups[0][flora.meadow_bushes()[2]]]:
		var what := "tree" if first.pool == flora.trunks else "bush"
		var home := _across(first.anchor)
		_carry(first, Vector3(-1.0, 0.0, 1.0))
		var to := home + Vector2(-1.0, 1.0) * Hand.reach_gain(2.0)
		var placed: Vector3 = world.state.groups[0].places.get(first.index, Vector3.INF)
		check(_across(first.anchor).distance_to(to) < 0.01 and _across(placed).distance_to(to) < 0.01, "a meadow %s is carried and set" % what)
		var snap := world.snapshot()
		world.restore({"seq": 0, "cmds": []})
		check(_across(first.anchor).distance_to(home) < 0.01, "an empty garden has the meadow %s where it grew" % what)
		world.restore(snap)
		check(_across(first.anchor).distance_to(to) < 0.01, "and its snapshot where it was carried")
		world.restore({"seq": 0, "cmds": []})


## One hand carries a planted bush; two hands on it size nothing and send nothing.
func _bushes_are_carried_not_sized() -> void:
	var at := world.terrain.ground(4, 16)
	world._order({"op": "plant", "kind": "bush", "seed": 3, "at": at}, world.me())
	var g := world.seq
	var blob: Flora.Plant = flora.groups[g][0]
	var look := blob.xform.basis
	_carry(blob, Vector3(0.0, 0.0, 1.2))
	var to := _across(at) + Vector2(0.0, 1.2) * Hand.reach_gain(2.0)
	check(_across(blob.anchor).distance_to(to) < 0.01 and _across(world.state.groups[g].places.get(0, Vector3.INF)).distance_to(to) < 0.01, "a bush is carried and set")
	check(flora.solid_hit(Vector3(to.x, 40.0, to.y), Vector3.DOWN, 60.0).get("plants", []) == flora.groups[g], "a ray strikes it where it stands now")
	var seq := world.seq
	var right := tool.mason(main.rig.right)
	var left := tool.mason(main.rig.left)
	var mid := blob.foot() + Vector3.BACK * 2.0
	for m: WallTool.Mason in [right, left]:
		m.hand.global_position = mid + Vector3.RIGHT * (0.5 if m == right else -0.5)
		tool.begin_grow(m, blob, m.hand.global_transform, blob.foot())
	tool.drag_pair(left, mid + Vector3.RIGHT, mid + Vector3.LEFT)
	tool.end_grow(left)
	tool.end_grow(right)
	check(world.seq == seq and blob.xform.basis.is_equal_approx(look), "two hands leave a bush its size, and send nothing")
	world._order({"op": "undo"}, world.me())
	check(_across(blob.anchor).distance_to(_across(at)) < 0.01, "an undo sets it back")
	world.restore({"seq": 0, "cmds": []})


## A carry's command as a peer checks it: a place on the map for a tree or bush, a size for a tree alone.
func _commands_are_checked() -> void:
	world._order({"op": "plant", "kind": "tree", "seed": 5, "at": world.terrain.ground(2, 12)}, world.me())
	var tree := world.seq
	world._order({"op": "plant", "kind": "bush", "seed": 6, "at": world.terrain.ground(3, 12)}, world.me())
	var bush := world.seq
	var there := world.terrain.ground(5, 14)
	check(_relayed({"op": "tree", "group": tree, "index": 0, "at": there}, 2).get("at") == there, "a peer takes a tree's new place")
	check(_relayed({"op": "tree", "group": bush, "index": 0, "at": there}, 2).get("at") == there, "and a bush's")
	var meadow_bush: int = flora.meadow_bushes()[0]
	check(_relayed({"op": "tree", "group": 0, "index": meadow_bush, "at": there}, 2).get("at") == there, "and a meadow bush's")
	check(Commands.clean({"op": "tree", "group": bush, "index": 0, "at": there, "scale": 1.5}, world.state, false, world.terrain).is_empty(), "a bush takes no size")
	check(Commands.clean({"op": "tree", "group": 0, "index": meadow_bush, "species": 1}, world.state, false, world.terrain).is_empty(), "nor a species")
	var grass := Array(flora.groups[0]).find_custom(func(p: Flora.Plant) -> bool: return p != null and p.pool == flora.grass)
	check(Commands.clean({"op": "tree", "group": 0, "index": grass, "at": there}, world.state, false, world.terrain).is_empty(), "grass is not carried")
	for bad: Variant in [Vector2(5, 14), Vector3(NAN, 0, 0), Vector3(1e6, 0, 0), "here"]:
		check(Commands.clean({"op": "tree", "group": tree, "index": 0, "at": bad}, world.state, false, world.terrain).is_empty(), "no place %s" % [bad])
	world._order({"op": "tree", "group": tree, "index": 0, "at": there}, 2)
	check(_across(flora.groups[tree][0].anchor).distance_to(_across(there)) < 0.01, "a peer's carry moves it here too")
	world.restore({"seq": 0, "cmds": []})
