class_name Rig
extends XROrigin3D

## The left stick aims a teleport whatever the hand holds, so no choice of tools leaves the player unable to move.

## Real metres: at 5 cm a face leaned in to a conure cut it open. Reversed depth keeps far stone apart at this near.
const NEAR := 0.02
## Past the farthest mountains and the sun's disc.
const FAR := 2600.0
## Real metres, until `stature` has measured the wearer's.
const EYE := 1.65
## A fraction of the scale: past it the view fades out and in at the new scale, so the world never grows in view.
const REFIT := 0.02
## Past these an avatar stands above the floor or sinks into it.
const FITS := Vector2(0.1, 10.0)
const AIR_REACH := 30.0
## Tremor moves a far target metres, so the aim follows faster the more it lags: a held hand stays still.
const STEADY_HZ := 0.5
const STEADY_HZ_PER_RAD := 60.0
## Past it the landing preview grows with distance, so it looks as big as it does there.
const MARKER_NEAR_M := 15.0
const FULL_STICK := 0.9
const DEADZONE := 0.3
const NEAREST := 0.1
## Seconds: a released stick springs back through smaller deflections, so the target reads where it was this long ago.
const RELEASE_LOOKBACK := 0.1
const MAX_LIFT := 40.0
## Steeper than 70 degrees: a ruin's leaning stones stay well inside it.
const STEEP := 0.34
const STAND_OFF_M := 0.3
## A side struck at most this high over the floor in front lands the player there; higher, they float.
const CLIMB := 1.5
## A target higher than this over its floor floats.
const LIFTED := 0.15
const SNAP := deg_to_rad(30.0)
## Flick action -> radians turned.
const TURNS := {"turn_left": SNAP, "turn_right": -SNAP, "turn_round": PI}
const FADE := 0.09
## Eyes inside something solid dim the view; it is never moved to push them out.
const INSIDE_DIM := 0.9
const INSIDE_TIME := 0.15
## Ground x and z.
const SPAWN := Vector2(0, 4)
const SPAWN_SEARCH_M := 20.0
const SPAWN_STEP_M := 2.0
## Above the tallest build.
const SPAWN_CLEAR := 200.0

signal placed
## A teleport or snap turn, never a step of the player's own.
signal jumped

var head: XRCamera3D
var gaze: Gaze
var left: Hand
var right: Hand
var hands: Array[Hand] = []
var body: Avatar
var _seen: Array[MeshInstance3D] = []
var _wrists_noted := [{}, {}]
var stature := Stature.new()

## Null while no teleport ray is out.
var aim_hand: Hand
## Left then right, null where none sits.
var shoulders: Array[Conure] = [null, null]
## In this node's space, so a snap turn or a teleport carries it with the player.
var _torso := NAN
var aim_ground: Variant = null
var aim_lift := 0.0
var terrain: Terrain
## The top surface at or just below a point: the ground or anything built on it.
var floor_under := func(p: Vector3) -> float: return terrain.shown_at(p.x, p.z)
## A ray's first solid hit short of `reach`, the ground aside, as {point, side: whether it struck a side}, or {}.
var solid_hit := func(_origin: Vector3, _dir: Vector3, _reach: float) -> Dictionary: return {}
var _fade_t := -1.0
var _covered := false
## Each way.
var _fade_s := FADE
## The eyes are inside something solid; set by `HandStop`.
var inside := false
var _dim := 0.0
var _pending: Variant = null
var _aim_clock := 0.0
## [time, forward deflection] over the last RELEASE_LOOKBACK, oldest first.
var _aim_trail: Array = []
var _steady_dir := Vector3.ZERO

var _landing := Landing.new()
var _underfoot := Underfoot.new()
## Floats measure from it, so building under a floating player leaves the ring and shadow where they began.
var _floor_y := 0.0
var _fade: MeshInstance3D
var _fade_mat: StandardMaterial3D


var expression_store := ExpressionStore.new()


func _init(ground: Terrain) -> void:
	add_child(expression_store)
	terrain = ground
	head = XRCamera3D.new()
	head.position = Vector3(0, EYE, 0)
	head.near = NEAR
	head.far = far()
	head.cull_mask = Quality.VIEW_MASK & ~Quality.SELF_LAYER | Quality.EYES_LAYER
	add_child(head)
	gaze = Gaze.new()
	add_child(gaze)
	left = Hand.new("left_hand", Hand.Tool.BOOK)
	right = Hand.new("right_hand", Hand.Tool.WALLS)
	hands = [left, right]
	for h in hands:
		add_child(h)
	_build_markers()


