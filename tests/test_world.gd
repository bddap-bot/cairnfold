extends "res://../tests/support/suite.gd"

## Headless checks of the garden's command log and per-player undo, with two players' commands fed to the
## host directly: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_world.gd

var world: World


func _initialize() -> void:
	boot_main()
	_run.call_deferred()


func _run() -> void:
	main.world.bounded = false
	await process_frame
	world = main.world
	_undo_takes_back_only_your_own_steps()
	_your_later_steps_never_block_your_earlier_ones()
	_a_step_someone_built_on_is_skipped()
	_redo_waits_on_the_same_condition()
	_bad_commands_are_dropped()
	_commands_cost_by_size()
	_ground_undo_waits_on_overlapping_ground()
	_a_mix_undo_waits_on_its_easel()
	_a_pond_undo_waits_on_the_ground_that_drained_it()
	_stacks_keep_their_newest_steps()
	_undo_restores_exact_values()
	await _ghosts_go_when_their_command_settles()
	_a_seed_decides_its_plants()
	_ghost_paths_never_change_what_grows()
	_snapshot_rebuilds_the_garden()
	_restore_forgets_history()
	await _a_storey_follows_what_it_stands_on()
	_a_stroke_painted_out_of_step_stays_shown()
	_gable_ends_go_through_the_host()
	finish()


func _wall(by: int, x: float) -> int:
	world._order({"op": "wall", "walls": [wall_data({"points": PackedVector3Array([Terrain.ground(x, -5), Terrain.ground(x + 4, -5)]), "seed": 3})]}, by)
	return world.seq * Commands.MAX_PIECES


func _height(id: int) -> float:
	return world.state.walls[id].height if world.state.walls.has(id) else -1.0


func _undo_takes_back_only_your_own_steps() -> void:
	var a := _wall(1, 0)
	var b := _wall(2, 10)
	world._order({"op": "undo"}, 1)
	check(not world.state.walls.has(a) and world.state.walls.has(b), "player 1's undo takes their wall, not player 2's later one")
	world._order({"op": "undo"}, 2)
	check(not world.state.walls.has(b), "player 2's undo takes theirs")
	check(main.tool.walls.is_empty(), "and the wall nodes go with them")


func _your_later_steps_never_block_your_earlier_ones() -> void:
	var a := _wall(1, 0)
	world._order({"op": "reshape", "of": "walls", "id": a, "data": {"height": 4.0}}, 1)
	world._order({"op": "undo"}, 1)
	check(is_equal_approx(_height(a), 2.6), "undo lowers the wall back")
	world._order({"op": "undo"}, 1)
	check(not world.state.walls.has(a), "the next undo takes down the wall the same player raised")


func _a_step_someone_built_on_is_skipped() -> void:
	world._order({"op": "plant", "kind": "tree", "seed": 4, "at": Terrain.ground(-8, 6)}, 1)
	var tree := world.seq
	var a := _wall(1, 0)
	world._order({"op": "reshape", "of": "walls", "id": a, "data": {"height": 5.0}}, 2)
	var before := world.seq
	world._order({"op": "undo"}, 1)
	check(world.state.walls.has(a) and is_equal_approx(_height(a), 5.0), "player 1's undo leaves the wall player 2 raised standing as raised")
	check(world.state.groups[tree].hidden.size() > 0, "and goes on to player 1's tree")
	check(world.seq == before + 1, "in one step")
	world._order({"op": "undo"}, 2)
	check(is_equal_approx(_height(a), 2.6), "player 2 can still undo their raise")


func _redo_waits_on_the_same_condition() -> void:
	var a := _wall(1, 20)
	world._order({"op": "reshape", "of": "walls", "id": a, "data": {"height": 3.2}}, 1)
	world._order({"op": "undo"}, 1)
	world._order({"op": "reshape", "of": "walls", "id": a, "data": {"top": 2}}, 2)
	var before := world.seq
	world._order({"op": "redo"}, 1)
	check(world.seq == before and is_equal_approx(_height(a), 2.6), "a redo of a step someone has since built on does nothing")
	world._order({"op": "take", "of": "walls", "ids": PackedInt32Array([a])}, 1)


