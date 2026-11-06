extends "res://../tests/support/suite.gd"

## A session recorded on a loaded host replays as it was on an idle one. Metered as a game is, a pond fills, walls go
## up, trees and a stroke of flowers grow and a path wears the ground while threads spin beside the game and every
## command finds the worker pool held; the player teleports to the first wall's foot, ducks and then birds come, and the
## walls are laid again under them. Its replay, in a fresh game with nothing else running, holds every check of the
## player and the wildlife.

## How long the worker pool is held for each command, in microseconds.
const HOLD_US := 1000000
## Threads kept spinning beside the game's own.
const SPINNERS := 2

var _hogging := true
var _threads: Array[Thread] = []
var _holds := PackedInt32Array()


func _initialize() -> void:
	var folder := "user://replay-timing-%d" % OS.get_process_id()
	boot_main({"record-sessions": true, "session-directory": folder, "seed": 11, "garden": folder.path_join("garden.save")})
	Budget.frame_deadline = true
	await process_frame
	_spin()
	var world := main.world
	var log := main.metrics.play_log
	await play([{"op": "view", "eye": [0, 1.65, 6], "at": [0, 1.2, 0]}])
	# The meadow's own trees go, so the birds perch on what the session builds.
	await _order({"op": "wipe"})
	await _pond(-9, -7)
	await _order({"op": "wall", "walls": [wall_data({"points": PackedVector3Array([world.terrain.ground(-3, -1), world.terrain.ground(3, -1)]), "seed": 3})]})
	await play([{"op": "aim", "dir": [0, -0.25, -1], "seconds": 0.2, "settle": 0.0}])
	var steps: Array[Dictionary] = [
		{"op": "plant", "kind": "tree", "seed": 4, "at": world.terrain.ground(-6, 2)},
		{"op": "plant", "kind": "flowers", "seed": 8, "dabs": range(20).map(func(i: int) -> Array: return [world.terrain.ground(-4 + i * 0.4, 4), 1.5, 40])},
		{"op": "path", "points": PackedVector3Array([world.terrain.ground(-8, 8), world.terrain.ground(8, 8)]), "half_widths": PackedFloat32Array([0.8, 0.8]), "seed": 42, "surface": PathLayout.Surface.DIRT},
		{"op": "wall", "walls": [wall_data({"points": PackedVector3Array([world.terrain.ground(4, -6), world.terrain.ground(10, -6), world.terrain.ground(10, -1)]), "seed": 5})]},
		{"op": "plant", "kind": "tree", "seed": 9, "at": world.terrain.ground(6, 3)},
	]
	for s in steps:
		await _order(s)
		await frames(20)
	Engine.time_scale = 4.0
	await until(func() -> bool: return not main.wildlife.birds.birds.is_empty(), "birds come to the walls and trees")
	for i in 6:
		for w: Wall in main.tool.walls:
			await _order({"op": "reshape", "of": "walls", "id": w.id, "data": {"height": 2.0 + 0.3 * ((i + w.id) % 4)}})
		await frames(Replay.CHECK_EVERY)
	Engine.time_scale = 1.0
	_hogging = false
	for t in _threads:
		t.wait_to_finish()
	for t in _holds:
		WorkerThreadPool.wait_for_task_completion(t)
	await until(func() -> bool: return not main.world._keep_due, "the garden kept")
	await frames(Replay.CHECK_EVERY)
	log.finish()
	main.metrics.play_log = null
	main.world.play_log = null
	check(main.rig.global_position.z > -1.0 and main.rig.global_position.z < 0.0, "the player stands at the first wall's foot: %s" % main.rig.global_position)

	var chunk := folder.path_join(Array(DirAccess.get_files_at(folder)).filter(func(f: String) -> bool: return f.ends_with(".jsonl"))[0])
	var record := Replay.read(chunk)
	check(record.checks.size() > 20, "the record took %d checks" % record.checks.size())
	var out := ProjectSettings.globalize_path(folder.path_join("replayed"))
	var said := []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--fixed-fps", "64", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "../tests/support/replayed.gd", "--", "--replay", ProjectSettings.globalize_path(chunk), "--out", out, "--deadline"], said, true)
	check(code == 0 and FileAccess.file_exists(out), "the replay runs: exit %d\n%s" % [code, said[0].right(4000)])
	if FileAccess.file_exists(out):
		var f := FileAccess.open(out, FileAccess.READ)
		var replayed: Dictionary = f.get_var()
		f.close()
		check(replayed.diverged.is_empty(), "replayed with nothing else running, every check holds: %s" % [replayed.diverged])

	for name in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(name))
	DirAccess.remove_absolute(folder)
	DirAccess.remove_absolute(Main.player_path(PlayLog.SWITCH))
	main.queue_free()
	await process_frame
	finish()


## Sends `cmd` as this player's tools do, with every thread of the worker pool held for HOLD_US, and waits for the
## garden to take it.
func _order(cmd: Dictionary) -> void:
	for i in OS.get_processor_count():
		_holds.append(WorkerThreadPool.add_task(OS.delay_usec.bind(HOLD_US), true))
	var seq := main.world.seq
	main.world.submit(cmd)
	await until(func() -> bool: return main.world.seq == seq + 1, "the garden takes the %s" % cmd.op)


## Digs a hollow at `x`, `z` and fills it to its brim, as the commands a grip pressing the ground and the pond tool
## send: a Driver step's tools would also act on the game outside the record.
func _pond(x: float, z: float) -> void:
	var terrain := main.world.terrain
	var depth := GroundGrab.dig_depth(1.6)
	var cells := Terrain.cells_around(x, z, 2.8)
	terrain.set_hump(0, x, z, 2.8, -depth)
	var values := terrain.raised(cells, 0)
	terrain.clear_hump(0)
	await _order({"op": "heights", "cells": cells, "values": values})
	var at := terrain.ground(x, z)
	at.y = Water.brim(terrain, x, z, GroundGrab.reach(2.8, depth))
	var p := Water.deepest(Water.candidates(terrain, at), at.y)
	await _order({"op": "ponds", "put": {p.at: at.y}, "wet": p.cells.size()})


## Keeps SPINNERS threads busy until `_hogging` ends.
func _spin() -> void:
	for i in SPINNERS:
		var t := Thread.new()
		t.start(func() -> void:
			while _hogging:
				pass)
		_threads.append(t)
