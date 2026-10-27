extends "res://../tests/support/suite.gd"

## A scripted session's record holds every frame's input as the game read it, and what the session started from.


class Probe:
	extends Node
	var main: Main
	var deltas: Array[float] = []
	var heads: Array[Transform3D] = []
	var triggers: Array[bool] = []
	var sticks: Array[Vector2] = []
	var hands: Array[Vector3] = []

	func _process(delta: float) -> void:
		deltas.append(delta)
		heads.append(main.rig.head.transform)
		triggers.append(Buttons.down(main.rig.left, "trigger_click"))
		sticks.append(main.rig.left.stick())
		hands.append_array([main.rig.left.controller.origin, main.rig.right.controller.origin])


func _initialize() -> void:
	boot_main()
	await process_frame
	main.world.restore({"seq": 0, "cmds": [{"op": "plant", "kind": "tree", "seed": 1, "at": main.world.terrain.ground(2, 2), "id": 5, "seq": 0, "by": 1}]})
	var folder := "user://replay-%d" % OS.get_process_id()
	var started := main.world.snapshot()
	main.record(PlayLog.new(folder))
	var probe := Probe.new()
	probe.main = main
	probe.process_priority = 1
	main.add_child(probe)
	await play([
		{"op": "view", "eye": [0, 1.65, 6], "at": [0, 1.2, 0]},
		{"op": "hands", "left": [-0.25, -0.35, -0.35], "right": [0.25, -0.3, -0.4]},
		{"op": "press", "button": "left_trigger", "seconds": 0.5},
		{"op": "aim", "dir": [0, -0.3, -1], "seconds": 0.5},
		{"op": "view", "eye": [3, 1.65, 4], "at": [0, 1.2, 0]},
	])
	var log := main.metrics.play_log
	var writes := [0, 0]
	await until(func() -> bool:
		if log._frames != writes[1]:
			writes[0] += 1
			writes[1] = log._frames
		return writes[0] >= 3, "three of the session's seconds written")
	await process_frame
	log.finish()
	main.metrics.play_log = null
	probe.queue_free()

	var events := []
	for name in DirAccess.get_files_at(folder):
		if name.ends_with(".jsonl"):
			for line in FileAccess.get_file_as_string(folder.path_join(name)).strip_edges().split("\n"):
				events.append(JSON.parse_string(line))
	var start: Dictionary = events.filter(func(e) -> bool: return e.event == "start")[0]
	check(start.revision == Main.revision() and start.input == JSON.parse_string(JSON.stringify(Replay.layout())), "the record carries its build revision and its frame layout")
	var replay: Array = events.filter(func(e) -> bool: return e.event == "replay")
	check(replay.size() == 1, "the session's seeds and starting garden are written once")
	check(replay[0].seeds == {"rng": str(main.rng_seed), "wildlife": str(main.wildlife.rng.seed)}, "with the seeds the session drew from")
	var save: Variant = bytes_to_var(Marshalls.base64_to_raw(replay[0].save).decompress(int(replay[0].save_bytes), FileAccess.COMPRESSION_DEFLATE))
	check(save == started and save.cmds.size() == 1, "and the garden it started in")

	var inputs: Array = events.filter(func(e) -> bool: return e.event == "input")
	inputs.sort_custom(func(a, b) -> bool: return a.first < b.first)
	check(inputs.size() > 2, "input is written as the session goes, not only at its end")
	var raw := PackedByteArray()
	for e in inputs:
		check(int(e.first) * Replay.FRAME_BYTES == raw.size(), "input events follow on from each other")
		var block := Replay.frames(e)
		check(block.size() == int(e.frames) * Replay.FRAME_BYTES, "an input event holds the frames it counts")
		raw.append_array(block)
	var n := raw.size() / Replay.FRAME_BYTES
	check(n == probe.deltas.size() and n > 120, "every frame of the session is recorded: %d of %d" % [n, probe.deltas.size()])
	var mismatched := 0
	var pressed := 0
	var pushed := 0
	for i in mini(n, probe.deltas.size()):
		var f := Replay.unpack(raw, i)
		var left: Dictionary = f.hands[0]
		var right: Dictionary = f.hands[1]
		if left.pose.origin != probe.hands[2 * i] or right.pose.origin != probe.hands[2 * i + 1] or f.delta != probe.deltas[i] or f.head != probe.heads[i] \
				or left.held.trigger_click != probe.triggers[i] or left.stick != probe.sticks[i]:
			mismatched += 1
		pressed += int(left.held.trigger_click)
		pushed += int(left.stick.y > 0.5)
	check(mismatched == 0, "each frame holds its delta, head and hand poses, stick and buttons as the game read them: %d differ" % mismatched)
	check(pressed > 0 and pushed > 0, "the script's trigger press and teleport aim are in the record")
	var ends := events.filter(func(e) -> bool: return e.event == "end")
	check(ends.size() == 1, "the session ends its record")
	var out := []
	var code := OS.execute("python3", [ProjectSettings.globalize_path("res://../scripts/sessions.py"), ProjectSettings.globalize_path(folder), "--json"], out, true)
	var read: Variant = JSON.parse_string(out[0]) if code == 0 else null
	check(read is Array and read.size() == 1 and int(read[0].replay.frames) == n and int(read[0].replay.missing) == 0 and read[0].replay.start,
		"scripts/sessions.py reads the record back whole: %s" % [out])

	for name in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(name))
	DirAccess.remove_absolute(folder)
	main.queue_free()
	await process_frame
	finish()
