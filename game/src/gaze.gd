class_name Gaze
extends XRController3D

## Where the eyes look (XR_EXT_eye_gaze_interaction), on runtimes that track them. The marker is a
## debug aid shown only by the driver's "gaze" step; nothing is built for it until then.

var _marker: Node3D


func _init() -> void:
	tracker = &"/user/eyes_ext"
	pose = &"default"


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
