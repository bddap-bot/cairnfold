extends "res://../tests/support/suite.gd"

## Headless checks of the teleport ray: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_teleport.gd

## The time each frame steps the rig: a release reads the last Rig.RELEASE_LOOKBACK of aiming, so a frame's real
## length, long on a loaded machine, would decide where it lands.
const STEP := 1.0 / 60.0


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


## The rig steps only through _frame from here; disabled in _initialize, it would be enabled again when it is
## made ready with the root.
func _finish(rig: Rig) -> void:
	rig.set_process(false)
	_aims_under_any_roof_land_on_its_floor(rig)
	_reaches_across_the_map(rig)
	_air_target_shows_the_preview(rig)
	_the_preview_holds_the_players_pose(rig)
	_mountains_are_sky(rig)
	await _stick_teleports_with_every_tool(rig)
	await _either_hand_moves(rig)
	await _eased_stick_lands_nearer(rig, Vector3(0, -0.3, -1), "ground")
	await _eased_stick_lands_nearer(rig, Vector3(0, 1, -1), "air")
	await _ground_pull_back_walks_the_ray(rig)
	await _far_aim_holds_against_tremor(rig)
	await _view_holds_after_teleport(rig, 0.0)
	await _view_holds_after_teleport(rig, 12.0)
	_landing_sounds(rig)
	_floating_shows_what_is_underfoot(rig)
	finish()


## A teleport swishes; one past MARKER_NEAR that stands the player on the ground or something on it sounds as a landing.
func _landing_sounds(rig: Rig) -> void:
	var cases := {
		"a short teleport onto the ground": [Terrain.ground(0, 0), 0.0, Cues.Act.TELEPORT],
		"a long teleport onto the ground": [Terrain.ground(0, -40), 0.0, Cues.Act.TELEPORT_ONTO],
		"a short teleport onto a roof": [Terrain.ground(0, 0) + Vector3.UP * 3.0, 0.0, Cues.Act.TELEPORT],
		"a long teleport into the air": [Terrain.ground(0, -40), 6.0, Cues.Act.TELEPORT],
		"a long teleport onto a roof": [Terrain.ground(0, -40) + Vector3.UP * 3.0, 0.0, Cues.Act.TELEPORT_ONTO],
	}
	for what: String in cases:
		rig.respawn()
		var before := {}
		for act in [Cues.Act.TELEPORT, Cues.Act.TELEPORT_ONTO]:
			before[act] = Cues.asked.get(act, 0)
		rig.teleport(cases[what][0], cases[what][1])
		var played: Cues.Act = cases[what][2]
		var other := Cues.Act.TELEPORT_ONTO if played == Cues.Act.TELEPORT else Cues.Act.TELEPORT
		check(Cues.asked.get(played, 0) == before[played] + 1 and Cues.asked.get(other, 0) == before[other], what + " plays " + Cues.Act.keys()[played])
	rig.respawn()


func _frame(rig: Rig) -> void:
	await process_frame
	rig._process(STEP)


func _pose(origin: Vector3, dir: Vector3) -> Transform3D:
	return Transform3D(Basis.looking_at(dir, Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.BACK), origin)


func _ground_target(rig: Rig) -> void:
	var o := Vector3(0, Terrain.height_at(0, 0) + 1.5, 0)
	rig.aim(_pose(o, Vector3(0, -0.3, -1)))
	check(rig.aim_ground != null, "a ray down at the meadow finds ground")
	if rig.aim_ground == null:
		return
	var g: Vector3 = rig.aim_ground
	check(absf(g.y - Terrain.height_at(g.x, g.z)) < 0.05, "the ground target sits on the terrain")
	check(rig.aim_lift < 0.15, "a ground target has no lift")
	check(absf(Vector2(g.x, g.z).length() - 1.5 / 0.3) < 1.5, "the ray is straight, not an arc")


