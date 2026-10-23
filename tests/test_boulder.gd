extends SceneTree

## Headless checks of boulders: each seed grows its own worn, faceted shape and the same one every time; a placed
## boulder is a build command kept with the garden, sized and painted by a reshape, taken back by undo, struck by the delete tool's
## beam, and stopping a hand; one hand carries and turns it every way and sets it down resting on the ground or as deep
## in it as it was pushed, two size it, and it rides the ground as it is reshaped: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_boulder.gd

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
	await _a_grip_carries_and_turns_it_onto_the_ground()
	await _let_go_in_the_air_it_drops()
	await _it_whooshes_moving_and_thuds_landing()
	await _two_hands_size_it()
	await _two_hands_grow_one_far_past_a_house()
	await _pushed_into_the_ground_it_stays()
	await _the_trigger_carries_a_new_one()
	await _the_trigger_buries_a_new_one()
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
	_check(Commands.clean({"op": "boulder", "at": at, "sink": 0.0, "turn": Quaternion.IDENTITY, "seed": 3, "scale": INF, "paint": Palette.plain(), "style": 0}, state, false).is_empty(), "a boulder without end is dropped")
	_check(Commands.clean({"op": "boulder", "at": at, "sink": 0.0, "turn": Quaternion.IDENTITY, "seed": 3, "scale": NAN, "paint": Palette.plain(), "style": 0}, state, false).is_empty(), "a boulder of no size is dropped")
	_check(Commands.clean({"op": "boulder", "at": at, "seed": 3, "scale": 0.01, "paint": Palette.plain(), "style": 0}, state, false).is_empty(), "under the smallest size it is dropped")
	_check(Commands.clean({"op": "boulder", "at": at, "seed": 3.0, "scale": 1.0, "paint": Palette.plain(), "style": 0}, state, false).is_empty(), "a seed that is no whole number is dropped")
	var q := Quaternion.IDENTITY
	_check(Commands.clean({"op": "boulder", "at": at, "turn": q, "seed": 3, "scale": 1.0, "paint": Palette.plain(), "style": 0}, state, false).is_empty(), "one with no depth is dropped")
	_check(Commands.clean({"op": "boulder", "at": at, "turn": q, "sink": -0.1, "seed": 3, "scale": 1.0, "paint": Palette.plain(), "style": 0}, state, false).is_empty(), "one sunk above the ground is dropped")
	_check(Commands.clean({"op": "boulder", "at": at, "turn": q, "sink": INF, "seed": 3, "scale": 1.0, "paint": Palette.plain(), "style": 0}, state, false).is_empty(), "one sunk without end is dropped")
	_check(Commands.clean({"op": "boulder", "at": at, "sink": 0.0, "seed": 3, "scale": 1.0, "paint": Palette.plain(), "style": 0}, state, false).is_empty(), "one with no turn is dropped")
	_check(Commands.clean({"op": "boulder", "at": at, "turn": Quaternion(0.5, 0, 0, 0.5), "sink": 0.0, "seed": 3, "scale": 1.0, "paint": Palette.plain(), "style": 0}, state, false).is_empty(), "a turn that is no rotation is dropped")
	_check(Commands.clean({"op": "boulder", "at": at, "turn": q, "sink": 0.0, "seed": 3, "scale": 1.0, "paint": Palette.plain(), "style": 0}, state, false).size() == 8, "a boulder command keeps its place, turn, depth, seed, size, paint and style")
	_check(Commands.clean({"op": "reshape", "of": "boulders", "id": 9, "data": {"scale": 1.0}}, state, false).is_empty(), "sizing a boulder that is not there is dropped")
	state.boulders[9] = {"at": at, "turn": q, "sink": 0.0, "seed": 3, "scale": 1.0, "paint": Palette.plain(), "style": 0}
	_check(not Commands.clean({"op": "reshape", "of": "boulders", "id": 9, "data": {"at": at + Vector3(2, 0, 1), "turn": Quaternion(Vector3.RIGHT, 1.2)}}, state, false).is_empty(), "a reshape moves and turns it")
	_check(not Commands.clean({"op": "reshape", "of": "boulders", "id": 9, "data": {"scale": 160.0}}, state, false).is_empty(), "a boulder sizes far past a house, unbounded")
	_check(Commands.clean({"op": "reshape", "of": "boulders", "id": 9, "data": {"seed": 4}}, state, false).is_empty(), "a reshape cannot swap its shape")
	_check(not Commands.clean({"op": "reshape", "of": "boulders", "id": 9, "data": {"sink": 0.4}}, state, false).is_empty(), "a reshape pushes it into the ground")
	_check(Commands.clean({"op": "reshape", "of": "boulders", "id": 9, "data": {"sink": -0.4}}, state, false).is_empty(), "and never out over it")


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
	_check(is_equal_approx(world.units.boulder * Budget.COSTS.boulder, Budget.BOULDER_MOST_US), "a boulder six times as wide costs the most one does (%s)" % world.units.boulder)
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
	var hit: Dictionary = main.rig.solid_hit.call(top, Vector3.DOWN, 10.0)
	_check(not hit.is_empty() and absf(hit.point.y - rock.point.y) < 0.01 and not hit.side, "the teleport ray lands on it")
	main.delete_tool.press(self, top, Vector3.DOWN)
	main.delete_tool.let_go(self)
	await _settled()
	_check(world.state.boulders.is_empty() and main.boulders.boulders.is_empty(), "a tap of the delete tool takes it")
	world.undo()
	await _settled()
	_check(world.state.boulders.size() == 1 and main.boulders.boulders.values()[0].visible, "undo puts it back, seen")


