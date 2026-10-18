extends SceneTree

## Headless checks of easels: strokes painted through the brush are build commands, kept with the garden and loaded
## back whole, taken back and put back by undo and redo, cleared by a fresh sheet, carried by a deleted easel's undo,
## and checked like every command: godot4 --headless --path game --script ../tests/test_easel.gd

var failures := 0
var main: Node
var world: World
var dir := ""


func _initialize() -> void:
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	await process_frame
	world = main.world
	dir = OS.get_temp_dir().path_join("nestcombe-easel-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(dir)
	_samples_keep_what_the_brush_did()
	_a_stroke_lays_the_same_dabs_every_time()
	await _strokes_are_kept_and_load_whole()
	await _undo_takes_back_a_stroke_and_redo_paints_it_again()
	await _a_fresh_sheet_clears_and_undo_brings_the_painting_back()
	await _a_deleted_easel_comes_back_with_its_painting()
	await _the_tray_loads_the_brush()
	await _the_trigger_sets_one_up_or_says_why_not()
	_easels_keep_their_distance_and_number()
	_bad_strokes_are_dropped()
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


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
		{"op": "dip", "what": "well", "index": 5},
		{"op": "brush", "points": [[0.1, 0.2, 0.8], [0.9, 0.22, 0.9]], "seconds": 0.3},
		{"op": "take", "what": "palette", "hand": "left"},
		{"op": "hold", "hand": "left", "at": [-0.9, 1.0, 0.4]},
		{"op": "take", "what": "flat"},
		{"op": "dip", "what": "tin"},
		{"op": "dip", "what": "well", "index": 1},
		{"op": "brush", "roll": 90, "points": [[0.1, 0.6, 1.0], [0.5, 0.65, 0.7], [0.9, 0.6, 1.0]], "seconds": 0.3},
		{"op": "let_go", "hand": "left"},
		{"op": "take", "what": "stick"},
		{"op": "brush", "points": [[0.2, 0.8, 0.3], [0.8, 0.85, 0.9]], "seconds": 0.3},
		{"op": "wait", "seconds": 0.1},
	])


func _samples_keep_what_the_brush_did() -> void:
	var s := Brushwork.pack(Vector2(0.25, 0.75), 0.5, PI * 0.5, 7)
	var back := Brushwork.unpack(s, 0)
	_check(back[0].distance_to(Vector2(0.25, 0.75)) < 1e-4 and absf(back[1] - 0.5) < 0.01 and absf(back[2] - PI * 0.5) < 0.02 and back[3] == 7, "a sample keeps where, how hard, which way and when: %s" % [back])


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
	_check(once == lay.call() and once.size() > 5 * Brushwork.DAB, "a stroke's samples lay the same dabs every time: %d" % (once.size() / Brushwork.DAB))
	var s := Brushwork.Stroker.new(stroke)
	for i in 5:
		s.add(Brushwork.unpack(samples, i))
	_check(s.left() < 1.0 and s.left() > 0.0, "and spend some of the paint on the brush: %.3f left" % s.left())


func _strokes_are_kept_and_load_whole() -> void:
	var path := dir.path_join("garden.save")
	world.load_from(path)
	await _paint_some()
	await _settled()
	var e := _easel()
	var media: Array = e.strokes.map(func(s: Dictionary) -> int: return s.medium)
	_check(media == [Brushwork.Medium.WATER, Brushwork.Medium.OIL, Brushwork.Medium.CHARCOAL], "a watercolour, an oil and a charcoal stroke are on the canvas: %s" % [media])
	_check(e.strokes.all(func(s: Dictionary) -> bool: return Brushwork.count(s) >= 2), "each stroke kept its samples")
	_check(main.easels.easels.size() == 1 and main.easels.easels.values()[0].canvas.ticks > 0, "the easel stands and its canvas has run")
	var picture := var_to_str(world.digest())
	world.restore({"seq": 0, "cmds": []})
	await _settled()
	_check(world.state.easels.is_empty() and main.easels.easels.is_empty(), "an empty garden holds no easel")
	world.load_from(path)
	_check(var_to_str(world.digest()) == picture, "loading puts the easel back where it stood with every stroke as painted")
	_check(main.easels.easels.size() == 1 and main.easels.easels.values()[0].canvas.catching_up(), "and replays its painting")


