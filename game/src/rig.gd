class_name Rig
extends XROrigin3D

## The player: head, two hands, and locomotion by teleport — onto the ground or into the air to float.
## The left stick pushed forward aims from the left hand whatever it holds, so no choice of tools leaves the
## player unable to move; how far forward it is pushed sets how far along the aim the target lies.

## The eyes' near clip: at 5 cm a face leaned in to a conure cut it open, and its far side, culled from inside,
## left nothing. Godot's reversed depth keeps far stone and paving apart at this near.
const NEAR := 0.02
## Past the farthest range round the garden (Mountains) and the sun's disc beyond it.
const FAR := 2600.0
## The eyes' height above the floor, standing.
const EYE := 1.65
const AIR_REACH := 30.0
## A target across the map moves metres for a fraction of a degree of hand tremor. The aim follows the hand at
## STEADY_HZ, plus STEADY_HZ_PER_RAD for each radian it lags, so a held hand stays still and a sweep catches up.
const STEADY_HZ := 0.5
const STEADY_HZ_PER_RAD := 60.0
## Past MARKER_NEAR from the eyes the markers grow with distance, so they look as big as they do there.
const MARKER_NEAR := 15.0
## Stick forward at or past FULL_STICK aims at the ray's full target; easing back to the deadzone brings it
## to NEAREST of the way there.
const FULL_STICK := 0.9
const DEADZONE := 0.3
const NEAREST := 0.1
## A released stick springs through every smaller deflection on its way to centre; the release takes the
## target from this long before the stick reached its deadzone.
const RELEASE_LOOKBACK := 0.1
const MAX_LIFT := 40.0
const SNAP := deg_to_rad(30.0)
const FADE := 0.09
## The render layers with a private use, one table so no two uses share a bit; everything else draws on layer 1.
## The tool wheel's icons: the sun skips them and the wheel's own light lights only them, so they look as they do on
## the default day at any hour.
const WHEEL_LAYER := 1 << 19
## The player's own avatar, which only the camera sees: their eyes would see it from inside.
const SELF_LAYER := 1 << 18

## The player was set down somewhere else.
signal placed
## The player was moved in one cut, by a teleport or a snap turn, not by any step of their own.
signal jumped

var head: XRCamera3D
var gaze: Gaze
var left: Hand
var right: Hand
var hands: Array[Hand] = []
## The player's own avatar, shown only while a camera is held, or null.
var body: Avatar

## The hand whose teleport ray is out, or null.
var aim_hand: Hand
var aim_ground: Variant = null
var aim_lift := 0.0
## What a point stands on: the ground, or a flat roof's deck or a stair's tread at or below it.
var floor_under := func(p: Vector3) -> float: return Terrain.height_at(p.x, p.z)
## Where a ray first meets something solid short of a reach, the ground aside: a build, a plant or stairs; or null.
var solid_hit := func(_origin: Vector3, _dir: Vector3, _reach: float) -> Variant: return null
var _moves: Buttons
var _turns: Buttons
var _fade_t := -1.0
var _pending: Variant = null
var _aim_clock := 0.0
## [time, aim_ground, aim_lift] over the last RELEASE_LOOKBACK of aiming, oldest first.
var _aim_trail: Array = []
var _steady_dir := Vector3.ZERO

var _ground_ring: MeshInstance3D
var _float_ring: MeshInstance3D
var _pole: MeshInstance3D
var _fade: MeshInstance3D
var _fade_mat: StandardMaterial3D


func _init() -> void:
	head = XRCamera3D.new()
	head.position = Vector3(0, EYE, 0)
	head.near = NEAR
	head.far = far()
	head.cull_mask = Quality.VIEW_MASK & ~SELF_LAYER
	add_child(head)
	gaze = Gaze.new()
	add_child(gaze)
	left = Hand.new("left_hand", Hand.Tool.BOOK)
	right = Hand.new("right_hand", Hand.Tool.WALLS)
	hands = [left, right]
	for h in hands:
		add_child(h)
	_moves = Buttons.new(left).watch(["teleport"])
	_turns = Buttons.new(right).watch(["turn_left", "turn_right"])
	_build_markers()


