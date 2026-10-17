class_name Rig
extends XROrigin3D

## The player: head, two hands, and locomotion by teleport — onto the ground or into the air to float.
## The left stick pushed forward aims from the left hand whatever it holds, so no choice of tools leaves the
## player unable to move; how far forward it is pushed sets how far along the aim the target lies.

## The eyes' near clip: at 5 cm a face leaned in to a conure cut it open, and its far side, culled from inside,
## left nothing. Godot's reversed depth keeps far stone and paving apart at this near.
const NEAR := 0.02
const MAX_REACH := 80.0
const AIR_REACH := 30.0
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

var head: XRCamera3D
var gaze: Gaze
var left: Hand
var right: Hand
var hands: Array[Hand] = []

## The hand whose teleport ray is out, or null.
var aim_hand: Hand
var aim_ground: Variant = null
var aim_lift := 0.0
## What a point stands on, as `WallTool.floor_under` finds it: the ground, or a flat roof's deck at or below it.
var floor_under := func(p: Vector3) -> float: return Terrain.height_at(p.x, p.z)
## Where a ray first meets something solid short of a reach, the ground aside, as `WallTool.solid_hit` finds it, or null.
var solid_hit := func(_origin: Vector3, _dir: Vector3, _reach: float) -> Variant: return null
var _moves: Buttons
var _turns: Buttons
var _fade_t := -1.0
var _pending: Variant = null
var _aim_clock := 0.0
## [time, aim_ground, aim_lift] over the last RELEASE_LOOKBACK of aiming, oldest first.
var _aim_trail: Array = []

var _ground_ring: MeshInstance3D
var _float_ring: MeshInstance3D
var _pole: MeshInstance3D
var _fade: MeshInstance3D
var _fade_mat: StandardMaterial3D


func _init() -> void:
	head = XRCamera3D.new()
	head.position = Vector3(0, 1.65, 0)
	head.near = NEAR
	head.far = 400.0
	add_child(head)
	gaze = Gaze.new()
	add_child(gaze)
	left = Hand.new("left_hand", Hand.Tool.FLOWERS)
	right = Hand.new("right_hand", Hand.Tool.WALLS)
	hands = [left, right]
	for h in hands:
		add_child(h)
	_moves = Buttons.new(left).watch([Controls.input("teleport", left.tracker)])
	_turns = Buttons.new(right).watch([Controls.input("turn_left", right.tracker), Controls.input("turn_right", right.tracker)])
	_build_markers()


func _build_markers() -> void:
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.albedo_color = Color(0.85, 0.97, 1.0, 0.75)
	glow.no_depth_test = false
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


func _marker(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.top_level = true
	mi.visible = false
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _process(delta: float) -> void:
	_locomotion_input(delta)
	_moves.latch()
	_turns.latch()
	_fade_step(delta)


func _locomotion_input(delta: float) -> void:
	if aim_hand == null and _moves.held(Controls.input("teleport", left.tracker)):
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
		aim(aim_hand.global_transform, reach_scale(stick.y))
		_aim_clock += delta
		_aim_trail.append([_aim_clock, aim_ground, aim_lift])
		while _aim_trail.size() > 1 and _aim_trail[1][0] <= _aim_clock - RELEASE_LOOKBACK:
			_aim_trail.pop_front()
	else:
		if _turns.pressed(Controls.input("turn_left", right.tracker)):
			snap_turn(SNAP)
		if _turns.pressed(Controls.input("turn_right", right.tracker)):
			snap_turn(-SNAP)


func _end_aim() -> void:
	aim_hand = null
	_aim_clock = 0.0
	_aim_trail.clear()
	hide_markers()


## The fraction of the way to the ray's full target that a forward stick deflection of `y` reaches.
static func reach_scale(y: float) -> float:
	return lerpf(NEAREST, 1.0, clampf((y - DEADZONE) / (FULL_STICK - DEADZONE), 0.0, 1.0))


## Cast the teleport ray from a pointing pose. Its full target is the first solid thing it hits, the ground, a roof
## of any pitch, a wall's top or a tree, where the player then stands; or, aimed above the horizon with nothing within
## AIR_REACH, the point in the air at that reach. The target lies `fraction` of the way there along the ray, in the
## air above the floor short of a hit.
func aim(from: Transform3D, fraction := 1.0) -> void:
	var origin := from.origin
	var dir := -from.basis.z.normalized()
	var upward := dir.y > 0.0
	var reach := AIR_REACH if upward else MAX_REACH
	var hit: Variant = Terrain.raycast(origin, dir, reach)
	var solid: Variant = solid_hit.call(origin, dir, reach if hit == null else origin.distance_to(hit))
	if solid != null:
		hit = solid
	if hit == null and not upward:
		aim_ground = null
		hide_markers()
		return
	var full: Vector3 = hit if hit != null else origin + dir * reach
	var target := origin.lerp(full, fraction)
	var g: float = full.y if hit != null and fraction >= 1.0 else floor_under.call(target)
	aim_ground = Vector3(target.x, g, target.z)
	aim_lift = clampf(target.y - g, 0.0, MAX_LIFT)
	if aim_hand != null:
		aim_hand.ray(target, Color(0.85, 0.97, 1.0, 0.75))
	var g3: Vector3 = aim_ground
	_ground_ring.visible = true
	_ground_ring.global_transform = Transform3D(Basis(), g3 + Vector3.UP * 0.03)
	var lifted := aim_lift > 0.15
	_float_ring.visible = lifted
	_pole.visible = lifted
	if lifted:
		_float_ring.global_transform = Transform3D(Basis(), g3 + Vector3.UP * aim_lift)
		_pole.global_transform = Transform3D(Basis().scaled(Vector3(1, aim_lift, 1)), g3 + Vector3.UP * aim_lift * 0.5)


func hide_markers() -> void:
	left.clear_pointer()
	_ground_ring.visible = false
	_float_ring.visible = false
	_pole.visible = false


## Move so the head stands over `ground`, `lift` metres up. The rig then stays exactly there: in a headset
## any view motion the player's head did not make is uncomfortable.
func teleport(ground: Vector3, lift_m: float) -> void:
	_pending = [ground, lift_m]
	_fade_t = 0.0
	_fade.visible = true


func place(ground: Vector3, lift_m: float) -> void:
	var h := head.global_position
	global_position = Vector3(global_position.x + ground.x - h.x, ground.y + lift_m, global_position.z + ground.z - h.z)


func snap_turn(angle: float) -> void:
	var pivot := head.global_position
	var t := Transform3D(Basis(Vector3.UP, angle), Vector3.ZERO)
	global_transform = Transform3D(t.basis * global_transform.basis, pivot + t.basis * (global_position - pivot))


func _fade_step(delta: float) -> void:
	if _fade_t < 0.0:
		return
	_fade_t += delta
	var a := 1.0 - absf(_fade_t / FADE - 1.0)
	if _pending != null and _fade_t >= FADE:
		place(_pending[0], _pending[1])
		_pending = null
	_fade_mat.albedo_color = Color(0, 0, 0, clampf(a, 0.0, 1.0))
	if _fade_t >= FADE * 2.0:
		_fade_t = -1.0
		_fade.visible = false