## How far its lowest point sits under the ground beneath it, as a share of how far it reaches below its centre: BURY
## when it rests, below zero when it floats.
func _sunk(b: Boulders.Boulder) -> float:
	var under := INF
	var depth := 0.0
	for p in b.shape.feet:
		var w := b.transform.basis * p
		var at := b.transform.origin + w
		under = minf(under, at.y - Terrain.height_at(at.x, at.z))
		depth = maxf(depth, -w.y)
	return -under / depth


func _it_stands_on_the_ground_as_it_moves() -> void:
	var b: Boulders.Boulder = main.boulders.boulders.values()[0]
	var id := b.id
	world.submit({"op": "reshape", "of": "boulders", "id": id, "data": {"turn": Quaternion(Vector3(1, 0, 1).normalized(), 2.0)}})
	await _settled()
	var was := b.transform.origin.y
	_check(absf(_sunk(b) - BoulderLayout.BURY) < 0.01, "turned on its side, it rests on the ground (%.3f)" % _sunk(b))
	var cells := Terrain.cells_around(b.ground.x, b.ground.z, 3.0)
	var values := Terrain.read(cells)
	for i in values.size():
		values[i] += 1.5
	world.submit({"op": "heights", "cells": cells, "values": values})
	await _settled()
	_check(absf(b.transform.origin.y - was - 1.5) < 0.05, "it rises with the ground under it (%.2f)" % (b.transform.origin.y - was))
	_check(absf(_sunk(b) - BoulderLayout.BURY) < 0.01, "and rests on the raised ground (%.3f)" % _sunk(b))
	for i in values.size():
		values[i] -= 3.0
	world.submit({"op": "heights", "cells": cells, "values": values})
	await _settled()
	_check(absf(b.transform.origin.y - was + 1.5) < 0.05, "it sinks with the ground lowered under it (%.2f)" % (b.transform.origin.y - was))
	_check(absf(_sunk(b) - BoulderLayout.BURY) < 0.01, "and rests in the hollow, not hanging over it (%.3f)" % _sunk(b))
	world.undo()
	await _settled()
	_check(absf(b.transform.origin.y - was - 1.5) < 0.05, "undoing the lowering lifts it back (%.2f)" % (b.transform.origin.y - was))
	world.undo()
	await _settled()
	_check(absf(b.transform.origin.y - was) < 0.01, "undoing the raising sets it back where it was (%.2f)" % (b.transform.origin.y - was))