func _build_markers() -> void:
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.albedo_color = Color(0.85, 0.97, 1.0, 0.75)
	glow.no_depth_test = false
	glow.disable_fog = true
	var ring := TorusMesh.new()
	ring.inner_radius = 0.32
	ring.outer_radius = 0.4
	ring.rings = 24
	ring.ring_segments = 6
	_ground_ring = _marker(ring, glow)
	_float_ring = _marker(ring, glow)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.012
	pole.bottom_radius = 0.012
	pole.height = 1.0
	pole.radial_segments = 6
	_pole = _marker(pole, glow)
	_fade_mat = StandardMaterial3D.new()
	_fade_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fade_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fade_mat.no_depth_test = true
	_fade_mat.render_priority = 100
	_fade_mat.albedo_color = Color(0, 0, 0, 0)
	_fade = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	_fade.mesh = quad
	_fade.position = Vector3(0, 0, -0.08)
	_fade.material_override = _fade_mat
	_fade.visible = false
	head.add_child(_fade)


## Wears `a` as the player's own avatar, posed from the head and hands by `pose_body`.
func wear(a: Avatar) -> void:
	if body != null:
		body.queue_free()
	body = a
	a.top_level = true
	a.visible = false
	for v: VisualInstance3D in a.find_children("*", "VisualInstance3D", true, false):
		v.layers = SELF_LAYER
	add_child(a)


## Poses the body from the head and hands; a hand in `holding` holds a camera, whose model stands in for it, so its
## fingers never reach in front of the lens.
func pose_body(holding: Array[Hand]) -> void:
	body.pose(head.global_transform, left.global_transform, right.global_transform)
	for h in holding:
		body.fold(hands.find(h))


