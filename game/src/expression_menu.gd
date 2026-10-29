class_name ExpressionMenu
extends RefCounted

## The avatar's controls as leaves for Hand's ToolWheel, sharing the player's parameter state.
var player: ExpressionPlayer
var current: Array
var parents: Array = []
var puppet: Dictionary = {}
var radial_start := 0.0


func _init(expressions: ExpressionPlayer) -> void:
	player = expressions
	current = player.state.data.get("menu", [])


func choose(control: Dictionary) -> void:
	player.state.activate(control)
	if control.type == "submenu":
		parents.append(current)
		current = control.controls
	elif control.type in ["radial", "twoAxis", "fourAxis"]:
		puppet = control
		var axes: Array = control.get("axes", [])
		radial_start = player.state.values.get(axes[0], 0.0) if not axes.is_empty() else 0.0


func back() -> bool:
	player.state.back()
	if not puppet.is_empty():
		puppet = {}
	elif not parents.is_empty():
		current = parents.pop_back()
	else:
		return false
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
		var mark := MeshInstance3D.new()
		var shape := TorusMesh.new()
		shape.inner_radius = 0.009
		shape.outer_radius = 0.016
		shape.rings = 16
		shape.ring_segments = 8
		mark.mesh = shape
		mark.rotation.x = PI / 2
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.25, 0.4, 0.48)
		mark.material_override = mat
		out.add_child(mark)
	if control.type in ["toggle", "button"]:
		var on := MeshInstance3D.new()
		on.name = "On"
		var sphere := SphereMesh.new()
		sphere.radius = 0.004
		sphere.height = 0.008
		on.mesh = sphere
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
