extends SceneTree

## Headless checks of the garden's command log and per-player undo, with two players' commands fed to the
## host directly: godot4 --headless --path game --script ../tests/test_world.gd

var failures := 0
var main: Node
var world: World


func _initialize() -> void:
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	await process_frame
	world = main.world
	_undo_takes_back_only_your_own_steps()
	_your_later_steps_never_block_your_earlier_ones()
	_a_step_someone_built_on_is_skipped()
	_redo_waits_on_the_same_condition()
	_bad_commands_are_dropped()
	_ground_undo_waits_on_overlapping_ground()
	_stacks_keep_their_newest_steps()
	_undo_restores_exact_values()
	await _ghosts_go_when_their_command_settles()
	_a_seed_decides_its_plants()
	_ghost_paths_never_change_what_grows()
	_snapshot_rebuilds_the_garden()
	_restore_forgets_history()
	await _a_storey_follows_what_it_stands_on()
	_a_stroke_painted_out_of_step_stays_shown()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _wall(by: int, x: float) -> int:
	world._order({"op": "wall", "walls": [{"points": PackedVector3Array([Terrain.ground(x, -5), Terrain.ground(x + 4, -5)]), "height": 2.6, "arches": PackedFloat32Array(), "seed": 3, "closed": false, "top": 0, "fence": false, "windows": PackedVector2Array(), "lanterns": PackedVector3Array(), "flags": PackedFloat32Array(), "ruins": PackedVector2Array(), "on": PackedInt32Array()}]}, by)
	return world.seq * Commands.MAX_PIECES


func _height(id: int) -> float:
	return world.state.walls[id].height if world.state.walls.has(id) else -1.0


func _undo_takes_back_only_your_own_steps() -> void:
	var a := _wall(1, 0)
	var b := _wall(2, 10)
	world._order({"op": "undo"}, 1)
	_check(not world.state.walls.has(a) and world.state.walls.has(b), "player 1's undo takes their wall, not player 2's later one")
	world._order({"op": "undo"}, 2)
	_check(not world.state.walls.has(b), "player 2's undo takes theirs")
	_check(main.tool.walls.is_empty(), "and the wall nodes go with them")


func _your_later_steps_never_block_your_earlier_ones() -> void:
	var a := _wall(1, 0)
	world._order({"op": "reshape", "id": a, "data": {"height": 4.0}}, 1)
	world._order({"op": "undo"}, 1)
	_check(is_equal_approx(_height(a), 2.6), "undo lowers the wall back")
	world._order({"op": "undo"}, 1)
	_check(not world.state.walls.has(a), "the next undo takes down the wall the same player raised")


func _a_step_someone_built_on_is_skipped() -> void:
	world._order({"op": "plant", "kind": "tree", "seed": 4, "at": Terrain.ground(-8, 6)}, 1)
	var tree := world.seq
	var a := _wall(1, 0)
	world._order({"op": "reshape", "id": a, "data": {"height": 5.0}}, 2)
	var before := world.seq
	world._order({"op": "undo"}, 1)
	_check(world.state.walls.has(a) and is_equal_approx(_height(a), 5.0), "player 1's undo leaves the wall player 2 raised standing as raised")
	_check(world.state.groups[tree].hidden.size() > 0, "and goes on to player 1's tree")
	_check(world.seq == before + 1, "in one step")
	world._order({"op": "undo"}, 2)
	_check(is_equal_approx(_height(a), 2.6), "player 2 can still undo their raise")


func _redo_waits_on_the_same_condition() -> void:
	var a := _wall(1, 20)
	world._order({"op": "reshape", "id": a, "data": {"height": 3.2}}, 1)
	world._order({"op": "undo"}, 1)
	world._order({"op": "reshape", "id": a, "data": {"top": 2}}, 2)
	var before := world.seq
	world._order({"op": "redo"}, 1)
	_check(world.seq == before and is_equal_approx(_height(a), 2.6), "a redo of a step someone has since built on does nothing")
	world._order({"op": "unwall", "ids": PackedInt32Array([a])}, 1)