func _wall_data(points: PackedVector3Array) -> Dictionary:
	return wall_data({"points": points, "seed": 3})


func _house_data(on: PackedInt32Array) -> Dictionary:
	var d := _wall_data(PackedVector3Array(WallLayout.rectangle(Terrain.ground(-40, 30), Terrain.ground(-34, 30), 4.0)))
	d.closed = true
	d.on = on
	d.roof = {"kind": RoofLayout.Kind.GABLE, "center": Terrain.ground(-37, 30), "radius": 2.0, "pitch": 1.6, "curve": 0.0, "seed": 4, "chimneys": PackedVector2Array(), "dormers": PackedVector2Array(), "overhang": RoofLayout.OVERHANG, "deck": RoofLayout.Deck.STONE, "flag": false, "thatch": false}
	return d


func _foot(id: int) -> float:
	return main.tool.find(id).layout.samples[0].y


## Waits out the frame's ripple and the worker laying the build again.
func _laid(id: int) -> void:
	await process_frame
	await process_frame
	main.tool.find(id).lay_now()


func _a_storey_follows_what_it_stands_on() -> void:
	world._order({"op": "wall", "walls": [_house_data(PackedInt32Array())]}, 1)
	var lower := world.seq * Commands.MAX_PIECES
	world._order({"op": "wall", "walls": [_house_data(PackedInt32Array([lower]))]}, 1)
	var upper := world.seq * Commands.MAX_PIECES
	var top := _foot(lower) + 2.6 + WallLayout.CAP
	check(absf(_foot(upper) - (top - WallLayout.SINK)) < 0.01, "the storey stands on the house")
	world._order({"op": "reshape", "of": "walls", "id": lower, "data": {"height": 3.5}}, 1)
	await _laid(upper)
	check(absf(_foot(upper) - (_foot(lower) + 3.5 + WallLayout.CAP - WallLayout.SINK)) < 0.01, "raising the house lifts the storey")
	world._order({"op": "take", "of": "walls", "ids": PackedInt32Array([lower])}, 1)
	check(not world.state.walls.has(upper) and main.tool.find(upper) == null and main.tool.find(lower) == null, "the storey goes with the house it stands on")
	world._order({"op": "undo"}, 1)
	await _laid(upper)
	check(world.state.walls.has(lower) and world.state.walls.has(upper) and absf(_foot(upper) - (_foot(lower) + 3.5 + WallLayout.CAP - WallLayout.SINK)) < 0.01, "undo brings the storey back on its house")
	var snap := world.snapshot()
	world.restore(snap)
	world._order({"op": "undo"}, 1)
	check(world.state.walls.has(lower) and world.state.walls.has(upper), "history went with the restore")
	var bad := _house_data(PackedInt32Array([upper + 50]))
	world._order({"op": "wall", "walls": [_with(bad, "on", PackedInt32Array([upper]))]}, 1)
	var later := world.seq * Commands.MAX_PIECES
	check(world.state.walls.has(later) and world.state.walls[later].on == PackedInt32Array([upper]), "a build may stand on one standing")
	check(Commands.clean({"op": "wall", "ids": PackedInt32Array([5]), "walls": [_with(bad, "on", PackedInt32Array([9]))], "seq": 1, "by": 1}, world.state, true).is_empty(), "never on a newer one")
	world._order({"op": "wall", "walls": [_with(bad, "on", PackedInt32Array([123456]))]}, 1)
	check(world.state.walls[world.seq * Commands.MAX_PIECES].on.is_empty(), "a proposal on a build since gone stands on the ground")
	for id in world.state.walls.keys():
		if world.state.walls.has(id):
			world._order({"op": "take", "of": "walls", "ids": PackedInt32Array([id])}, 1)