func _air_target(rig: Rig) -> void:
	var o := Vector3(0, Terrain.height_at(0, 0) + 1.5, 0)
	var dir := Vector3(0, 1, -1).normalized()
	rig.aim(_pose(o, dir))
	check(rig.aim_ground != null, "a ray into the sky targets the air")
	if rig.aim_ground == null:
		return
	var target: Vector3 = rig.aim_ground + Vector3.UP * rig.aim_lift
	check(target.distance_to(o + dir * Rig.AIR_REACH) < 0.01, "the air target is on the ray at the air reach")
	check(rig.aim_lift > 8.0, "an air target lifts the landing above the ground")


func _air_reach_stops_at_nearer_ground(rig: Rig) -> void:
	var o := Vector3(0, Terrain.height_at(0, -50) + 0.3, -50)
	var dir := Vector3(0, 0.05, -1).normalized()
	var hill: Variant = Terrain.raycast(o, dir, Rig.AIR_REACH)
	check(hill != null, "the rim's slope rises across a shallow ray")
	if hill == null:
		return
	rig.aim(_pose(o, dir))
	check(rig.aim_lift < 0.15 and rig.aim_ground.distance_to(hill) < 0.1, "a rising ray that meets a hillside within reach lands on it")


## The mountains are sky to the ray: aimed at one over the map's ground, level or up at its ridge, it gives what the
## sky over it gives, nothing near the map's side and the air reach farther in, and never the floor at the edge.
## Aimed down near the edge it still lands on the ground there.
func _mountains_are_sky(rig: Rig) -> void:
	var half := Terrain.SIZE * 0.5
	var ranges: Dictionary = Mountains.RANGES[0]
	for side: Vector2 in [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]:
		var az := atan2(side.y, side.x)
		var ridge: Vector3 = Vector3(side.x, 0, side.y) * ranges.radius + Vector3.UP * Mountains.ridge(ranges, Mountains.noise_for(ranges), az)
		for at: Vector2 in [Vector2(half - 6.0, Rig.EYE), Vector2(40.0, 25.0)]:
			var from := at.x
			var o := Vector3(side.x * from, Terrain.height_at(side.x * from, side.y * from) + at.y, side.y * from)
			var sky := Vector3(side.x, 0.5, side.y).normalized()
			rig.aim(_pose(o, sky))
			var above: Variant = rig.aim_ground
			var above_lift := rig.aim_lift
			for dir: Vector3 in [Vector3(side.x, 0, side.y), Vector3(side.x, 0.2, side.y), ridge - o]:
				dir = dir.normalized()
				rig.aim(_pose(o, dir))
				var g: Variant = rig.aim_ground
				var what := "a ray from %.0f m at the mountains along %s" % [from, dir]
				check(Terrain.raycast(o, dir) == null, what + " clears the map's ground")
				var air := o + dir * Rig.AIR_REACH
				if dir.y <= 0.0 or not Terrain.over_map(air):
					check(g == null and not rig._landing.visible, what + " has no target, as the sky has none: %s" % g)
				else:
					check(g != null and (g + Vector3.UP * rig.aim_lift).distance_to(air) < 0.01, what + " targets the air at the reach, as the sky does: %s" % g)
				if from == half - 6.0:
					check(g == null and above == null, what + " gives what the sky above it gives: %s and %s" % [g, above])
			if from != half - 6.0:
				check(above != null and (above + Vector3.UP * above_lift).distance_to(o + sky * Rig.AIR_REACH) < 0.01, "the sky from %.0f m in targets the air" % from)
		var near := Vector3(side.x, 0, side.y) * (half - 6.0)
		var eye := near + Vector3.UP * (Terrain.height_at(near.x, near.z) + Rig.EYE)
		rig.aim(_pose(eye, Vector3(side.x, -0.5, side.y).normalized()))
		var g: Variant = rig.aim_ground
		check(g != null and Terrain.over_map(g) and absf(g.y - Terrain.height_at(g.x, g.z)) < 0.05 and rig.aim_lift < 0.15, "a ray down at the ground by the edge lands on it: %s" % g)
	rig.hide_markers()