func _wall_data(points: PackedVector3Array) -> Dictionary:
	return {"points": points, "height": 2.6, "arches": PackedFloat32Array(), "seed": 3, "closed": false, "top": 0, "fence": false, "windows": PackedVector2Array(), "lanterns": PackedVector3Array(), "flags": PackedFloat32Array(), "ruins": PackedVector2Array(), "on": PackedInt32Array()}


func _house_data(on: PackedInt32Array) -> Dictionary:
	var d := _wall_data(PackedVector3Array(WallLayout.rectangle(Terrain.ground(-40, 30), Terrain.ground(-34, 30), 4.0)))
	d.closed = true
	d.on = on
	d.roof = {"kind": RoofLayout.Kind.GABLE, "center": Terrain.ground(-37, 30), "radius": 2.0, "pitch": 1.6, "curve": 0.0, "seed": 4, "chimneys": PackedVector2Array(), "flag": false}
	return d


func _foot(id: int) -> float:
	return main.tool.find(id).layout.samples[0].y


## Waits out the frame's ripple and the worker laying the build again.
func _laid(id: int) -> void:
	await process_frame
	for i in 300:
		await process_frame
		if not main.tool.find(id).laying():
			return


func _a_storey_follows_what_it_stands_on() -> void:
	world._order({"op": "wall", "walls": [_house_data(PackedInt32Array())]}, 1)
	var lower := world.seq * Commands.MAX_PIECES
	world._order({"op": "wall", "walls": [_house_data(PackedInt32Array([lower]))]}, 1)
	var upper := world.seq * Commands.MAX_PIECES
	var top := _foot(lower) + 2.6 + WallLayout.CAP
	_check(absf(_foot(upper) - (top - WallLayout.SINK)) < 0.01, "the storey stands on the house")
	world._order({"op": "reshape", "id": lower, "data": {"height": 3.5}}, 1)
	await _laid(upper)
	_check(absf(_foot(upper) - (_foot(lower) + 3.5 + WallLayout.CAP - WallLayout.SINK)) < 0.01, "raising the house lifts the storey")
	world._order({"op": "unwall", "ids": PackedInt32Array([lower])}, 1)
	await _laid(upper)
	_check(_foot(upper) < top - 1.0, "with the house gone the storey stands on the ground")
	var snap := world.snapshot()
	world.restore(snap)
	world._order({"op": "undo"}, 1)
	_check(world.state.walls.size() == 1, "history went with the restore")
	var bad := _house_data(PackedInt32Array([upper + 50]))
	world._order({"op": "wall", "walls": [_with(bad, "on", PackedInt32Array([upper]))]}, 1)
	var later := world.seq * Commands.MAX_PIECES
	_check(world.state.walls.has(later) and world.state.walls[later].on == PackedInt32Array([upper]), "a build may stand on one standing")
	_check(Commands.clean({"op": "wall", "ids": PackedInt32Array([5]), "walls": [_with(bad, "on", PackedInt32Array([9]))], "seq": 1, "by": 1}, world.state, true).is_empty(), "never on a newer one")
	world._order({"op": "wall", "walls": [_with(bad, "on", PackedInt32Array([123456]))]}, 1)
	_check(world.state.walls[world.seq * Commands.MAX_PIECES].on.is_empty(), "a proposal on a build since gone stands on the ground")
	for id in world.state.walls.keys():
		world._order({"op": "unwall", "ids": PackedInt32Array([id])}, 1)


