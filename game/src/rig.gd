class_name Rig
extends XROrigin3D

## The player: head, two hands, and locomotion by teleport — onto the ground or into the air to float.
## A hand holding the teleport tool aims with its trigger; the left stick pushed forward aims from the
## left hand whatever it holds, so no choice of tools leaves the player unable to move.

const MAX_REACH := 80.0
const AIR_REACH := 10.0
const REACH_RATE := 12.0
const MIN_AIR_REACH := 2.0
const MAX_AIR_REACH := 40.0
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
var air_reach := AIR_REACH
var aim_ground: Variant = null
var aim_lift := 0.0
var _turned := false
var _fade_t := -1.0
var _pending: Variant = null

var _ground_ring: MeshInstance3D
var _float_ring: MeshInstance3D
var _pole: MeshInstance3D
var _fade: MeshInstance3D
var _fade_mat: StandardMaterial3D


func _init() -> void:
	head = XRCamera3D.new()
	head.position = Vector3(0, 1.65, 0)
	head.near = 0.05
	head.far = 400.0
	add_child(head)
	gaze = Gaze.new()
	add_child(gaze)
	left = Hand.new("left_hand", Hand.Tool.FLOWERS)
	right = Hand.new("right_hand", Hand.Tool.WALLS)
	hands = [left, right]
	for h in hands:
		add_child(h)
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
	_fade_step(delta)


func _locomotion_input(delta: float) -> void:
	if aim_hand == null and left.stick().y > 0.65:
		aim_hand = left
	if aim_hand != null and aim_hand.picking:
		aim_hand = null
		hide_markers()
	if aim_hand != null:
		var rstick := right.stick()
		if absf(rstick.y) > 0.25:
			air_reach = clampf(air_reach + signf(rstick.y) * (absf(rstick.y) - 0.25) / 0.75 * REACH_RATE * delta, MIN_AIR_REACH, MAX_AIR_REACH)
		aim(aim_hand.global_transform)
		if left.stick().length() < 0.3:
			if aim_ground != null:
				teleport(aim_ground, aim_lift)
			aim_hand = null
			hide_markers()
	else:
		var x := right.stick().x
		if absf(x) > 0.7:
			if not _turned:
				snap_turn(-signf(x) * SNAP)
			_turned = true
		elif absf(x) < 0.3:
			_turned = false


## Cast the teleport ray from a pointing pose. It lands on the ground it hits; aimed above the horizon with no ground within `air_reach`, it targets the point in the air at that reach.
func aim(from: Transform3D) -> void:
	var origin := from.origin
	var dir := -from.basis.z.normalized()
	var upward := dir.y > 0.0
	var reach := air_reach if upward else MAX_REACH
	var hit: Variant = Terrain.raycast(origin, dir, reach)
	var target: Vector3
	if hit != null:
		target = hit
	elif upward:
		target = origin + dir * reach
	else:
		aim_ground = null
		hide_markers()
		return
	var g := Terrain.height_at(target.x, target.z)
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