func _build_markers() -> void:
	add_child(_landing)
	add_child(_underfoot)
	_fade_mat = Meshes.glow(Color(0, 0, 0, 0))
	_fade_mat.no_depth_test = true
	_fade_mat.render_priority = 100
	_fade = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	_fade.mesh = quad
	_fade.position = Vector3(0, 0, -0.08)
	_fade.material_override = _fade_mat
	_fade.visible = false
	head.add_child(_fade)


## Cameras and mirrors see it whole; the eyes see it headless while both hands are empty.
func wear(a: Avatar) -> void:
	for hand in hands:
		hand.close_wheel()
	expression_store.wear(a.expressions, a.source)
	if body != null:
		body.queue_free()
	body = a
	a.local = true
	a.add_to_group(Contacts.BODIES)
	a.top_level = true
	a.ground = func(p: Vector3) -> float: return floor_under.call(p)
	a.visible = true
	for v: VisualInstance3D in a.find_children("*", "VisualInstance3D", true, false):
		v.layers = Quality.SELF_LAYER
	for mi in a.swaying():
		mi.layers = Quality.PEOPLE_LAYER | Quality.SELF_LAYER
	_seen = a.headless()
	for mi in _seen:
		mi.layers = Quality.EYES_LAYER
	add_child(a)
	_landing.wear(a)


## A hand holding a tool is drawn as the tool alone, so its fingers never reach in front of a camera's lens.
func pose_body() -> void:
	body.torso = torso().basis.get_euler().y
	body.palms = [left.palm, right.palm]
	body.pose(head.global_transform, left.body.global_transform, right.body.global_transform, gaze.look)
	body.curl(left.curls + right.curls)
	_note_wrists()
	for h in hands:
		if h.tool != Hand.Tool.NONE:
			body.fold(hands.find(h))
	for mi in _seen:
		mi.visible = bare()


func _note_wrists() -> void:
	for s in 2:
		var h := hands[s]
		var key := h.palm_noted + (" shaped" if not h.shaped.is_empty() else "")
		if h.palm_noted == "" or _wrists_noted[s].has(key) or h.held_still or h.bare:
			continue
		_wrists_noted[s][key] = true
		var wrist := body.bone(["leftHand", "rightHand"][s]).origin
		var aim := h.body.global_transform
		var palm := aim * h.palm
		var mm := func(a: Vector3, b: Vector3) -> float: return 1000.0 * a.distance_to(b) / world_scale
		var real := "no runtime wrist"
		if not h.shaped.is_empty():
			var joint: Vector3 = (h.shaped[HandShape.WRIST] as Transform3D).origin
			real = "the runtime's wrist %.0f mm from the avatar's and %.0f mm from the aim" % [mm.call(joint, wrist), mm.call(joint, aim.origin)]
		Metrics.note("wrist: %s on %s, %.0f mm from the palm; %s" % [h.tracker, h.palm_noted, mm.call(wrist, palm.origin), real])


func bare() -> bool:
	return hands.all(func(h: Hand) -> bool: return h.tool == Hand.Tool.NONE)


## The eyes see the avatar's own hands, so no controller is drawn over them.
func shows_hands() -> bool:
	return body != null and bare()


## In world space.
func torso() -> Transform3D:
	_torso = Torso.follow(_torso, head.transform.basis)
	return global_transform * Torso.frame(head.transform, _torso)


## Under a pond the water's fog hides everything past its end, so the eyes clip there.
var under := false


func far() -> float:
	return maxf(FAR, terrain.bounds().size.length() + AIR_REACH + MAX_LIFT)


func _process(delta: float) -> void:
	head.far = Look.WATER_FOG.fog_depth_end if under else far()
	_locomotion_input(delta)
	_fade_step(delta)
	_underfoot.follow(head.global_position, global_position.y, _floor_y)
	_refit(delta)


## The avatar's eye height over the wearer's, so they see from its eyes and reach as far as its arms.
func fit() -> float:
	return clampf(body.eye_height / stature.eye(EYE), FITS.x, FITS.y) if body != null else 1.0