## From one corner of the map, high enough to see it, the ray lands on the far corner's ground, and the preview there
## looks as big as one nearby.
func _reaches_across_the_map(rig: Rig) -> void:
	var half := Terrain.SIZE * 0.5 - 4.0
	var o := Vector3(-half, Terrain.height_at(-half, half) + 30.0, half)
	var dir := (Terrain.ground(half, -half) - o).normalized()
	var far: Vector3 = Terrain.raycast(o, dir, INF)
	rig.place(Vector3(o.x, o.y - Rig.EYE, o.z), 0.0)
	rig.aim(_pose(o, dir))
	var g: Variant = rig.aim_ground
	check(o.distance_to(far) > 200.0 and g != null and g.distance_to(far) < 0.1 and rig.aim_lift < 0.15, "a ray %.0f m across the map lands where it hits: %s for %s" % [o.distance_to(far), g, far])
	var preview := rig._landing.global_transform
	check(rig._landing.visible and preview.basis.get_scale().x > o.distance_to(far) / Rig.MARKER_NEAR * 0.9, "the far preview grows with its distance: %.1f" % preview.basis.get_scale().x)
	rig.hide_markers()
	rig.place(Vector3(0, Terrain.height_at(0, 4), 4), 0.0)


## An air target stands the player's preview on the target itself; depth in the headset places it, so nothing marks
## the ground below.
func _air_target_shows_the_preview(rig: Rig) -> void:
	var o := Vector3(0, Terrain.height_at(0, 0) + 1.5, 0)
	rig.aim(_pose(o, Vector3(0, 1, -1).normalized()))
	var target: Vector3 = rig.aim_ground + Vector3.UP * rig.aim_lift
	check(rig._landing.visible and rig._landing.global_position.distance_to(target) < 0.01, "an air target shows the preview on the target: %s for %s" % [rig._landing.global_position, target])
	rig.hide_markers()


func _stick_deflection_sets_reach() -> void:
	check(Rig.reach_scale(1.0) == 1.0 and Rig.reach_scale(Rig.FULL_STICK) == 1.0, "full forward reaches the full target")
	check(is_equal_approx(Rig.reach_scale(Rig.DEADZONE), Rig.NEAREST), "the stick at its deadzone reaches the nearest")
	var last := 0.0
	var rising := true
	for i in 21:
		var f := Rig.reach_scale(i / 20.0)
		rising = rising and f >= last
		last = f
	check(rising, "easing the stick back never pushes the target farther")


func _eased_ground_target(rig: Rig) -> void:
	var o := Vector3(0, Terrain.height_at(0, 0) + 1.5, 0)
	var pose := _pose(o, Vector3(0, -0.3, -1))
	rig.aim(pose)
	var hit: Vector3 = rig.aim_ground
	rig.aim(pose, 0.5)
	check(rig.aim_ground != null, "an eased ground aim still has a target")
	if rig.aim_ground == null:
		return
	var target: Vector3 = rig.aim_ground + Vector3.UP * rig.aim_lift
	check(target.distance_to(o.lerp(hit, 0.5)) < 0.01, "an eased ground target sits halfway along the ray, not on the ground below it: %s for %s" % [target, o.lerp(hit, 0.5)])
	check(rig.aim_lift > 0.15, "an eased ground target floats above the ground: %.2f m" % rig.aim_lift)


func _eased_air_target(rig: Rig) -> void:
	var o := Vector3(0, Terrain.height_at(0, 0) + 1.5, 0)
	var dir := Vector3(0, 1, -1).normalized()
	rig.aim(_pose(o, dir), 0.4)
	check(rig.aim_ground != null, "an eased air aim still targets the air")
	if rig.aim_ground == null:
		return
	var target: Vector3 = rig.aim_ground + Vector3.UP * rig.aim_lift
	check(target.distance_to(o + dir * Rig.AIR_REACH * 0.4) < 0.01, "an eased air target sits nearer along the ray")


