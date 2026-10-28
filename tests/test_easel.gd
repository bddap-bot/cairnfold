extends "res://../tests/support/suite.gd"

## Headless checks of easels: strokes painted through the brush are build commands, kept with the garden and loaded
## back whole, taken back and put back by undo and redo, cleared by a fresh sheet, carried by a deleted easel's undo,
## stands on the ground as it is reshaped, and checked like every command: godot4 --headless --path game --script ../tests/test_easel.gd

var world: World
var dir := ""


func _initialize() -> void:
	boot_main()
	_run.call_deferred()


func _run() -> void:
	main.world.bounded = false
	await process_frame
	world = main.world
	dir = OS.get_user_data_dir().path_join("cairnfold-easel-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(dir)
	_samples_keep_what_the_brush_did()
	_a_stroke_lays_the_same_dabs_every_time()
	await _strokes_are_kept_and_load_whole()
	await _undo_takes_back_a_stroke_and_redo_paints_it_again()
	await _a_fresh_sheet_clears_and_undo_brings_the_painting_back()
	await _undoing_a_stroke_replays_nothing_however_many_came_before()
	await _a_deleted_easel_comes_back_with_its_painting()
	_a_grip_on_its_stand_carries_it()
	await _it_rides_the_ground_as_it_is_reshaped()
	await _the_tray_loads_the_brush()
	_each_brush_in_the_pot_is_taken_alone()
	_no_brush_crosses_the_pot()
	_reaches_for_each_implement()
	await _preview_matches_the_grip()
	await _each_easel_holds_one_of_each_tool()
	await _sticks_come_in_sizes()
	await _a_held_stick_leans_back()
	await _a_side_stroke_turns_with_the_stick()
	_no_plank_crosses_the_canvas()
	_no_implement_crosses_the_easel()
	_easels_share_their_geometry()
	_the_ghost_is_the_easel()
	await _the_palette_stays_in_the_hand_by_its_thumb_hole()
	await _every_way_out_lets_the_palette_go()
	await _every_held_change_logs_a_line()
	await _a_tip_in_each_well_loads_its_colour()
	await _oil_paints_onto_the_board_as_onto_the_canvas()
	await _a_touch_paints_the_board_as_it_paints_the_canvas()
	await _the_trigger_sets_one_up_or_says_why_not()
	_easels_keep_their_distance_and_number()
	_bad_strokes_are_dropped()
	_every_demo_dips_into_something_on_the_tray()
	await _held_brush_stops_with_its_hand()
	await _changing_canvases_ends_the_previous_stroke()
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
	finish()


func _settled() -> void:
	await process_frame
	world.flush()


func _easel() -> Dictionary:
	return world.state.easels.values()[-1]


func _paint_some() -> void:
	await play([
		{"op": "place", "x": 0, "z": 6},
		{"op": "easel", "x": 0, "z": 3},
		{"op": "take", "what": "big"},
		{"op": "dip", "what": "jar"},
		{"op": "dip", "what": "pan", "index": 5},
		{"op": "brush", "points": [[0.1, 0.2, 0.8], [0.9, 0.22, 0.9]], "seconds": 0.3},
		{"op": "take", "what": "palette", "hand": "left"},
		{"op": "hold", "hand": "left", "at": [-0.9, 1.0, 0.4]},
		{"op": "take", "what": "flat"},
		{"op": "dip", "what": "oil", "index": 1},
		{"op": "mix", "points": [[-0.1, 0.1, 0.6], [0.3, 0.1, 0.6]], "seconds": 0.2},
		{"op": "brush", "roll": 90, "points": [[0.1, 0.6, 1.0], [0.5, 0.65, 0.7], [0.9, 0.6, 1.0]], "seconds": 0.3},
		{"op": "set_down", "hand": "left"},
		{"op": "take", "what": "stick"},
		{"op": "brush", "points": [[0.2, 0.8, 0.3], [0.8, 0.85, 0.9]], "seconds": 0.3},
		{"op": "wait", "seconds": 0.1},
	])


func _samples_keep_what_the_brush_did() -> void:
	var s := Brushwork.pack(Vector2(0.25, 0.75), 0.5, PI * 0.5, 7)
	var back := Brushwork.unpack(s, 0)
	check(back[0].distance_to(Vector2(0.25, 0.75)) < 1e-4 and absf(back[1] - 0.5) < 0.01 and absf(back[2] - PI * 0.5) < 0.02 and back[3] == 7, "a sample keeps where, how hard, which way and when: %s" % [back])


func _a_stroke_lays_the_same_dabs_every_time() -> void:
	var samples := PackedInt32Array()
	for i in 5:
		samples.append_array(Brushwork.pack(Vector2(0.1 + i * 0.1, 0.5), 0.3 + i * 0.1, 0.0, 0 if i == 0 else 3))
	var stroke := {"medium": Brushwork.Medium.WATER, "brush": Brushwork.Brush.BIG, "colour": Vector3(1, 1, 1), "strength": 1.0, "load": 1.0, "gap": 0, "samples": samples}
	var lay := func() -> PackedFloat32Array:
		var s := Brushwork.Stroker.new(stroke)
		var out := PackedFloat32Array()
		for i in 5:
			out.append_array(s.add(Brushwork.unpack(samples, i)))
		return out
	var once: PackedFloat32Array = lay.call()
	check(once == lay.call() and once.size() > 5 * Brushwork.DAB, "a stroke's samples lay the same dabs every time: %d" % (once.size() / Brushwork.DAB))
	for medium in [Brushwork.Medium.WATER, Brushwork.Medium.OIL]:
		stroke.medium = medium
		stroke.load = 0.4
		var s := Brushwork.Stroker.new(stroke)
		var constant := true
		for i in 512:
			var dabs := s.add([Vector2(0.1 if i % 2 == 0 else 0.9, 0.5), 1.0, 0.0, 3, 0.0])
			for d in range(5, dabs.size(), Brushwork.DAB):
				constant = constant and is_equal_approx(dabs[d], 0.4)
		check(constant, "a long stroke keeps its load in medium %d" % medium)



func _strokes_are_kept_and_load_whole() -> void:
	var path := dir.path_join("garden.save")
	world.load_from(path)
	await _paint_some()
	await _settled()
	var e := _easel()
	var media: Array = e.strokes.map(func(s: Dictionary) -> int: return s.medium)
	check(media == [Brushwork.Medium.WATER, Brushwork.Medium.OIL, Brushwork.Medium.CHARCOAL], "a watercolour, an oil and a charcoal stroke are on the canvas: %s" % [media])
	check(e.strokes.all(func(s: Dictionary) -> bool: return Brushwork.count(s) >= 2), "each stroke kept its samples")
	check(main.easels.easels.size() == 1 and main.easels.easels.values()[0].canvas.ticks > 0, "the easel stands and its canvas has run")
	check(not e.palette.is_empty() and e.palette.all(func(s: Dictionary) -> bool: return s.medium == Brushwork.Medium.OIL), "the oil painted onto the palette held in a hand is kept as strokes on the palette")
	var picture := var_to_str(world.digest())
	world.restore({"seq": 0, "cmds": []})
	await _settled()
	check(world.state.easels.is_empty() and main.easels.easels.is_empty(), "an empty garden holds no easel")
	world.load_from(path)
	check(var_to_str(world.digest()) == picture, "loading puts the easel back where it stood with every stroke as painted and its palette as mixed")
	check(main.easels.easels.size() == 1 and main.easels.easels.values()[0].canvas.catching_up(), "and replays its painting")
	check(main.easels.easels.values()[0].board.catching_up(), "and the paint on its palette")


func _undo_takes_back_a_stroke_and_redo_paints_it_again() -> void:
	await play([{"op": "take", "what": "big"}, {"op": "dip", "what": "jar"}, {"op": "dip", "what": "pan", "index": 4}, {"op": "brush", "points": [[0.3, 0.4, 0.9], [0.6, 0.45, 0.9]], "seconds": 0.2}])
	var before: Array = _easel().strokes.duplicate()
	check(before.size() == 4, "a loaded painting takes more strokes: %d" % before.size())
	await play([{"op": "press", "button": "dpad_down"}])
	check(_easel().strokes == before.slice(0, before.size() - 1), "undo takes the last stroke off the canvas")
	await play([{"op": "press", "button": "A"}])
	check(_easel().strokes == before, "redo paints it again")


func _a_fresh_sheet_clears_and_undo_brings_the_painting_back() -> void:
	var before: Array = _easel().strokes.duplicate()
	await play([{"op": "sheet", "pull": 0.1}])
	check(_easel().strokes == before, "a sheet pulled a little and let go stays on")
	await play([{"op": "sheet", "pull": 0.45}])
	check(_easel().strokes.is_empty(), "a sheet pulled well off tears away, leaving a fresh one")
	await play([{"op": "press", "button": "dpad_down"}])
	check(_easel().strokes == before, "undo puts the painting back")


## Undo's cost does not grow with the painting: the canvas goes back to the checkpoint the stroke before kept, at its
## tick, with nothing left to replay, at 10 strokes as at 200; a stroke further back replays only those after the
## nearest checkpoint.
func _undoing_a_stroke_replays_nothing_however_many_came_before() -> void:
	for n in [10, 200]:
		var canvas := Canvas.new()
		root.add_child(canvas)
		var strokes := Driver.painting(n + 1)
		var kept := strokes.slice(0, n)
		canvas.rebuild(kept)
		while canvas.catching_up():
			await process_frame
		var at := canvas.last_end
		canvas.play(strokes[n], 30)
		while canvas.last_end == at:
			await process_frame
		canvas.rebuild(kept)
		check(not canvas.catching_up() and canvas.ticks == at and canvas.last_end == at, "undo at %d strokes goes straight back to the stroke before, tick %d: %d" % [n, at, canvas.ticks])
		canvas.rebuild(strokes.slice(0, 2))
		check(canvas.catching_up() and canvas.ticks == 0, "a stroke before any checkpoint replays from a blank sheet")
		while canvas.catching_up():
			await process_frame
		canvas.rebuild(strokes.slice(0, 3))
		check(canvas.catching_up() and canvas._pending == 1, "the stroke after a checkpoint is all that replays: %d" % canvas._pending)
		canvas.queue_free()


func _a_deleted_easel_comes_back_with_its_painting() -> void:
	var id: int = world.state.easels.keys()[-1]
	var before: Array = _easel().strokes.duplicate()
	var e: Easels.Easel = main.easels.find(id)
	var from: Vector3 = main.rig.head.global_position
	main.delete_tool.press(main.rig.right, from, e.canvas_frame().origin - from)
	main.delete_tool.let_go(main.rig.right)
	await frames(2)
	check(world.state.easels.is_empty() and main.easels.easels.is_empty(), "the delete tool's beam takes an easel away")
	await play([{"op": "press", "button": "dpad_down"}])
	check(world.state.easels.has(id) and world.state.easels[id].strokes == before and main.easels.find(id) != null, "undo stands it back up with its painting")


## Ground raised, dug, undone, loaded whole or set back under an easel leaves it standing on that ground.
func _it_rides_the_ground_as_it_is_reshaped() -> void:
	var id: int = world.state.easels.keys()[-1]
	var e: Easels.Easel = main.easels.find(id)
	var at: Vector3 = _easel().at
	var was := e.position.y
	var cells := Terrain.cells_around(at.x, at.z, 3.0)
	var values := world.terrain.read(cells)
	for i in values.size():
		values[i] += 1.5
	world.submit({"op": "heights", "cells": cells, "values": values})
	await _settled()
	check(absf(e.position.y - was - 1.5) < 0.05, "an easel rises with the ground raised under it (%.2f)" % (e.position.y - was))
	for i in values.size():
		values[i] -= 3.0
	world.submit({"op": "heights", "cells": cells, "values": values})
	await _settled()
	check(absf(e.position.y - was + 1.5) < 0.05, "and sinks into the ground dug under it (%.2f)" % (e.position.y - was))
	world.undo()
	await _settled()
	check(absf(e.position.y - was - 1.5) < 0.05, "undoing the digging lifts it back (%.2f)" % (e.position.y - was))
	world.restore(world.snapshot())
	await _settled()
	e = main.easels.find(id)
	check(e != null and absf(e.position.y - was - 1.5) < 0.05, "a garden loaded whole, as a joining peer gets it, stands it on the raised ground")
	for i in values.size():
		values[i] += 1.5
	world.submit({"op": "heights", "cells": cells, "values": values})
	await _settled()
	check(e != null and absf(e.position.y - was) < 0.01, "the ground set back sets it back where it stood")


## A grip on an easel's legs or tray carries it along the ground and turns it with the hand, painting and all, set
## where it is let go as one reshape; its canvas and kit keep their painting grips, and two hands size no easel.
func _a_grip_on_its_stand_carries_it() -> void:
	var tool: WallTool = main.tool
	var id: int = world.state.easels.keys()[-1]
	var e: Easels.Easel = main.easels.find(id)
	var strokes: Array = _easel().strokes.duplicate()
	var was := {"at": _easel().at, "yaw": _easel().yaw}
	var right: Hand = main.rig.right
	var left: Hand = main.rig.left
	var leg: Array = Easels.legs()[0]
	var aim: Vector3 = e.global_transform * leg[0].lerp(leg[1], 0.5)
	var from := Transform3D(Basis(), e.global_transform * Vector3(0.4, 1.2, -2.0))
	var hit: Dictionary = main.easels.pick_stand(from.origin, aim - from.origin)
	check(hit.get("easel") == e, "a ray from the hand meets the easel's leg")
	var face := e.canvas_frame()
	check(main.easels.pick_stand(face * Vector3(0, 0, 2.0), face.basis * Vector3.FORWARD).is_empty(), "the canvas hides the stand behind it, keeping its own grip")
	right.global_transform = Transform3D(Basis(), e.brushes[Brushwork.Brush.BIG].global_transform * Easels.grip(Brushwork.Brush.BIG))
	check(main.easel_tool.claims(right), "a grip at the pot is painting's")
	right.global_transform = from
	check(not main.easel_tool.claims(right), "a grip away from the kit and canvas is not")
	if hit.is_empty():
		return
	var m := tool.mason(right)
	tool.grip_easel(m, id, from, hit.point)
	check(m.growing is WallTool.EaselGrip and tool.busy(right), "a grip on its stand takes the easel")
	var lm := tool.mason(left)
	left.global_transform = Transform3D(Basis(), from.origin + Vector3(-0.5, 0, 0))
	tool.grip_easel(lm, id, left.global_transform, hit.point)
	check(lm.growing == null, "the other hand's grip on it takes nothing: two hands size no easel")
	var to := Transform3D(Basis(Vector3.UP, 0.6), from.origin + Vector3(2.0, 0.4, -1.0))
	m.sizing.follow.call(m, to)
	var expect := WallTool.carry_easel(was, from, to, Hand.reach_gain(from.origin.distance_to(hit.point)), world.terrain.height_at)
	check(e.global_position.is_equal_approx(expect.at) and is_equal_approx(expect.yaw, wrapf(was.yaw + 0.6, -PI, PI)), "the hand's move and turn carry and turn it: %s" % [expect])
	check(is_equal_approx(expect.at.y, world.terrain.height_at(expect.at.x, expect.at.z)), "it stays on the ground as the hand rises")
	check(_easel().at == was.at, "nothing is sent while it is held")
	tool.end_grow(m)
	check(_easel().at.is_equal_approx(expect.at) and is_equal_approx(_easel().yaw, expect.yaw), "let go, it is set where the hand carried and turned it")
	check(main.easels.find(id) == e and _easel().strokes == strokes and e.canvas_frame().origin.is_equal_approx(Transform3D(Basis(Vector3.UP, expect.yaw), expect.at) * Easels.CANVAS_AT), "the same easel stands there, painting and all")
	var moved := {"at": _easel().at, "yaw": _easel().yaw}
	tool.grip_easel(m, id, from, hit.point)
	m.sizing.follow.call(m, Transform3D(Basis(), from.origin + Vector3(0.01, 0, 0)))
	tool.end_grow(m)
	check(_easel().at == moved.at and e.global_position.is_equal_approx(moved.at), "a trembling grip leaves it where it stood")
	world.undo()
	check(_easel().at == was.at and _easel().yaw == was.yaw and e.global_position.is_equal_approx(was.at) and _easel().strokes == strokes, "one undo puts it back where it stood")
	var state := World.blank()
	state.easels[1] = {"at": world.terrain.ground(10, 10), "yaw": 0.0, "strokes": [], "palette": []}
	state.easels[2] = {"at": world.terrain.ground(20, 10), "yaw": 0.0, "strokes": [], "palette": []}
	var move := func(data: Dictionary) -> Dictionary: return Commands.clean({"op": "reshape", "of": "easels", "id": 1, "data": data}, state, false, world.terrain)
	check(not move.call({"at": world.terrain.ground(14, 12), "yaw": 1.0}).is_empty(), "a reshape may move and turn an easel, as a grip does")
	check(not move.call({"at": world.terrain.ground(10.5, 10)}).is_empty(), "a little way from where it stood")
	check(move.call({"at": world.terrain.ground(20.5, 10)}).is_empty(), "but never onto another")
	check(move.call({"yaw": 99.0}).is_empty() and move.call({"at": Vector3(INF, 0, 0)}).is_empty(), "nor turned or set past what one may stand")
	check(move.call({"strokes": []}).is_empty(), "and a reshape paints nothing")


func _the_tray_loads_the_brush() -> void:
	await play([{"op": "take", "what": "small"}, {"op": "dip", "what": "jar"}, {"op": "dip", "what": "pan", "index": 5}, {"op": "dip", "what": "pan", "index": 1}])
	var p: EaselTool.Painter = main.easel_tool.painter(main.rig.right)
	var e: Easels.Easel = main.easels.easels.values()[-1]
	var blue := Brushwork.absorbance(Brushwork.PIGMENTS[5])
	var lemon := Brushwork.absorbance(Brushwork.PIGMENTS[1])
	var red := Brushwork.absorbance(Brushwork.PIGMENTS[3])
	check(p.brush == Brushwork.Brush.SMALL and p.medium == Brushwork.Medium.WATER and main.rig.right.tool == Hand.Tool.EASEL, "a grip at the pot takes a brush; the watercolour pans make it watercolour")
	check(p.colour.distance_to((blue + lemon * 0.1) / 1.1) < 1e-3, "a pan mixes its tenth with the loaded watercolour brush")
	check(e.wash.albedo_color.is_equal_approx(main.easel_tool._paint_colour(p)), "the box's mixing field shows the mix")
	var clear := e.water.albedo_color
	await play([{"op": "dip", "what": "jar"}])
	check(e.water.albedo_color != clear and p.medium == Brushwork.Medium.WATER, "rinsing in the jar clouds its water: %s from %s" % [e.water.albedo_color, clear])
	await play([{"op": "dip", "what": "oil", "index": 3}])
	check(p.medium == Brushwork.Medium.OIL and p.colour.distance_to(red) < 1e-4 and p.strength == 1.0 and is_equal_approx(p.load, 0.1), "the oil palette's paint makes it oil, its own colour, not the watercolour's")
	await play([{"op": "dip", "what": "oil", "index": 1}])
	check(p.colour.distance_to((red + lemon) * 0.5) < 1e-4, "two oil taps mix on the brush")
	await play([{"op": "dip", "what": "pan", "index": 5}])
	check(p.medium == Brushwork.Medium.WATER and p.colour.distance_to(blue) < 1e-4, "and a pan makes it watercolour again, clean of the oil")
	for i in 9:
		await play([{"op": "dip", "what": "pan", "index": 5}])
	await play([{"op": "rag_wipe"}])
	check(is_equal_approx(p.load, 0.75), "one physical rag wipe lowers load once")
	await play([{"op": "brush", "points": [[0.1, 0.5, 0.8], [0.9, 0.5, 0.8]], "seconds": 0.4}])
	await _settled()
	check(is_equal_approx(p.load, 0.75) and is_equal_approx(world.state.easels[e.id].strokes[-1].load, 0.75), "painting keeps the wiped load and sends it in the stroke command: brush=%s stroke=%s" % [p.load, world.state.easels[e.id].strokes[-1].load])

	await play([{"op": "rag_wipe", "times": 2}])
	check(is_equal_approx(p.load, 0.25), "three wipes leave a quarter load")
	await play([{"op": "rag_wipe", "times": 5}])
	check(is_equal_approx(p.load, 0.15), "the rag leaves a dry-brush floor")
	check(e.rag.get_shader_parameter("stained"), "the rag picks up pigment")
	await play([{"op": "dip", "what": "pan", "index": 5}])
	check(is_equal_approx(p.load, 0.25), "a tap adds ten percent to the wiped load")

	await play([{"op": "take", "what": "stick"}])
	check(p.brush == Brushwork.Brush.STICK and p.medium == Brushwork.Medium.CHARCOAL, "the stick is charcoal")
	await play([{"op": "dip", "what": "jar"}, {"op": "dip", "what": "pan", "index": 2}, {"op": "dip", "what": "oil", "index": 2}])
	await play([{"op": "rag_wipe"}])
	check(p.medium == Brushwork.Medium.CHARCOAL and p.load == 1.0, "and stays charcoal whatever it is dipped in")
	await play([{"op": "take", "what": "box"}, {"op": "set_down"}, {"op": "take", "what": "big"}])
	check(p.brush == Brushwork.Brush.BIG and p.palette == null and main.rig.right.tool == Hand.Tool.EASEL, "from the charcoal a hand takes a palette, sets it down and takes a brush")


## Every brush standing in the pot keeps its whole surface inside the pot's inner wall from the pot's foot to its rim,
## so none shows through the wall or its lip, sampled densely enough that a crossing of a millimetre shows.
func _no_brush_crosses_the_pot() -> void:
	const STEPS := 48
	var e: Easels.Easel = main.easels.easels.values()[-1]
	var inner := Easels.POT_SIZE.x - Easels.POT_WALL
	for kind: Brushwork.Brush in Easels.SPLAY:
		var worst := -INF
		var below := 0
		for mi: MeshInstance3D in e.brushes[kind].find_children("*", "MeshInstance3D", true, false):
			var into := e.global_transform.affine_inverse() * mi.global_transform
			var arrays := mi.mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for t in range(0, indices.size(), 3):
				var a := into * vertices[indices[t]]
				var b := into * vertices[indices[t + 1]]
				var c := into * vertices[indices[t + 2]]
				for i in STEPS + 1:
					for j in STEPS + 1 - i:
						var at := a + (b - a) * (float(i) / STEPS) + (c - a) * (float(j) / STEPS) - Easels.POT
						if at.y < 0.0:
							below += 1
						elif at.y <= Easels.POT_SIZE.y:
							worst = maxf(worst, Vector2(at.x, at.z).length())
		check(below == 0 and worst < inner, "the %s stands inside the pot: %d points below its foot, %.4f m out where its inner wall is %.4f m" % [Brushwork.Brush.keys()[kind], below, worst, inner])


## The brushes splay out of the pot, each handle leaving through its mouth, and a grip anywhere within a few
## centimetres of a brush's handle or a stick of charcoal takes that one, never its neighbour.
func _each_brush_in_the_pot_is_taken_alone() -> void:
	const SLACK := 0.045
	var e: Easels.Easel = main.easels.easels.values()[-1]
	var p: EaselTool.Painter = main.easel_tool.painter(main.rig.right)
	var grips := {}
	for kind: Brushwork.Brush in e.brushes:
		grips[kind] = e.brushes[kind].global_transform * Easels.grip(kind)
		if not Brushwork.is_stick(kind):
			check((e.global_transform.affine_inverse() * grips[kind]).y > Easels.POT.y + Easels.POT_SIZE.y, "the %s is gripped above the pot's rim" % Brushwork.Brush.keys()[kind])
	for kind: Brushwork.Brush in e.brushes:
		var offsets: Array[Vector3] = [Vector3.ZERO, Vector3.LEFT, Vector3.RIGHT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]
		for other: Brushwork.Brush in grips:
			if other != kind:
				check(grips[kind].distance_to(grips[other]) > SLACK * 2.0, "the %s's grip is %.3f m from the %s's" % [Brushwork.Brush.keys()[kind], grips[kind].distance_to(grips[other]), Brushwork.Brush.keys()[other]])
				offsets.append((grips[other] - grips[kind]).normalized())
		for o: Vector3 in offsets:
			_empty_handed(p, kind)
			main.rig.right.global_transform = Transform3D(e.global_basis, grips[kind] + o * SLACK)
			main.easel_tool.grab(p)
			check(p.brush == kind and p.palette == null, "a grip %s %.0f cm off the %s's handle takes it, not the %s" % [o, SLACK * 100.0, Brushwork.Brush.keys()[kind], Brushwork.Brush.keys()[p.brush]])


## Every part of the stand lies wholly behind the canvas's face, or wholly below its bottom edge, so from anywhere a
## player stands none covers any of the painting.
func _no_plank_crosses_the_canvas() -> void:
	var e: Easels.Easel = main.easels.easels.values()[-1]
	var face := e.canvas_frame()
	var bottom := (face * Vector3(0, -Brushwork.METRES.y * 0.5, 0)).y
	var planks := e.get_node("stand").get_children()
	check(planks.size() >= 5, "the stand has its legs, tray and rail: %d parts" % planks.size())
	for mi: MeshInstance3D in planks:
		var box := mi.get_aabb()
		var behind := true
		var below := true
		for k in 8:
			var corner := mi.global_transform * box.get_endpoint(k)
			behind = behind and (face.affine_inverse() * corner).z < 0.0
			below = below and corner.y < bottom
		check(behind or below, "a plank at %s stays behind the canvas's face or below it" % (e.global_transform.affine_inverse() * mi.global_position))


func _no_implement_crosses_the_easel() -> void:
	var e: Easels.Easel = main.easels.easels.values()[-1]
	var parts: Array[MeshInstance3D] = []
	for n in e.get_node("stand").get_children() + e.get_children():
		if n is MeshInstance3D:
			parts.append(n)
	check(parts.size() >= 7, "the easel has its stand, backing and face: %d parts" % parts.size())
	var implements := e.get_node("implements").find_children("*", "MeshInstance3D", true, false)
	check(implements.size() >= 10, "the tray holds its pot, jar, brushes, charcoal and palettes: %d meshes" % implements.size())
	for mi: MeshInstance3D in implements:
		for part in parts:
			var into := part.global_transform.affine_inverse() * mi.global_transform
			var vertices := mi.mesh.get_faces()
			var clear := true
			for i in range(0, vertices.size(), 3):
				var bounds := AABB(into * vertices[i], Vector3.ZERO)
				bounds = bounds.expand(into * vertices[i + 1]).expand(into * vertices[i + 2])
				clear = clear and not _inside(part.get_aabb()).intersects(bounds)
			check(clear, "%s on the tray stays clear of %s at %s %s" % [e.get_node("implements").get_path_to(mi), e.get_path_to(part), e.global_transform.affine_inverse() * part.global_position, part.get_aabb()])


## Setting an easel up builds no geometry: every mesh it shows is the one the easel before it shows, so a placement
## costs its nodes and its canvas, not a bake.
func _easels_share_their_geometry() -> void:
	var stands := Easels.new()
	stands.terrain = world.terrain
	main.add_child(stands)
	var meshes := []
	for id in 2:
		var e := stands.put(id, {"at": Vector3(id * 2.0, 0, 0), "yaw": 0.0, "strokes": [], "palette": []})
		meshes.append(e.find_children("*", "MeshInstance3D", true, false).map(func(mi: MeshInstance3D) -> Mesh: return mi.mesh))
	check(meshes[0].size() >= 17 and meshes[0] == meshes[1], "a second easel shows the first one's %d meshes" % meshes[0].size())
	stands.free()


## `box` less a millimetre each way, so things resting on it do not count as crossing it; a face keeps a millimetre.
func _inside(box: AABB) -> AABB:
	var size := box.size - Vector3.ONE * 0.002
	size = Vector3(maxf(size.x, 0.001), maxf(size.y, 0.001), maxf(size.z, 0.001))
	return AABB(box.get_center() - size * 0.5, size)


## Taken by a grip, either palette stays in either hand after the grip lets go, as a brush does, held by its thumb hole
## with its paint up and reaching toward the other hand, clear of the controller; the next grip, wherever the hand is,
## sends it back to its rest on the tray, travelling there rather than jumping, and gives the hand back what it held.
func _the_palette_stays_in_the_hand_by_its_thumb_hole() -> void:
	var e: Easels.Easel = main.easels.easels.values()[-1]
	for kit: Brushwork.Medium in e.palettes:
		var name: String = {Brushwork.Medium.WATER: "box", Brushwork.Medium.OIL: "palette"}[kit]
		var node: Node3D = e.palettes[kit]
		var rest := Transform3D(Basis(), Easels.KITS[kit])
		var paint := Easels.MIX_AT if kit == Brushwork.Medium.WATER else Vector3.ZERO
		check(Easels.THUMB.x < paint.x - 0.08, "the %s's thumb hole is at the end away from the paint" % name)
		for side in ["left", "right"]:
			var hand: Hand = main.rig.left if side == "left" else main.rig.right
			var p: EaselTool.Painter = main.easel_tool.painter(hand)
			var held := EaselTool.held(hand)
			check((held * Easels.THUMB).distance_to(EaselTool.GRIP) < 1e-5, "the %s hand holds the %s at its thumb hole" % [side, name])
			check((held.basis * Vector3.UP).dot(Vector3.UP) > 0.99, "the %s hand holds its paint up" % side)
			var controller := held.affine_inverse() * Vector3.ZERO
			var grip := held.affine_inverse() * EaselTool.GRIP
			for i in Brushwork.PIGMENTS.size():
				var w := Easels.well(kit, i)
				for at: Vector3 in [controller, grip]:
					check(Vector2(at.x - w.x, at.z - w.z).length() > Easels.WELL_REACH + 0.04, "the %s hand's grip is clear of the %s's colour %d" % [side, name, i])
				check((held * w).x * (1.0 if side == "left" else -1.0) > 0.0, "the %s's colour %d lies toward the other hand from the %s hand" % [name, i, side])
			check((held * paint).z < 0.0, "the %s hand's %s reaches forward" % [side, name])
			var tool := hand.tool
			await play([{"op": "take", "what": name, "hand": side}, {"op": "hold", "hand": side, "at": [-0.5 if side == "left" else 0.5, 1.0, 0.5]}])
			await frames(10)
			check(p.palette == e and p.kit == kit and node.global_transform.is_equal_approx(hand.global_transform * held), "the %s stays in the %s hand once the grip lets go" % [name, side])
			await play([{"op": "hold", "hand": side, "at": [0.0, 1.1, 0.6]}])
			check(node.global_transform.is_equal_approx(hand.global_transform * held), "and goes where that hand goes")
			var from := node.global_transform
			check(hand.global_position.distance_to(e.tray(Easels.KITS[kit])) > Easels.KIT_REACH[kit] + EaselTool.REACH, "the %s hand is well away from the %s's place on the tray" % [side, name])
			main.easel_tool.grab(p)
			check(p.palette == null and hand.tool == tool, "a grip there lets go of the %s and gives the %s hand back its %s" % [name, side, Hand.Tool.keys()[tool]])
			await frames(int(EaselTool.RETURN * 30.0))
			var rest_at: Vector3 = e.global_transform * Easels.KITS[kit]
			var along: float = node.global_position.distance_to(rest_at) / from.origin.distance_to(rest_at)
			check(along > 0.05 and along < 0.95, "halfway through its return the %s is on its way to the tray, not jumped there: %.2f of the way left" % [name, along])
			await frames(int(EaselTool.RETURN * 60.0))
			check(not node.top_level and node.transform.is_equal_approx(rest) and main.easel_tool.returning.is_empty(), "and the %s comes to rest at its place on the tray" % name)
		var left: EaselTool.Painter = main.easel_tool.painter(main.rig.left)
		left.brush = Brushwork.Brush.SMALL
		await play([{"op": "take", "what": name, "hand": "left"}, {"op": "take", "what": "big", "hand": "left"}])
		await frames(int(EaselTool.RETURN * 60.0) + 1)
		check(left.palette == null and node.transform.is_equal_approx(rest) and left.brush == Brushwork.Brush.SMALL, "a grip at a brush while holding the %s sends it back and takes no brush" % name)
	await play([{"op": "take", "what": "box", "hand": "left"}, {"op": "take", "what": "box", "hand": "right"}])
	var right: EaselTool.Painter = main.easel_tool.painter(main.rig.right)
	check(right.palette == null, "the box in one hand is not the other's to take")
	await play([{"op": "take", "what": "palette", "hand": "right"}])
	check(right.kit == Brushwork.Medium.OIL and right.palette == e, "while the other hand takes the oil palette")
	await play([{"op": "set_down", "hand": "left"}, {"op": "set_down", "hand": "right"}])
	await play([{"op": "rests"}])


## Besides a grip anywhere, picking another tool from the wheel sends a held palette home and leaves that tool in the
## hand, and an easel taken away while its palette is held leaves the hand holding nothing of it.
func _every_way_out_lets_the_palette_go() -> void:
	var e: Easels.Easel = main.easels.easels.values()[-1]
	var p: EaselTool.Painter = main.easel_tool.painter(main.rig.left)
	var node: Node3D = e.palettes[Brushwork.Medium.OIL]
	await play([{"op": "take", "what": "palette", "hand": "left"}, {"op": "pick", "hand": "left", "tool": "seeds"}, {"op": "rests"}])
	check(p.palette == null and main.rig.left.tool == Hand.Tool.SEEDS and not node.top_level and node.transform.is_equal_approx(Transform3D(Basis(), Easels.KITS[Brushwork.Medium.OIL])), "picking seeds from the wheel sends the palette home and holds seeds")
	await play([{"op": "pick", "hand": "left", "tool": "easel"}, {"op": "take", "what": "palette", "hand": "left"}])
	var id := e.id
	var from: Vector3 = main.rig.head.global_position
	main.delete_tool.press(main.rig.right, from, e.canvas_frame().origin - from)
	main.delete_tool.let_go(main.rig.right)
	await frames(int(EaselTool.RETURN * 60.0) + 2)
	check(main.easels.find(id) == null and p.palette == null and main.easel_tool.returning.is_empty() and EaselTool.holding(p) != "oil palette", "an easel taken away while its palette is held leaves the hand holding none")
	await play([{"op": "press", "button": "dpad_down"}])
	check(main.easels.find(id) != null, "and undo stands it back up")


class Lines:
	extends Logger
	var lines: PackedStringArray = []

	func _log_message(message: String, _error: bool) -> void:
		lines.append_array(message.split("\n", false))


## Each change in what a hand holds, and each grip that takes something, prints one line saying what it holds now: a
## brush, a stick of charcoal or a palette taken, the one held taken again, a palette set down, the sheet gripped and
## let go, and another tool picked and the easel tool picked back.
func _every_held_change_logs_a_line() -> void:
	var log := Lines.new()
	OS.add_logger(log)
	var transitions := [
		["right", "stick", [{"op": "take", "what": "stick"}]],
		["right", "big", [{"op": "take", "what": "big"}]],
		["right", "stick", [{"op": "take", "what": "stick"}]],
		["right", "stick", [{"op": "take", "what": "stick"}]],
		["right", "oil palette", [{"op": "take", "what": "palette"}]],
		["right", "stick", [{"op": "set_down"}]],
		["right", "seeds", [{"op": "pick", "tool": "seeds"}]],
		["right", "stick", [{"op": "pick", "tool": "easel"}]],
		["right", "sheet", [{"op": "sheet", "pull": 0.1, "seconds": 0.1}, {"op": "hold", "at": [0.4, 1.0, 0.5]}]],
		["left", "water palette", [{"op": "take", "what": "box", "hand": "left"}]],
		["left", "walls", [{"op": "pick", "hand": "left", "tool": "walls"}]],
		["right", "flat", [{"op": "take", "what": "flat"}]],
		["right", "camera", [{"op": "pick", "tool": "camera"}]],
	]
	for t: Array in transitions:
		var tracker := "%s_hand " % t[0]
		var from := log.lines.size()
		await play(t[2])
		await frames(2)
		var said := Array(log.lines.slice(from)).filter(func(l: String) -> bool: return l.begins_with("easel: " + tracker))
		check(said.size() == (2 if t[1] == "sheet" else 1) and said[0].contains("holds %s," % t[1]), "%s to %s logs one line: %s" % [t[2], t[1], said])
		if t[1] == "sheet":
			check(said.size() == 2 and said[1].contains("holds stick,"), "letting the sheet go logs one line: %s" % [said])
	OS.remove_logger(log)


## A brush whose tip goes in anywhere over a pan's or an oil colour's paint, or on through the palette under it, comes
## out in that colour and medium, from a palette in the other hand or on the tray, and paints in it.
func _a_tip_in_each_well_loads_its_colour() -> void:
	var e: Easels.Easel = main.easels.easels.values()[-1]
	var tool: EaselTool = main.easel_tool
	var hand: Hand = main.rig.right
	var p := tool.painter(hand)
	var along := Vector3(0.3, -1.0, -0.4).normalized()
	var tip_at := func(at: Vector3) -> void:
		var basis := Basis.looking_at(along, Vector3.UP)
		hand.global_transform = Transform3D(basis, at - basis * ToolModels.BRUSH_TIP)
		hand.held_still = true
	for kit: Brushwork.Medium in e.palettes:
		var reach: float = {Brushwork.Medium.WATER: Easels.PAN.x * 0.45, Brushwork.Medium.OIL: Easels.WELL_RADIUS * 0.9}[kit]
		for held in [true, false]:
			if held:
				await play([{"op": "take", "what": "box" if kit == Brushwork.Medium.WATER else "palette", "hand": "left"}, {"op": "hold", "hand": "left", "at": [-0.5, 1.0, 0.5]}])
			for i in Brushwork.PIGMENTS.size():
				var w := Easels.well(kit, i)
				for spot: Vector3 in [Vector3.ZERO, Vector3(reach, 0.005, 0), Vector3(0, -0.03, -reach), Vector3(-0.008, -0.045, 0.008)]:
					tool._take_brush(p, Brushwork.Brush.BIG, e)
					var into: Vector3 = e.palettes[kit].global_transform * (w + spot)
					tip_at.call(into - along * 0.1)
					await frames(2)
					tip_at.call(into)
					await frames(2)
					var shown: Color = p.tip.get_shader_parameter("paint_colour")
					check(p.medium == kit and p.colour.distance_to(Brushwork.absorbance(Brushwork.PIGMENTS[i])) < 1e-4 and is_equal_approx(p.load, 0.1), "a tip at %s in %s %d of a palette %s loads its colour" % [spot, EaselTool.PAINTS[kit], i, "in hand" if held else "on the tray"])
					check(shown.is_equal_approx(tool._paint_colour(p)), "the bristles show %s %d's colour" % [EaselTool.PAINTS[kit], i])
			if held:
				await play([{"op": "set_down", "hand": "left"}])
	await play([{"op": "brush", "points": [[0.3, 0.3, 0.8], [0.6, 0.32, 0.9]], "seconds": 0.2}])
	await _settled()
	var strokes: Array = world.state.easels[e.id].strokes
	check(not strokes.is_empty() and Vector3(strokes[-1].colour).distance_to(Brushwork.absorbance(Brushwork.PIGMENTS[-1])) < 1e-4 and strokes[-1].medium == Brushwork.Medium.OIL, "the stroke after paints in the last oil colour")


func _oil_paints_onto_the_board_as_onto_the_canvas() -> void:
	world.restore({"seq": 0, "cmds": []})
	await _settled()
	await play([{"op": "place", "x": 0, "z": 6}, {"op": "easel", "x": 0, "z": 3}, {"op": "take", "what": "big"}, {"op": "dip", "what": "oil", "index": 5}])
	var e: Easels.Easel = main.easels.easels.values()[-1]
	var p: EaselTool.Painter = main.easel_tool.painter(main.rig.right)
	check(e.board.size == Easels.BOARD and e.board.metres.x > Easels.PALETTE_SIZE.x and e.board.metres.y > Easels.PALETTE_SIZE.y, "the board is a paint surface covering the palette: %s m" % e.board.metres)
	await play([{"op": "mix", "points": [[-0.3, 0.0, 0.7], [0.1, 0.0, 0.7]], "seconds": 0.3}])
	await _settled()
	var laid: Array = _easel().palette
	check(laid.size() == 1 and laid[0].medium == Brushwork.Medium.OIL and Vector3(laid[0].colour).distance_to(Brushwork.absorbance(Brushwork.PIGMENTS[5])) < 1e-4 and Brushwork.count(laid[0]) >= 2, "blue painted onto the board is a stroke of it there: %d strokes" % laid.size())
	check(_easel().strokes.is_empty(), "not on the canvas")
	check(is_equal_approx(p.load, 0.1), "painting keeps the tap's load: %.2f" % p.load)
	var dabs := Brushwork.Stroker.new(laid[0], e.board.size).add(Brushwork.unpack(laid[0].samples, 0))
	var uv := Vector2(dabs[0], dabs[1]) / Vector2(e.board.size)
	check(uv.distance_to(Vector2(0.5 - 0.3 * Easels.PALETTE_SIZE.x * 0.5 / e.board.metres.x, 0.5)) < 0.02, "where the brush touched the board: %s" % uv)
	await play([{"op": "take", "what": "small"}, {"op": "mix", "points": [[0.0, 0.0, 0.6], [0.02, 0.0, 0.6]], "seconds": 0.3}])
	await _settled()
	check(_easel().palette.size() == 1, "a clean brush lays nothing on it")
	await play([{"op": "press", "button": "dpad_down"}])
	check(_easel().palette.is_empty() and main.easels.easels.values()[-1].board.settled(), "undo takes the board's stroke off")
	await play([{"op": "press", "button": "A"}])
	check(_easel().palette.size() == 1, "and redo puts it back")
	var state := {"stairs": {}, "easels": {7: {"at": Vector3.ZERO, "yaw": 0.0, "strokes": [], "palette": []}}, "walls": {}, "paths": {}, "grounds": {}, "groups": {}, "ponds": {}}
	check(not Commands.clean({"op": "paint", "easel": 7, "palette": true, "stroke": laid[0]}, state, false, world.terrain).is_empty(), "a stroke on the board is a command")
	check(Commands.clean({"op": "paint", "easel": 7, "palette": 1, "stroke": laid[0]}, state, false, world.terrain).is_empty(), "naming its surface by a flag, not anything else")
	check(Commands.clean({"op": "unpaint", "easel": 7, "palette": true}, state, false, world.terrain).is_empty(), "nor is taking one off an empty board")
	check(not Easels.open_at(Vector2(Easels.THUMB.x, Easels.THUMB.z)) and not Easels.open_at(Easels.PALETTE_SIZE * 0.5) and Easels.open_at(Vector2.ZERO), "paint lies on the open board, not over the thumb hole or off its edge")


## The same touch, in each surface's own frame, on the canvas and on the oil palette's board: each brush and the
## charcoal stop at the face, the bristles bend as far, the hand feels it alike, and a brush's stroke keeps the same
## samples, as far apart in metres, as hard and at the same angle. Charcoal marks the canvas's paper, not the board.
func _a_touch_paints_the_board_as_it_paints_the_canvas() -> void:
	world.restore({"seq": 0, "cmds": []})
	await _settled()
	await play([{"op": "place", "x": 0, "z": 6}, {"op": "easel", "x": 0, "z": 3}])
	var e: Easels.Easel = main.easels.easels.values()[-1]
	var tool: EaselTool = main.easel_tool
	var p: EaselTool.Painter = tool.painter(main.rig.right)
	var felt := [0, 0]
	var on := [false]
	var feel := func(hand: Hand, _at: Vector3, _stick: bool, touching: bool, _pressure: float, _speed: float, _distance: float, _hard: bool) -> void:
		if hand == p.hand and touching:
			felt[1 if on[0] else 0] += 1
	tool.canvas_contact.connect(feel)
	const STEPS := 40
	for kind: Brushwork.Brush in [Brushwork.Brush.BIG, Brushwork.Brush.FLAT, Brushwork.Brush.STICK]:
		var b := Basis(Vector3.RIGHT, -PI * 0.25) if Brushwork.is_stick(kind) else Basis(Vector3.RIGHT, 0.4) * Basis(Vector3.BACK, 0.3)
		var runs := []
		for palette: bool in [false, true]:
			on[0] = palette
			felt[1 if palette else 0] = 0
			tool._take_brush(p, kind, e)
			if not Brushwork.is_stick(kind):
				tool.dip(p, "oil5")
			var frame := e.frame(palette)
			var deepest := INF
			var bent := 0.0
			var data := {}
			for i in STEPS:
				var tip := Vector3(-0.02 + 0.04 * i / (STEPS - 1.0), 0.01, 0.02 - 0.05 * minf(i / 10.0, 1.0))
				p.hand.body.global_transform = frame * Transform3D(b, tip - b * ToolModels.BRUSH_TIP) * ToolModels.hold(p.brush).affine_inverse()
				tool._touch(p, e, palette, 1.0 / 60.0)
				deepest = minf(deepest, (frame.affine_inverse() * EaselTool.held_brush(p) * ToolModels.BRUSH_TIP).z)
				bent = maxf(bent, p.bend.length())
				if not p.stroke.is_empty():
					data = p.stroke.data
			tool.end_stroke(p)
			tool._clear_contact(p)
			world.flush()
			runs.append({"deepest": deepest, "bent": bent, "data": data, "metres": e.surface(palette).metres, "felt": felt[1 if palette else 0]})
		var what: String = Brushwork.Brush.keys()[kind].to_lower()
		var canvas: Dictionary = runs[0]
		var board: Dictionary = runs[1]
		check(absf(board.deepest - canvas.deepest) < 1e-4, "the %s stops as deep at the board as at the canvas: %.4f and %.4f m" % [what, board.deepest, canvas.deepest])
		check(absf(board.bent - canvas.bent) < 1e-4 and (Brushwork.is_stick(kind) or canvas.bent > CanvasContact.BEND * 0.9), "its bristles bend as far against each: %.4f and %.4f m" % [board.bent, canvas.bent])
		check(board.felt == canvas.felt and canvas.felt > 0, "the hand feels each touch alike: %d and %d frames" % [board.felt, canvas.felt])
		if Brushwork.is_stick(kind):
			check(not canvas.data.is_empty() and board.data.is_empty(), "the %s marks the canvas and not the board" % what)
			continue
		check(not canvas.data.is_empty() and not board.data.is_empty(), "the %s paints both the canvas and the board" % what)
		if canvas.data.is_empty() or board.data.is_empty():
			continue
		var n := Brushwork.count(canvas.data)
		check(Brushwork.count(board.data) == n and n > 5, "it keeps as many samples on each: %d and %d" % [Brushwork.count(board.data), n])
		if Brushwork.count(board.data) != n:
			continue
		var worst := Vector3.ZERO
		var first := [Brushwork.unpack(canvas.data.samples, 0), Brushwork.unpack(board.data.samples, 0)]
		for i in n:
			var c := Brushwork.unpack(canvas.data.samples, i)
			var o := Brushwork.unpack(board.data.samples, i)
			var moved: Vector2 = (c[0] - first[0][0]) * canvas.metres - (o[0] - first[1][0]) * board.metres
			worst = Vector3(maxf(worst.x, moved.length()), maxf(worst.y, absf(c[1] - o[1])), maxf(worst.z, absf(Brushwork.turn(c[2], o[2]))))
		check(worst.x < 1e-4 and worst.y < 1.5 / 255.0 and worst.z < 0.02, "and each sample alike, worst apart %.5f m, pressure %.3f, angle %.3f" % [worst.x, worst.y, worst.z])
		check(board.data.medium == canvas.data.medium and board.data.brush == canvas.data.brush, "in the same medium")
	tool.canvas_contact.disconnect(feel)


## The trigger path a headset player uses: the easel tool taken from the wheel, the hand pointed at the ground, the
## trigger pressed; on either hand and either headset's controls. A press that sets none up says why.
func _the_trigger_sets_one_up_or_says_why_not() -> void:
	world.restore({"seq": 0, "cmds": []})
	await _settled()
	var why: Array[String] = []
	main.easel_tool.declined.connect(func(w: String) -> void: why.append(w))
	var press := func(hand: String, device: String, at: Array) -> void:
		why.clear()
		await play([
			{"op": "pick", "tool": "easel", "hand": hand},
			{"op": "point", "tool": "easel", "hand": hand, "at": at},
			{"op": "press", "button": hand + "_trigger", "device": device},
		])
		await _settled()
	await play([{"op": "place", "x": 0, "z": 6}, {"op": "wait", "seconds": 0.05}])
	for t in [["right", "quest", [-6, 0, 0]], ["left", "quest", [6, 0, 0]], ["right", "frame", [0, 0, -2]], ["left", "frame", [-3, 0, -6]]]:
		var before: int = world.state.easels.size()
		await press.call(t[0], t[1], t[2])
		check(world.state.easels.size() == before + 1 and why.is_empty(), "the %s trigger on the %s sets an easel up from the wheel: %d easels, %s" % [t[0], t[1], world.state.easels.size(), why])
	await press.call("right", "quest", [3, 0, 10])
	check(world.state.easels.size() == Easels.MAX and why.size() == 1 and why[0].contains("holds its"), "past the garden's easels a press sets none up and says so: %s" % [why])
	await play([{"op": "press", "button": "dpad_down"}])
	await press.call("right", "quest", [-6.5, 0, 0.3])
	check(world.state.easels.size() == Easels.MAX - 1 and why.size() == 1 and why[0].contains("another easel"), "nor beside another easel: %s" % [why])
	await press.call("right", "quest", [0, 30, -10])
	check(why.size() == 1 and why[0].contains("no ground"), "nor at the sky: %s" % [why])
	var first: Vector3 = world.state.easels.values()[0].at
	await play([{"op": "place", "x": first.x, "z": first.z + 1.0}, {"op": "wait", "seconds": 0.05}])
	await press.call("right", "quest", [first.x, 0, first.z - 8])
	check(world.state.easels.size() == Easels.MAX - 1 and why.size() == 1 and why[0].contains("of an easel"), "nor from a hand at an easel: %s" % [why])


func _easels_keep_their_distance_and_number() -> void:
	var state := World.blank()
	var at := world.terrain.ground(10, 10)
	var cmd := {"op": "easel", "at": at, "yaw": 0.5}
	check(not Commands.clean(cmd, state, false, world.terrain).is_empty(), "an easel may stand on open ground")
	state.easels[1] = {"at": at, "yaw": 0.0, "strokes": []}
	check(Commands.clean(cmd, state, false, world.terrain).is_empty(), "but not on another")
	for i in Easels.MAX - 1:
		state.easels[i + 2] = {"at": world.terrain.ground(-20 + i * 5, -20), "yaw": 0.0, "strokes": []}
	check(Commands.clean({"op": "easel", "at": world.terrain.ground(20, 20), "yaw": 0.0}, state, false, world.terrain).is_empty(), "nor one more than a garden holds")
	check(Commands.clean({"op": "easel", "at": world.terrain.ground(20, 20), "yaw": 0.0, "strokes": [{}]}, World.blank(), false, world.terrain).is_empty(), "a player's new easel brings no painting with it")


func _bad_strokes_are_dropped() -> void:
	var good := {"medium": Brushwork.Medium.OIL, "brush": Brushwork.Brush.FLAT, "colour": Vector3(1, 2, 3), "strength": 1.0, "load": 0.5, "gap": 3, "samples": Brushwork.pack(Vector2(0.5, 0.5), 0.5, 0.0, 0) + Brushwork.pack(Vector2(0.6, 0.5), 0.5, 0.0, 2)}
	check(Brushwork.clean(good) != null, "a stroke a brush could paint is kept")
	var bad := {
		"no samples": {"samples": PackedInt32Array()},
		"half a sample": {"samples": PackedInt32Array([1, 2, 3])},
		"too many samples": {"samples": _many(Brushwork.MAX_SAMPLES + 1)},
		"an unknown medium": {"medium": 7},
		"charcoal on a brush": {"medium": Brushwork.Medium.CHARCOAL},
		"a stick dipped in oil": {"brush": Brushwork.Brush.STICK},
		"a colour past any pigment": {"colour": Vector3(0, 0, 99)},
		"a colour not a number": {"colour": Vector3(NAN, 0, 0)},
		"more paint than a brush holds": {"load": 1.5},
		"a gap past drying": {"gap": Brushwork.DRY_TICKS + 1},
		"a float for samples": {"samples": PackedFloat32Array([0.5, 0.5])},
	}
	for what in bad:
		var s := good.duplicate()
		s.merge(bad[what], true)
		check(Brushwork.clean(s) == null, "a stroke with %s is dropped" % what)
	var state := {"easels": {4: {"at": Vector3.ZERO, "yaw": 0.0, "strokes": []}}}
	check(not Commands.clean({"op": "paint", "easel": 4, "stroke": good}, state, false, world.terrain).is_empty(), "a good stroke paints a standing easel")
	check(Commands.clean({"op": "paint", "easel": 5, "stroke": good}, state, false, world.terrain).is_empty(), "but no easel that is not there")
	check(Commands.clean({"op": "sheet", "easel": 4, "strokes": [good]}, state, false, world.terrain).is_empty(), "a player's fresh sheet is blank")
	var full: Array = []
	var each := _many(Brushwork.MAX_SAMPLES)
	for i in Brushwork.MAX_TOTAL / Brushwork.MAX_SAMPLES:
		var s := good.duplicate()
		s.samples = each
		full.append(s)
	var rest := good.duplicate()
	rest.samples = _many(Brushwork.MAX_TOTAL % Brushwork.MAX_SAMPLES)
	full.append(rest)
	state.easels[4].strokes = full
	check(Commands.clean({"op": "paint", "easel": 4, "stroke": good}, state, false, world.terrain).is_empty(), "a full canvas takes no more")


## Each demo script's dips name the jar or a palette's paint, so none plays a dip the driver cannot place.
func _every_demo_dips_into_something_on_the_tray() -> void:
	var known: Array = EaselTool.PAINTS.values() + ["jar"]
	var demos := ProjectSettings.globalize_path("res://").path_join("../demo")
	for f in DirAccess.get_files_at(demos):
		if not f.ends_with(".json"):
			continue
		for step: Dictionary in JSON.parse_string(FileAccess.get_file_as_string(demos.path_join(f))):
			if step.get("op") == "dip":
				check(step.what in known, "%s dips into %s, which is on no tray" % [f, step.what])


func _many(n: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in n:
		out.append_array(Brushwork.pack(Vector2(0.5, 0.5), 0.5, 0.0, 1))
	return out


func _reaches_for_each_implement() -> void:
	var e: Easels.Easel = main.easels.easels.values()[-1]
	var p: EaselTool.Painter = main.easel_tool.painter(main.rig.right)
	check(is_inf(EaselTool.pick_distance(Transform3D.IDENTITY, Vector3.FORWARD * 0.13)), "pointing does not extend grab reach")
	var hits := 0
	var total := 0
	for kind: Brushwork.Brush in Brushwork.Brush.values():
		var node: Node3D = e.brushes[kind]
		var target := node.global_transform * Easels.grip(kind)
		var correct := 0
		for yaw in [-60.0, -30.0, 0.0, 30.0, 60.0]:
			for height in [0.2, 0.8]:
				var approach := e.global_basis * Vector3(sin(deg_to_rad(yaw)), height, cos(deg_to_rad(yaw))).normalized()
				for distance in [0.04, 0.08, 0.11]:
					for noise in [-0.008, 0.0, 0.008]:
						var at: Vector3 = target + approach * distance + e.global_basis.x * noise
						main.easel_tool._set_down(p)
						p.peel = null
						p.hand.tool = Hand.Tool.EASEL
						_empty_handed(p, kind)
						p.hand.global_transform = Transform3D(Basis.looking_at(-approach), at)
						main.easel_tool.grab(p)
						var hit := p.hand.tool == Hand.Tool.EASEL and p.palette == null and p.peel == null and p.brush == kind
						correct += int(hit)
						total += 1
		print("pick-rate: %s %d/90" % [Brushwork.Brush.keys()[kind], correct])
		hits += correct
	print("pick-rate: total %d/%d (%.2f%%)" % [hits, total, 100.0 * hits / total])
	check(hits * 360 >= 338 * total, "aimed reaches take the intended implement at least 338 times in 360")
	main.easel_tool._set_down(p)
	p.peel = null


func _preview_matches_the_grip() -> void:
	var e: Easels.Easel = main.easels.easels.values()[-1]
	var p: EaselTool.Painter = main.easel_tool.painter(main.rig.right)
	_empty_handed(p, Brushwork.Brush.SMALL)
	for kind: Brushwork.Brush in Brushwork.Brush.values():
		await play([{"op": "take", "what": Brushwork.Brush.keys()[kind].to_lower(), "preview": true}])
		var node: Node3D = e.brushes[kind]
		check(main.easel_tool.highlighted.has(node), "the approached %s is highlighted before grip" % Brushwork.Brush.keys()[kind])
		for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
			check(mesh.material_overlay == main.easel_tool.highlight, "the preview visibly highlights its meshes")
		main.easel_tool.grab(p)
		check(p.brush == kind and p.palette == null, "grip takes the highlighted implement")
	p.hand.global_position += Vector3.UP * 2.0
	await _settled()
	check(main.easel_tool.highlighted.is_empty(), "moving away clears the highlight")


## No hand here shows a tool taken from an easel, so every easel shows all of its, and `p`'s brush is not `kind`, so
## a grip that takes `kind` changes it.
func _empty_handed(p: EaselTool.Painter, kind: Brushwork.Brush) -> void:
	for o in main.easel_tool.painters:
		o.brush_from = 0
	p.brush = Brushwork.Brush.BIG if kind != Brushwork.Brush.BIG else Brushwork.Brush.SMALL
	main.easel_tool._rack()


## An easel holds one of each brush, stick and palette; the one a hand takes is off it, the other hand cannot take it
## too, and it is back while that hand shows anything else and once it takes another. What a player across the garden
## holds is off it as well.
func _each_easel_holds_one_of_each_tool() -> void:
	var e: Easels.Easel = main.easels.easels.values()[-1]
	var right: EaselTool.Painter = main.easel_tool.painter(main.rig.right)
	var left: EaselTool.Painter = main.easel_tool.painter(main.rig.left)
	_empty_handed(right, Brushwork.Brush.SMALL)
	var implements := e.get_node("implements").get_children()
	var tools := implements.filter(func(n: Node) -> bool: return n in e.brushes.values() or n in e.palettes.values())
	var charcoal := e.get_node("implements").find_children("*", "MeshInstance3D", true, false).filter(func(m: MeshInstance3D) -> bool: return m.material_override == ToolModels.charcoal_material())
	check(e.brushes.size() == Brushwork.Brush.size() and e.palettes.size() == Easels.KITS.size() and tools.size() == Brushwork.Brush.size() + Easels.KITS.size(), "an easel holds one of each brush, stick and palette: %d tools" % tools.size())
	check(charcoal.size() == Brushwork.STICKS.size(), "and no charcoal but its sticks: %d pieces" % charcoal.size())
	check(e.brushes.values().all(func(n: Node3D) -> bool: return n.visible), "with nothing taken all of it shows")
	await play([{"op": "take", "what": "small"}])
	await process_frame
	check(right.brush == Brushwork.Brush.SMALL and not e.brushes[Brushwork.Brush.SMALL].visible, "the small brush a hand takes is off the easel")
	left.hand.global_transform = Transform3D(e.global_basis, e.brushes[Brushwork.Brush.SMALL].global_transform * Easels.grip(Brushwork.Brush.SMALL))
	check(main.easel_tool.candidate(left).get("node") != e.brushes[Brushwork.Brush.SMALL], "and the other hand cannot take it too")
	await play([{"op": "take", "what": "thick_stick"}])
	await process_frame
	check(e.brushes[Brushwork.Brush.SMALL].visible and not e.brushes[Brushwork.Brush.THICK_STICK].visible, "taking another puts it back and takes that one off")
	await play([{"op": "take", "what": "thick_stick"}])
	check(right.brush == Brushwork.Brush.THICK_STICK and not e.brushes[Brushwork.Brush.THICK_STICK].visible, "a grip at the one in hand takes it again, not a neighbour")
	await play([{"op": "pick", "tool": "seeds"}])
	await process_frame
	check(e.brushes[Brushwork.Brush.THICK_STICK].visible, "it is back while the hand holds another tool")
	await play([{"op": "pick", "tool": "easel"}])
	await process_frame
	check(not e.brushes[Brushwork.Brush.THICK_STICK].visible, "and off again in hand when the easel tool is picked back")
	await play([{"op": "pick", "tool": "seeds"}, {"op": "take", "what": "thick_stick", "hand": "left"}, {"op": "pick", "tool": "easel"}])
	await process_frame
	check(left.brush == Brushwork.Brush.THICK_STICK and left.brush_from == e.id and right.brush_from == 0 and not e.brushes[Brushwork.Brush.THICK_STICK].visible, "taken by the other hand meanwhile, it stays with that hand")
	await play([{"op": "take", "what": "small", "hand": "left"}])
	await play([{"op": "take", "what": "flat"}])
	await process_frame
	check(e.brushes[Brushwork.Brush.THICK_STICK].visible and not e.brushes[Brushwork.Brush.FLAT].visible, "a stick goes back as a brush does")
	var peer := HeldItem.new()
	peer.add_to_group(HeldItem.GROUP)
	root.add_child(peer)
	peer.state = [HeldItem.Kind.BRUSH, Brushwork.Brush.BIG, Transform3D(), Color.WHITE, 0.0, e.id, false, Vector3.ZERO]
	await process_frame
	check(not e.brushes[Brushwork.Brush.BIG].visible, "a brush a player across the garden took from it is off it")
	peer.state = [HeldItem.Kind.PALETTE, Brushwork.Medium.OIL, Transform3D(), Color.WHITE, 0.0, e.id, false, Vector3.ZERO]
	await process_frame
	right.hand.global_transform = Transform3D(e.global_basis, e.palettes[Brushwork.Medium.OIL].global_position)
	check(e.brushes[Brushwork.Brush.BIG].visible and not e.palettes[Brushwork.Medium.OIL].visible and main.easel_tool.candidate(right).is_empty(), "and so is a palette, which no hand here can take")
	peer.free()
	await process_frame
	check(e.palettes[Brushwork.Medium.OIL].visible, "and it is back when they let it go")
	_empty_handed(right, Brushwork.Brush.SMALL)


## The charcoal comes in three sizes laid well apart on the tray: a grip at each takes it, and a thicker stick is a
## thicker, shorter model and lays a wider mark.
func _sticks_come_in_sizes() -> void:
	var e: Easels.Easel = main.easels.easels.values()[-1]
	var p: EaselTool.Painter = main.easel_tool.painter(main.rig.right)
	var sizes: Array = Brushwork.STICKS.keys()
	check(sizes.size() == 3, "three sizes of charcoal")
	var marks := []
	for kind: Brushwork.Brush in sizes:
		var data := {"medium": Brushwork.Medium.CHARCOAL, "brush": kind, "load": 1.0}
		marks.append(Brushwork.Stroker.new(data).add([Vector2(0.5, 0.5), 1.0, 0.0, 0, 0.0])[2])
	for i in range(1, sizes.size()):
		var thin: Brushwork.Brush = sizes[i - 1]
		var thick: Brushwork.Brush = sizes[i]
		var what := "the %s against the %s" % [Brushwork.Brush.keys()[thick], Brushwork.Brush.keys()[thin]]
		check(_thickness(e.brushes[thick]) > _thickness(e.brushes[thin]) * 1.4, "%s: a thicker model, %.4f m to %.4f m" % [what, _thickness(e.brushes[thick]), _thickness(e.brushes[thin])])
		check(_length(e.brushes[thick]) < _length(e.brushes[thin]) * 0.75, "%s: a shorter model, %.3f m to %.3f m" % [what, _length(e.brushes[thick]), _length(e.brushes[thin])])
		check(marks[i] > marks[i - 1] * 1.4, "%s: a wider mark, %.1f to %.1f texels" % [what, marks[i], marks[i - 1]])
		var gap: float = (e.brushes[thick].global_transform * Easels.grip(thick)).distance_to(e.brushes[thin].global_transform * Easels.grip(thin))
		check(gap >= 0.09, "%s: %.3f m apart on the tray" % [what, gap])
	for kind: Brushwork.Brush in sizes:
		_empty_handed(p, kind)
		await play([{"op": "take", "what": Brushwork.Brush.keys()[kind].to_lower()}])
		check(p.brush == kind and p.medium == Brushwork.Medium.CHARCOAL, "a grip at the %s takes it" % Brushwork.Brush.keys()[kind])
	_empty_handed(p, Brushwork.Brush.SMALL)


## How thick a stick of charcoal's model is across its length.
static func _thickness(stick: Node3D) -> float:
	var mi: MeshInstance3D = stick.get_node("tip")
	return (mi.transform * mi.get_aabb()).size.x


## How long a stick of charcoal's model is.
static func _length(stick: Node3D) -> float:
	var mi: MeshInstance3D = stick.get_node("tip")
	return (mi.transform * mi.get_aabb()).size.z


## A stick of charcoal is held leaned back 45 degrees from the hand's aim, its tip raised, and a brush along the aim.
func _a_held_stick_leans_back() -> void:
	var p: EaselTool.Painter = main.easel_tool.painter(main.rig.right)
	for kind: Brushwork.Brush in Brushwork.STICKS:
		_empty_handed(p, kind)
		await play([{"op": "take", "what": Brushwork.Brush.keys()[kind].to_lower()}])
		await process_frame
		var body := p.hand.body.global_basis.orthonormalized()
		var along: Vector3 = -p.models[kind].global_basis.orthonormalized().z
		check(absf(rad_to_deg((-body.z).angle_to(along)) - 45.0) < 1.0 and along.dot(body.y) > 0.0, "the %s is held leaned back 45 degrees, tip up: %.1f" % [Brushwork.Brush.keys()[kind], rad_to_deg((-body.z).angle_to(along))])
		check((EaselTool.held_brush(p) * ToolModels.BRUSH_TIP).distance_to(p.models[kind].global_transform * ToolModels.BRUSH_TIP) < 1e-4, "its tip is where it paints")
	await play([{"op": "take", "what": "big"}])
	await process_frame
	check(p.models[Brushwork.Brush.BIG].global_basis.z.normalized().dot(p.hand.body.global_basis.z.normalized()) > 0.9999, "a brush is held along the aim")
	_empty_handed(p, Brushwork.Brush.SMALL)


## A stick lying on its side and turned on the canvas through half a turn about its middle, as drawing a circle with its
## side, lays a mark that turns with it: the stroke keeps each turn, its dabs turn smoothly through the half turn to
## end where the stick does, and it lays as much charcoal as a straight side stroke sweeping as far.
func _a_side_stroke_turns_with_the_stick() -> void:
	const STEPS := 60
	var e: Easels.Easel = main.easels.easels.values()[-1]
	var p: EaselTool.Painter = main.easel_tool.painter(main.rig.right)
	main.easel_tool.end_stroke(p)
	main.easel_tool._take_brush(p, Brushwork.Brush.STICK, e)
	var frame := e.canvas_frame()
	var last_angle := 0.0
	for i in STEPS + 1:
		var d := Vector3.RIGHT.rotated(Vector3.BACK, PI * i / STEPS)
		var b := Basis.looking_at(-d, Vector3.BACK)
		var size: Vector2 = Brushwork.STICKS[p.brush]
		var tip := Vector3(0, 0, size.x - 0.004) - d * size.y * 0.5
		p.hand.body.global_transform = frame * Transform3D(b, tip - b * ToolModels.BRUSH_TIP) * ToolModels.hold(p.brush).affine_inverse()
		main.easel_tool._touch(p, e, false, 1.0 / 60.0)
		last_angle = atan2(-d.y, d.x)
	check(not p.stroke.is_empty(), "the stick lies on the canvas throughout")
	if p.stroke.is_empty():
		return
	var data: Dictionary = p.stroke.data
	main.easel_tool.end_stroke(p)
	var n := Brushwork.count(data)
	check(n >= STEPS * 0.9, "the stroke keeps the stick's every turn: %d samples of %d" % [n, STEPS + 1])
	var stroker := Brushwork.Stroker.new(data)
	var angles := PackedFloat32Array()
	var laid := 0.0
	var pressure := 0.0
	for i in n:
		var sample := Brushwork.unpack(data.samples, i)
		pressure += sample[1] / n
		var dabs := stroker.add(sample)
		for k in range(0, dabs.size(), Brushwork.DAB):
			angles.append(dabs[k + 7])
			laid += dabs[k + 5]
	var turned := 0.0
	var step := 0.0
	for k in range(1, angles.size()):
		var t := Brushwork.turn(angles[k - 1], angles[k])
		turned += t
		step = maxf(step, absf(t))
	check(absf(absf(turned) - PI) < 0.1 and step < 0.1, "its dabs turn smoothly through half a turn: %.3f rad, at most %.3f a dab" % [turned, step])
	check(angles.size() > 0 and absf(Brushwork.turn(angles[-1], last_angle)) < 0.05, "and end where the stick lies")
	var straight := Brushwork.Stroker.new(data)
	var sweep := Brushwork.side_reach(data.brush, 1.0) * PI * 0.5
	straight.add([Vector2(0.3, 0.5), pressure, PI * 0.5, 0, 1.0])
	var along := 0.0
	for k in 60:
		var dabs := straight.add([Vector2(0.3 + sweep / Brushwork.SIZE.x * (k + 1) / 60.0, 0.5), pressure, PI * 0.5, 1, 1.0])
		for j in range(0, dabs.size(), Brushwork.DAB):
			along += dabs[j + 5]
	check(laid > along * 0.75 and laid < along * 1.25, "it lays as much as a straight stroke sweeping as far: %.1f against %.1f" % [laid, along])


func _held_brush_stops_with_its_hand() -> void:
	var e: Easels.Easel = main.easels.easels.values()[0]
	var p: EaselTool.Painter = main.easel_tool.painter(main.rig.right)
	main.easel_tool._take_brush(p, Brushwork.Brush.BIG, e)
	var frame := e.canvas_frame()
	p.hand.global_transform = Transform3D(frame.basis, frame * Vector3(0, 0, 0.1) - frame.basis * ToolModels.BRUSH_TIP)
	p.hand.held_still = true
	await process_frame
	await process_frame
	p.hand.global_transform = Transform3D(frame.basis, frame * Vector3(0, 0, -0.3) - frame.basis * ToolModels.BRUSH_TIP)
	await process_frame
	await process_frame
	var tracked := e.on_canvas(p.hand.global_transform * ToolModels.BRUSH_TIP)
	var visible := e.on_canvas(p.hand.body.global_transform * ToolModels.BRUSH_TIP)
	check(tracked.z < -0.29 and visible.z >= -CanvasContact.BEND - 0.001, "tracked hand passes the canvas while visible brush and hand stop: %s / %s" % [tracked, visible])
	check(p.models[p.brush].get_parent() == p.hand.body, "brush follows the collision-stopped visible hand")
	p.hand.tool = Hand.Tool.WALLS
	await process_frame
	check(p.hand.body.basis.is_equal_approx(Basis()), "dropping a tool restores the tracked hand orientation")


func _changing_canvases_ends_the_previous_stroke() -> void:
	world.restore({"seq": 0, "cmds": []})
	await _settled()
	await play([{"op": "easel", "x": -3, "z": 0}, {"op": "easel", "x": 3, "z": 0}])
	var p: EaselTool.Painter = main.easel_tool.painter(main.rig.right)
	var stands: Array = main.easels.easels.values()
	main.easel_tool._take_brush(p, Brushwork.Brush.STICK, stands[0])
	for e: Easels.Easel in stands:
		var frame := e.canvas_frame()
		p.hand.body.global_transform = Transform3D(frame.basis, frame * Vector3(0, 0, -0.01) - frame.basis * ToolModels.BRUSH_TIP) * ToolModels.hold(p.brush).affine_inverse()
		main.easel_tool._touch(p, e, false, 1.0 / 60.0)
	world.flush()
	check(world.state.easels[stands[0].id].strokes.size() == 1 and p.stroke.easel == stands[1], "crossing to another canvas commits the old stroke to its own canvas")
	main.easel_tool.end_stroke(p)
	world.flush()
	check(world.state.easels[stands[1].id].strokes.size() == 1, "the next canvas receives its own stroke command")


func _the_ghost_is_the_easel() -> void:
	var g: Node3D = main.easel_tool.painters[0].ghost
	var bounds := AABB()
	var first := true
	for mi: MeshInstance3D in g.find_children("*", "MeshInstance3D", true, false):
		var x := Transform3D(g.global_transform.basis, Vector3.ZERO) * g.global_transform.affine_inverse() * mi.global_transform
		var b := x * mi.get_aabb()
		bounds = b if first else bounds.merge(b)
		first = false
	check(bounds.grow(0.001).encloses(Easels.TRAY), "the easel's ghost carries its tray: %s" % bounds)
	check(absf(bounds.end.y - (Easels.canvas_local() * Vector3(0, Brushwork.METRES.y * 0.5, 0)).y) < 0.1, "the ghost stands as tall as the easel's canvas: top %.2f" % bounds.end.y)
