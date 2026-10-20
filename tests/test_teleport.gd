extends SceneTree

## Headless checks of the teleport ray: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_teleport.gd

## The time each frame steps the rig: a release reads the last Rig.RELEASE_LOOKBACK of aiming, so a frame's real
## length, long on a loaded machine, would decide where it lands.
const STEP := 1.0 / 60.0

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


## The rig steps only through _frame from here; disabled in _initialize, it would be enabled again when it is
## made ready with the root.
func _finish(rig: Rig) -> void:
	rig.set_process(false)
	_a_ray_lands_on_any_roof_it_hits(rig)
	_reaches_across_the_map(rig)
	_backdrop_stops_no_ray(rig)
	await _stick_teleports_with_every_tool(rig)
	await _eased_stick_lands_nearer(rig, Vector3(0, -0.3, -1), "ground")
	await _eased_stick_lands_nearer(rig, Vector3(0, 1, -1), "air")
	await _ground_pull_back_walks_the_ray(rig)
	await _far_aim_holds_against_tremor(rig)
	await _view_holds_after_teleport(rig, 0.0)
	await _view_holds_after_teleport(rig, 12.0)
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _frame(rig: Rig) -> void:
	await process_frame
	rig._process(STEP)


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


## From one corner of the map, high enough to see it, the ray lands on the far corner's ground, and a ring there
## looks as big as one nearby.
## The mountains and everything round the map are scenery: a ray toward them from anywhere on it, level, a little
## down or up at a ridge, lands on the map's own floor where it leaves, or at the air reach short of that; never on
## nothing, nor in the air past the map.
func _backdrop_stops_no_ray(rig: Rig) -> void:
	var half := Terrain.SIZE * 0.5
	var ranges: Dictionary = Mountains.RANGES[0]
	for side: Vector2 in [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]:
		var az := atan2(side.y, side.x)
		var ridge: Vector3 = Vector3(side.x, 0, side.y) * ranges.radius + Vector3.UP * Mountains.ridge(ranges, Mountains.noise_for(ranges), az)
		for from in [40.0, 65.0, half - 6.0]:
			var o := Vector3(side.x * from, Terrain.height_at(side.x * from, side.y * from) + Rig.EYE, side.y * from)
			for dir: Vector3 in [Vector3(side.x, 0, side.y), Vector3(side.x, -0.02, side.y), Vector3(side.x, 0.2, side.y), ridge - o]:
				rig.aim(_pose(o, dir.normalized()))
				var g: Variant = rig.aim_ground
				var what := "a ray from %.0f m toward the mountains along %s" % [from, dir.normalized()]
				_check(g != null, what + " has a target")
				if g == null:
					continue
				_check(maxf(absf(g.x), absf(g.z)) <= half + 0.01, what + " lands on the map: %s" % g)
				var on_floor: bool = rig.aim_lift < 0.15 and absf(g.y - Terrain.height_at(g.x, g.z)) < 0.05
				var air: bool = (g + Vector3.UP * rig.aim_lift).distance_to(o + dir.normalized() * Rig.AIR_REACH) < 0.01
				_check(on_floor or air, what + " stands on the floor or at the air reach: %s, lift %.2f" % [g, rig.aim_lift])
				_check(Vector2(g.x - o.x, g.z - o.z).length() > 4.0, what + " goes out toward them: %s" % g)
	rig.hide_markers()


func _reaches_across_the_map(rig: Rig) -> void:
	var half := Terrain.SIZE * 0.5 - 4.0
	var o := Vector3(-half, Terrain.height_at(-half, half) + 30.0, half)
	var dir := (Terrain.ground(half, -half) - o).normalized()
	var far: Vector3 = Terrain.raycast(o, dir, INF)
	rig.place(Vector3(o.x, o.y - Rig.EYE, o.z), 0.0)
	rig.aim(_pose(o, dir))
	var g: Variant = rig.aim_ground
	_check(o.distance_to(far) > 200.0 and g != null and g.distance_to(far) < 0.1 and rig.aim_lift < 0.15, "a ray %.0f m across the map lands where it hits: %s for %s" % [o.distance_to(far), g, far])
	var ring := rig._ground_ring.global_transform
	_check(rig._ground_ring.visible and ring.basis.get_scale().x > o.distance_to(far) / Rig.MARKER_NEAR * 0.9, "the far ring grows with its distance: %.1f" % ring.basis.get_scale().x)
	rig.hide_markers()
	rig.place(Vector3(0, Terrain.height_at(0, 4), 4), 0.0)


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