func _bad_commands_are_dropped() -> void:
	var a := _wall(1, 30)
	var good := _wall_data(PackedVector3Array([Terrain.ground(0, 0), Terrain.ground(3, 0)]))
	var cases := {
		"unknown op": {"op": "explode"},
		"unwall of nothing": {"op": "unwall", "ids": PackedInt32Array([9999])},
		"reshape of nothing": {"op": "reshape", "id": 9999, "data": {"height": 3.0}},
		"reshape of an unknown field": {"op": "reshape", "id": a, "data": {"points": 5}},
		"reshape out of range": {"op": "reshape", "id": a, "data": {"height": 500.0}},
		"reshape of a roof it lacks": {"op": "reshape", "id": a, "data": {"roof": {"pitch": 2.0}}},
		"wall with a string height": {"op": "wall", "walls": [_with(good, "height", "tall")]},
		"wall of one point": {"op": "wall", "walls": [_with(good, "points", PackedVector3Array([Vector3.ZERO]))]},
		"wall off the map": {"op": "wall", "walls": [_with(good, "points", PackedVector3Array([Vector3.ZERO, Vector3(1e9, 0, 0)]))]},
		"wall through NaN": {"op": "wall", "walls": [_with(good, "points", PackedVector3Array([Vector3.ZERO, Vector3(NAN, 0, 0)]))]},
		"wall with a bad roof": {"op": "wall", "walls": [_with(good, "roof", {"kind": 0, "center": Vector3.ZERO, "radius": 2.0, "pitch": 900.0, "curve": 0.0, "seed": 1, "chimneys": PackedVector2Array(), "flag": false})]},
		"stroke of too many walls": {"op": "wall", "walls": range(Commands.MAX_PIECES + 1).map(func(_i: int) -> Dictionary: return good)},
		"no walls": {"op": "wall", "walls": []},
		"wall longer than any stroke": {"op": "wall", "walls": [_with(good, "points", PackedVector3Array(range(200).map(func(i: int) -> Vector3: return Vector3(-70 if i % 2 else 70, 0, 0))))]},
		"unwall of one wall twice": {"op": "unwall", "ids": PackedInt32Array([a, a])},
		"dabs whose count overflows": {"op": "plant", "kind": "grass", "seed": 1, "dabs": [[Vector3.ZERO, 1.0, 1 << 62], [Vector3.ZERO, 1.0, 1 << 62], [Vector3.ZERO, 1.0, 1 << 62], [Vector3.ZERO, 1.0, 1 << 62]]},
		"reshape keyed by a name": {"op": "reshape", "id": a, "data": {&"height": NAN}},
		"heights that drain someone's pond": {"op": "heights", "cells": Rect2i(0, 0, 1, 1), "values": Terrain.read(Rect2i(0, 0, 1, 1)), "unseed": Vector2i(0, 0)},
		"heights seeding a pond outside them": {"op": "heights", "cells": Rect2i(0, 0, 1, 1), "values": Terrain.read(Rect2i(0, 0, 1, 1)), "seed": Vector2i(50, 50)},
		"heights of a backwards box": {"op": "heights", "cells": Rect2i(160, 160, -160, -160), "values": PackedFloat32Array()},
		"path longer than any stroke": {"op": "path", "path": {"points": PackedVector3Array(range(100).map(func(i: int) -> Vector3: return Vector3(-70 if i % 2 else 70, 0, 0))), "half_widths": PackedFloat32Array(range(100).map(func(_i: int) -> float: return 1.0)), "seed": 1}},
		"show of no group": {"op": "show", "plants": {9999: PackedInt32Array([0])}, "on": false},
		"show past a group's end": {"op": "show", "plants": {0: PackedInt32Array([999999])}, "on": false},
		"plant of a rock": {"op": "plant", "kind": "rock", "seed": 1, "dabs": [[Vector3.ZERO, 1.0, 3]]},
		"plant of a numeric kind": {"op": "plant", "kind": 4, "seed": 1, "at": Vector3.ZERO},
		"dab of two fields": {"op": "plant", "kind": "grass", "seed": 1, "dabs": [[Vector3.ZERO, 1.0]]},
		"stroke past its size": {"op": "plant", "kind": "grass", "seed": 1, "dabs": [[Vector3.ZERO, 1.0, Commands.MAX_STROKE + 1]]},
		"dab of a huge brush": {"op": "plant", "kind": "grass", "seed": 1, "dabs": [[Vector3.ZERO, 1000.0, 3]]},
		"heights too wide from a player": {"op": "heights", "cells": Rect2i(0, 0, 100, 100), "values": Terrain.read(Rect2i(0, 0, 100, 100))},
		"heights off the grid": {"op": "heights", "cells": Rect2i(-5, 0, 10, 10), "values": PackedFloat32Array()},
		"heights of NaN": {"op": "heights", "cells": Rect2i(0, 0, 1, 1), "values": PackedFloat32Array([NAN])},
	}
	for what in cases:
		_check(Commands.clean(cases[what], world.state, false).is_empty(), "refused: %s" % what)
	var before := world.seq
	for what in cases:
		world._order(cases[what], 2)
	_check(world.seq == before, "and none of them reaches the garden")
	_check(not Commands.clean({"op": "wall", "ids": PackedInt32Array([world.seq * 8 + 40]), "walls": [good]}, world.state, false).has("ids"), "a player cannot choose a new wall's id")
	var extra := Commands.clean({"op": "unwall", "ids": PackedInt32Array([a]), "junk": "x".repeat(1000)}, world.state, false)
	_check(extra.keys().map(str) == ["op", "ids"], "fields a command does not define are dropped: %s" % [extra.keys()])
	world._order({"op": "unwall", "ids": PackedInt32Array([a])}, 1)


