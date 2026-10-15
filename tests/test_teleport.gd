extends SceneTree

## Headless checks of the teleport ray: godot4 --headless --path game --script ../tests/test_teleport.gd

var failures := 0


func _initialize() -> void:
	var rig := Rig.new()
	root.add_child(rig)
	_ground_target(rig)
	_air_target(rig)
	_air_reach_stops_at_nearer_ground(rig)
	_no_teleport_tool()
	_finish.call_deferred(rig)


func _finish(rig: Rig) -> void:
	await _stick_teleports_with_every_tool(rig)
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	quit(1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _pose(origin: Vector3, dir: Vector3) -> Transform3D:
	return Transform3D(Basis.looking_at(dir, Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.BACK), origin)


func _ground_target(rig: Rig) -> void:
	var o := Vector3(0, Terrain.height_at(0, 0) + 1.5, 0)
	rig.aim(_pose(o, Vector3(0, -0.3, -1)))
	_check(rig.aim_ground != null, "a ray down at the meadow finds ground")
	if rig.aim_ground == null:
		return
	var g: Vector3 = rig.aim_ground
	_check(absf(g.y - Terrain.height_at(g.x, g.z)) < 0.05, "the ground target sits on the terrain")
	_check(rig.aim_lift < 0.15, "a ground target has no lift")
	_check(absf(Vector2(g.x, g.z).length() - 1.5 / 0.3) < 1.5, "the ray is straight, not an arc")


func _air_target(rig: Rig) -> void:
	rig.air_reach = 12.0
	var o := Vector3(0, Terrain.height_at(0, 0) + 1.5, 0)
	var dir := Vector3(0, 1, -1).normalized()
	rig.aim(_pose(o, dir))
	_check(rig.aim_ground != null, "a ray into the sky targets the air")
	if rig.aim_ground == null:
		return
	var target: Vector3 = rig.aim_ground + Vector3.UP * rig.aim_lift
	_check(target.distance_to(o + dir * 12.0) < 0.01, "the air target is on the ray at the air reach")
	_check(rig.aim_lift > 8.0, "an air target lifts the landing above the ground")
	rig.place(rig.aim_ground, rig.aim_lift)
	_check(rig.floating, "arriving at an air target floats")


func _air_reach_stops_at_nearer_ground(rig: Rig) -> void:
	rig.air_reach = 40.0
	var o := Vector3(0, Terrain.height_at(0, -50) + 0.3, -50)
	var dir := Vector3(0, 0.05, -1).normalized()
	var hill: Variant = Terrain.raycast(o, dir, 40.0)
	_check(hill != null, "the rim's slope rises across a shallow ray")
	if hill == null:
		return
	rig.aim(_pose(o, dir))
	_check(rig.aim_lift < 0.15 and rig.aim_ground.distance_to(hill) < 0.1, "a rising ray that meets a hillside within reach lands on it")


func _no_teleport_tool() -> void:
	_check(not Hand.Tool.has("TELEPORT"), "teleport is not a tool")
	_check(Hand.MENU.size() == Hand.Tool.size(), "the ring holds every tool and nothing else")


## Through real frames, as a player: the rig's own _process reads the stick.
func _stick_teleports_with_every_tool(rig: Rig) -> void:
	for t in Hand.Tool.values():
		rig.left.tool = t
		rig.right.tool = t
		rig.place(Vector3(0, Terrain.height_at(0, 0), 0), 0.0)
		await process_frame
		var from := rig.head.global_position
		rig.left.global_transform = Transform3D(Basis.looking_at(Vector3(0, -0.3, -1), Vector3.UP), from + Vector3(-0.2, -0.4, -0.3))
		Hand.injected_sticks[rig.left.tracker] = Vector2(0, 1)
		await process_frame
		await process_frame
		var aimed: bool = rig.aim_hand == rig.left and rig.aim_ground != null
		Hand.injected_sticks[rig.left.tracker] = Vector2.ZERO
		for f in 30:
			await process_frame
		var moved := Vector2(rig.head.global_position.x - from.x, rig.head.global_position.z - from.z).length()
		_check(aimed and moved > 2.0, "left stick forward aims and goes holding %s (moved %.1f m)" % [Hand.Tool.keys()[t], moved])
	Hand.injected_sticks.erase(rig.left.tracker)