func _a_grip_carries_and_turns_it_onto_the_ground() -> void:
	world.restore({"seq": 0, "cmds": []})
	main.flora_tool.place_boulder(Terrain.ground(4, 6), null, 31, 1.0)
	await _settled()
	var id: int = world.state.boulders.keys()[0]
	var b: Boulders.Boulder = main.boulders.find(id)
	var start := b.transform
	var tool: WallTool = main.tool
	var m := tool.mason(main.rig.right)
	var hand := Transform3D(Basis(), b.position + Vector3(0, 0.3, 2.0))
	var dir := (b.position - hand.origin).normalized()
	var rock: Dictionary = main.boulders.pick(hand.origin, dir)
	_check(not rock.is_empty() and rock.boulder == b, "a hand pointing at a boulder meets it")
	tool.begin_grow(m, b, hand, rock.point)
	_check(m.growing == b and tool.busy(main.rig.right), "a grip on a boulder takes it")
	var gain := Hand.reach_gain(hand.origin.distance_to(rock.point))
	var twist := Basis(Vector3.RIGHT, 1.1) * Basis(Vector3.FORWARD, 0.7)
	var to := Transform3D(twist, hand.origin + Vector3(3.0, 1.0, -2.0))
	m.sizing.follow.call(m, to)
	_check(b.position.distance_to(start.origin + Vector3(3.0, 1.0, -2.0) * gain) < 1e-3, "held, it moves with the hand, up off the ground too")
	var turned := b.transform.basis.orthonormalized()
	_check(turned.is_equal_approx(twist * start.basis.orthonormalized()), "held, it turns as the hand turns, every way")
	_check((turned * Vector3.UP).dot(Vector3.UP) < 0.6, "tipped well over, not only about the upright")
	_check(is_equal_approx(b.size, 1.0) and is_equal_approx(world.state.boulders[id].scale, 1.0), "one hand moves it without sizing it")
	tool.end_grow(m)
	_check(absf(_sunk(b) - BoulderLayout.BURY) < 0.01, "let go, it drops onto the ground at once (%.3f)" % _sunk(b))
	await _settled()
	var kept: Dictionary = world.state.boulders[id]
	_check(absf(kept.at.x - b.position.x) < 1e-3 and absf(kept.at.z - b.position.z) < 1e-3 and absf(kept.at.x - start.origin.x - 3.0 * gain) < 1e-3, "the garden keeps it where it was set down")
	_check(Basis(kept.turn).is_equal_approx(turned), "and turned as it was held")
	_check(b.transform.basis.orthonormalized().is_equal_approx(turned), "set down, it keeps the hand's turn")
	_check(absf(_sunk(b) - BoulderLayout.BURY) < 0.01, "it rests on the ground (%.3f)" % _sunk(b))
	world.undo()
	await _settled()
	_check(b.transform.is_equal_approx(start), "undo puts it back as it was")
	world.redo()
	await _settled()
	_check(b.transform.basis.orthonormalized().is_equal_approx(turned) and absf(_sunk(b) - BoulderLayout.BURY) < 0.01, "redo sets it down turned again")


func _let_go_in_the_air_it_drops() -> void:
	var b: Boulders.Boulder = main.boulders.boulders.values()[0]
	var rest := b.transform
	var tool: WallTool = main.tool
	var m := tool.mason(main.rig.left)
	var hand := Transform3D(Basis(), b.position + Vector3(0, 0, 2.0))
	tool.begin_grow(m, b, hand, b.position + Vector3(0, 0, 0.4))
	m.sizing.follow.call(m, hand.translated(Vector3.UP * 4.0))
	_check(b.position.y > rest.origin.y + 3.9, "held high, it hangs in the hand")
	tool.end_grow(m)
	await _settled()
	_check(b.transform.is_equal_approx(rest) and absf(_sunk(b) - BoulderLayout.BURY) < 0.01, "let go in the air, it drops back onto the ground (%.3f over)" % (b.position.y - rest.origin.y))
	_check(absf(world.state.boulders[b.id].at.y - Terrain.height_at(b.position.x, b.position.z)) < 1e-3, "the garden keeps it on the ground")