func _with(d: Dictionary, k: String, v: Variant) -> Dictionary:
	var out := d.duplicate(true)
	out[k] = v
	return out


func _hill(at: Rect2i, lift: float) -> Dictionary:
	var v := Terrain.read(at)
	for i in v.size():
		v[i] += lift
	return {"op": "heights", "cells": at, "values": v}


func _ground_undo_waits_on_overlapping_ground() -> void:
	var original := Terrain.read(Rect2i(60, 60, 12, 12))
	world._order(_hill(Rect2i(60, 60, 6, 6), 1.0), 21)
	world._order(_hill(Rect2i(63, 63, 6, 6), 0.5), 22)
	var before := world.seq
	world._order({"op": "undo"}, 21)
	_check(world.seq == before, "a ground edit someone has since edited over is not undone")
	world._order({"op": "undo"}, 22)
	world._order(_hill(Rect2i(140, 140, 4, 4), 1.0), 21)
	world._order(_hill(Rect2i(20, 140, 4, 4), 1.0), 22)
	world._order({"op": "undo"}, 21)
	_check(world.seq == before + 4, "but one with another player's edit far off is")
	world._order({"op": "undo"}, 22)
	world._order({"op": "heights", "cells": Rect2i(60, 60, 12, 12), "values": original}, 21)


func _stacks_keep_their_newest_steps() -> void:
	var a := _wall(3, 40)
	for i in World.LIMIT + 5:
		world._order({"op": "reshape", "id": a, "data": {"top": i % 3}}, 3)
	_check(world.stacks[3].undo.size() == World.LIMIT, "a stack holds %d steps" % World.LIMIT)
	world._order({"op": "undo"}, 3)
	_check(world.state.walls[a].top == (World.LIMIT + 3) % 3, "and undo takes the newest first")
	world._order({"op": "unwall", "ids": PackedInt32Array([a])}, 3)


func _undo_restores_exact_values() -> void:
	world._order({"op": "wall", "walls": [_with(_wall_data(PackedVector3Array([Terrain.ground(-30, 0), Terrain.ground(-30, 4), Terrain.ground(-26, 4), Terrain.ground(-26, 0)])), "closed", true).merged({"roof": {"kind": 0, "center": Terrain.ground(-28, 2), "radius": 2.0, "pitch": 2.0, "curve": 0.0, "seed": 2, "chimneys": PackedVector2Array(), "flag": false}}, true)]}, 1)
	var a := world.seq * Commands.MAX_PIECES
	world._order({"op": "reshape", "id": a, "data": {"roof": {"pitch": 3.5, "curve": 0.4}}}, 1)
	world._order({"op": "undo"}, 1)
	_check(is_equal_approx(world.state.walls[a].roof.pitch, 2.0) and is_equal_approx(world.state.walls[a].roof.curve, 0.0), "undo puts a roof back as it was")
	_check(is_equal_approx(main.tool.find(a).roof.pitch, 2.0), "and its wall shows it")
	world._order({"op": "reshape", "id": a, "data": {"roof": {"pitch": 0.0}}}, 1)
	_check(world.state.walls[a].roof.pitch == 0.0 and main.tool.find(a).layout.cover == WallLayout.Cover.DECK, "a roof pushed flat is taken and laid as a deck")
	world._order({"op": "reshape", "id": a, "data": {"top": WallLayout.Top.CRENEL}}, 1)
	main.tool.find(a).lay_now()
	_check(main.tool.find(a).layout.stones.any(func(s): return s.kind == "merlon"), "a flat-roofed house's top restyles like an open wall's")
	world._order({"op": "undo"}, 1)
	world._order({"op": "undo"}, 1)
	_check(is_equal_approx(main.tool.find(a).roof.pitch, 2.0) and main.tool.find(a).layout.cover == WallLayout.Cover.ROOF, "undo raises it back into a pitched roof")
	var sent := {"op": "reshape", "id": a, "data": {"height": 3.0}}
	world._order(sent, 1)
	sent.data.height = 7.0
	_check(is_equal_approx(world.state.walls[a].height, 3.0), "the garden keeps its own copy of a command's values")
	world._order({"op": "unwall", "ids": PackedInt32Array([a])}, 1)