func _bad_commands_are_dropped() -> void:
	var a := _wall(1, 30)
	var good := _wall_data(PackedVector3Array([Terrain.ground(0, 0), Terrain.ground(3, 0)]))
	var cases := {
		"unknown op": {"op": "explode"},
		"taking a wall that is not there": {"op": "take", "of": "walls", "ids": PackedInt32Array([9999])},
		"reshape of nothing": {"op": "reshape", "of": "walls", "id": 9999, "data": {"height": 3.0}},
		"reshape of an unknown field": {"op": "reshape", "of": "walls", "id": a, "data": {"points": 5}},
		"reshape below the lowest wall": {"op": "reshape", "of": "walls", "id": a, "data": {"height": 0.5}},
		"reshape to an endless height": {"op": "reshape", "of": "walls", "id": a, "data": {"height": INF}},
		"reshape of a roof it lacks": {"op": "reshape", "of": "walls", "id": a, "data": {"roof": {"pitch": 2.0}}},
		"wall with a string height": {"op": "wall", "walls": [_with(good, "height", "tall")]},
		"wall of one point": {"op": "wall", "walls": [_with(good, "points", PackedVector3Array([Vector3.ZERO]))]},
		"wall off the map": {"op": "wall", "walls": [_with(good, "points", PackedVector3Array([Vector3.ZERO, Vector3(1e9, 0, 0)]))]},
		"wall through NaN": {"op": "wall", "walls": [_with(good, "points", PackedVector3Array([Vector3.ZERO, Vector3(NAN, 0, 0)]))]},
		"wall with a bad roof": {"op": "wall", "walls": [_with(good, "roof", {"kind": 0, "center": Vector3.ZERO, "radius": 2.0, "pitch": -1.0, "curve": 0.0, "seed": 1, "chimneys": PackedVector2Array(), "dormers": PackedVector2Array(), "overhang": RoofLayout.OVERHANG, "deck": RoofLayout.Deck.STONE, "flag": false, "thatch": false})]},
		"stroke of too many walls": {"op": "wall", "walls": range(Commands.MAX_PIECES + 1).map(func(_i: int) -> Dictionary: return good)},
		"no walls": {"op": "wall", "walls": []},
		"wall longer than any stroke": {"op": "wall", "walls": [_with(good, "points", PackedVector3Array(range(200).map(func(i: int) -> Vector3: return Vector3(-70 if i % 2 else 70, 0, 0))))]},
		"taking one wall twice": {"op": "take", "of": "walls", "ids": PackedInt32Array([a, a])},
		"dabs whose count overflows": {"op": "plant", "kind": "grass", "seed": 1, "dabs": [[Vector3.ZERO, 1.0, 1 << 62], [Vector3.ZERO, 1.0, 1 << 62], [Vector3.ZERO, 1.0, 1 << 62], [Vector3.ZERO, 1.0, 1 << 62]]},
		"reshape to no gable end": {"op": "reshape", "of": "walls", "id": a, "data": {"gable_end": WallLayout.GableEnd.size()}},
		"reshape to a named gable end": {"op": "reshape", "of": "walls", "id": a, "data": {"gable_end": "steps"}},
		"reshape keyed by a name": {"op": "reshape", "of": "walls", "id": a, "data": {&"height": NAN}},
		"heights that put a pond": {"op": "heights", "cells": Rect2i(0, 0, 1, 1), "values": Terrain.read(Rect2i(0, 0, 1, 1)), "put": {Vector2i(0, 0): 1.0}},
		"heights that drain someone's pond": {"op": "heights", "cells": Rect2i(0, 0, 1, 1), "values": Terrain.read(Rect2i(0, 0, 1, 1)), "drop": [Vector2i(0, 0)]},
		"a pond at the world's edge, where water runs off": {"op": "ponds", "put": {Vector2i(0, 80): 50.0}},
		"two ponds at once": {"op": "ponds", "put": {Vector2i(80, 80): 1.0, Vector2i(10, 10): 1.0}},
		"a pond off the map": {"op": "ponds", "put": {Vector2i(-1, 0): 1.0}},
		"a pond at a NaN level": {"op": "ponds", "put": {Vector2i(80, 80): NAN}},
		"no pond": {"op": "ponds", "put": {}},
		"a pond taking another out": {"op": "ponds", "put": {Vector2i(80, 80): 1.0}, "drop": [Vector2i(81, 80)]},
		"heights of a backwards box": {"op": "heights", "cells": Rect2i(160, 160, -160, -160), "values": PackedFloat32Array()},
		"path longer than any stroke": {"op": "path", "path": {"points": PackedVector3Array(range(100).map(func(i: int) -> Vector3: return Vector3(-70 if i % 2 else 70, 0, 0))), "half_widths": PackedFloat32Array(range(100).map(func(_i: int) -> float: return 1.0)), "seed": 1}},
		"show of no group": {"op": "show", "plants": {9999: PackedInt32Array([0])}, "on": false},
		"show past a group's end": {"op": "show", "plants": {0: PackedInt32Array([999999])}, "on": false},
		"plant of a rock": {"op": "plant", "kind": "rock", "seed": 1, "dabs": [[Vector3.ZERO, 1.0, 3]]},
		"plant of a numeric kind": {"op": "plant", "kind": 4, "seed": 1, "at": Vector3.ZERO},
		"dab of two fields": {"op": "plant", "kind": "grass", "seed": 1, "dabs": [[Vector3.ZERO, 1.0]]},
		"stroke past its size": {"op": "plant", "kind": "grass", "seed": 1, "dabs": [[Vector3.ZERO, 1.0, Commands.MAX_STROKE + 1]]},
		"dab of a huge brush": {"op": "plant", "kind": "grass", "seed": 1, "dabs": [[Vector3.ZERO, 1000.0, 3]]},
		"heights off the grid": {"op": "heights", "cells": Rect2i(-5, 0, 10, 10), "values": PackedFloat32Array()},
		"heights of NaN": {"op": "heights", "cells": Rect2i(0, 0, 1, 1), "values": PackedFloat32Array([NAN])},
		"heights over the highest hill": {"op": "heights", "cells": Rect2i(0, 0, 1, 1), "values": PackedFloat32Array([Terrain.RELIEF * 1.01])},
		"heights under the deepest hollow": {"op": "heights", "cells": Rect2i(0, 0, 1, 1), "values": PackedFloat32Array([-1e30])},
	}
	for what in cases:
		check(Commands.clean(cases[what], world.state, false).is_empty(), "refused: %s" % what)
	var before := world.seq
	for what in cases:
		world._order(cases[what], 2)
	check(world.seq == before, "and none of them reaches the garden")
	check(not Commands.clean({"op": "wall", "ids": PackedInt32Array([world.seq * 8 + 40]), "walls": [good]}, world.state, false).has("ids"), "a player cannot choose a new wall's id")
	var extra := Commands.clean({"op": "take", "of": "walls", "ids": PackedInt32Array([a]), "junk": "x".repeat(1000)}, world.state, false)
	check(extra.keys().map(str) == ["op", "of", "ids"], "fields a command does not define are dropped: %s" % [extra.keys()])
	world._order({"op": "take", "of": "walls", "ids": PackedInt32Array([a])}, 1)