## A held boulder whooshes while it moves, not while still nor when pebble-sized; let go, it thuds, harder from higher.
func _it_whooshes_moving_and_thuds_landing() -> void:
	var still := Transform3D(Basis(), Vector3(0, 1, 0))
	_check(Boulders.swing(still, still, 0.6, 1.0 / 60.0) == 0.0, "a still boulder swings not at all")
	_check(Boulders.swing(still, still.translated(Vector3.RIGHT * 0.005), 0.6, 1.0 / 60.0) == 0.0, "nor one eased along slowly")
	_check(Boulders.swing(still, still.translated(Vector3.RIGHT * 0.1), 0.6, 1.0 / 60.0) == 1.0, "one swept fast swings fully")
	_check(Boulders.swing(still, Transform3D(Basis(Vector3.UP, 0.05), still.origin), 0.6, 1.0 / 60.0) > 0.0, "turning it swings its surface")
	_check(Boulders.impact(0.0) == 0.0 and Boulders.impact(2.5) > 0.99 and Boulders.impact(0.5) > 0.0, "it lands as hard as its fall")
	var b: Boulders.Boulder = main.boulders.boulders.values()[0]
	var tool: WallTool = main.tool
	var m := tool.mason(main.rig.right)
	for case: Array in [[1.0, 0.0, false], [1.0, 0.05, true], [0.2, 0.05, false]]:
		world.submit({"op": "reshape", "of": "boulders", "id": b.id, "data": {"scale": case[0]}})
		await _settled()
		var hand := Transform3D(Basis(), b.position + Vector3(0, 0, 2.0))
		tool.begin_grow(m, b, hand, b.position)
		var whooshes: int = Cues.asked.get(Cues.Act.BOULDER_MOVE, 0)
		for f in 30:
			await process_frame
			m.sizing.follow.call(m, hand.translated(Vector3(case[1] * f, 0.5, 0)))
		var heard: bool = Cues.asked.get(Cues.Act.BOULDER_MOVE, 0) > whooshes
		_check(heard == case[2], "a boulder %s wide moved %s m a frame %s" % [case[0], case[1], "whooshes" if case[2] else "is silent"])
		var thuds: int = Cues.asked.get(Cues.Act.BOULDER_PLACE, 0)
		tool.end_grow(m)
		_check(Cues.asked.get(Cues.Act.BOULDER_PLACE, 0) == thuds + 1, "let go, a boulder %s wide thuds" % case[0])
		await _settled()
	world.submit({"op": "reshape", "of": "boulders", "id": b.id, "data": {"scale": 1.0}})
	await _settled()


## The share of its height that shows above the ground under it.
func _showing(b: Boulders.Boulder) -> float:
	var clear := -INF
	var low := INF
	var high := -INF
	for p in b.shape.feet:
		var w := b.transform.basis * p
		var at := b.transform.origin + w
		clear = maxf(clear, at.y - Terrain.height_at(at.x, at.z))
		low = minf(low, w.y)
		high = maxf(high, w.y)
	return clear / (high - low)


