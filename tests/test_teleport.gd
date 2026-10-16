extends SceneTree

## Headless checks of the teleport ray: godot4 --headless --path game --script ../tests/test_teleport.gd

var failures := 0


func _initialize() -> void:
	var rig := Rig.new()
	root.add_child(rig)
	_ground_target(rig)
	_air_target(rig)
	_air_reach_stops_at_nearer_ground(rig)
	_stick_deflection_sets_reach()
	_eased_ground_target(rig)
	_eased_air_target(rig)
	_no_teleport_tool()
	_finish.call_deferred(rig)


func _finish(rig: Rig) -> void:
	_a_flat_roof_is_floor_and_a_pitched_one_stops_the_ray(rig)
	await _stick_teleports_with_every_tool(rig)
	await _eased_stick_lands_nearer(rig, Vector3(0, -0.3, -1), "ground")
	await _eased_stick_lands_nearer(rig, Vector3(0, 1, -1), "air")
	await _ground_pull_back_walks_the_ray(rig)
	await _view_holds_after_teleport(rig, 0.0)
	await _view_holds_after_teleport(rig, 12.0)
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


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
	var o := Vector3(0, Terrain.height_at(0, 0) + 1.5, 0)
	var dir := Vector3(0, 1, -1).normalized()
	rig.aim(_pose(o, dir))
	_check(rig.aim_ground != null, "a ray into the sky targets the air")
	if rig.aim_ground == null:
		return
	var target: Vector3 = rig.aim_ground + Vector3.UP * rig.aim_lift
	_check(target.distance_to(o + dir * Rig.AIR_REACH) < 0.01, "the air target is on the ray at the air reach")
	_check(rig.aim_lift > 8.0, "an air target lifts the landing above the ground")


func _air_reach_stops_at_nearer_ground(rig: Rig) -> void:
	var o := Vector3(0, Terrain.height_at(0, -50) + 0.3, -50)
	var dir := Vector3(0, 0.05, -1).normalized()
	var hill: Variant = Terrain.raycast(o, dir, Rig.AIR_REACH)
	_check(hill != null, "the rim's slope rises across a shallow ray")
	if hill == null:
		return
	rig.aim(_pose(o, dir))
	_check(rig.aim_lift < 0.15 and rig.aim_ground.distance_to(hill) < 0.1, "a rising ray that meets a hillside within reach lands on it")


func _stick_deflection_sets_reach() -> void:
	_check(Rig.reach_scale(1.0) == 1.0 and Rig.reach_scale(Rig.FULL_STICK) == 1.0, "full forward reaches the full target")
	_check(is_equal_approx(Rig.reach_scale(Rig.DEADZONE), Rig.NEAREST), "the stick at its deadzone reaches the nearest")
	var last := 0.0
	var rising := true
	for i in 21:
		var f := Rig.reach_scale(i / 20.0)
		rising = rising and f >= last
		last = f
	_check(rising, "easing the stick back never pushes the target farther")


func _eased_ground_target(rig: Rig) -> void:
	var o := Vector3(0, Terrain.height_at(0, 0) + 1.5, 0)
	var pose := _pose(o, Vector3(0, -0.3, -1))
	rig.aim(pose)
	var hit: Vector3 = rig.aim_ground
	rig.aim(pose, 0.5)
	_check(rig.aim_ground != null, "an eased ground aim still has a target")
	if rig.aim_ground == null:
		return
	var target: Vector3 = rig.aim_ground + Vector3.UP * rig.aim_lift
	_check(target.distance_to(o.lerp(hit, 0.5)) < 0.01, "an eased ground target sits halfway along the ray, not on the ground below it: %s for %s" % [target, o.lerp(hit, 0.5)])
	_check(rig.aim_lift > 0.15, "an eased ground target floats above the ground: %.2f m" % rig.aim_lift)


func _eased_air_target(rig: Rig) -> void:
	var o := Vector3(0, Terrain.height_at(0, 0) + 1.5, 0)
	var dir := Vector3(0, 1, -1).normalized()
	rig.aim(_pose(o, dir), 0.4)
	_check(rig.aim_ground != null, "an eased air aim still targets the air")
	if rig.aim_ground == null:
		return
	var target: Vector3 = rig.aim_ground + Vector3.UP * rig.aim_lift
	_check(target.distance_to(o + dir * Rig.AIR_REACH * 0.4) < 0.01, "an eased air target sits nearer along the ray")


