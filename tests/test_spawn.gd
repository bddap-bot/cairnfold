extends SceneTree

var failures := 0


func _initialize() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate() as Main
	root.add_child(main)
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
	_check(rig._pending == null, "a pending teleport cannot carry a destination from the previous garden")
	rig.place(Vector3(0, -100, 4), 0.0)
	_grounded(rig, "a below-world placement recovers to current ground")
	rig.teleport(Vector3(0, -20, 4), 0.0)
	rig._fade_step(Rig.FADE)
	_grounded(rig, "teleport placement resamples a stale ground target")
	var g := Terrain.ground(0, 4)
	rig.place(g, 8.0)
	_check(absf(rig.global_position.y - g.y - 8.0) < 0.01, "intentional floating is preserved")
	rig.respawn()
	_grounded(rig, "respawn returns from the air to current ground")
	main.world.restore(home)
	_grounded(rig, "returning home samples its lower terrain")
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _grounded(rig: Rig, what: String) -> void:
	var h := rig.head.global_position
	_check(absf(rig.global_position.y - Terrain.height_at(h.x, h.z)) < 0.01 and Vector2(h.x, h.z).distance_to(Vector2(0, 4)) < 0.01, what)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)