func _refit(delta: float) -> void:
	stature.add(head.position.y / world_scale, delta)
	if _fade_t < 0.0 and aim_hand == null and absf(fit() / world_scale - 1.0) > REFIT:
		var h := head.global_position
		_cut(Vector3(h.x, _floor_y, h.z), global_position.y - _floor_y)


func _locomotion_input(delta: float) -> void:
	if _covered:
		return
	if aim_hand == null and left.buttons.held("teleport"):
		aim_hand = left
	if aim_hand != null and aim_hand.picking:
		end_aim()
	if aim_hand != null:
		var stick := aim_hand.stick()
		if stick.length() < DEADZONE:
			if aim_ground != null:
				teleport(aim_ground, aim_lift)
			end_aim()
			return
		_aim_clock += delta
		_aim_trail.append([_aim_clock, stick.y])
		while _aim_trail.size() > 1 and _aim_trail[1][0] <= _aim_clock - RELEASE_LOOKBACK:
			_aim_trail.pop_front()
		aim(_steadied(aim_hand.global_transform, delta), reach_scale(_aim_trail[0][1]))
		return
	for turn: String in TURNS:
		if left.buttons.pressed(turn):
			snap_turn(TURNS[turn], left)


func end_aim() -> void:
	aim_hand = null
	aim_ground = null
	_aim_clock = 0.0
	_aim_trail.clear()
	_steady_dir = Vector3.ZERO
	hide_markers()


func _steadied(pose: Transform3D, delta: float) -> Transform3D:
	var dir := -pose.basis.z.normalized()
	if _steady_dir == Vector3.ZERO:
		_steady_dir = dir
		return pose
	var hz := STEADY_HZ + STEADY_HZ_PER_RAD * _steady_dir.angle_to(dir)
	_steady_dir = _steady_dir.slerp(dir, 1.0 - exp(-TAU * hz * delta)).normalized()
	return Transform3D(Basis(Quaternion(dir, _steady_dir)) * pose.basis, pose.origin)


static func reach_scale(y: float) -> float:
	return lerpf(NEAREST, 1.0, clampf((y - DEADZONE) / (FULL_STICK - DEADZONE), 0.0, 1.0))


## The mountains are sky to the ray, which ends at the map's side.
func aim(from: Transform3D, fraction := 1.0) -> void:
	var origin := from.origin
	var dir := -from.basis.z.normalized()
	var reach := minf(terrain.exit_along(origin, dir), Terrain.side_along(origin, dir))
	var hit: Variant = terrain.raycast(origin, dir, reach)
	var solid: Dictionary = solid_hit.call(origin, dir, reach if hit == null else origin.distance_to(hit))
	if not solid.is_empty():
		hit = solid.point
	if hit == null and dir.y <= 0.0:
		var leaves := origin + dir * reach
		hit = Vector3(leaves.x, floor_under.call(leaves), leaves.z)
	var full: Vector3 = hit if hit != null else origin + dir * minf(AIR_REACH, reach)
	var target := origin.lerp(full, fraction)
	var stand := target
	var g: float = floor_under.call(target)
	if hit != null and fraction >= 1.0:
		stand = full
		g = full.y
		var back := Vector3(dir.x, 0.0, dir.z)
		if solid.get("side", false) and back.length() > 1e-3:
			stand -= back.normalized() * STAND_OFF_M
			g = floor_under.call(stand)
			if full.y - g <= CLIMB:
				stand.y = g
	aim_ground = Vector3(stand.x, g, stand.z)
	aim_lift = clampf(stand.y - g, 0.0, MAX_LIFT)
	var size := maxf(1.0, head.global_position.distance_to(target) / MARKER_NEAR_M)
	_landing.put(aim_ground + Vector3.UP * (aim_lift if aim_lift > LIFTED else 0.0), size, self)


static func side(normal: Vector3) -> bool:
	return normal.normalized().y < STEEP


static func box_normal(box: AABB, p: Vector3) -> Vector3:
	var best := INF
	var n := Vector3.ZERO
	for k in 3:
		for end in [false, true]:
			var d := absf(p[k] - (box.end[k] if end else box.position[k]))
			if d < best:
				best = d
				n = Vector3.ZERO
				n[k] = 1.0 if end else -1.0
	return n