func _a_flat_roof_is_floor_and_a_pitched_one_stops_the_ray(rig: Rig) -> void:
	var r := RoofLayout.new()
	var ground := Terrain.height_at(0, -20)
	r.corners = WallLayout.rectangle(Vector3(-3, ground, -20), Vector3(3, ground, -20), 4.0)
	r.base = ground + 3.0
	r.pitch = 0.0
	r.build()
	rig.floor_under = func(p: Vector3) -> float: return maxf(Terrain.height_at(p.x, p.z), r.deck_under(p))
	rig.roof_hit = func(o: Vector3, d: Vector3) -> Dictionary:
		var t := r.ray_hit(o, d)
		return {} if t == INF else {"along": t, "point": o + d * t, "flat": r.flat()}
	var o := Vector3(0, r.base + 4.0, -14)
	rig.aim(_pose(o, Vector3(0, -4.0, -5.0)))
	_check(rig.aim_ground != null and absf(rig.aim_ground.y - r.base) < 0.01 and rig.aim_lift < 0.15, "a ray onto a flat roof lands on its deck: %s" % [rig.aim_ground])
	if rig.aim_ground != null:
		rig.place(rig.aim_ground, rig.aim_lift)
		_check(absf(rig.global_position.y - r.base) < 0.2, "the player stands on the deck, not inside the house: %.2f for %.2f" % [rig.global_position.y, r.base])
	_aims_into_the_house_land_on_its_floor(rig, r, "flat")
	r.pitch = 2.0
	r.build()
	rig.aim(_pose(o, Vector3(0, -4.0, -5.0)))
	_check(rig.aim_ground == null, "a pitched roof stops the ray: no landing inside the house beneath it")
	_aims_into_the_house_land_on_its_floor(rig, r, "pitched")
	rig.floor_under = func(p: Vector3) -> float: return Terrain.height_at(p.x, p.z)
	rig.roof_hit = func(_o: Vector3, _d: Vector3) -> Dictionary: return {}
	rig.place(Vector3(0, Terrain.height_at(0, 4), 4), 0.0)


## Rays that pass under the roof: from outside at a doorway's height and a window's, and from inside down at the
## floor, at full reach and eased. Each lands inside the walls, under the roof: on the floor at full reach, on the
## ray over the floor eased.
func _aims_into_the_house_land_on_its_floor(rig: Rig, r: RoofLayout, roof: String) -> void:
	var f := r.frame()
	var mid := Vector3(f.mid.x, 0.0, f.mid.z)
	var out: Vector3 = f.across * (r.half_span() + 4.0)
	var floor := func(p: Vector3) -> Vector3: return Vector3(p.x, Terrain.height_at(p.x, p.z), p.z)
	var inner: Vector3 = f.across * (r.half_span() - 0.6)
	var aims := {
		"through a doorway": [floor.call(mid + out) + Vector3.UP * 1.2, floor.call(mid), 1.0],
		"through a window": [floor.call(mid + out) + Vector3.UP * 1.8, floor.call(mid - inner), 1.0],
		"at the floor from inside": [floor.call(mid + inner) + Vector3.UP * 1.2, floor.call(mid - inner), 1.0],
		"eased, at the floor from inside": [floor.call(mid + inner) + Vector3.UP * 1.2, floor.call(mid - inner), 0.6],
	}
	for what: String in aims:
		var a: Array = aims[what]
		var from: Vector3 = a[0]
		rig.aim(_pose(from, a[1] - from), a[2])
		var g: Variant = rig.aim_ground
		var inside: bool = g != null and r.over(g.x, g.z)
		var on_floor: bool = g != null and absf(g.y - Terrain.height_at(g.x, g.z)) < 0.05
		var on_ray: bool = g != null and (g + Vector3.UP * rig.aim_lift).distance_to(from.lerp(a[1], a[2])) < 0.05
		_check(inside and on_floor and on_ray, "%s roof, aimed %s: lands inside over the floor, not on the roof: %s up %.2f for floor %.2f, roof %.2f" % [roof, what, g, rig.aim_lift, Terrain.height_at(g.x, g.z) if g != null else NAN, r.base])


func _no_teleport_tool() -> void:
	_check(not Hand.Tool.has("TELEPORT"), "teleport is not a tool")
	_check(ToolWheel.paths(Hand.TREE).size() == Hand.Tool.size(), "the wheel holds every tool and nothing else")


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


## Through real frames: full forward, ease back and hold, then a release whose spring sweeps the stick through
## smaller deflections. The eased landing is nearer than the full one, and a release straight from full
## forward still goes the full distance.
func _eased_stick_lands_nearer(rig: Rig, dir: Vector3, what: String) -> void:
	var full := await _stick_landing(rig, dir, 0.6)
	var eased := await _stick_landing(rig, dir, 0.6, 0.45)
	var ratio := eased / full
	var expect := Rig.reach_scale(0.45)
	_check(absf(ratio - expect) < 0.08, "%s: easing back to 0.45 lands %.2f of the full distance (%.1f of %.1f m), want %.2f" % [what, ratio, eased, full, expect])
	rig.place(Vector3(0, Terrain.height_at(0, 0), 0), 0.0)
	await process_frame
	var aimed := rig.head.global_position
	rig.left.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), aimed + Vector3(-0.2, -0.4, -0.3))
	rig.aim(rig.left.global_transform)
	var far: Vector3 = rig.aim_ground
	var snapped := await _stick_landing(rig, dir, 0.0)
	_check(absf(snapped - Vector2(far.x - aimed.x, far.z - aimed.z).length()) < 1.0, "%s: a release straight from full forward goes the full distance" % what)