func _undo_takes_back_a_stroke_and_redo_paints_it_again() -> void:
	await _play([{"op": "take", "what": "big"}, {"op": "dip", "what": "jar"}, {"op": "dip", "what": "well", "index": 4}, {"op": "brush", "points": [[0.3, 0.4, 0.9], [0.6, 0.45, 0.9]], "seconds": 0.2}])
	var before: Array = _easel().strokes.duplicate()
	_check(before.size() == 4, "a loaded painting takes more strokes: %d" % before.size())
	await _play([{"op": "press", "button": "dpad_down"}])
	_check(_easel().strokes == before.slice(0, before.size() - 1), "undo takes the last stroke off the canvas")
	await _play([{"op": "press", "button": "A"}])
	_check(_easel().strokes == before, "redo paints it again")


func _a_fresh_sheet_clears_and_undo_brings_the_painting_back() -> void:
	var before: Array = _easel().strokes.duplicate()
	await _play([{"op": "sheet", "pull": 0.1}])
	_check(_easel().strokes == before, "a sheet pulled a little and let go stays on")
	await _play([{"op": "sheet", "pull": 0.45}])
	_check(_easel().strokes.is_empty(), "a sheet pulled well off tears away, leaving a fresh one")
	await _play([{"op": "press", "button": "dpad_down"}])
	_check(_easel().strokes == before, "undo puts the painting back")


func _a_deleted_easel_comes_back_with_its_painting() -> void:
	var id: int = world.state.easels.keys()[-1]
	var before: Array = _easel().strokes.duplicate()
	var e: Easels.Easel = main.easels.find(id)
	var from: Vector3 = main.rig.head.global_position
	main.delete_tool.press(main.rig.right, from, e.canvas_frame().origin - from)
	main.delete_tool.let_go(main.rig.right)
	await _frames(2)
	_check(world.state.easels.is_empty() and main.easels.easels.is_empty(), "the delete tool's beam takes an easel away")
	await _play([{"op": "press", "button": "dpad_down"}])
	_check(world.state.easels.has(id) and world.state.easels[id].strokes == before and main.easels.find(id) != null, "undo stands it back up with its painting")


func _the_tray_loads_the_brush() -> void:
	await _play([{"op": "take", "what": "small"}, {"op": "dip", "what": "jar"}, {"op": "dip", "what": "well", "index": 5}, {"op": "dip", "what": "well", "index": 1}])
	var p: EaselTool.Painter = main.easel_tool.painter(main.rig.right)
	var blue := Brushwork.absorbance(Brushwork.PIGMENTS[5])
	var lemon := Brushwork.absorbance(Brushwork.PIGMENTS[1])
	_check(p.brush == Brushwork.Brush.SMALL and p.medium == Brushwork.Medium.WATER and main.rig.right.tool == Hand.Tool.EASEL, "a grip at the pot takes a brush; the jar makes it watercolour")
	_check(p.colour.distance_to((blue + lemon) * 0.5) < 1e-3, "two wells mix on the brush")
	await _play([{"op": "dip", "what": "tin"}])
	_check(p.medium == Brushwork.Medium.OIL, "the tin makes it oil")
	await _play([{"op": "take", "what": "stick"}])
	_check(p.brush == Brushwork.Brush.STICK and p.medium == Brushwork.Medium.CHARCOAL, "the stick is charcoal")


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
		_check(world.state.easels.size() == before + 1 and why.is_empty(), "the %s trigger on the %s sets an easel up from the wheel: %d easels, %s" % [t[0], t[1], world.state.easels.size(), why])
	await press.call("right", "quest", [3, 0, 10])
	_check(world.state.easels.size() == Easels.MAX and why.size() == 1 and why[0].contains("holds its"), "past the garden's easels a press sets none up and says so: %s" % [why])
	await _play([{"op": "press", "button": "dpad_down"}])
	await press.call("right", "quest", [-6.5, 0, 0.3])
	_check(world.state.easels.size() == Easels.MAX - 1 and why.size() == 1 and why[0].contains("another easel"), "nor beside another easel: %s" % [why])
	await press.call("right", "quest", [0, 30, -10])
	_check(why.size() == 1 and why[0].contains("no ground"), "nor at the sky: %s" % [why])
	var first: Vector3 = world.state.easels.values()[0].at
	await _play([{"op": "place", "x": first.x, "z": first.z + 1.0}, {"op": "wait", "seconds": 0.05}])
	await press.call("right", "quest", [first.x, 0, first.z - 8])
	_check(world.state.easels.size() == Easels.MAX - 1 and why.size() == 1 and why[0].contains("of an easel"), "nor from a hand at an easel: %s" % [why])