## Pushed halfway into the ground and let go it stays there, pushed further it stays with KEEP of it showing; the
## garden keeps its depth through a style, a resize by two hands, a raised ground, an undo and a reload, a ray from
## above still finds it, and none finds its buried part through the ground.
func _pushed_into_the_ground_it_stays() -> void:
	world.restore({"seq": 0, "cmds": []})
	main.flora_tool.place_boulder(Terrain.ground(-3, 5), null, 43, 1.2)
	await _settled()
	var b: Boulders.Boulder = main.boulders.boulders.values()[0]
	var id := b.id
	var rest := b.transform
	var shown := _showing(b)
	var tool: WallTool = main.tool
	var m := tool.mason(main.rig.right)
	var hand := Transform3D(Basis(), b.position + Vector3(0, 0.5, 1.5))
	tool.begin_grow(m, b, hand, b.position + Vector3(0, 0.3, 0.4))
	m.sizing.follow.call(m, hand.translated(Vector3.DOWN * 0.25))
	var held := b.position
	_check(held.y < rest.origin.y - 0.2, "held, it pushes into the ground (%.2f)" % (rest.origin.y - held.y))
	tool.end_grow(m)
	_check(b.position.is_equal_approx(held), "let go part buried, it stays as deep as it was pushed (%.3f)" % (b.position.y - held.y))
	await _settled()
	_check(b.position.distance_to(held) < 1e-3 and world.state.boulders[id].sink > 0.1, "the garden keeps it there (%.3f)" % world.state.boulders[id].sink)
	_check(_showing(b) < shown, "less of it shows than resting (%.2f of %.2f)" % [_showing(b), shown])
	tool.begin_grow(m, b, hand, b.position + Vector3(0, 0.3, 0.4))
	m.sizing.follow.call(m, hand.translated(Vector3.DOWN * 5.0))
	tool.end_grow(m)
	await _settled()
	var buried := b.transform
	_check(absf(_showing(b) - BoulderLayout.KEEP) < 0.01, "pushed far down, it keeps KEEP of it above the ground (%.3f)" % _showing(b))
	var rock: Dictionary = main.boulders.pick(b.position + Vector3.UP * 4.0, Vector3.DOWN)
	_check(not rock.is_empty() and rock.boulder == b, "a ray from above still meets it")
	var under := Terrain.ground(b.position.x, b.position.z) + Vector3(3.0, 0.4, 0)
	var low := b.position + Vector3(0, -0.2, 0)
	_check(main.boulders.pick(under, (low - under).normalized()).is_empty(), "a ray aimed through the ground at its buried part meets nothing")
	world.submit({"op": "reshape", "of": "boulders", "id": id, "data": {"style": 1}})
	await _settled()
	_check(b.transform.is_equal_approx(buried), "restyled, it stays buried")
	var left := tool.mason(main.rig.left)
	main.rig.right.global_position = b.position + Vector3(0.3, 0.3, 1.5)
	main.rig.left.global_position = b.position + Vector3(-0.3, 0.3, 1.5)
	tool.begin_grow(m, b, main.rig.right.global_transform, b.position + Vector3(0, 0.3, 0.4))
	tool.begin_grow(left, b, main.rig.left.global_transform, b.position + Vector3(0, 0.3, 0.4))
	tool.drag_pair(left, b.position + Vector3(0.75, 0.3, 1.5), b.position + Vector3(-0.75, 0.3, 1.5))
	tool.end_grow(left)
	tool.end_grow(m)
	await _settled()
	_check(is_equal_approx(b.size, 1.2 * 2.5), "two hands size it buried (%.2f)" % b.size)
	_check(_showing(b) < 0.5 and _showing(b) >= BoulderLayout.KEEP - 0.01, "and it stays mostly buried at its new size (%.3f)" % _showing(b))
	world.undo()
	await _settled()
	_check(b.transform.is_equal_approx(buried), "undo takes back the size, still buried")
	var was := b.position.y
	var cells := Terrain.cells_around(b.ground.x, b.ground.z, 3.0)
	var values := Terrain.read(cells)
	for i in values.size():
		values[i] += 1.0
	world.submit({"op": "heights", "cells": cells, "values": values})
	await _settled()
	_check(absf(b.position.y - was - 1.0) < 0.05 and absf(_showing(b) - BoulderLayout.KEEP) < 0.01, "it rises buried with the ground raised under it (%.2f)" % (b.position.y - was))
	world.undo()
	await _settled()
	world.undo()
	await _settled()
	_check(b.transform.is_equal_approx(buried), "undoing the style keeps it buried")
	world.undo()
	await _settled()
	_check(b.position.distance_to(held) < 1e-3, "undo sets it back halfway")
	world.undo()
	await _settled()
	_check(b.transform.is_equal_approx(rest), "and back onto the ground")
	for i in 3:
		world.redo()
		await _settled()
	world.flush()
	var saved := var_to_str(world.digest())
	world.restore({"seq": 0, "cmds": []})
	await _settled()
	world.load_from(world.save_path)
	await _settled()
	_check(var_to_str(world.digest()) == saved and main.boulders.boulders.values()[0].transform.is_equal_approx(buried), "a buried boulder loads back as deep")