func _aims_under_any_roof_land_on_its_floor(rig: Rig) -> void:
	var r := RoofLayout.new()
	var ground := Terrain.height_at(0, -20)
	r.corners = WallLayout.rectangle(Vector3(-3, ground, -20), Vector3(3, ground, -20), 4.0)
	r.base = ground + 3.0
	r.pitch = 0.0
	r.build()
	rig.floor_under = func(p: Vector3) -> float: return maxf(Terrain.height_at(p.x, p.z), r.deck_under(p))
	rig.solid_hit = func(o: Vector3, d: Vector3, reach: float) -> Dictionary:
		var t := r.ray_hit(o, d)
		return {"point": o + d * t, "side": false} if t < reach else {}
	_aims_into_the_house_land_on_its_floor(rig, r, "flat")
	r.pitch = 2.0
	r.build()
	_aims_into_the_house_land_on_its_floor(rig, r, "pitched")
	rig.floor_under = func(p: Vector3) -> float: return Terrain.height_at(p.x, p.z)
	rig.solid_hit = func(_o: Vector3, _d: Vector3, _reach: float) -> Dictionary: return {}
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
		check(inside and on_floor and on_ray, "%s roof, aimed %s: lands inside over the floor, not on the roof: %s up %.2f for floor %.2f, roof %.2f" % [roof, what, g, rig.aim_lift, Terrain.height_at(g.x, g.z) if g != null else NAN, r.base])


func _no_teleport_tool() -> void:
	check(not Hand.Tool.has("TELEPORT"), "teleport is not a tool")


## Through real frames, as a player: the rig's own _process reads the stick.
## Either stick forward aims from its own hand and goes; either flicked sideways snap-turns, back turns round.
func _either_hand_moves(rig: Rig) -> void:
	for h in rig.hands:
		rig.place(Vector3(0, Terrain.height_at(0, 0), 0), 0.0)
		await _frame(rig)
		var from := rig.head.global_position
		h.global_transform = Transform3D(Basis.looking_at(Vector3(0, -0.3, -1), Vector3.UP), from + Vector3(0, -0.4, -0.3))
		Hand.injected_sticks[h.tracker] = Vector2(0, 1)
		await _frame(rig)
		await _frame(rig)
		var aimed: bool = rig.aim_hand == h and rig.aim_ground != null
		Hand.injected_sticks[h.tracker] = Vector2.ZERO
		for f in 30:
			await _frame(rig)
		var moved := Vector2(rig.head.global_position.x - from.x, rig.head.global_position.z - from.z).length()
		check(aimed and moved > 2.0, "%s stick forward aims from its hand and goes (moved %.1f m)" % [h.tracker, moved])
		for turn: Array in [[Vector2(-1, 0), Rig.SNAP], [Vector2(1, 0), -Rig.SNAP], [Vector2(0, -1), PI]]:
			var yaw := rig.global_basis.get_euler().y
			Hand.injected_sticks[h.tracker] = turn[0]
			await _frame(rig)
			await _frame(rig)
			Hand.injected_sticks[h.tracker] = Vector2.ZERO
			await _frame(rig)
			var turned := wrapf(rig.global_basis.get_euler().y - yaw, -PI, PI)
			check(absf(absf(turned) - absf(turn[1])) < 0.01 and signf(turned) == signf(turn[1]) or absf(turn[1]) == PI and absf(absf(turned) - PI) < 0.01, "%s stick %s turns %.0f deg: %.0f" % [h.tracker, turn[0], rad_to_deg(turn[1]), rad_to_deg(turned)])
		Hand.injected_sticks.erase(h.tracker)


