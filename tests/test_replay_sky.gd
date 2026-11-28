extends "res://../tests/support/suite.gd"

const Replayed := preload("res://../tests/support/replayed.gd")


func _initialize() -> void:
	var folder := "user://replay-sky-%d" % OS.get_process_id()
	boot_main({"record-sessions": true, "session-directory": folder, "garden": folder.path_join("gardens")})
	await process_frame
	var log := main.metrics.play_log
	var world := main.world
	var after := Replayed.after_keep(main)
	var at_command := {}
	world.applied.connect(func(cmd: Dictionary) -> void:
		if cmd.get("seq") == world.seq:
			at_command[world.seq] = Replay.garden(world))
	world.submit({"op": "sky", "time": 0.5, "pace": SkyTool.FASTEST})
	await until(func() -> bool: return world.seq == 1 and not world._record_due, "the sky set running and kept")
	world.submit({"op": "plant", "kind": "tree", "seed": 7, "at": world.terrain.ground(3, -2)})
	after.act = func() -> void: world.submit({"op": "plant", "kind": "tree", "seed": 8, "at": world.terrain.ground(-3, -2)})
	await until(func() -> bool: return world.seq == 3, "a tree planted, and another in the frame its garden is kept")
	await frames(5)
	world.flush()
	world.submit({"op": "plant", "kind": "tree", "seed": 9, "at": world.terrain.ground(0, -5)})
	await until(func() -> bool: return world.seq == 4 and not world._record_due, "the garden kept between frames, and a tree planted after it")
	await frames(Replay.CHECK_EVERY)
	log.finish()
	main.metrics.play_log = null
	world.play_log = null

	var chunk := folder.path_join(Array(DirAccess.get_files_at(folder)).filter(func(f: String) -> bool: return f.ends_with(".jsonl"))[0])
	var avatars := ProjectSettings.globalize_path(folder.path_join("avatars"))
	var record := Replay.read(chunk, avatars)
	var kept := {}
	for c: Dictionary in record.checks:
		if c.has("garden"):
			kept[int(c.seq)] = c
	var ordered := {}
	for i in record.messages.size():
		var m: Array = record.messages[i]
		if m[3] == "ordered":
			ordered[int(m[4][0].seq)] = {"frame": m[0], "index": i}
	check(kept.has(2) and kept[2].garden != at_command.get(2),
		"the first tree's garden was kept after the running sky had moved on from where it stood at the command: %s against %s" % [kept.get(2), at_command.get(2)])
	for pair in [[2, 3], [3, 4]]:
		check(kept.has(pair[0]) and ordered.has(pair[1]) and ordered[pair[1]].frame == kept[pair[0]].frame and ordered[pair[1]].index >= kept[pair[0]].heard,
			"command %d was ordered after the garden at %d was kept, in the same frame: %s, %s" % [pair[1], pair[0], kept.get(pair[0]), ordered.get(pair[1])])
	var replayed := Replayed.replay(self, chunk, avatars)
	if not replayed.is_empty():
		check(replayed.diverged.is_empty(), "replayed, every garden holds, each compared where it was kept: %s" % [replayed.diverged])

	var exact := {}
	for c: Dictionary in record.checks:
		if c.has("garden") and c.turn and (c.heard == record.messages.size() or record.messages[c.heard][0] > c.frame):
			exact["%d %d" % [c.frame, c.seq]] = c
	check(exact.values().any(func(c: Dictionary) -> bool: return c.heard > 0 and record.messages[c.heard - 1][0] == c.frame),
		"such a garden is kept after a message of its own frame: %s" % [exact])
	check(exact.values().any(func(c: Dictionary) -> bool: return c.heard < record.messages.size()),
		"such a garden is kept before a message of a later frame: %s" % [exact])
	var earlier := Replayed.copy(chunk, "earlier", func(e: Dictionary) -> Dictionary:
		if e.event == "checks":
			for c: Dictionary in e.checks:
				if exact.has("%d %d" % [c.frame, c.get("seq", -1)]) and c.has("garden"):
					c.erase("heard")
					c.erase("turn")
		return e)
	var read_earlier := Replay.read(earlier, avatars)
	var placed: Array = read_earlier.get("checks", []).filter(func(c: Dictionary) -> bool:
		var was: Dictionary = exact.get("%d %d" % [c.frame, c.get("seq", -1)], {})
		return not was.is_empty() and c.get("heard") == was.heard and c.get("turn") == was.turn)
	check(exact.values().any(func(c: Dictionary) -> bool: return int(c.seq) == 4) and placed.size() == exact.size(),
		"a record that keeps its gardens without where each was kept reads each with no message after it in its frame, the garden of the tree planted after the keep between frames among them, as kept there: %s of %s" % [placed.size(), exact.keys()])
	replayed = Replayed.replay(self, earlier, avatars)
	if not replayed.is_empty():
		check(replayed.diverged.is_empty(), "replayed, such a record's gardens hold: %s" % [replayed.diverged])

	var changed := Replayed.copy(chunk, "changed", func(e: Dictionary) -> Dictionary:
		if e.event == "checks":
			for c: Dictionary in e.checks:
				if c.get("seq") == 3.0 and c.has("garden"):
					c.garden = "0000000000000000"
		return e)
	replayed = Replayed.replay(self, changed, avatars)
	if not replayed.is_empty():
		var d: Dictionary = replayed.diverged.get("garden", {})
		check(d.get("frame") == kept[3].frame and d.get("commands") == ["3 plant"] and not "stood" in d.get("said", ""),
			"a kept garden that differs is named, with the command since the last that held: %s" % [d])
	var renumbered := Replayed.copy(chunk, "renumbered", func(e: Dictionary) -> Dictionary:
		if e.event == "checks":
			for c: Dictionary in e.checks:
				if c.get("seq") == 2.0 and c.has("garden"):
					c.seq = 3
		return e)
	replayed = Replayed.replay(self, renumbered, avatars)
	if not replayed.is_empty():
		var d: Dictionary = replayed.diverged.get("garden", {})
		check(d.get("frame") == kept[2].frame and "stood at command 2, not 3" in d.get("said", ""),
			"a garden kept at another command than the replay stands at says which: %s" % [d])

	for sub in ["earlier", "changed", "renumbered", "avatars", ""]:
		for name in DirAccess.get_files_at(folder.path_join(sub)):
			DirAccess.remove_absolute(folder.path_join(sub).path_join(name))
		DirAccess.remove_absolute(folder.path_join(sub))
	DirAccess.remove_absolute(Main.player_path(PlayLog.SWITCH))
	main.queue_free()
	await process_frame
	finish()