func _ghosts_go_when_their_command_settles() -> void:
	var tool: WallTool = main.tool
	var ghosts := func() -> int: return main.get_node("Builds").get_children().filter(func(n: Node) -> bool: return n is Wall and not n.is_queued_for_deletion()).size()
	var before: int = ghosts.call()
	await _play([{"op": "wall", "points": [[-40, 20], [-35, 20]], "seconds": 0.2}])
	_check(ghosts.call() == before + 1, "a drawn wall leaves one wall standing, not its ghost as well (%d more)" % (ghosts.call() - before))
	var settled := [false]
	world.submit({"op": "unwall", "ids": PackedInt32Array([9999])}, func() -> void: settled[0] = true)
	_check(settled[0], "a refused command's ghost goes")
	world._order({"op": "unwall", "ids": PackedInt32Array([tool.walls[-1].id])}, 1)


func _a_seed_decides_its_plants() -> void:
	var flora: Flora = main.flora_tool.flora
	var dabs := [[Terrain.ground(-15, -15), 1.0, 20]]
	world._order({"op": "plant", "kind": "grass", "seed": 1, "dabs": dabs}, 1)
	flora.settle()
	var one: Array = flora.groups[world.seq].map(func(p: Flora.Plant) -> Vector3: return p.anchor)
	world._order({"op": "plant", "kind": "grass", "seed": 2, "dabs": dabs}, 1)
	flora.settle()
	var two: Array = flora.groups[world.seq].map(func(p: Flora.Plant) -> Vector3: return p.anchor)
	_check(one != two, "two seeds grow two different strokes")
	var g := world.seq
	_check(flora.set_shown(g, PackedInt32Array([0, 1]), false).size() == 2 and flora.set_shown(g, PackedInt32Array([0, 1]), false).is_empty(), "hiding hidden plants changes nothing")
	flora.set_shown(g, PackedInt32Array([0, 1]), true)


func _ghost_paths_never_change_what_grows() -> void:
	var paths: Paths = main.get_node("Builds").get_children().filter(func(n: Node) -> bool: return n is Paths)[0]
	var flora: Flora = main.flora_tool.flora
	var dabs := [[Terrain.ground(-25, -30), 2.0, 60]]
	world._order({"op": "plant", "kind": "grass", "seed": 5, "dabs": dabs}, 1)
	flora.settle()
	var clear: int = flora.groups[world.seq].filter(func(p: Variant) -> bool: return p != null).size()
	paths.begin(Terrain.ground(-28, -30), 2.5)
	for i in 20:
		paths.extend(Terrain.ground(-28 + i * 0.4, -30), 2.5)
	paths._relay()
	world._order({"op": "plant", "kind": "grass", "seed": 5, "dabs": dabs}, 1)
	flora.settle()
	var beside_ghost: int = flora.groups[world.seq].filter(func(p: Variant) -> bool: return p != null).size()
	paths.forget()
	_check(beside_ghost == clear, "a path still being drawn changes nothing a build command grows (%d vs %d)" % [beside_ghost, clear])


func _restore_forgets_history() -> void:
	world.restore(world.snapshot())
	_check(world.stacks.is_empty() and world.touched.is_empty(), "a swapped garden starts with no history")
	var flora: Flora = main.flora_tool.flora
	world.restore({"seq": 0, "cmds": []})
	_check(flora.groups[0].all(func(p: Flora.Plant) -> bool: return p.shown()), "the meadow stands whole again")
	_check(flora.grass.size() == flora.grass.kept and flora.ghost_grass.size() == 0, "with no painted or ghost plants left")