func _stick_teleports_with_every_tool(rig: Rig) -> void:
	for t in Hand.Tool.values():
		rig.left.tool = t
		rig.right.tool = t
		rig.place(Vector3(0, Terrain.height_at(0, 0), 0), 0.0)
		await _frame(rig)
		var from := rig.head.global_position
		rig.left.global_transform = Transform3D(Basis.looking_at(Vector3(0, -0.3, -1), Vector3.UP), from + Vector3(-0.2, -0.4, -0.3))
		Hand.injected_sticks[rig.left.tracker] = Vector2(0, 1)
		await _frame(rig)
		await _frame(rig)
		var aimed: bool = rig.aim_hand == rig.left and rig.aim_ground != null
		Hand.injected_sticks[rig.left.tracker] = Vector2.ZERO
		for f in 30:
			await _frame(rig)
		var moved := Vector2(rig.head.global_position.x - from.x, rig.head.global_position.z - from.z).length()
		check(aimed and moved > 2.0, "left stick forward aims and goes holding %s (moved %.1f m)" % [Hand.Tool.keys()[t], moved])
	Hand.injected_sticks.erase(rig.left.tracker)


## Through real frames: full forward, ease back and hold, then a release whose spring sweeps the stick through
## smaller deflections. The eased landing is nearer than the full one, and a release straight from full
## forward still goes the full distance.
func _eased_stick_lands_nearer(rig: Rig, dir: Vector3, what: String) -> void:
	var full := await _stick_landing(rig, dir, 0.6)
	var eased := await _stick_landing(rig, dir, 0.6, 0.45)
	var ratio := eased / full
	var expect := Rig.reach_scale(0.45)
	check(absf(ratio - expect) < 0.08, "%s: easing back to 0.45 lands %.2f of the full distance (%.1f of %.1f m), want %.2f" % [what, ratio, eased, full, expect])
	rig.place(Vector3(0, Terrain.height_at(0, 0), 0), 0.0)
	await _frame(rig)
	var aimed := rig.head.global_position
	rig.left.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), aimed + Vector3(-0.2, -0.4, -0.3))
	rig.aim(rig.left.global_transform)
	var far: Vector3 = rig.aim_ground
	var snapped := await _stick_landing(rig, dir, 0.0)
	check(absf(snapped - Vector2(far.x - aimed.x, far.z - aimed.z).length()) < 1.0, "%s: a release straight from full forward goes the full distance" % what)


## Through real frames, aimed at the ground: easing the stick back walks the target back along the ray, a slow
## release lands there in the air, and only a quick release from full forward lands on the ground the ray hit.
func _ground_pull_back_walks_the_ray(rig: Rig) -> void:
	var dir := Vector3(0, -0.3, -1).normalized()
	rig.place(Vector3(0, Terrain.height_at(0, 0), 0), 0.0)
	await _frame(rig)
	var from := rig.head.global_position
	rig.left.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), from + Vector3(-0.2, -0.4, -0.3))
	var o := rig.left.global_position
	Hand.injected_sticks[rig.left.tracker] = Vector2(0, 1)
	await _frame(rig)
	await _frame(rig)
	var hit: Vector3 = rig.aim_ground
	for y in [0.85, 0.7, 0.55, 0.4]:
		Hand.injected_sticks[rig.left.tracker] = Vector2(0, y)
		await _frame(rig)
		var target: Vector3 = rig.aim_ground + Vector3.UP * rig.aim_lift
		var want := o.lerp(hit, Rig.reach_scale(y))
		check(target.distance_to(want) < 0.01, "ground, stick at %.2f: the target is on the ray at %s, not %s" % [y, want, target])
	var eased: Vector3 = rig.aim_ground + Vector3.UP * rig.aim_lift
	for f in roundi(0.3 / STEP):
		await _frame(rig)
	for y in [0.35, 0.0]:
		Hand.injected_sticks[rig.left.tracker] = Vector2(0, y)
		await _frame(rig)
	Hand.injected_sticks.erase(rig.left.tracker)
	for f in 30:
		await _frame(rig)
	var landed := rig.global_position
	var h := rig.head.global_position
	check(Vector2(h.x - eased.x, h.z - eased.z).length() < 0.05 and absf(landed.y - eased.y) < 0.05, "ground: a slow release lands on the eased point on the ray: %s for %s" % [Vector3(h.x, landed.y, h.z), eased])
	check(landed.y - Terrain.height_at(h.x, h.z) > 0.15, "ground: the eased landing floats above the ground")
	await _stick_landing(rig, dir, 0.0)
	h = rig.head.global_position
	check(Vector2(h.x - hit.x, h.z - hit.z).length() < 1.0 and absf(rig.global_position.y - Terrain.height_at(h.x, h.z)) < 0.05, "ground: a quick release from full forward lands on the ground the ray hit")


