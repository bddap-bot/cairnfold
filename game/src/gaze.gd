class_name Gaze
extends XRController3D

## `look`, in the head's frame (-Z ahead), is where the avatar points its eyes for everyone who sees it. The marker
## is a debug aid for the driver's "gaze" step, built only when first shown.

const GLANCE := deg_to_rad(30.0)
const FACE_NEAR := 4.0
## Seconds of lost tracking held as a blink.
const BLINK := 0.4
## Closing rate, plus HZ_PER_RAD per radian of lag: steady against tracking noise, yet a jump lands in a few frames.
const STEADY_HZ := 3.0
const HZ_PER_RAD := 20.0

var look := Vector3.FORWARD
var _aim := Vector3.FORWARD
var _untracked := INF
var _marker: Node3D


func _init() -> void:
	tracker = &"/user/eyes_ext"
	pose = &"default"


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


## `faces` in world space; the result in the head's frame.
static func glance(head: Transform3D, faces: Array[Vector3]) -> Vector3:
	var best := FACE_NEAR
	var to := Vector3.FORWARD
	for f in faces:
		var d := head.affine_inverse() * f
		if d.length() < best and d.angle_to(Vector3.FORWARD) < GLANCE:
			best = d.length()
			to = d.normalized()
	return to


static func steady(from: Vector3, to: Vector3, delta: float) -> Vector3:
	var hz := STEADY_HZ + HZ_PER_RAD * from.angle_to(to)
	return turned(from, to, 1.0 - exp(-TAU * hz * delta))


## Not Vector3.slerp: for looks differing only by float noise it builds its axis from a denormal, non-unit cross product.
static func turned(from: Vector3, to: Vector3, w: float) -> Vector3:
	var v := from.lerp(to, w)
	return v.normalized() if v.length_squared() > 1e-6 else to


func show_marker(on: bool) -> void:
	if _marker == null:
		if not on:
			return
		_marker = _build_marker()
		add_child(_marker)
	_marker.visible = on


static func _build_marker() -> Node3D:
	var mat := Meshes.glow(Color(1.0, 0.25, 0.6), false)
	var root := Node3D.new()
	var ray := CylinderMesh.new()
	ray.top_radius = 0.002
	ray.bottom_radius = 0.002
	ray.height = 20.0
	ray.radial_segments = 4
	ToolModels.piece(root, ray, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0, -10.0)), mat)
	ToolModels.piece(root, ToolModels.sphere(0.008, 0.016), Transform3D(Basis(), Vector3(0, 0, -1.5)), mat)
	return root