## A house's gable ends travel as any other reshape: a player turns them, the host's cleaned command passes a peer's
## check, the house is laid again with them, saves keep them and an undo puts them back; and the house tool lays its
## next house with the style last turned to.
func _gable_ends_go_through_the_host() -> void:
	world._order({"op": "wall", "walls": [_house_data(PackedInt32Array())]}, 1)
	var id := world.seq * Commands.MAX_PIECES
	check(world.state.walls[id].gable_end == WallLayout.GableEnd.WALL, "a house sent with the wall's gable end has it")
	var unset := _house_data(PackedInt32Array())
	unset.erase("gable_end")
	check(Commands.clean({"op": "wall", "walls": [unset]}, world.state, false).is_empty(), "a house sent without a gable end is refused")
	var turn := {"op": "reshape", "of": "walls", "id": id, "data": {"gable_end": WallLayout.GableEnd.STEPS}}
	var hosted := Commands.clean(turn, world.state, false)
	hosted.seq = world.seq + 1
	hosted.by = 2
	var relayed := Commands.clean(hosted, world.state, true)
	check(relayed.get("data", {}).get("gable_end") == WallLayout.GableEnd.STEPS, "a peer takes the host's turn of a gable end: %s" % relayed)
	world._order(turn, 2)
	check(world.state.walls[id].gable_end == WallLayout.GableEnd.STEPS and main.tool.find(id).layout.gable_end == WallLayout.GableEnd.STEPS, "the house is laid again with crow steps")
	world._order({"op": "undo"}, 2)
	check(world.state.walls[id].gable_end == WallLayout.GableEnd.WALL and main.tool.find(id).layout.gable_end == WallLayout.GableEnd.WALL, "an undo puts the wall's back")
	var picker: PaletteTool = main.palette_tool
	picker.open(main.rig.right, picker.style_target(PaletteTool.Restyle.GABLE, main.tool.find(id), Vector3.ZERO))
	picker.twist(main.rig.right, Palette.TWIST_STEP)
	picker.close(main.rig.right)
	check(world.state.walls[id].gable_end == WallLayout.GableEnd.BOARDS and main.tool.gable_end == WallLayout.GableEnd.BOARDS, "a twist of the style tool on them turns them to the next style")
	world.restore(world.snapshot())
	check(world.state.walls[id].gable_end == WallLayout.GableEnd.BOARDS and main.tool.find(id).layout.gable_end == WallLayout.GableEnd.BOARDS, "a save carries them")
	var next: Wall = main.tool.new_house(WallTool.stance(Terrain.ground(-20, 30), 0.0))
	check(next.layout.gable_end == WallLayout.GableEnd.BOARDS, "and the next house is laid with it")
	var built: Array[Wall] = [next]
	main.tool.build(built)
	check(world.state.walls[world.seq * Commands.MAX_PIECES].gable_end == WallLayout.GableEnd.BOARDS, "which the garden takes from it")
	main.tool.gable_end = WallLayout.GableEnd.WALL
	for wall in world.state.walls.keys():
		world._order({"op": "take", "of": "walls", "ids": PackedInt32Array([wall])}, 1)