func _play(steps: Array) -> void:
	var d := Driver.new(main, steps)
	main.add_child(d)
	await d.finished
	d.queue_free()


func _snapshot_rebuilds_the_garden() -> void:
	world._order({"op": "plant", "kind": "flowers", "seed": 8, "dabs": [[Terrain.ground(5, 5), 1.0, 30], [Terrain.ground(5.5, 5), 1.0, 30]]}, 1)
	var flowers := world.seq
	var flora: Flora = main.flora_tool.flora
	world._order({"op": "show", "plants": {flowers: PackedInt32Array([0, 1, 2]), 0: PackedInt32Array([7])}, "on": false}, 2)
	var hill := Rect2i(90, 90, 5, 5)
	var raised := Terrain.read(hill)
	for i in raised.size():
		raised[i] += 1.5
	world._order({"op": "heights", "cells": hill, "values": raised}, 1)
	var a := _wall(2, -20)
	world._order({"op": "reshape", "id": a, "data": {"arches": PackedFloat32Array([2.0])}}, 2)
	var picture := _picture()
	var snap := world.snapshot()
	world.restore({"seq": 0, "cmds": []})
	_check(_picture() != picture, "restoring an empty snapshot clears the garden")
	_check(flora.groups.size() == 1 and absf(Terrain.height_at(12, 12) - Terrain.base_heights()[92 * Terrain.VERTS + 92]) < 0.01, "back to the meadow and its ground")
	world.restore(snap)
	_check(_picture() == picture, "the snapshot rebuilds every wall, plant and height")


func _picture() -> String:
	return var_to_str(world.digest())


## A visitor whose garden fell out of step with the host's drops what the host sends until the whole garden comes
## again, its own strokes among it; a stroke painted meanwhile stays shown until then and stands in what comes.
func _a_stroke_painted_out_of_step_stays_shown() -> void:
	var flora: Flora = main.flora_tool.flora
	var tool: FloraTool = main.flora_tool
	var home := world.snapshot()
	var real := main.multiplayer.multiplayer_peer
	var client := ENetMultiplayerPeer.new()
	client.create_client("127.0.0.1", 9)
	main.multiplayer.multiplayer_peer = client
	world._commit({"op": "reshape", "id": 123456, "data": {"height": 3.0}, "seq": world.seq + 1, "by": 1})
	var b := tool.brushes[0]
	b.hand.tool = Hand.Tool.FLOWERS
	for i in 30:
		tool.paint(b, Terrain.ground(-20 + i * 0.1, 30), 1.0, 1.0 / 30.0)
	var painted := b.stroke.filter(func(p: Variant) -> bool: return p != null)
	var cmd := {"op": "plant", "kind": b.kind, "seed": b.rng.seed, "dabs": b.dabs.duplicate(true)}
	tool.end_stroke(b)
	var mine := cmd.duplicate(true)
	mine.merge({"id": world.seq + 2, "seq": world.seq + 2, "by": world.me(), "token": world._next_token})
	world._commit(mine)
	_check(not painted.is_empty() and painted.all(func(p: Flora.Plant) -> bool: return p.shown()), "a stroke the out-of-step garden cannot take yet stays shown (%d painted)" % painted.size())
	var cmds: Array = home.cmds.duplicate(true)
	cmd.merge({"id": home.seq + 1, "seq": home.seq + 1, "by": world.me()})
	cmds.append(cmd)
	world._welcome({"seq": home.seq + 1, "cmds": cmds})
	var grown: Array = flora.groups.get(home.seq + 1, []).filter(func(p: Variant) -> bool: return p != null and p.shown())
	_check(grown.size() == painted.size(), "and stands in the garden the host sends: %d of %d" % [grown.size(), painted.size()])
	_check(flora.ghost_flowers.size() == 0, "its ghost gone once it stands")
	client.close()
	main.multiplayer.multiplayer_peer = real
	world.restore(home)
