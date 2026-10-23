extends "res://../tests/support/suite.gd"


func _initialize() -> void:
	boot_main()
	await process_frame
	var rig := main.rig
	var home := main.world.snapshot()
	var heights := Terrain.read(Terrain.ALL)
	for i in heights.size():
		heights[i] += 12.0
	var mountain := {"seq": 1, "cmds": [{"op": "heights", "cells": Terrain.ALL, "values": heights}]}
	# A tracked head can stand away from its play-space origin.
	rig.head.position += Vector3(0.8, 0, -0.4)
	rig.teleport(Vector3(0, -10, 4), 0.0)
	main.world.restore(mountain)
	_grounded(rig, "restoring a raised garden places the offset head over current ground")
	check(rig._pending == null, "a pending teleport cannot carry a destination from the previous garden")
	rig.place(Vector3(0, -100, 4), 0.0)
	_grounded(rig, "a below-world placement recovers to current ground")
	rig.teleport(Vector3(0, -20, 4), 0.0)
	rig._fade_step(Rig.FADE)
	_grounded(rig, "teleport placement resamples a stale ground target")
	var g := Terrain.ground(0, 4)
	rig.place(g, 8.0)
	check(absf(rig.global_position.y - g.y - 8.0) < 0.01, "intentional floating is preserved")
	rig.respawn()
	_grounded(rig, "respawn returns from the air to current ground")
	main.world.restore(home)
	_grounded(rig, "returning home samples its lower terrain")
	_spawns_on_open_ground()
	await _a_swap_happens_in_the_dark()
	finish()


## A build standing at the spawn point sends the player to the nearest open ground; with nowhere open, onto its top.
func _spawns_on_open_ground() -> void:
	var rig := Rig.new()
	root.add_child(rig)
	var house := Rect2(-3, 1, 6, 6)
	rig.solid_hit = func(origin: Vector3, _dir: Vector3, _reach: float) -> Dictionary:
		return {"point": Vector3(origin.x, 7.0, origin.z), "side": false} if house.has_point(Vector2(origin.x, origin.z)) else {}
	rig.respawn()
	var h := rig.head.global_position
	var g := Vector2(h.x, h.z)
	check(not house.has_point(g) and g.distance_to(Rig.SPAWN) <= 2.0 * Rig.SPAWN_STEP + 0.01 and absf(rig.global_position.y - Terrain.height_at(h.x, h.z)) < 0.01, "a house at the spawn sends the player to open ground beside it: %s" % g)
	rig.solid_hit = func(origin: Vector3, _dir: Vector3, _reach: float) -> Dictionary: return {"point": origin, "side": false}
	rig.floor_under = func(p: Vector3) -> float: return Terrain.height_at(p.x, p.z) + 7.0
	rig.respawn()
	h = rig.head.global_position
	check(Vector2(h.x, h.z).distance_to(Rig.SPAWN) < 0.01 and absf(rig.global_position.y - Terrain.height_at(h.x, h.z) - 7.0) < 0.01, "with nowhere open the player stands on the top at the spawn")
	rig.free()


## Visiting or coming home goes dark before the garden changes, holds dark while it rebuilds, and fades in after.
func _a_swap_happens_in_the_dark() -> void:
	var rig := main.rig
	var world := main.world
	for frame in 30:
		await process_frame
	var before := world.seq
	var seen := []
	world.loaded.connect(func() -> void: seen.append(rig._fade.visible and rig._fade_mat.albedo_color.a == 1.0), CONNECT_ONE_SHOT)
	world.swap({"seq": before + 5, "cmds": []})
	check(world.seq == before, "the garden waits for the dark")
	for frame in 30:
		await process_frame
		if not seen.is_empty():
			break
	check(seen == [true] and world.seq == before + 5, "the garden swaps under a black view: %s" % [seen])
	for frame in 30:
		await process_frame
	check(not rig._fade.visible, "the view fades in again")
	before = world.seq
	world.swap({"seq": before + 1, "cmds": []})
	world.swap({"seq": before + 2, "cmds": []})
	for frame in 60:
		await process_frame
	check(world.seq == before + 2 and not rig._fade.visible and world._queue.is_empty(), "two swaps in a row each go dark and the second lands: seq %d of %d" % [world.seq, before + 2])


func _grounded(rig: Rig, what: String) -> void:
	var h := rig.head.global_position
	check(absf(rig.global_position.y - Terrain.height_at(h.x, h.z)) < 0.01 and Vector2(h.x, h.z).distance_to(Vector2(0, 4)) < 0.01, what)
