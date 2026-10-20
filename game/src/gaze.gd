class_name Gaze
extends XRController3D

## Where the eyes look (XR_EXT_eye_gaze_interaction), on runtimes that track them. The marker is a
## debug aid shown only by the driver's "gaze" step; nothing is built for it until then.
##
## `look` is where the player's avatar points its eyes, in the head's frame (-Z ahead), for everyone who sees it:
## the tracked gaze, held through a blink; untracked, ahead, or the nearest face near ahead.

## An untracked look turns to the nearest face within GLANCE of ahead and FACE_NEAR metres.
const GLANCE := deg_to_rad(30.0)
const FACE_NEAR := 4.0
## Tracking lost for less than this is a blink: the look holds.
const BLINK := 0.4
## The look closes on its aim at STEADY_HZ, which steadies tracking noise, plus HZ_PER_RAD for each radian it lags,
## so a jump lands in a few frames rather than drifting there.
const STEADY_HZ := 3.0
const HZ_PER_RAD := 20.0

var look := Vector3.FORWARD
var _aim := Vector3.FORWARD
var _untracked := INF
var _marker: Node3D


func _init() -> void:
	tracker = &"/user/eyes_ext"
	pose = &"default"


## Moves `look` toward where the eyes look now, from the head's pose and the faces of the others in view.
func follow(head: Transform3D, faces: Array[Vector3], delta: float) -> void:
	# A runtime reports a blink or lost track as a pose of low confidence, not as no pose.
	var tracked := get_has_tracking_data() and get_pose().tracking_confidence == XRPose.XR_TRACKING_CONFIDENCE_HIGH
	_untracked = 0.0 if tracked else _untracked + delta
	if _untracked == 0.0:
		var to := head.basis.inverse() * -global_basis.z
		if to.is_finite() and to.length() > 0.1:
			_aim = to.normalized()
	elif _untracked > BLINK:
		_aim = glance(head, faces)
	look = steady(look, _aim, delta)


## Ahead, or toward the nearest of `faces` within GLANCE of ahead and FACE_NEAR, in the head's frame.
static func glance(head: Transform3D, faces: Array[Vector3]) -> Vector3:
	var best := FACE_NEAR
	var to := Vector3.FORWARD
	for f in faces:
		var d := head.affine_inverse() * f
		if d.length() < best and d.angle_to(Vector3.FORWARD) < GLANCE:
			best = d.length()
			to = d.normalized()
	return to


## One frame of `from` closing on `to`.
static func steady(from: Vector3, to: Vector3, delta: float) -> Vector3:
	var hz := STEADY_HZ + HZ_PER_RAD * from.angle_to(to)
	return from.slerp(to, 1.0 - exp(-TAU * hz * delta)).normalized()


func show_marker(on: bool) -> void:
	if _marker == null:
		if not on:
			return
		_marker = _build_marker()
		add_child(_marker)
	_marker.visible = on


static func _build_marker() -> Node3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.25, 0.6)
	var root := Node3D.new()
	var ray := CylinderMesh.new()
	ray.top_radius = 0.002
	ray.bottom_radius = 0.002
	ray.height = 20.0
	ray.radial_segments = 4
	var dot := SphereMesh.new()
	dot.radius = 0.008
	dot.height = 0.016
	for part in [[ray, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0, -10.0))], [dot, Transform3D(Basis(), Vector3(0, 0, -1.5))]]:
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.material_override = mat
		mi.transform = part[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return root