## Through real frames, aimed at ground 130 m out: a hand trembling half a degree at 9 Hz moves the target well under
## what the same tremor moves the bare ray, and a deliberate turn of 10 degrees is followed within a quarter second.
func _far_aim_holds_against_tremor(rig: Rig) -> void:
	rig.place(Vector3(0, Terrain.height_at(0, 60) + 20.0, 60), 0.0)
	await _frame(rig)
	var from := rig.head.global_position + Vector3(-0.2, -0.4, -0.3)
	var far := Terrain.ground(0, -70)
	var aim := (far - from).normalized()
	var side := aim.cross(Vector3.UP).normalized()
	var pose := func(a: float) -> Transform3D: return Transform3D(Basis.looking_at(aim.rotated(Vector3.UP, a), Vector3.UP), from)
	rig.left.global_transform = pose.call(0.0)
	Hand.injected_sticks[rig.left.tracker] = Vector2(0, 1)
	await _frame(rig)
	await _frame(rig)
	var steady: Array[Vector3] = []
	var bare: Array[Vector3] = []
	for f in 120:
		var wobble := deg_to_rad(0.5) * sin(TAU * 9.0 * f * STEP)
		rig.left.global_transform = pose.call(wobble)
		await _frame(rig)
		if f >= 30:
			steady.append(rig.aim_ground)
			bare.append(Terrain.raycast(from, -rig.left.global_basis.z, 400.0))
	var spread := func(ps: Array[Vector3]) -> float:
		var most := 0.0
		for p in ps:
			most = maxf(most, absf((p - ps[0]).dot(side)))
		return most
	var held: float = spread.call(steady)
	var shaken: float = spread.call(bare)
	check(far.distance_to(from) > 120.0 and held < shaken * 0.25, "a trembling hand moves a %.0f m target %.2f m, the bare ray %.2f m" % [far.distance_to(from), held, shaken])
	var turn := deg_to_rad(10.0)
	rig.left.global_transform = pose.call(turn)
	for f in roundi(0.25 / STEP):
		await _frame(rig)
	var turned: Vector3 = rig.aim_ground - from
	var wanted := aim.rotated(Vector3.UP, turn)
	var off := Vector2(turned.x, turned.z).angle_to(Vector2(wanted.x, wanted.z))
	check(absf(off) < deg_to_rad(0.5), "a 10 degree turn is followed within a quarter second: %.2f degrees off" % rad_to_deg(off))
	Hand.injected_sticks.erase(rig.left.tracker)
	for f in 30:
		await _frame(rig)


## Places the rig at the origin, aims along `dir` with the stick full forward, then at `eased` for `hold`
## seconds, then lets the stick spring back through 0.6 and 0.35 to centre; returns how far the head moved.
func _stick_landing(rig: Rig, dir: Vector3, hold: float, eased := 1.0) -> float:
	rig.place(Vector3(0, Terrain.height_at(0, 0), 0), 0.0)
	await _frame(rig)
	var from := rig.head.global_position
	rig.left.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), from + Vector3(-0.2, -0.4, -0.3))
	Hand.injected_sticks[rig.left.tracker] = Vector2(0, 1)
	await _frame(rig)
	await _frame(rig)
	Hand.injected_sticks[rig.left.tracker] = Vector2(0, eased)
	for f in roundi(hold / STEP):
		await _frame(rig)
	for y in [0.6, 0.35, 0.0]:
		Hand.injected_sticks[rig.left.tracker] = Vector2(0, y)
		await _frame(rig)
	Hand.injected_sticks.erase(rig.left.tracker)
	for f in 30:
		await _frame(rig)
	return Vector2(rig.head.global_position.x - from.x, rig.head.global_position.z - from.z).length()