func _marker(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.top_level = true
	mi.visible = false
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## The eyes' far clip: at least FAR, and the whole ground from anywhere a player can stand or float over it,
## however high or deep it is pulled.
static func far() -> float:
	return maxf(FAR, Terrain.bounds().size.length() + AIR_REACH + MAX_LIFT)


func _process(delta: float) -> void:
	head.far = far()
	_locomotion_input(delta)
	_moves.latch()
	_turns.latch()
	_fade_step(delta)


func _locomotion_input(delta: float) -> void:
	if aim_hand == null and _moves.held("teleport"):
		aim_hand = left
	if aim_hand != null and aim_hand.picking:
		_end_aim()
	if aim_hand != null:
		var stick := left.stick()
		if stick.length() < DEADZONE:
			var held: Array = _aim_trail[0] if not _aim_trail.is_empty() else [0.0, null, 0.0]
			if held[1] != null:
				teleport(held[1], held[2])
			_end_aim()
			return
		aim(_steadied(aim_hand.global_transform, delta), reach_scale(stick.y))
		_aim_clock += delta
		_aim_trail.append([_aim_clock, aim_ground, aim_lift])
		while _aim_trail.size() > 1 and _aim_trail[1][0] <= _aim_clock - RELEASE_LOOKBACK:
			_aim_trail.pop_front()
	else:
		if _turns.pressed("turn_left"):
			snap_turn(SNAP)
		if _turns.pressed("turn_right"):
			snap_turn(-SNAP)


func _end_aim() -> void:
	aim_hand = null
	_aim_clock = 0.0
	_aim_trail.clear()
	_steady_dir = Vector3.ZERO
	hide_markers()


## `pose` turned from the hand's own direction to the steadied one.
func _steadied(pose: Transform3D, delta: float) -> Transform3D:
	var dir := -pose.basis.z.normalized()
	if _steady_dir == Vector3.ZERO:
		_steady_dir = dir
		return pose
	var hz := STEADY_HZ + STEADY_HZ_PER_RAD * _steady_dir.angle_to(dir)
	_steady_dir = _steady_dir.slerp(dir, 1.0 - exp(-TAU * hz * delta)).normalized()
	return Transform3D(Basis(Quaternion(dir, _steady_dir)) * pose.basis, pose.origin)


## The fraction of the way to the ray's full target that a forward stick deflection of `y` reaches.
static func reach_scale(y: float) -> float:
	return lerpf(NEAREST, 1.0, clampf((y - DEADZONE) / (FULL_STICK - DEADZONE), 0.0, 1.0))


## Cast the teleport ray from a pointing pose. Its full target is the first solid thing it hits anywhere on the map,
## the ground, a roof of any pitch, a wall's top or a tree, where the player then stands; or, aimed above the horizon
## with nothing on the map to hit, the point in the air AIR_REACH along it. A ray leaving the map's side first, toward
## the scenery round it that nobody stands on, stands the player on the floor where it leaves. The target lies
## `fraction` of the way there along the ray, in the air above the floor short of a hit.
func aim(from: Transform3D, fraction := 1.0) -> void:
	var origin := from.origin
	var dir := -from.basis.z.normalized()
	var upward := dir.y > 0.0
	var reach := Terrain.exit_along(origin, dir)
	var hit: Variant = Terrain.raycast(origin, dir, reach)
	var solid: Variant = solid_hit.call(origin, dir, reach if hit == null else origin.distance_to(hit))
	if solid != null:
		hit = solid
	var leaves := origin + dir * reach
	if hit == null and (not upward or reach < AIR_REACH) and Terrain.on_side(leaves):
		hit = Vector3(leaves.x, floor_under.call(leaves), leaves.z)
	if hit == null and not upward:
		aim_ground = null
		hide_markers()
		return
	var full: Vector3 = hit if hit != null else origin + dir * AIR_REACH
	var target := origin.lerp(full, fraction)
	var g: float = full.y if hit != null and fraction >= 1.0 else floor_under.call(target)
	aim_ground = Vector3(target.x, g, target.z)
	aim_lift = clampf(target.y - g, 0.0, MAX_LIFT)
	if aim_hand != null:
		aim_hand.ray(target, Color(0.85, 0.97, 1.0, 0.75))
	var g3: Vector3 = aim_ground
	var size := maxf(1.0, head.global_position.distance_to(target) / MARKER_NEAR)
	_ground_ring.visible = true
	_ground_ring.global_transform = Transform3D(Basis().scaled(Vector3.ONE * size), g3 + Vector3.UP * 0.03 * size)
	var lifted := aim_lift > 0.15
	_float_ring.visible = lifted
	_pole.visible = lifted
	if lifted:
		_float_ring.global_transform = Transform3D(Basis().scaled(Vector3.ONE * size), g3 + Vector3.UP * aim_lift)
		_pole.global_transform = Transform3D(Basis().scaled(Vector3(size, aim_lift, size)), g3 + Vector3.UP * aim_lift * 0.5)


func hide_markers() -> void:
	left.clear_pointer()
	_ground_ring.visible = false
	_float_ring.visible = false
	_pole.visible = false


## Move so the head stands over `ground`, `lift` metres up. The rig then stays exactly there: in a headset
## any view motion the player's head did not make is uncomfortable.
func teleport(ground: Vector3, lift_m: float) -> void:
	Cues.play(Cues.Act.TELEPORT, ground + Vector3.UP * (lift_m + head.position.y), left)
	_pending = [ground, lift_m]
	_fade_t = 0.0
	_fade.visible = true


func respawn() -> void:
	_pending = null
	place(Vector3(0, Terrain.height_at(0, 4), 4), 0.0)


func place(ground: Vector3, lift_m: float) -> void:
	var h := head.global_position
	global_position = Vector3(global_position.x + ground.x - h.x, maxf(ground.y + lift_m, Terrain.height_at(ground.x, ground.z)), global_position.z + ground.z - h.z)
	placed.emit()


func snap_turn(angle: float) -> void:
	var pivot := head.global_position
	var t := Transform3D(Basis(Vector3.UP, angle), Vector3.ZERO)
	global_transform = Transform3D(t.basis * global_transform.basis, pivot + t.basis * (global_position - pivot))
	jumped.emit()
	Cues.play(Cues.Act.TURN, pivot, right)


func _fade_step(delta: float) -> void:
	if _fade_t < 0.0:
		return
	_fade_t += delta
	var a := 1.0 - absf(_fade_t / FADE - 1.0)
	if _pending != null and _fade_t >= FADE:
		place(_pending[0], _pending[1])
		_pending = null
		jumped.emit()
	_fade_mat.albedo_color = Color(0, 0, 0, clampf(a, 0.0, 1.0))
	if _fade_t >= FADE * 2.0:
		_fade_t = -1.0
		_fade.visible = false