func _with(d: Dictionary, k: String, v: Variant) -> Dictionary:
	var out := d.duplicate(true)
	out[k] = v
	return out


func _hill(at: Rect2i, lift: float) -> Dictionary:
	var v := Terrain.read(at)
	for i in v.size():
		v[i] += lift
	return {"op": "heights", "cells": at, "values": v}


## A peer's allowance pays for what a command carries, so a burst of the largest commands costs what it sends; the
## largest a tool makes still goes through on a full allowance.
func _commands_cost_by_size() -> void:
	var small := World.cost({"op": "sky", "time": 0.5})
	var whole := World.cost({"op": "heights", "cells": Terrain.ALL, "values": Terrain.read(Terrain.ALL)})
	check(small >= 1.0 and small < 1.1, "a small command costs one (%.2f)" % small)
	check(whole > 20.0 and whole <= World.BURST, "the whole ground costs as much as it carries, within a burst (%.1f)" % whole)
	var wall := _wall_data(PackedVector3Array(range(Commands.MAX_POINTS).map(func(i: int) -> Vector3: return Terrain.ground(i * 0.1, 0))))
	var stroke := {"op": "wall", "walls": range(Commands.MAX_PIECES).map(func(_i: int) -> Dictionary: return wall)}
	check(var_to_bytes(stroke).size() / float(World.COMMAND_BYTES) < World.BURST - 1.0, "the largest stroke fits a full allowance (%d bytes)" % var_to_bytes(stroke).size())
	Terrain.set_hump(0, 0, 0, 9, 1e6)
	var raised := Terrain.raised(Rect2i(80, 80, 1, 1), 0)
	Terrain.clear_hump(0)
	check(raised[0] == Terrain.RELIEF, "the ground tool raises the ground no higher than the highest hill (%s)" % raised[0])


