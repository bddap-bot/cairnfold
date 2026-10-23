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
	dir = OS.get_temp_dir().path_join("nestcombe-easel-%d" % OS.get_process_id())
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
	_no_plank_crosses_the_canvas()
	_no_implement_crosses_the_easel()
	_easels_share_their_geometry()
	await _the_palette_stays_in_the_hand_by_its_thumb_hole()
	await _every_way_out_lets_the_palette_go()
	await _every_held_change_logs_a_line()
	await _a_tip_in_each_well_loads_its_colour()
	await _oil_mixes_by_painting_onto_the_board_and_picking_up_from_it()
	_mixing_trades_paint_as_pigment()
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


func _play(steps: Array) -> void:
	var d := Driver.new(main, steps)
	main.add_child(d)
	await d.finished
	d.queue_free()


func _settled() -> void:
	await process_frame
	world.flush()


func _easel() -> Dictionary:
	return world.state.easels.values()[-1]


func _paint_some() -> void:
	await _play([
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
	var s := Brushwork.Stroker.new(stroke)
	for i in 5:
		s.add(Brushwork.unpack(samples, i))
	check(s.left() < 1.0 and s.left() > 0.0, "and spend some of the paint on the brush: %.3f left" % s.left())


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
	check(not e.mix.is_empty() and e.mix == main.easels.easels.values()[0].mixing.bytes, "the oil painted onto the palette held in a hand is kept as the palette shows it")
	var picture := var_to_str(world.digest())
	world.restore({"seq": 0, "cmds": []})
	await _settled()
	check(world.state.easels.is_empty() and main.easels.easels.is_empty(), "an empty garden holds no easel")
	world.load_from(path)
	check(var_to_str(world.digest()) == picture, "loading puts the easel back where it stood with every stroke as painted and its palette as mixed")
	check(main.easels.easels.values()[0].mixing.bytes == e.mix, "and the palette shows its paint again")
	check(main.easels.easels.size() == 1 and main.easels.easels.values()[0].canvas.catching_up(), "and replays its painting")


func _undo_takes_back_a_stroke_and_redo_paints_it_again() -> void:
	await _play([{"op": "take", "what": "big"}, {"op": "dip", "what": "jar"}, {"op": "dip", "what": "pan", "index": 4}, {"op": "brush", "points": [[0.3, 0.4, 0.9], [0.6, 0.45, 0.9]], "seconds": 0.2}])
	var before: Array = _easel().strokes.duplicate()
	check(before.size() == 4, "a loaded painting takes more strokes: %d" % before.size())
	await _play([{"op": "press", "button": "dpad_down"}])
	check(_easel().strokes == before.slice(0, before.size() - 1), "undo takes the last stroke off the canvas")
	await _play([{"op": "press", "button": "A"}])
	check(_easel().strokes == before, "redo paints it again")


func _a_fresh_sheet_clears_and_undo_brings_the_painting_back() -> void:
	var before: Array = _easel().strokes.duplicate()
	await _play([{"op": "sheet", "pull": 0.1}])
	check(_easel().strokes == before, "a sheet pulled a little and let go stays on")
	await _play([{"op": "sheet", "pull": 0.45}])
	check(_easel().strokes.is_empty(), "a sheet pulled well off tears away, leaving a fresh one")
	await _play([{"op": "press", "button": "dpad_down"}])
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
	await _play([{"op": "press", "button": "dpad_down"}])
	check(world.state.easels.has(id) and world.state.easels[id].strokes == before and main.easels.find(id) != null, "undo stands it back up with its painting")


## Ground raised, dug, undone, loaded whole or set back under an easel leaves it standing on that ground.
func _it_rides_the_ground_as_it_is_reshaped() -> void:
	var id: int = world.state.easels.keys()[-1]
	var e: Easels.Easel = main.easels.find(id)
	var at: Vector3 = _easel().at
	var was := e.position.y
	var cells := Terrain.cells_around(at.x, at.z, 3.0)
	var values := Terrain.read(cells)
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
	var expect := WallTool.carry_easel(was, from, to, Hand.reach_gain(from.origin.distance_to(hit.point)))
	check(e.global_position.is_equal_approx(expect.at) and is_equal_approx(expect.yaw, wrapf(was.yaw + 0.6, -PI, PI)), "the hand's move and turn carry and turn it: %s" % [expect])
	check(is_equal_approx(expect.at.y, Terrain.height_at(expect.at.x, expect.at.z)), "it stays on the ground as the hand rises")
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
	state.easels[1] = {"at": Terrain.ground(10, 10), "yaw": 0.0, "strokes": [], "mix": PackedByteArray()}
	state.easels[2] = {"at": Terrain.ground(20, 10), "yaw": 0.0, "strokes": [], "mix": PackedByteArray()}
	var move := func(data: Dictionary) -> Dictionary: return Commands.clean({"op": "reshape", "of": "easels", "id": 1, "data": data}, state, false)
	check(not move.call({"at": Terrain.ground(14, 12), "yaw": 1.0}).is_empty(), "a reshape may move and turn an easel, as a grip does")
	check(not move.call({"at": Terrain.ground(10.5, 10)}).is_empty(), "a little way from where it stood")
	check(move.call({"at": Terrain.ground(20.5, 10)}).is_empty(), "but never onto another")
	check(move.call({"yaw": 99.0}).is_empty() and move.call({"at": Vector3(INF, 0, 0)}).is_empty(), "nor turned or set past what one may stand")
	check(move.call({"strokes": []}).is_empty(), "and a reshape paints nothing")


func _the_tray_loads_the_brush() -> void:
	await _play([{"op": "take", "what": "small"}, {"op": "dip", "what": "jar"}, {"op": "dip", "what": "pan", "index": 5}, {"op": "dip", "what": "pan", "index": 1}])
	var p: EaselTool.Painter = main.easel_tool.painter(main.rig.right)
	var e: Easels.Easel = main.easels.easels.values()[-1]
	var blue := Brushwork.absorbance(Brushwork.PIGMENTS[5])
	var lemon := Brushwork.absorbance(Brushwork.PIGMENTS[1])
	var red := Brushwork.absorbance(Brushwork.PIGMENTS[3])
	check(p.brush == Brushwork.Brush.SMALL and p.medium == Brushwork.Medium.WATER and main.rig.right.tool == Hand.Tool.EASEL, "a grip at the pot takes a brush; the watercolour pans make it watercolour")
	check(p.colour.distance_to((blue + lemon) * 0.5) < 1e-3, "two pans mix on the brush")
	check(e.wash.albedo_color.is_equal_approx(main.easel_tool._paint_colour(p)), "the box's mixing field shows the mix")
	var clear := e.water.albedo_color
	await _play([{"op": "dip", "what": "jar"}])
	check(e.water.albedo_color != clear and p.medium == Brushwork.Medium.WATER, "rinsing in the jar clouds its water: %s from %s" % [e.water.albedo_color, clear])
	await _play([{"op": "dip", "what": "oil", "index": 3}])
	check(p.medium == Brushwork.Medium.OIL and p.colour.distance_to(red) < 1e-4 and p.strength == 1.0 and p.load == 1.0, "the oil palette's paint makes it oil, its own colour, not the watercolour's")
	await _play([{"op": "dip", "what": "oil", "index": 1}])
	check(p.colour.distance_to(lemon) < 1e-4, "a second oil colour replaces the first: oils mix on the palette's board, not in the paint")
	await _play([{"op": "dip", "what": "pan", "index": 5}])
	check(p.medium == Brushwork.Medium.WATER and p.colour.distance_to(blue) < 1e-4, "and a pan makes it watercolour again, clean of the oil")
	await _play([{"op": "take", "what": "stick"}])
	check(p.brush == Brushwork.Brush.STICK and p.medium == Brushwork.Medium.CHARCOAL, "the stick is charcoal")
	await _play([{"op": "dip", "what": "jar"}, {"op": "dip", "what": "pan", "index": 2}, {"op": "dip", "what": "oil", "index": 2}])
	check(p.medium == Brushwork.Medium.CHARCOAL and p.load == 1.0, "and stays charcoal whatever it is dipped in")
	await _play([{"op": "take", "what": "box"}, {"op": "set_down"}, {"op": "take", "what": "big"}])
	check(p.brush == Brushwork.Brush.BIG and p.palette == null and main.rig.right.tool == Hand.Tool.EASEL, "from the charcoal a hand takes a palette, sets it down and takes a brush")


## Every brush standing in the pot keeps its whole surface inside the pot's inner wall from the pot's foot to its rim,
## so none shows through the wall or its lip, sampled densely enough that a crossing of a millimetre shows.
func _no_brush_crosses_the_pot() -> void:
	const STEPS := 48
	var e: Easels.Easel = main.easels.easels.values()[-1]
	var inner := Easels.POT_SIZE.x - Easels.POT_WALL
	for kind: Brushwork.Brush in e.brushes:
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
## centimetres of a brush's handle takes that brush, never its neighbour or the charcoal.
func _each_brush_in_the_pot_is_taken_alone() -> void:
	const SLACK := 0.045
	var e: Easels.Easel = main.easels.easels.values()[-1]
	var p: EaselTool.Painter = main.easel_tool.painter(main.rig.right)
	var grips := {}
	for kind: Brushwork.Brush in e.brushes:
		grips[kind] = e.brushes[kind].global_transform * Easels.grip(kind)
		check((e.global_transform.affine_inverse() * grips[kind]).y > Easels.POT.y + Easels.POT_SIZE.y, "the %s is gripped above the pot's rim" % Brushwork.Brush.keys()[kind])
	grips[Brushwork.Brush.STICK] = e.stick.global_transform * Easels.grip(Brushwork.Brush.STICK)
	for kind: Brushwork.Brush in e.brushes:
		var offsets: Array[Vector3] = [Vector3.ZERO, Vector3.LEFT, Vector3.RIGHT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]
		for other: Brushwork.Brush in grips:
			if other != kind:
				check(grips[kind].distance_to(grips[other]) > SLACK * 2.0, "the %s's grip is %.3f m from the %s's" % [Brushwork.Brush.keys()[kind], grips[kind].distance_to(grips[other]), Brushwork.Brush.keys()[other]])
				offsets.append((grips[other] - grips[kind]).normalized())
		for o: Vector3 in offsets:
			p.brush = Brushwork.Brush.STICK if kind != Brushwork.Brush.STICK else Brushwork.Brush.BIG
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
			check(not _inside(part.get_aabb()).intersects(into * mi.get_aabb()), "%s on the tray stays clear of %s at %s %s" % [e.get_node("implements").get_path_to(mi), e.get_path_to(part), e.global_transform.affine_inverse() * part.global_position, part.get_aabb()])


## Setting an easel up builds no geometry: every mesh it shows is the one the easel before it shows, so a placement
## costs its nodes and its canvas, not a bake.
func _easels_share_their_geometry() -> void:
	var stands := Easels.new()
	main.add_child(stands)
	var meshes := []
	for id in 2:
		var e := stands.put(id, {"at": Vector3(id * 2.0, 0, 0), "yaw": 0.0, "strokes": [], "mix": PackedByteArray()})
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
			await _play([{"op": "take", "what": name, "hand": side}, {"op": "hold", "hand": side, "at": [-0.5 if side == "left" else 0.5, 1.0, 0.5]}])
			await frames(10)
			check(p.palette == e and p.kit == kit and node.global_transform.is_equal_approx(hand.global_transform * held), "the %s stays in the %s hand once the grip lets go" % [name, side])
			await _play([{"op": "hold", "hand": side, "at": [0.0, 1.1, 0.6]}])
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
		await _play([{"op": "take", "what": name, "hand": "left"}, {"op": "take", "what": "big", "hand": "left"}])
		await frames(int(EaselTool.RETURN * 60.0) + 1)
		check(left.palette == null and node.transform.is_equal_approx(rest) and left.brush == Brushwork.Brush.SMALL, "a grip at a brush while holding the %s sends it back and takes no brush" % name)
	await _play([{"op": "take", "what": "box", "hand": "left"}, {"op": "take", "what": "box", "hand": "right"}])
	var right: EaselTool.Painter = main.easel_tool.painter(main.rig.right)
	check(right.palette == null, "the box in one hand is not the other's to take")
	await _play([{"op": "take", "what": "palette", "hand": "right"}])
	check(right.kit == Brushwork.Medium.OIL and right.palette == e, "while the other hand takes the oil palette")
	await _play([{"op": "set_down", "hand": "left"}, {"op": "set_down", "hand": "right"}])
	await _play([{"op": "rests"}])


## Besides a grip anywhere, picking another tool from the wheel sends a held palette home and leaves that tool in the
## hand, and an easel taken away while its palette is held leaves the hand holding nothing of it.
func _every_way_out_lets_the_palette_go() -> void:
	var e: Easels.Easel = main.easels.easels.values()[-1]
	var p: EaselTool.Painter = main.easel_tool.painter(main.rig.left)
	var node: Node3D = e.palettes[Brushwork.Medium.OIL]
	await _play([{"op": "take", "what": "palette", "hand": "left"}, {"op": "pick", "hand": "left", "tool": "seeds"}, {"op": "rests"}])
	check(p.palette == null and main.rig.left.tool == Hand.Tool.SEEDS and not node.top_level and node.transform.is_equal_approx(Transform3D(Basis(), Easels.KITS[Brushwork.Medium.OIL])), "picking seeds from the wheel sends the palette home and holds seeds")
	await _play([{"op": "pick", "hand": "left", "tool": "easel"}, {"op": "take", "what": "palette", "hand": "left"}])
	var id := e.id
	var from: Vector3 = main.rig.head.global_position
	main.delete_tool.press(main.rig.right, from, e.canvas_frame().origin - from)
	main.delete_tool.let_go(main.rig.right)
	await frames(int(EaselTool.RETURN * 60.0) + 2)
	check(main.easels.find(id) == null and p.palette == null and main.easel_tool.returning.is_empty() and EaselTool.holding(p) != "oil palette", "an easel taken away while its palette is held leaves the hand holding none")
	await _play([{"op": "press", "button": "dpad_down"}])
	check(main.easels.find(id) != null, "and undo stands it back up")


class Lines:
	extends Logger
	var lines: PackedStringArray = []

	func _log_message(message: String, _error: bool) -> void:
		lines.append_array(message.split("\n", false))


## Each change in what a hand holds, and each grip that takes something, prints one line saying what it holds now: a
## brush, the charcoal or a palette taken, a palette set down, the sheet gripped and let go, and another tool picked
## and the easel tool picked back.
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
		await _play(t[2])
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
				await _play([{"op": "take", "what": "box" if kit == Brushwork.Medium.WATER else "palette", "hand": "left"}, {"op": "hold", "hand": "left", "at": [-0.5, 1.0, 0.5]}])
			for i in Brushwork.PIGMENTS.size():
				var w := Easels.well(kit, i)
				for spot: Vector3 in [Vector3.ZERO, Vector3(reach, 0.005, 0), Vector3(0, -0.03, -reach), Vector3(-0.008, -0.045, 0.008)]:
					tool._take_brush(p, Brushwork.Brush.BIG)
					var into: Vector3 = e.palettes[kit].global_transform * (w + spot)
					tip_at.call(into - along * 0.1)
					await frames(2)
					tip_at.call(into)
					await frames(2)
					var shown := p.tip.albedo_color
					check(p.medium == kit and p.colour.distance_to(Brushwork.absorbance(Brushwork.PIGMENTS[i])) < 1e-4 and p.load > 0.5, "a tip at %s in %s %d of a palette %s loads its colour" % [spot, EaselTool.PAINTS[kit], i, "in hand" if held else "on the tray"])
					check(shown.is_equal_approx(tool._paint_colour(p)), "the bristles show %s %d's colour" % [EaselTool.PAINTS[kit], i])
			if held:
				await _play([{"op": "set_down", "hand": "left"}])
	await _play([{"op": "brush", "points": [[0.3, 0.3, 0.8], [0.6, 0.32, 0.9]], "seconds": 0.2}])
	await _settled()
	var strokes: Array = world.state.easels[e.id].strokes
	check(not strokes.is_empty() and Vector3(strokes[-1].colour).distance_to(Brushwork.absorbance(Brushwork.PIGMENTS[-1])) < 1e-4 and strokes[-1].medium == Brushwork.Medium.OIL, "the stroke after paints in the last oil colour")


## Blue painted onto the oil palette's board and yellow painted over it and stirred make green there, which a clean
## brush touching it takes up and paints onto the canvas; each working of the board is a command undo takes back.
func _oil_mixes_by_painting_onto_the_board_and_picking_up_from_it() -> void:
	world.restore({"seq": 0, "cmds": []})
	await _settled()
	await _play([{"op": "place", "x": 0, "z": 6}, {"op": "easel", "x": 0, "z": 3}, {"op": "take", "what": "big"}, {"op": "dip", "what": "oil", "index": 5}])
	var e: Easels.Easel = main.easels.easels.values()[-1]
	var p: EaselTool.Painter = main.easel_tool.painter(main.rig.right)
	var spot := Vector2(0.0, 0.0)
	var colour := func() -> Color: return Brushwork.colour(Mixing.density_of(e.mixing.at(spot).ks))
	check(e.mixing.empty(), "a new easel's palette has a clean board")
	await _play([{"op": "mix", "points": [[-0.3, 0.0, 0.7], [0.1, 0.0, 0.7]], "seconds": 0.3}])
	var blue: Color = colour.call()
	check(e.mixing.at(spot).amount > 0.05 and blue.b > blue.g and blue.b > blue.r, "blue painted onto the board lies there: %s, %.2f" % [blue, e.mixing.at(spot).amount])
	check(p.load < 1.0 and p.load > 0.2, "and leaves the brush: %.2f left" % p.load)
	await _settled()
	var after_blue: PackedByteArray = _easel().mix
	check(after_blue == e.mixing.bytes, "the garden has the board as it was left")
	await _play([{"op": "dip", "what": "oil", "index": 1}, {"op": "mix", "points": [[0.1, -0.1, 0.7], [-0.1, 0.1, 0.8], [0.1, 0.1, 0.8], [-0.1, -0.1, 0.8], [0.0, 0.0, 0.8], [0.1, -0.1, 0.8], [-0.1, 0.1, 0.8]], "seconds": 1.5}])
	var green: Color = colour.call()
	check(green.g > green.r and green.g > green.b and green.g < 0.7, "yellow stirred into the blue makes green: %s" % green)
	await _play([{"op": "take", "what": "small"}])
	check(p.load == 0.0, "a fresh brush is clean")
	await _play([{"op": "mix", "points": [[0.0, 0.0, 0.6], [0.02, 0.0, 0.6]], "seconds": 0.3}])
	var tip := Brushwork.colour(p.colour)
	check(p.medium == Brushwork.Medium.OIL and p.load > 0.1 and tip.g > tip.r and tip.g > tip.b, "touching the green picks it up: %s, load %.2f" % [tip, p.load])
	await _play([{"op": "brush", "points": [[0.3, 0.3, 0.8], [0.4, 0.32, 0.8]], "seconds": 0.2}])
	await _settled()
	var strokes: Array = _easel().strokes
	check(strokes.size() == 1 and strokes[0].medium == Brushwork.Medium.OIL and Vector3(strokes[0].colour).distance_to(p.colour) < 0.2, "and paints with it on the canvas")
	var mixed: PackedByteArray = _easel().mix
	await _play([{"op": "press", "button": "dpad_down"}, {"op": "press", "button": "dpad_down"}])
	check(_easel().strokes.is_empty() and _easel().mix != mixed and e.mixing.bytes == _easel().mix, "undo takes the stroke off, then the pick-up's working of the board")
	await _play([{"op": "press", "button": "A"}, {"op": "press", "button": "A"}])
	check(_easel().mix == mixed and e.mixing.bytes == mixed and _easel().strokes.size() == 1, "and redo puts both back")
	var state := {"stairs": {}, "easels": {7: {"at": Vector3.ZERO, "yaw": 0.0, "strokes": [], "mix": PackedByteArray()}}, "walls": {}, "paths": {}, "grounds": {}, "groups": {}, "ponds": {}}
	check(not Commands.clean({"op": "mix", "easel": 7, "mix": mixed}, state, false).is_empty(), "a board as the palette holds it is a command")
	check(Commands.clean({"op": "mix", "easel": 7, "mix": mixed.slice(4)}, state, false).is_empty(), "a board of the wrong size is not")
	check(Commands.clean({"op": "mix", "easel": 8, "mix": mixed}, state, false).is_empty(), "nor one for an easel that is not there")


## Mixing on the board, without the game: paint trades both ways, the amounts hold, and the colours mix as pigments.
func _mixing_trades_paint_as_pigment() -> void:
	var m := Mixing.new()
	var blue := Mixing.ks_of(Brushwork.absorbance(Brushwork.PIGMENTS[5]))
	var white := Mixing.ks_of(Brushwork.absorbance(Brushwork.PIGMENTS[0]))
	var brush := {"ks": blue, "load": 1.0}
	for f in 60:
		brush = m.touch(brush, Vector2.ZERO, 0.02, 1.0 / 60.0)[0]
	var laid: float = m.at(Vector2.ZERO).amount
	check(laid > 0.2 and brush.load < 0.8 and brush.load > laid, "a full brush held on a clean board lays paint and keeps more than it laid: %.2f laid, %.2f kept" % [laid, brush.load])
	brush = {"ks": white, "load": 1.0}
	for f in 60:
		brush = m.touch(brush, Vector2.ZERO, 0.02, 1.0 / 60.0)[0]
	var tint := Brushwork.colour(Mixing.density_of(m.at(Vector2.ZERO).ks))
	var pure := Brushwork.PIGMENTS[5]
	check(tint.b > pure.b and tint.r > pure.r and tint.b > tint.r, "white worked into blue lightens it and keeps it blue: %s from %s" % [tint, pure])
	var back := PackedByteArray(m.bytes)
	var again := Mixing.new()
	again.load_bytes(back)
	check(again.bytes == m.bytes and absf(again.at(Vector2.ZERO).amount - m.at(Vector2.ZERO).amount) < 0.01, "the board loads back from what the garden keeps")
	check(not Mixing.open_at(Vector2(Easels.THUMB.x, Easels.THUMB.z)) and not Mixing.open_at(Easels.PALETTE_SIZE * 0.5) and Mixing.open_at(Vector2.ZERO), "paint lies on the open board, not over the thumb hole or off its edge")


## The trigger path a headset player uses: the easel tool taken from the wheel, the hand pointed at the ground, the
## trigger pressed; on either hand and either headset's controls. A press that sets none up says why.
func _the_trigger_sets_one_up_or_says_why_not() -> void:
	world.restore({"seq": 0, "cmds": []})
	await _settled()
	var why: Array[String] = []
	main.easel_tool.declined.connect(func(w: String) -> void: why.append(w))
	var press := func(hand: String, device: String, at: Array) -> void:
		why.clear()
		await _play([
			{"op": "pick", "tool": "easel", "hand": hand},
			{"op": "point", "tool": "easel", "hand": hand, "at": at},
			{"op": "press", "button": hand + "_trigger", "device": device},
		])
		await _settled()
	await _play([{"op": "place", "x": 0, "z": 6}, {"op": "wait", "seconds": 0.05}])
	for t in [["right", "quest", [-6, 0, 0]], ["left", "quest", [6, 0, 0]], ["right", "frame", [0, 0, -2]], ["left", "frame", [-3, 0, -6]]]:
		var before: int = world.state.easels.size()
		await press.call(t[0], t[1], t[2])
		check(world.state.easels.size() == before + 1 and why.is_empty(), "the %s trigger on the %s sets an easel up from the wheel: %d easels, %s" % [t[0], t[1], world.state.easels.size(), why])
	await press.call("right", "quest", [3, 0, 10])
	check(world.state.easels.size() == Easels.MAX and why.size() == 1 and why[0].contains("holds its"), "past the garden's easels a press sets none up and says so: %s" % [why])
	await _play([{"op": "press", "button": "dpad_down"}])
	await press.call("right", "quest", [-6.5, 0, 0.3])
	check(world.state.easels.size() == Easels.MAX - 1 and why.size() == 1 and why[0].contains("another easel"), "nor beside another easel: %s" % [why])
	await press.call("right", "quest", [0, 30, -10])
	check(why.size() == 1 and why[0].contains("no ground"), "nor at the sky: %s" % [why])
	var first: Vector3 = world.state.easels.values()[0].at
	await _play([{"op": "place", "x": first.x, "z": first.z + 1.0}, {"op": "wait", "seconds": 0.05}])
	await press.call("right", "quest", [first.x, 0, first.z - 8])
	check(world.state.easels.size() == Easels.MAX - 1 and why.size() == 1 and why[0].contains("of an easel"), "nor from a hand at an easel: %s" % [why])


func _easels_keep_their_distance_and_number() -> void:
	var state := World.blank()
	var at := Terrain.ground(10, 10)
	var cmd := {"op": "easel", "at": at, "yaw": 0.5}
	check(not Commands.clean(cmd, state, false).is_empty(), "an easel may stand on open ground")
	state.easels[1] = {"at": at, "yaw": 0.0, "strokes": []}
	check(Commands.clean(cmd, state, false).is_empty(), "but not on another")
	for i in Easels.MAX - 1:
		state.easels[i + 2] = {"at": Terrain.ground(-20 + i * 5, -20), "yaw": 0.0, "strokes": []}
	check(Commands.clean({"op": "easel", "at": Terrain.ground(20, 20), "yaw": 0.0}, state, false).is_empty(), "nor one more than a garden holds")
	check(Commands.clean({"op": "easel", "at": Terrain.ground(20, 20), "yaw": 0.0, "strokes": [{}]}, World.blank(), false).is_empty(), "a player's new easel brings no painting with it")


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
	check(not Commands.clean({"op": "paint", "easel": 4, "stroke": good}, state, false).is_empty(), "a good stroke paints a standing easel")
	check(Commands.clean({"op": "paint", "easel": 5, "stroke": good}, state, false).is_empty(), "but no easel that is not there")
	check(Commands.clean({"op": "sheet", "easel": 4, "strokes": [good]}, state, false).is_empty(), "a player's fresh sheet is blank")
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
	check(Commands.clean({"op": "paint", "easel": 4, "stroke": good}, state, false).is_empty(), "a full canvas takes no more")


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
		var node: Node3D = e.stick if kind == Brushwork.Brush.STICK else e.brushes[kind]
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
						p.brush = Brushwork.Brush.BIG if kind == Brushwork.Brush.STICK else Brushwork.Brush.STICK
						p.hand.global_transform = Transform3D(Basis.looking_at(-approach), at)
						main.easel_tool.grab(p)
						var hit := p.hand.tool == Hand.Tool.EASEL and p.palette == null and p.peel == null and p.brush == kind
						correct += int(hit)
						total += 1
		print("pick-rate: %s %d/90" % [Brushwork.Brush.keys()[kind], correct])
		hits += correct
	print("pick-rate: total %d/%d (%.2f%%)" % [hits, total, 100.0 * hits / total])
	check(hits >= 338, "aimed reaches take the intended implement at least 338/360 times")
	main.easel_tool._set_down(p)
	p.peel = null


func _preview_matches_the_grip() -> void:
	var e: Easels.Easel = main.easels.easels.values()[-1]
	var p: EaselTool.Painter = main.easel_tool.painter(main.rig.right)
	for kind: Brushwork.Brush in Brushwork.Brush.values():
		await _play([{"op": "take", "what": Brushwork.Brush.keys()[kind].to_lower(), "preview": true}])
		var node: Node3D = e.stick if kind == Brushwork.Brush.STICK else e.brushes[kind]
		check(main.easel_tool.highlighted.has(node), "the approached %s is highlighted before grip" % Brushwork.Brush.keys()[kind])
		for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
			check(mesh.material_overlay == main.easel_tool.highlight, "the preview visibly highlights its meshes")
		main.easel_tool.grab(p)
		check(p.brush == kind and p.palette == null, "grip takes the highlighted implement")
	p.hand.global_position += Vector3.UP * 2.0
	await _settled()
	check(main.easel_tool.highlighted.is_empty(), "moving away clears the highlight")


func _held_brush_stops_with_its_hand() -> void:
	var e: Easels.Easel = main.easels.easels.values()[0]
	var p: EaselTool.Painter = main.easel_tool.painter(main.rig.right)
	main.easel_tool._take_brush(p, Brushwork.Brush.BIG)
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
	await _play([{"op": "easel", "x": -3, "z": 0}, {"op": "easel", "x": 3, "z": 0}])
	var p: EaselTool.Painter = main.easel_tool.painter(main.rig.right)
	main.easel_tool._take_brush(p, Brushwork.Brush.STICK)
	var stands: Array = main.easels.easels.values()
	for e: Easels.Easel in stands:
		var frame := e.canvas_frame()
		p.hand.body.global_transform = Transform3D(frame.basis, frame * Vector3(0, 0, -0.01) - frame.basis * ToolModels.BRUSH_TIP)
		main.easel_tool._touch(p, e, 1.0 / 60.0)
	world.flush()
	check(world.state.easels[stands[0].id].strokes.size() == 1 and p.stroke.easel == stands[1], "crossing to another canvas commits the old stroke to its own canvas")
	main.easel_tool.end_stroke(p)
	world.flush()
	check(world.state.easels[stands[1].id].strokes.size() == 1, "the next canvas receives its own stroke command")