func _a_ray_lands_on_any_roof_it_hits(rig: Rig) -> void:
	var r := RoofLayout.new()
	var ground := Terrain.height_at(0, -20)
	r.corners = WallLayout.rectangle(Vector3(-3, ground, -20), Vector3(3, ground, -20), 4.0)
	r.base = ground + 3.0
	r.pitch = 0.0
	r.build()
	rig.floor_under = func(p: Vector3) -> float: return maxf(Terrain.height_at(p.x, p.z), r.deck_under(p))
	rig.solid_hit = func(o: Vector3, d: Vector3, reach: float) -> Variant:
		var t := r.ray_hit(o, d)
		return o + d * t if t < reach else null
	var o := Vector3(0, r.base + 4.0, -14)
	rig.aim(_pose(o, Vector3(0, -4.0, -5.0)))
	_check(rig.aim_ground != null and absf(rig.aim_ground.y - r.base) < 0.01 and rig.aim_lift < 0.15, "a ray onto a flat roof lands on its deck: %s" % [rig.aim_ground])
	if rig.aim_ground != null:
		rig.place(rig.aim_ground, rig.aim_lift)
		_check(absf(rig.global_position.y - r.base) < 0.2, "the player stands on the deck, not inside the house: %.2f for %.2f" % [rig.global_position.y, r.base])
	_aims_into_the_house_land_on_its_floor(rig, r, "flat")
	r.pitch = 2.0
	r.build()
	var f := r.frame()
	var slope: Vector3 = Vector3(f.mid.x, 0.0, f.mid.z) + f.across * r.half_span() * 0.5
	slope.y = r.height_at(slope.x, slope.z)
	var aims := {
		"from the air above it": slope + Vector3(0, 9, 0) + f.across * 6.0,
		"from the ground below its eaves": Terrain.ground(slope.x, slope.z) + f.across * (r.half_span() + 3.0) + Vector3.UP * 1.2,
	}
	for what: String in aims:
		var from: Vector3 = aims[what]
		rig.aim(_pose(from, slope - from))
		var g: Variant = rig.aim_ground
		var hit: Vector3 = from + (slope - from).normalized() * r.ray_hit(from, (slope - from).normalized())
		_check(g != null and rig.aim_lift == 0.0 and g.distance_to(hit) < 0.01 and r.over(g.x, g.z), "a ray %s onto a pitched roof lands where it hits: %s for %s" % [what, g, hit])
		if g == null:
			continue
		rig.place(g, rig.aim_lift)
		var h := rig.head.global_position
		var stand := rig.global_position
		_check(absf(stand.y - r.height_at(h.x, h.z)) < 0.3 and stand.y - Terrain.height_at(h.x, h.z) > r.base - ground - 0.3, "aimed %s, the player stands on the slope, not in the air or inside: %.2f for roof %.2f" % [what, stand.y, r.height_at(h.x, h.z)])
		_check(rig.global_basis.y.is_equal_approx(Vector3.UP), "aimed %s, the player stands upright on the slope" % what)
	_aims_into_the_house_land_on_its_floor(rig, r, "pitched")
	rig.floor_under = func(p: Vector3) -> float: return Terrain.height_at(p.x, p.z)
	rig.solid_hit = func(_o: Vector3, _d: Vector3, _reach: float) -> Variant: return null
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


## Through real frames, as a player: the rig's own _process reads the stick.
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
	await _frame(rig)
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
		_check(target.distance_to(want) < 0.01, "ground, stick at %.2f: the target is on the ray at %s, not %s" % [y, want, target])
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
	_check(Vector2(h.x - eased.x, h.z - eased.z).length() < 0.05 and absf(landed.y - eased.y) < 0.05, "ground: a slow release lands on the eased point on the ray: %s for %s" % [Vector3(h.x, landed.y, h.z), eased])
	_check(landed.y - Terrain.height_at(h.x, h.z) > 0.15, "ground: the eased landing floats above the ground")
	await _stick_landing(rig, dir, 0.0)
	h = rig.head.global_position
	_check(Vector2(h.x - hit.x, h.z - hit.z).length() < 1.0 and absf(rig.global_position.y - Terrain.height_at(h.x, h.z)) < 0.05, "ground: a quick release from full forward lands on the ground the ray hit")


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
	_check(far.distance_to(from) > 120.0 and held < shaken * 0.25, "a trembling hand moves a %.0f m target %.2f m, the bare ray %.2f m" % [far.distance_to(from), held, shaken])
	var turn := deg_to_rad(10.0)
	rig.left.global_transform = pose.call(turn)
	for f in roundi(0.25 / STEP):
		await _frame(rig)
	var turned: Vector3 = rig.aim_ground - from
	var wanted := aim.rotated(Vector3.UP, turn)
	var off := Vector2(turned.x, turned.z).angle_to(Vector2(wanted.x, wanted.z))
	_check(absf(off) < deg_to_rad(0.5), "a 10 degree turn is followed within a quarter second: %.2f degrees off" % rad_to_deg(off))
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
	_check(trace.size() == 2, "a %s m teleport moves the origin once, then holds it: %s" % [lift_m, trace])
	var h := rig.head.global_position
	_check(Vector2(h.x - ground.x, h.z - ground.z).length() < 1e-4 and absf(rig.global_position.y - ground.y - lift_m) < 1e-4, "a %s m teleport lands exactly on its target" % lift_m)
