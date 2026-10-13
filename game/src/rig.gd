class_name Rig
extends XROrigin3D

## The player: head, two hands, and locomotion by teleport — onto the ground or into the air to float.

const MAX_REACH := 80.0
const AIR_REACH := 10.0
const REACH_RATE := 12.0
const MIN_AIR_REACH := 2.0
const MAX_AIR_REACH := 40.0
const MAX_LIFT := 40.0
const ARRIVE_LIFT := 0.45
const SNAP := deg_to_rad(30.0)
const FADE := 0.09

var head: XRCamera3D
var left: XRController3D
var right: XRController3D

var floating := false
var aiming := false
var air_reach := AIR_REACH
var aim_ground: Variant = null
var aim_lift := 0.0
var _rest_y := 0.0
var _vel_y := 0.0
var _bob := 0.0
var _turned := false
var _descend_held := false
var _fade_t := -1.0
var _pending: Variant = null

var _beam: MeshInstance3D
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
	left = _hand("left_hand")
	right = _hand("right_hand")
	_build_markers()


func _hand(tracker: String) -> XRController3D:
	var c := XRController3D.new()
	c.tracker = tracker
	c.pose = &"aim"
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.rounded_box(0.3, 2, 7)
	mi.scale = Vector3(0.05, 0.035, 0.11)
	mi.position = Vector3(0, -0.01, 0.04)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.93, 0.9, 0.84)
	mat.roughness = 0.6
	mi.material_override = mat
	c.add_child(mi)
	add_child(c)
	return c


func _build_markers() -> void:
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.albedo_color = Color(0.85, 0.97, 1.0, 0.75)
	glow.no_depth_test = false
	_beam = MeshInstance3D.new()
	_beam.mesh = ImmediateMesh.new()
	_beam.material_override = glow
	_beam.top_level = true
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)
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


func ground_under_head() -> float:
	var h := head.global_position
	return Terrain.height_at(h.x, h.z)


## Lift above the ground of where the player is standing or hovering.
func lift() -> float:
	return global_position.y - ground_under_head()


func _process(delta: float) -> void:
	_locomotion_input(delta)
	_hover(delta)
	_fade_step(delta)


func _locomotion_input(delta: float) -> void:
	var stick := left.get_vector2("primary")
	var rstick := right.get_vector2("primary")
	if not aiming and stick.y > 0.65:
		aiming = true
	if aiming:
		if absf(rstick.y) > 0.25:
			air_reach = clampf(air_reach + signf(rstick.y) * (absf(rstick.y) - 0.25) / 0.75 * REACH_RATE * delta, MIN_AIR_REACH, MAX_AIR_REACH)
		aim(left.global_transform)
		if stick.length() < 0.3:
			aiming = false
			if aim_ground != null:
				teleport(aim_ground, aim_lift)
			hide_markers()
	elif absf(rstick.x) > 0.7:
		if not _turned:
			snap_turn(-signf(rstick.x) * SNAP)
		_turned = true
	elif absf(rstick.x) < 0.3:
		_turned = false
	var descend := left.is_button_pressed("by_button")
	if descend and not _descend_held and floating:
		settle_down()
	_descend_held = descend


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
	_draw_beam(origin, target)
	var g3: Vector3 = aim_ground
	_ground_ring.visible = true
	_ground_ring.global_transform = Transform3D(Basis(), g3 + Vector3.UP * 0.03)
	var lifted := aim_lift > 0.15
	_float_ring.visible = lifted
	_pole.visible = lifted
	if lifted:
		_float_ring.global_transform = Transform3D(Basis(), g3 + Vector3.UP * aim_lift)
		_pole.global_transform = Transform3D(Basis().scaled(Vector3(1, aim_lift, 1)), g3 + Vector3.UP * aim_lift * 0.5)


func _draw_beam(a: Vector3, b: Vector3) -> void:
	var im: ImmediateMesh = _beam.mesh
	im.clear_surfaces()
	var side := (b - a).cross(head.global_position - a).normalized() * 0.012
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for p in [a, b]:
		im.surface_add_vertex(p - side)
		im.surface_add_vertex(p + side)
	im.surface_end()


func hide_markers() -> void:
	(_beam.mesh as ImmediateMesh).clear_surfaces()
	_ground_ring.visible = false
	_float_ring.visible = false
	_pole.visible = false


## Move so the head stands over `ground`, `lift` metres up; any lift above a hand's breadth floats.
func teleport(ground: Vector3, lift_m: float) -> void:
	_pending = [ground, lift_m]
	_fade_t = 0.0
	_fade.visible = true


func place(ground: Vector3, lift_m: float) -> void:
	var h := head.global_position
	global_position += Vector3(ground.x - h.x, 0, ground.z - h.z)
	_rest_y = ground.y + lift_m
	floating = lift_m > 0.15
	_vel_y = 0.0
	_bob = 0.0
	global_position.y = _rest_y + (ARRIVE_LIFT if floating else 0.0)


func settle_down() -> void:
	floating = false
	_rest_y = ground_under_head()


func snap_turn(angle: float) -> void:
	var pivot := head.global_position
	var t := Transform3D(Basis(Vector3.UP, angle), Vector3.ZERO)
	global_transform = Transform3D(t.basis * global_transform.basis, pivot + t.basis * (global_position - pivot))


func _hover(delta: float) -> void:
	if not floating and _rest_y == global_position.y and _vel_y == 0.0:
		return
	var target := _rest_y
	if floating:
		_bob += delta
		target += sin(_bob * TAU / 4.5) * 0.025 * smoothstep(1.5, 3.0, _bob)
	var k := 6.0 if floating else 9.0
	var damping := 2.0 * sqrt(k) * (0.75 if floating else 1.0)
	_vel_y += (k * (target - global_position.y) - damping * _vel_y) * delta
	global_position.y += _vel_y * delta
	if not floating and absf(global_position.y - target) < 0.002 and absf(_vel_y) < 0.01:
		global_position.y = target
		_vel_y = 0.0


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