func _frames(n: int) -> void:
	for f in n:
		await process_frame


func _easels_keep_their_distance_and_number() -> void:
	var state := {"easels": {}, "walls": {}, "paths": {}, "grounds": {}, "groups": {}, "seeds": []}
	var at := Terrain.ground(10, 10)
	var cmd := {"op": "easel", "at": at, "yaw": 0.5}
	_check(not Commands.clean(cmd, state, false).is_empty(), "an easel may stand on open ground")
	state.easels[1] = {"at": at, "yaw": 0.0, "strokes": []}
	_check(Commands.clean(cmd, state, false).is_empty(), "but not on another")
	for i in Easels.MAX - 1:
		state.easels[i + 2] = {"at": Terrain.ground(-20 + i * 5, -20), "yaw": 0.0, "strokes": []}
	_check(Commands.clean({"op": "easel", "at": Terrain.ground(20, 20), "yaw": 0.0}, state, false).is_empty(), "nor one more than a garden holds")
	_check(Commands.clean({"op": "easel", "at": Terrain.ground(20, 20), "yaw": 0.0, "strokes": [{}]}, {"easels": {}, "walls": {}, "paths": {}, "grounds": {}, "groups": {}, "seeds": []}, false).is_empty(), "a player's new easel brings no painting with it")


func _bad_strokes_are_dropped() -> void:
	var good := {"medium": Brushwork.Medium.OIL, "brush": Brushwork.Brush.FLAT, "colour": Vector3(1, 2, 3), "strength": 1.0, "load": 0.5, "gap": 3, "samples": Brushwork.pack(Vector2(0.5, 0.5), 0.5, 0.0, 0) + Brushwork.pack(Vector2(0.6, 0.5), 0.5, 0.0, 2)}
	_check(Brushwork.clean(good) != null, "a stroke a brush could paint is kept")
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
		_check(Brushwork.clean(s) == null, "a stroke with %s is dropped" % what)
	var state := {"easels": {4: {"at": Vector3.ZERO, "yaw": 0.0, "strokes": []}}}
	_check(not Commands.clean({"op": "paint", "easel": 4, "stroke": good}, state, false).is_empty(), "a good stroke paints a standing easel")
	_check(Commands.clean({"op": "paint", "easel": 5, "stroke": good}, state, false).is_empty(), "but no easel that is not there")
	_check(Commands.clean({"op": "sheet", "easel": 4, "strokes": [good]}, state, false).is_empty(), "a player's fresh sheet is blank")
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
	_check(Commands.clean({"op": "paint", "easel": 4, "stroke": good}, state, false).is_empty(), "a full canvas takes no more")


func _many(n: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in n:
		out.append_array(Brushwork.pack(Vector2(0.5, 0.5), 0.5, 0.0, 1))
	return out