func _two_hands_size_it() -> void:
	var b: Boulders.Boulder = main.boulders.boulders.values()[0]
	var id := b.id
	var tool: WallTool = main.tool
	var right := tool.mason(main.rig.right)
	var left := tool.mason(main.rig.left)
	var at := b.position + Vector3(0, 0, 0.4)
	main.rig.right.global_position = b.position + Vector3(0.3, 0, 1.5)
	main.rig.left.global_position = b.position + Vector3(-0.3, 0, 1.5)
	tool.begin_grow(right, b, main.rig.right.global_transform, at)
	tool.begin_grow(left, b, main.rig.left.global_transform, at)
	_check(left.partner == right and right.partner == left, "the other hand's grip joins the first")
	tool.drag_pair(left, b.position + Vector3(0.6, 0, 1.5), b.position + Vector3(-0.6, 0, 1.5))
	_check(is_equal_approx(b.size, 2.0), "pulled to twice their span, the hands size it twice as big (%.2f)" % b.size)
	tool.end_grow(left)
	_check(right.growing == b and right.partner == null, "letting one go leaves it in the other")
	var held := b.position
	right.sizing.follow.call(right, main.rig.right.global_transform.translated(Vector3(1.0, 0, 0)))
	_check(b.position.x > held.x + 0.9 and is_equal_approx(b.size, 2.0), "which carries it on at its new size")
	tool.end_grow(right)
	await _settled()
	_check(is_equal_approx(world.state.boulders[id].scale, 2.0) and b.position.distance_to(held + Vector3(1.0, 0, 0)) < 1e-3 and _sunk(b) > BoulderLayout.BURY, "set down, the garden keeps its size and it stays where it was held, grown into the ground")
	world.undo()
	await _settled()
	_check(is_equal_approx(b.size, 1.0) and absf(b.position.x - held.x) < 1e-3, "undo takes back the size and the move as one")


## Twenty times the size a house could hide behind: nothing bounds it, and it draws, stops a ray, holds a player up
## and saves as any other.
func _two_hands_grow_one_far_past_a_house() -> void:
	world.restore({"seq": 0, "cmds": []})
	main.flora_tool.place_boulder(Terrain.ground(10, -10), null, 29, 8.0)
	await _settled()
	var b: Boulders.Boulder = main.boulders.boulders.values()[0]
	var id := b.id
	_check(world.fits({"op": "reshape", "of": "boulders", "id": id, "data": {"scale": 9.0}}), "it grows past a house while the budget has room")
	_check(world.fits({"op": "reshape", "of": "boulders", "id": id, "data": {"scale": 160.0}}), "and past any size, costing no more once it fills the view")
	var share := world.fill()
	var tool: WallTool = main.tool
	var right := tool.mason(main.rig.right)
	var left := tool.mason(main.rig.left)
	var mid := b.position + Vector3.BACK * (b.shape.reach() * b.size + 1.5)
	main.rig.right.global_position = mid + Vector3(0.3, 0, 0)
	main.rig.left.global_position = mid - Vector3(0.3, 0, 0)
	tool.begin_grow(right, b, main.rig.right.global_transform, b.position)
	tool.begin_grow(left, b, main.rig.left.global_transform, b.position)
	tool.drag_pair(left, mid + Vector3(6.0, 0, 0), mid - Vector3(6.0, 0, 0))
	tool.end_grow(left)
	tool.end_grow(right)
	await _settled()
	_check(is_equal_approx(world.state.boulders[id].scale, 160.0) and is_equal_approx(b.size, 160.0), "spread twenty times apart, the hands grow it twenty times past a house (%.1f)" % b.size)
	_check(is_equal_approx(world.fill(), share), "the budget's share stays what the dearest boulder costs (%.3f to %.3f)" % [share, world.fill()])
	_check(b.near.visibility_range_end >= Boulders.NEAR_TO * 160.0 and b.far.visibility_range_end >= Boulders.FAR_TO * 160.0, "its detail reaches as far as it is big")
	var box := b.near.global_transform * b.near.multimesh.mesh.get_aabb()
	_check(box.size.x > 100.0, "it is culled by its grown bounds (%.0f m across)" % box.size.x)
	var over := Vector3(b.position.x, b.position.y + b.shape.reach() * 160.0 + 5.0, b.position.z)
	var top: Dictionary = main.boulders.pick(over, Vector3.DOWN)
	_check(not top.is_empty() and top.point.y > Terrain.height_at(over.x, over.z) + 20.0, "a ray from above meets its top, high over the ground")
	_check(absf(main.rig.floor_under.call(top.point + Vector3.UP * 0.3) - top.point.y) < 0.05, "a player over it stands on its top, not the ground inside it")
	_check(main.boulders.inside(b.position + Vector3.UP * 5.0) == b, "its inside is solid")
	world.flush()
	var saved := var_to_str(world.digest())
	world.restore({"seq": 0, "cmds": []})
	await _settled()
	world.load_from(world.save_path)
	await _settled()
	_check(var_to_str(world.digest()) == saved and is_equal_approx(main.boulders.find(id).size, 160.0), "it saves and loads back at its size")