func _ground_undo_waits_on_overlapping_ground() -> void:
	var original := Terrain.read(Rect2i(60, 60, 12, 12))
	world._order(_hill(Rect2i(60, 60, 6, 6), 1.0), 21)
	world._order(_hill(Rect2i(63, 63, 6, 6), 0.5), 22)
	var before := world.seq
	world._order({"op": "undo"}, 21)
	check(world.seq == before, "a ground edit someone has since edited over is not undone")
	world._order({"op": "undo"}, 22)
	world._order(_hill(Rect2i(140, 140, 4, 4), 1.0), 21)
	world._order(_hill(Rect2i(20, 140, 4, 4), 1.0), 22)
	world._order({"op": "undo"}, 21)
	check(world.seq == before + 4, "but one with another player's edit far off is")
	world._order({"op": "undo"}, 22)
	world._order({"op": "heights", "cells": Rect2i(60, 60, 12, 12), "values": original}, 21)


func _a_mix_undo_waits_on_its_easel() -> void:
	world._order({"op": "easel", "at": Terrain.ground(-40, -40), "yaw": 0.0, "strokes": [], "mix": PackedByteArray()}, 31)
	var id := world.seq
	var mix := PackedByteArray()
	mix.resize(Mixing.SIZE.x * Mixing.SIZE.y * 4)
	mix.fill(200)
	world._order({"op": "mix", "easel": id, "mix": mix}, 31)
	world._order({"op": "take", "of": "easels", "ids": PackedInt32Array([id])}, 32)
	var before := world.seq
	world._order({"op": "undo"}, 31)
	check(world.seq == before, "a mix on an easel someone has since taken away is not undone")
	world._order({"op": "undo"}, 32)
	world._order({"op": "undo"}, 31)
	check(world.state.easels.has(id) and world.state.easels[id].mix == mix, "nor once they put it back: it keeps the mix")
	world._order({"op": "take", "of": "easels", "ids": PackedInt32Array([id])}, 32)


func _a_pond_undo_waits_on_the_ground_that_drained_it() -> void:
	var cells := Terrain.cells_around(-40, 40, 2.8)
	world._order(_hill(cells, -1.0), 33)
	var hit := Vector3(-40, Water.brim(-40, 40, 2.8 * GroundGrab.SPREAD), 40)
	var p: PondLayout.Pond = Water.deepest(Water.candidates(hit), hit.y)
	world._order({"op": "ponds", "put": {p.at: hit.y}, "wet": p.cells.size()}, 33)
	check(world.state.ponds.has(p.at), "a pond fills the hollow")
	world._order(_hill(cells, 1.0), 34)
	check(not world.state.ponds.has(p.at), "and drains when someone fills the hollow in")
	check(world._resolve(33, "undo", false).is_empty(), "so its pourer's undo waits on that sculpt, which took the pond")
	world._order({"op": "undo"}, 34)
	world._order({"op": "undo"}, 33)


func _stacks_keep_their_newest_steps() -> void:
	var a := _wall(3, 40)
	for i in World.LIMIT + 5:
		world._order({"op": "reshape", "of": "walls", "id": a, "data": {"top": i % 3}}, 3)
	check(world.stacks[3].undo.size() == World.LIMIT, "a stack holds %d steps" % World.LIMIT)
	world._order({"op": "undo"}, 3)
	check(world.state.walls[a].top == (World.LIMIT + 3) % 3, "and undo takes the newest first")
	world._order({"op": "take", "of": "walls", "ids": PackedInt32Array([a])}, 3)


