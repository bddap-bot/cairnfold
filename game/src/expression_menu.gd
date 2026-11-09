class_name ExpressionMenu
extends RefCounted

## The avatar's controls as leaves for Hand's ToolWheel, sharing the player's parameter state.
var player: ExpressionPlayer
## The controls of the innermost submenu open, or the top menu's.
var current: Array:
	get:
		for c in range(player.state.opened.size() - 1, -1, -1):
			if player.state.opened[c].type == "submenu":
				return player.state.opened[c].controls
		return player.state.data.get("menu", [])
## The radial or axis control open, or empty.
var puppet: Dictionary:
	get:
		var opened := player.state.opened
		return opened.back() if not opened.is_empty() and opened.back().type != "submenu" else {}
var radial_start := 0.0


func _init(expressions: ExpressionPlayer) -> void:
	player = expressions


func choose(control: Dictionary) -> void:
	player.state.activate(control)
	if control.type in ["radial", "twoAxis", "fourAxis"]:
		var axes: Array = control.get("axes", [])
		radial_start = player.state.values.get(axes[0], 0.0) if not axes.is_empty() else 0.0


## Steps the menu one level out; false at the top.
func back() -> bool:
	if player.state.opened.is_empty():
		return false
	player.state.back()
	return true


func close() -> void:
	if is_instance_valid(player):
		player.state.close()


func icon(control: Dictionary) -> Node3D:
	var out := Node3D.new()
	var index := int(control.get("icon", -1))
	if index >= 0 and index < player.icons.size() and player.icons[index] != null:
		var picture := MeshInstance3D.new()
		var plane := QuadMesh.new()
		plane.size = Vector2.ONE * 0.045
		picture.mesh = plane
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = player.icons[index]
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		picture.material_override = mat
		out.add_child(picture)
	else:
		out.add_child(_ring(0.009, 0.016, Color(0.25, 0.4, 0.48)))
	if control.type in ["toggle", "button"]:
		var on := MeshInstance3D.new()
		on.name = "On"
		on.mesh = ToolModels.sphere(0.004, 0.008)
		on.position = Vector3(0.025, 0.025, 0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.1, 0.65, 0.2)
		on.material_override = mat
		on.visible = player.state.active(control)
		out.add_child(on)
	var label := Label3D.new()
	label.text = control.get("name", "")
	label.font_size = 32
	label.pixel_size = 0.00018
	label.position.y = -0.028
	label.no_depth_test = false
	out.add_child(label)
	return out


static func reset_icon() -> Node3D:
	var out := Node3D.new()
	var ring := _ring(0.012, 0.018, Color(0.85, 0.55, 0.2))
	var mat: StandardMaterial3D = ring.material_override
	out.add_child(ring)
	var head := MeshInstance3D.new()
	var arrow := PrismMesh.new()
	arrow.size = Vector3(0.014, 0.012, 0.006)
	head.mesh = arrow
	head.position = Vector3(0, 0.015, 0)
	head.rotation.z = -PI / 2
	head.material_override = mat
	out.add_child(head)
	return out


static func _ring(inner: float, outer: float, colour: Color) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var shape := TorusMesh.new()
	shape.inner_radius = inner
	shape.outer_radius = outer
	shape.rings = 16
	shape.ring_segments = 8
	ring.mesh = shape
	ring.rotation.x = PI / 2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	ring.material_override = mat
	return ring