func _the_trigger_carries_a_new_one() -> void:
	world.restore({"seq": 0, "cmds": []})
	await _settled()
	var tools: FloraTool = main.flora_tool
	var brush := tools.brush(main.rig.right)
	var spot := Terrain.ground(-5, 9)
	main.rig.right.global_transform = Transform3D(Basis(), spot + Vector3(0, 1.2, 2.0))
	tools.take_boulder(brush, spot, 77, 1.5)
	_check(tools.busy(main.rig.right) and world.state.boulders.is_empty(), "the trigger takes up a new boulder, not yet in the garden")
	var twist := Basis(Vector3(1, 1, 0).normalized(), 1.4)
	tools.carry_boulder(brush, Transform3D(twist, main.rig.right.global_position + Vector3(-1, 3, 0)))
	var carried := brush.rock.transform.basis.orthonormalized()
	_check(brush.rock.position.y > spot.y + 3.0 and carried.is_equal_approx(twist), "it is carried up and turned with the hand")
	tools.set_boulder(brush)
	await _settled()
	_check(world.state.boulders.size() == 1 and main.boulders.boulders.size() == 1, "let go, it is set down as one command")
	var b: Boulders.Boulder = main.boulders.boulders.values()[0]
	_check(b.transform.basis.orthonormalized().is_equal_approx(carried) and absf(_sunk(b) - BoulderLayout.BURY) < 0.01 and is_equal_approx(b.size, 1.5), "turned as it was held, at its size, resting on the ground")
	_check(absf(b.position.x - spot.x + Hand.reach_gain(main.rig.right.global_position.distance_to(spot))) < 1e-3, "where the hand took it")
	world.undo()
	await _settled()
	_check(world.state.boulders.is_empty() and main.boulders.boulders.is_empty() and main.boulders.get_child_count() == 0, "undo takes it away, ghost and all")


## A new boulder taken up with the trigger and pushed into the ground before it is let go is set down there.
func _the_trigger_buries_a_new_one() -> void:
	world.restore({"seq": 0, "cmds": []})
	await _settled()
	var tools: FloraTool = main.flora_tool
	var brush := tools.brush(main.rig.right)
	var spot := Terrain.ground(-5, 9)
	main.rig.right.global_transform = Transform3D(Basis(), spot + Vector3(0, 1.2, 2.0))
	tools.take_boulder(brush, spot, 77, 1.5)
	var rest := brush.rock.position
	tools.carry_boulder(brush, main.rig.right.global_transform.translated(Vector3.DOWN * 0.15))
	var held := brush.rock.position
	tools.set_boulder(brush)
	await _settled()
	var b: Boulders.Boulder = main.boulders.boulders.values()[0]
	_check(held.y < rest.y - 0.2 and b.position.distance_to(held) < 1e-3, "let go in the ground, it is set down as deep as it was held (%.3f)" % (b.position.y - held.y))