func _undo_restores_exact_values() -> void:
	world._order({"op": "wall", "walls": [_with(_wall_data(PackedVector3Array([Terrain.ground(-30, 0), Terrain.ground(-30, 4), Terrain.ground(-26, 4), Terrain.ground(-26, 0)])), "closed", true).merged({"roof": {"kind": 0, "center": Terrain.ground(-28, 2), "radius": 2.0, "pitch": 2.0, "curve": 0.0, "seed": 2, "chimneys": PackedVector2Array(), "dormers": PackedVector2Array(), "overhang": RoofLayout.OVERHANG, "deck": RoofLayout.Deck.STONE, "flag": false, "thatch": false}}, true)]}, 1)
	var a := world.seq * Commands.MAX_PIECES
	world._order({"op": "reshape", "of": "walls", "id": a, "data": {"roof": {"pitch": 3.5, "curve": 0.4}}}, 1)
	world._order({"op": "undo"}, 1)
	check(is_equal_approx(world.state.walls[a].roof.pitch, 2.0) and is_equal_approx(world.state.walls[a].roof.curve, 0.0), "undo puts a roof back as it was")
	check(is_equal_approx(main.tool.find(a).roof.pitch, 2.0), "and its wall shows it")
	world._order({"op": "reshape", "of": "walls", "id": a, "data": {"roof": {"pitch": 0.0}}}, 1)
	check(world.state.walls[a].roof.pitch == 0.0 and main.tool.find(a).layout.cover == WallLayout.Cover.DECK, "a roof pushed flat is taken and laid as a deck")
	world._order({"op": "reshape", "of": "walls", "id": a, "data": {"top": WallLayout.Top.CRENEL}}, 1)
	main.tool.find(a).lay_now()
	check(main.tool.find(a).layout.stones.any(func(s): return s.kind == "merlon"), "a flat-roofed house's top restyles like an open wall's")
	world._order({"op": "undo"}, 1)
	world._order({"op": "undo"}, 1)
	check(is_equal_approx(main.tool.find(a).roof.pitch, 2.0) and main.tool.find(a).layout.cover == WallLayout.Cover.ROOF, "undo raises it back into a pitched roof")
	var sent := {"op": "reshape", "of": "walls", "id": a, "data": {"height": 3.0}}
	world._order(sent, 1)
	sent.data.height = 7.0
	check(is_equal_approx(world.state.walls[a].height, 3.0), "the garden keeps its own copy of a command's values")
	world._order({"op": "take", "of": "walls", "ids": PackedInt32Array([a])}, 1)


func _ghosts_go_when_their_command_settles() -> void:
	var tool: WallTool = main.tool
	var ghosts := func() -> int: return main.get_node("Builds").get_children().filter(func(n: Node) -> bool: return n is Wall and not n.is_queued_for_deletion()).size()
	var before: int = ghosts.call()
	await play([{"op": "wall", "points": [[-40, 20], [-35, 20]], "seconds": 0.2}])
	check(ghosts.call() == before + 1, "a drawn wall leaves one wall standing, not its ghost as well (%d more)" % (ghosts.call() - before))
	var settled := [false]
	world.submit({"op": "take", "of": "walls", "ids": PackedInt32Array([9999])}, func() -> void: settled[0] = true)
	check(settled[0], "a refused command's ghost goes")
	world._order({"op": "take", "of": "walls", "ids": PackedInt32Array([tool.walls[-1].id])}, 1)


func _a_seed_decides_its_plants() -> void:
	var flora: Flora = main.flora_tool.flora
	var dabs := [[Terrain.ground(-15, -15), 1.0, 20]]
	world._order({"op": "plant", "kind": "grass", "seed": 1, "dabs": dabs}, 1)
	flora.grow_now()
	var one: Array = flora.groups[world.seq].map(func(p: Flora.Plant) -> Vector3: return p.anchor)
	world._order({"op": "plant", "kind": "grass", "seed": 2, "dabs": dabs}, 1)
	flora.grow_now()
	var two: Array = flora.groups[world.seq].map(func(p: Flora.Plant) -> Vector3: return p.anchor)
	check(one != two, "two seeds grow two different strokes")
	var g := world.seq
	check(flora.set_shown(g, PackedInt32Array([0, 1]), false).size() == 2 and flora.set_shown(g, PackedInt32Array([0, 1]), false).is_empty(), "hiding hidden plants changes nothing")
	flora.set_shown(g, PackedInt32Array([0, 1]), true)