## With no input, the frames after a teleport change the origin once, the cut, and leave it on the target.
func _view_holds_after_teleport(rig: Rig, lift_m: float) -> void:
	var ground := Vector3(6, Terrain.height_at(6, -3), -3)
	var before := rig.global_position
	rig.teleport(ground, lift_m)
	var trace: Array[Vector3] = [before]
	for f in roundi(1.5 / STEP):
		await _frame(rig)
		if rig.global_position != trace[-1]:
			trace.append(rig.global_position)
	check(trace.size() == 2, "a %s m teleport moves the origin once, then holds it: %s" % [lift_m, trace])
	var h := rig.head.global_position
	check(Vector2(h.x - ground.x, h.z - ground.z).length() < 1e-4 and absf(rig.global_position.y - ground.y - lift_m) < 1e-4, "a %s m teleport lands exactly on its target" % lift_m)


## The preview is the player's own avatar standing at the target, turned as they face and holding their head and hands
## where they hold them now, about the floor under their head.
func _the_preview_holds_the_players_pose(rig: Rig) -> void:
	rig.wear(Avatar.open(Avatar.built_in(0), Color.WHITE))
	rig.head.position = Vector3(0.1, 1.5, 0.2)
	rig.head.rotation = Vector3(-0.3, 0.8, 0.0)
	rig.left.position = Vector3(-0.3, 1.1, -0.2)
	var o := rig.head.global_position
	rig.aim(_pose(o, (rig.head.global_basis * Vector3(0, -0.3, -1)).normalized()))
	var avatar: Avatar = rig._landing._avatar
	var at := rig._landing.global_transform
	var ahead := -rig.head.global_basis.z
	var facing := -at.basis.z.normalized()
	check(rig._landing.visible and absf(Vector2(facing.x, facing.z).angle_to(Vector2(ahead.x, ahead.z))) < 0.01, "the preview faces as the player does: %s for %s" % [facing, ahead])
	check(absf(avatar.eyes.origin.y - 1.5) < 0.01 and absf(avatar.eyes.basis.get_euler().x + 0.3) < 0.01, "the preview's eyes stand and tilt as the player's: %s" % avatar.eyes)
	var hand := avatar.hands[0].origin - avatar.eyes.origin
	var real := rig.left.global_position - rig.head.global_position
	check(absf(hand.length() - real.length()) < 0.01 and absf(hand.y - real.y) < 0.01, "the preview's left hand is where the player's is from the head: %s for %s" % [hand, real])
	rig.hide_markers()
	rig.head.transform = Transform3D(Basis.IDENTITY, Vector3(0, Rig.EYE, 0))
	rig.left.transform = Transform3D.IDENTITY


## Floating, a ring marks the floor the player floats on and a shadow the ground below; standing, neither shows.
func _floating_shows_what_is_underfoot(rig: Rig) -> void:
	var g := Terrain.ground(0, 0)
	rig.place(g, 0.0)
	rig._process(STEP)
	check(not rig._underfoot.visible, "standing shows nothing underfoot")
	rig.place(g, 12.0)
	rig._process(STEP)
	var h := rig.head.global_position
	var ring: Vector3 = rig._underfoot._ring.global_position
	var shadow: Vector3 = rig._underfoot._shadow.global_position
	check(rig._underfoot.visible and absf(ring.y - g.y - 12.0) < 0.1 and absf(shadow.y - g.y) < 0.1 and Vector2(ring.x - h.x, ring.z - h.z).length() < 0.01 and Vector2(shadow.x - h.x, shadow.z - h.z).length() < 0.01, "floating 12 m up shows a ring at the feet, %s, and a shadow on the ground, %s" % [ring, shadow])
	rig.place(g, 0.0)
	rig._process(STEP)
	check(not rig._underfoot.visible, "coming back down hides both")