func hide_markers() -> void:
	_landing.hide()


## A cut, not a glide: in a headset any view motion the head did not make is uncomfortable.
func teleport(ground: Vector3, lift_m: float) -> void:
	var at := ground + Vector3.UP * (lift_m + head.position.y)
	var landing := lift_m <= LIFTED and head.global_position.distance_to(at) > MARKER_NEAR_M
	Cues.play(Cues.Act.TELEPORT_ONTO if landing else Cues.Act.TELEPORT, at, left if aim_hand == null else aim_hand)
	_cut(ground, lift_m)


func _cut(ground: Vector3, lift_m: float) -> void:
	_pending = [ground, lift_m]
	_fade_s = FADE
	_fade_t = 0.0
	_fade.visible = true


## Holds black until `respawn`; says whether it is black yet.
func blackout() -> bool:
	if not _covered:
		end_aim()
		_pending = null
	return cover()


func respawn() -> void:
	_pending = null
	place(spawn(), 0.0)
	uncover()


## Says whether it is black yet. Black is never brighter than what it covers.
func cover(fade := FADE) -> bool:
	if not _covered:
		_covered = true
		_fade_t = 0.0 if _fade_t < 0.0 else minf(_fade_t, _fade_s * 2.0 - _fade_t) * fade / _fade_s
		_fade_s = fade
		_fade.visible = true
	return _fade_t >= _fade_s


func uncover() -> void:
	_covered = false


func covered() -> bool:
	return _covered


## Open ground, so the player never arrives inside a build.
func spawn() -> Vector3:
	for ring in int(SPAWN_SEARCH_M / SPAWN_STEP_M) + 1:
		var r := ring * SPAWN_STEP_M
		var n := maxi(1, int(TAU * r / SPAWN_STEP_M))
		for k in n:
			var at := SPAWN + Vector2.from_angle(TAU * k / n) * r
			var g := terrain.ground(at.x, at.y)
			if solid_hit.call(g + Vector3.UP * SPAWN_CLEAR, Vector3.DOWN, SPAWN_CLEAR).is_empty():
				return g
	var top := Vector3(SPAWN.x, terrain.shown_at(SPAWN.x, SPAWN.y) + MAX_LIFT, SPAWN.y)
	return Vector3(top.x, floor_under.call(top), top.z)


## The head moves with the scale between frames, as a runtime reports it, never within one, so a session record keeps
## each frame's head as given and a replay places the player from the same pose.
func place(ground: Vector3, lift_m: float) -> void:
	var s := fit()
	var h := global_transform * (head.position * s / world_scale)
	if s != world_scale:
		(func(by: float) -> void: head.position *= by).call_deferred(s / world_scale)
	world_scale = s
	head.near = NEAR * s
	_floor_y = maxf(ground.y, terrain.shown_at(ground.x, ground.z))
	global_position = Vector3(global_position.x + ground.x - h.x, maxf(ground.y + lift_m, _floor_y), global_position.z + ground.z - h.z)
	placed.emit()


func snap_turn(angle: float, hand: Hand) -> void:
	var pivot := head.global_position
	var turn := Basis(Vector3.UP, angle)
	global_transform = Transform3D(turn * global_transform.basis, pivot + turn * (global_position - pivot))
	jumped.emit()
	Cues.play(Cues.Act.TURN, pivot, hand)


func _fade_step(delta: float) -> void:
	_dim = move_toward(_dim, INSIDE_DIM if inside else 0.0, INSIDE_DIM * delta / INSIDE_TIME)
	var a := 0.0
	if _fade_t >= 0.0:
		_fade_t += delta
		if _covered:
			_fade_t = minf(_fade_t, _fade_s)
		a = clampf(1.0 - absf(_fade_t / _fade_s - 1.0), 0.0, 1.0)
		if _pending != null and _fade_t >= _fade_s:
			place(_pending[0], _pending[1])
			_pending = null
			jumped.emit()
		if _fade_t >= _fade_s * 2.0:
			_fade_t = -1.0
			a = 0.0
	a = maxf(a, _dim)
	_fade_mat.albedo_color = Color(0, 0, 0, a)
	_fade.visible = a > 0.0