func _ghost_paths_never_change_what_grows() -> void:
	var paths: Paths = main.get_node("Builds").get_children().filter(func(n: Node) -> bool: return n is Paths)[0]
	var flora: Flora = main.flora_tool.flora
	var dabs := [[Terrain.ground(-25, -30), 2.0, 60]]
	world._order({"op": "plant", "kind": "grass", "seed": 5, "dabs": dabs}, 1)
	flora.grow_now()
	var clear: int = flora.groups[world.seq].filter(func(p: Variant) -> bool: return p != null).size()
	paths.begin(Terrain.ground(-28, -30), 2.5)
	for i in 20:
		paths.extend(Terrain.ground(-28 + i * 0.4, -30), 2.5)
	paths._relay()
	world._order({"op": "plant", "kind": "grass", "seed": 5, "dabs": dabs}, 1)
	flora.grow_now()
	var beside_ghost: int = flora.groups[world.seq].filter(func(p: Variant) -> bool: return p != null).size()
	paths.forget()
	check(beside_ghost == clear, "a path still being drawn changes nothing a build command grows (%d vs %d)" % [beside_ghost, clear])


func _restore_forgets_history() -> void:
	world.restore(world.snapshot())
	check(world.stacks.is_empty() and world.touched.is_empty(), "a swapped garden starts with no history")
	var flora: Flora = main.flora_tool.flora
	world.restore({"seq": 0, "cmds": []})
	check(flora.groups[0].all(func(p: Flora.Plant) -> bool: return p.shown()), "the meadow stands whole again")
	check(flora.grass.size() == flora.grass.kept and flora.ghost_grass.size() == 0, "with no painted or ghost plants left")


func _snapshot_rebuilds_the_garden() -> void:
	world._order({"op": "plant", "kind": "flowers", "seed": 8, "dabs": [[Terrain.ground(5, 5), 1.0, 30], [Terrain.ground(5.5, 5), 1.0, 30]]}, 1)
	var flowers := world.seq
	var flora: Flora = main.flora_tool.flora
	world._order({"op": "show", "plants": {flowers: PackedInt32Array([0, 1, 2]), 0: PackedInt32Array([7])}, "on": false}, 2)
	var hill := Rect2i(82, 82, 14, 14)
	var raised := Terrain.read(hill)
	for i in raised.size():
		raised[i] += 1.5
	world._order({"op": "heights", "cells": hill, "values": raised}, 1)
	var a := _wall(2, -20)
	world._order({"op": "reshape", "of": "walls", "id": a, "data": {"openings": PackedVector4Array([2.0].map(WallLayout.archway))}}, 2)
	var picture := _picture()
	var snap := world.snapshot()
	world.restore({"seq": 0, "cmds": []})
	check(_picture() != picture, "restoring an empty snapshot clears the garden")
	check(flora.groups.size() == 1 and absf(Terrain.height_at(12, 12) - Terrain.base_heights()[92 * Terrain.VERTS + 92]) < 0.01, "back to the meadow and its ground")
	world.restore(snap)
	check(_picture() == picture, "the snapshot rebuilds every wall, plant and height, flowers standing where the hill rose under them")


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
	world._commit({"op": "reshape", "of": "walls", "id": 123456, "data": {"height": 3.0}, "seq": world.seq + 1, "by": 1})
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
	check(not painted.is_empty() and painted.all(func(p: Flora.Plant) -> bool: return p.shown()), "a stroke the out-of-step garden cannot take yet stays shown (%d painted)" % painted.size())
	var cmds: Array = home.cmds.duplicate(true)
	cmd.merge({"id": home.seq + 1, "seq": home.seq + 1, "by": world.me()})
	cmds.append(cmd)
	world._welcome({"seq": home.seq + 1, "cmds": cmds})
	var grown: Array = flora.groups.get(home.seq + 1, []).filter(func(p: Variant) -> bool: return p != null and p.shown())
	check(grown.size() == painted.size(), "and stands in the garden the host sends: %d of %d" % [grown.size(), painted.size()])
	check(flora.ghost_flowers.size() == 0, "its ghost gone once it stands")
	client.close()
	main.multiplayer.multiplayer_peer = real
	world.restore(home)