## Through real frames, aimed at the ground: easing the stick back walks the target back along the ray, a slow
## release lands there in the air, and only a quick release from full forward lands on the ground the ray hit.
func _ground_pull_back_walks_the_ray(rig: Rig) -> void:
	var dir := Vector3(0, -0.3, -1).normalized()
	rig.place(Vector3(0, Terrain.height_at(0, 0), 0), 0.0)
	await process_frame
	var from := rig.head.global_position
	rig.left.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), from + Vector3(-0.2, -0.4, -0.3))
	var o := rig.left.global_position
	Hand.injected_sticks[rig.left.tracker] = Vector2(0, 1)
	await process_frame
	await process_frame
	var hit: Vector3 = rig.aim_ground
	for y in [0.85, 0.7, 0.55, 0.4]:
		Hand.injected_sticks[rig.left.tracker] = Vector2(0, y)
		await process_frame
		var target: Vector3 = rig.aim_ground + Vector3.UP * rig.aim_lift
		var want := o.lerp(hit, Rig.reach_scale(y))
		_check(target.distance_to(want) < 0.01, "ground, stick at %.2f: the target is on the ray at %s, not %s" % [y, want, target])
	var eased: Vector3 = rig.aim_ground + Vector3.UP * rig.aim_lift
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 300:
		await process_frame
	for y in [0.35, 0.0]:
		Hand.injected_sticks[rig.left.tracker] = Vector2(0, y)
		await process_frame
	Hand.injected_sticks.erase(rig.left.tracker)
	for f in 30:
		await process_frame
	var landed := rig.global_position
	var h := rig.head.global_position
	_check(Vector2(h.x - eased.x, h.z - eased.z).length() < 0.05 and absf(landed.y - eased.y) < 0.05, "ground: a slow release lands on the eased point on the ray: %s for %s" % [Vector3(h.x, landed.y, h.z), eased])
	_check(landed.y - Terrain.height_at(h.x, h.z) > 0.15, "ground: the eased landing floats above the ground")
	await _stick_landing(rig, dir, 0.0)
	h = rig.head.global_position
	_check(Vector2(h.x - hit.x, h.z - hit.z).length() < 1.0 and absf(rig.global_position.y - Terrain.height_at(h.x, h.z)) < 0.05, "ground: a quick release from full forward lands on the ground the ray hit")


## Places the rig at the origin, aims along `dir` with the stick full forward, then at `eased` for `hold`
## seconds, then lets the stick spring back through 0.6 and 0.35 to centre; returns how far the head moved.
func _stick_landing(rig: Rig, dir: Vector3, hold: float, eased := 1.0) -> float:
	rig.place(Vector3(0, Terrain.height_at(0, 0), 0), 0.0)
	await process_frame
	var from := rig.head.global_position
	rig.left.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), from + Vector3(-0.2, -0.4, -0.3))
	Hand.injected_sticks[rig.left.tracker] = Vector2(0, 1)
	await process_frame
	await process_frame
	Hand.injected_sticks[rig.left.tracker] = Vector2(0, eased)
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < hold * 1000.0:
		await process_frame
	for y in [0.6, 0.35, 0.0]:
		Hand.injected_sticks[rig.left.tracker] = Vector2(0, y)
		await process_frame
	Hand.injected_sticks.erase(rig.left.tracker)
	for f in 30:
		await process_frame
	return Vector2(rig.head.global_position.x - from.x, rig.head.global_position.z - from.z).length()


## With no input, the frames after a teleport change the origin once, the cut, and leave it on the target.
func _view_holds_after_teleport(rig: Rig, lift_m: float) -> void:
	var ground := Vector3(6, Terrain.height_at(6, -3), -3)
	var before := rig.global_position
	rig.teleport(ground, lift_m)
	var trace: Array[Vector3] = [before]
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 1500:
		await process_frame
		if rig.global_position != trace[-1]:
			trace.append(rig.global_position)
	print("trace %s m: %s over %d ms" % [lift_m, trace, Time.get_ticks_msec() - start])
	_check(trace.size() == 2, "a %s m teleport moves the origin once, then holds it: %d moves" % [lift_m, trace.size() - 1])
	var h := rig.head.global_position
	_check(Vector2(h.x - ground.x, h.z - ground.z).length() < 1e-4 and absf(rig.global_position.y - ground.y - lift_m) < 1e-4, "a %s m teleport lands exactly on its target" % lift_m)
