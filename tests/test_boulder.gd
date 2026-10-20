extends SceneTree

## Headless checks of boulders: each seed grows its own worn, faceted shape and the same one every time; a placed
## boulder is a build command kept with the garden, sized and painted by a reshape, taken back by undo, struck by the delete tool's
## beam, and stopping a hand: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_boulder.gd

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
	world.load_from(OS.get_temp_dir().path_join("nestcombe-boulder-%d.garden" % OS.get_process_id()))
	_a_seed_grows_the_same_shape()
	_seeds_differ()
	_a_boulder_is_faceted_not_a_ball()
	_its_mesh_is_its_surface()
	_bad_commands_are_dropped()
	await _a_placed_boulder_sizes_undoes_and_reloads()
	await _the_beam_takes_one()
	await _it_stands_on_the_ground_as_it_moves()
	await _a_grip_grows_it_to_a_house_and_shrinks_it_to_a_pebble()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _settled() -> void:
	await process_frame
	world.flush()


static func _directions(n: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in n:
		var y := 1.0 - 2.0 * (i + 0.5) / n
		var a := i * PI * (3.0 - sqrt(5.0))
		var r := sqrt(1.0 - y * y)
		out.append(Vector3(cos(a) * r, y, sin(a) * r))
	return out


func _a_seed_grows_the_same_shape() -> void:
	var a: PackedVector3Array = BoulderLayout.arrays(BoulderLayout.shape(41), BoulderLayout.NEAR)[Mesh.ARRAY_VERTEX]
	var b: PackedVector3Array = BoulderLayout.arrays(BoulderLayout.shape(41), BoulderLayout.NEAR)[Mesh.ARRAY_VERTEX]
	_check(a == b, "one seed grows one shape")


func _seeds_differ() -> void:
	var dirs := _directions(200)
	var shapes := range(12).map(func(i: int) -> BoulderLayout.Shape: return BoulderLayout.shape(1000 + i * 7919))
	for i in shapes.size():
		for j in range(i + 1, shapes.size()):
			var apart := 0.0
			for u in dirs:
				apart = maxf(apart, absf(shapes[i].radius(u) - shapes[j].radius(u)) / shapes[i].radius(u))
			_check(apart > 0.15, "seeds %d and %d differ somewhere by more than 15%% (%.2f)" % [i, j, apart])


## A ball's radius barely changes from one direction to the next; a fractured stone's runs flat across a face, so its
## radius rises toward the face's edges as the secant of the angle off its middle, and its extremes lie far apart.
func _a_boulder_is_faceted_not_a_ball() -> void:
	var dirs := _directions(400)
	for seed in [3, 77, 1234, 99991]:
		var s := BoulderLayout.shape(seed)
		var radii := dirs.map(func(u: Vector3) -> float: return s.radius(u))
		_check(radii.min() / radii.max() < 0.7, "seed %d: its narrowest is under 0.7 of its widest (%.2f)" % [seed, radii.min() / radii.max()])
		var flat := 0
		for c in s.cuts:
			var n := Vector3(c.x, c.y, c.z)
			if absf(s.radius(n) - c.w) < c.w * 0.12:
				flat += 1
		_check(flat >= 4, "seed %d: at least four fracture faces show (%d)" % [seed, flat])
		var bed := s.radius(Vector3.DOWN)
		_check(bed < s.axes.y * 0.8, "seed %d: it rests on a flat bed, not a rounded bottom" % seed)


func _its_mesh_is_its_surface() -> void:
	var s := BoulderLayout.shape(5)
	for subdiv in [BoulderLayout.NEAR, BoulderLayout.FAR]:
		var verts: PackedVector3Array = BoulderLayout.arrays(s, subdiv)[Mesh.ARRAY_VERTEX]
		var off := 0.0
		for v in verts:
			off = maxf(off, absf(v.length() - s.radius(v.normalized())))
			_check(v.length() <= s.reach(), "no vertex reaches past its reach")
		_check(off < 1e-4, "every vertex lies on the radial surface the hand and beam meet")
	var near: PackedInt32Array = BoulderLayout.arrays(s, BoulderLayout.NEAR)[Mesh.ARRAY_INDEX]
	var far: PackedInt32Array = BoulderLayout.arrays(s, BoulderLayout.FAR)[Mesh.ARRAY_INDEX]
	_check(near.size() == 16 * far.size(), "the far mesh draws a sixteenth of the near's triangles")
	var t := s.hit(Vector3(0, 0, 5), Vector3.BACK * -1.0)
	_check(is_equal_approx(snappedf(t, 1e-3), snappedf(5.0 - s.radius(Vector3.BACK), 1e-3)), "a ray meets the surface where the radius says (%.3f)" % t)


func _bad_commands_are_dropped() -> void:
	var state := World.blank()
	var at := Terrain.ground(10, 10)
	_check(Commands.clean({"op": "boulder", "at": at, "seed": 3, "scale": 20.0, "paint": Palette.plain()}, state, false).is_empty(), "past the largest size it is dropped")
	_check(Commands.clean({"op": "boulder", "at": at, "seed": 3, "scale": 0.01, "paint": Palette.plain()}, state, false).is_empty(), "under the smallest size it is dropped")
	_check(Commands.clean({"op": "boulder", "at": at, "seed": 3.0, "scale": 1.0, "paint": Palette.plain()}, state, false).is_empty(), "a seed that is no whole number is dropped")
	_check(Commands.clean({"op": "boulder", "at": at, "seed": 3, "scale": 1.0, "paint": Palette.plain()}, state, false).size() == 5, "a boulder command keeps its place, seed, size and paint")
	_check(Commands.clean({"op": "reshape", "of": "boulders", "id": 9, "data": {"scale": 1.0}}, state, false).is_empty(), "sizing a boulder that is not there is dropped")
	state.boulders[9] = {"at": at, "seed": 3, "scale": 1.0, "paint": Palette.plain()}
	_check(not Commands.clean({"op": "reshape", "of": "boulders", "id": 9, "data": {"scale": 8.0}}, state, false).is_empty(), "a boulder sizes up to a house")
	_check(Commands.clean({"op": "reshape", "of": "boulders", "id": 9, "data": {"scale": 9.0}}, state, false).is_empty(), "and no further")
	_check(Commands.clean({"op": "reshape", "of": "boulders", "id": 9, "data": {"seed": 4}}, state, false).is_empty(), "a reshape cannot swap its shape")


func _a_placed_boulder_sizes_undoes_and_reloads() -> void:
	world.restore({"seq": 0, "cmds": []})
	main.flora_tool.place_boulder(Terrain.ground(3, -2), null, 17, 1.0)
	await _settled()
	_check(world.state.boulders.size() == 1 and main.boulders.boulders.size() == 1, "a placed boulder stands")
	var id: int = world.state.boulders.keys()[0]
	var before := world.units.get("boulder", 0.0) as float
	_check(is_equal_approx(before, 1.0), "a metre-wide boulder counts one unit (%s)" % before)
	world.submit({"op": "reshape", "of": "boulders", "id": id, "data": {"scale": 6.0, "paint": {Palette.Element.STONE: 4}}})
	await _settled()
	var b: Boulders.Boulder = main.boulders.find(id)
	_check(is_equal_approx(b.size, 6.0) and is_equal_approx(b.transform.basis.get_scale().x, 6.0), "a resize grows it where it stands")
	_check(is_equal_approx(world.units.boulder, 36.0), "a boulder six times as wide counts its scale squared (%s)" % world.units.boulder)
	_check(b.data.paint[Palette.Element.STONE] == 4, "it takes a stone swatch from the colour wheel")
	_check(b.far.visibility_range_begin > b.near.visibility_range_end - 0.01 and b.near.visibility_range_end > 100.0, "its detail reaches farther as it grows")
	world.undo()
	await _settled()
	_check(is_equal_approx(main.boulders.find(id).size, 1.0), "undo sizes it back")
	world.redo()
	await _settled()
	world.flush()
	var saved := var_to_str(world.digest())
	world.restore({"seq": 0, "cmds": []})
	await _settled()
	_check(main.boulders.boulders.is_empty(), "an empty garden holds no boulder")
	world.load_from(world.save_path)
	await _settled()
	var loaded := var_to_str(world.digest())
	_check(loaded == saved, "a saved boulder loads back the same seed, size and place:\n%s\n%s" % [saved, loaded])
	world.undo()
	await _settled()


func _the_beam_takes_one() -> void:
	world.restore({"seq": 0, "cmds": []})
	main.flora_tool.place_boulder(Terrain.ground(-6, 8), null, 23, 2.0)
	await _settled()
	var top := Terrain.ground(-6, 8) + Vector3.UP * 6.0
	var aimed: Dictionary = main.delete_tool.aim(top, Vector3.DOWN)
	_check(aimed.has("boulder"), "the delete beam strikes a boulder before the ground under it")
	var rock: Dictionary = main.boulders.pick(top, Vector3.DOWN)
	_check(not rock.is_empty() and rock.point.y > Terrain.height_at(-6, 8) + 0.3, "a ray from above meets its top")
	_check(main.boulders.inside(rock.point + Vector3.DOWN * 0.2) != null, "just under its top is inside it")
	var hit: Variant = main.rig.solid_hit.call(top, Vector3.DOWN, 10.0)
	_check(hit != null and absf(hit.y - rock.point.y) < 0.01, "the teleport ray lands on it")
	main.delete_tool.press(self, top, Vector3.DOWN)
	main.delete_tool.let_go(self)
	await _settled()
	_check(world.state.boulders.is_empty() and main.boulders.boulders.is_empty(), "a tap of the delete tool takes it")
	world.undo()
	await _settled()
	_check(world.state.boulders.size() == 1 and main.boulders.boulders.values()[0].visible, "undo puts it back, seen")


func _it_stands_on_the_ground_as_it_moves() -> void:
	var b: Boulders.Boulder = main.boulders.boulders.values()[0]
	var was := b.transform.origin.y
	var cells := Terrain.cells_around(b.ground.x, b.ground.z, 3.0)
	var values := Terrain.read(cells)
	for i in values.size():
		values[i] += 1.5
	world.submit({"op": "heights", "cells": cells, "values": values})
	await _settled()
	_check(absf(b.transform.origin.y - was - 1.5) < 0.05, "it rises with the ground under it (%.2f)" % (b.transform.origin.y - was))


func _a_grip_grows_it_to_a_house_and_shrinks_it_to_a_pebble() -> void:
	world.restore({"seq": 0, "cmds": []})
	main.flora_tool.place_boulder(Terrain.ground(4, 6), null, 31, 1.0)
	await _settled()
	var id: int = world.state.boulders.keys()[0]
	var b: Boulders.Boulder = main.boulders.find(id)
	var tool: WallTool = main.tool
	var m := tool.mason(main.rig.right)
	var top := b.ground + Vector3.UP * b.top()
	var hand := top + Vector3(0, 0.3, 2.0)
	var dir := (top - hand).normalized()
	var rock: Dictionary = main.boulders.pick(hand, dir)
	_check(not rock.is_empty() and rock.boulder == b, "a hand pointing at a boulder's top meets it")
	tool.begin_grow(m, b, hand, rock.point)
	_check(m.growing == b and tool.busy(main.rig.right), "a grip on a boulder takes it")
	tool.drag_grow(m, hand.y + 40.0)
	_check(is_equal_approx(b.size, BoulderLayout.SCALES.y), "raised far, it grows to its largest: %s" % b.size)
	tool.end_grow(m)
	await _settled()
	_check(is_equal_approx(world.state.boulders[id].scale, BoulderLayout.SCALES.y), "let go, the garden keeps it house-sized")
	tool.begin_grow(m, b, hand, rock.point)
	tool.drag_grow(m, hand.y - 40.0)
	tool.end_grow(m)
	await _settled()
	_check(is_equal_approx(world.state.boulders[id].scale, BoulderLayout.SCALES.x) and is_equal_approx(b.size, BoulderLayout.SCALES.x), "lowered far, it shrinks to a pebble")
	world.undo()
	await _settled()
	_check(is_equal_approx(b.size, BoulderLayout.SCALES.y), "undo grows it back")
