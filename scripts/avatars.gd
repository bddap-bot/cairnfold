extends SceneTree

## Writes the built-in avatars (game/avatars/*.vrm): run from game/ as
## godot4 --headless --path . --script ../scripts/avatars.gd
## Each is a VRM 1.0 humanoid in T-pose facing +Z with a floating head, mittens and a small smock;
## surfaces whose material name starts with "tint" take the player's colour.

const STONE := Color(0.78, 0.74, 0.66)
const DARK := Color(0.12, 0.1, 0.09)
const BARK := Color(0.42, 0.29, 0.17)


func _init() -> void:
	for a in [_pebble(), _acorn(), _hood()]:
		Vrm.write(a, "res://avatars/%s.vrm" % a.name)
		print("avatars: ", a.name)
		a.free()
	quit()


func _pebble() -> Node3D:
	var root := _skeleton("pebble")
	var head: Node3D = root.find_child("head", true, false)
	_part(head, Meshes.rounded_box(0.45, 3, 11), _tint(), Vector3(0, 0.12, 0), Vector3(0.24, 0.22, 0.22))
	_eyes(head, DARK, 0.12)
	_mittens(root, _tint())
	_smock(root, _mat(STONE))
	return root


func _acorn() -> Node3D:
	var root := _skeleton("acorn")
	var head: Node3D = root.find_child("head", true, false)
	_part(head, _sphere(0.11, 10, 6), _mat(STONE), Vector3(0, 0.11, 0), Vector3(1, 1.1, 1))
	var cap := _sphere(0.125, 10, 6, true)
	_part(head, cap, _tint(), Vector3(0, 0.14, 0), Vector3(1, 0.7, 1))
	_part(head, _cylinder(0.012, 0.02, 0.05, 5), _mat(BARK), Vector3(0, 0.25, 0), Vector3.ONE)
	_eyes(head, DARK, 0.1)
	_mittens(root, _mat(STONE))
	_smock(root, _tint())
	return root


func _hood() -> Node3D:
	var root := _skeleton("hood")
	var head: Node3D = root.find_child("head", true, false)
	_part(head, _cylinder(0.0, 0.15, 0.36, 10), _tint(), Vector3(0, 0.2, -0.02), Vector3(1, 1, 0.95))
	_part(head, _sphere(0.1, 10, 6), _mat(DARK), Vector3(0, 0.1, 0.04), Vector3(1, 0.9, 0.8))
	_eyes(head, Color(0.98, 0.9, 0.6), 0.1)
	_mittens(root, _tint())
	_smock(root, _tint())
	return root


## The VRM bone hierarchy in T-pose, eyes 1.65 m up.
func _skeleton(name: String) -> Node3D:
	var root := Node3D.new()
	root.name = name
	root.set_meta("eyes", Vector3(0, 0.12, 0.09))
	var hips := _bone(root, "hips", Vector3(0, 0.95, 0))
	var spine := _bone(hips, "spine", Vector3(0, 0.2, 0))
	_bone(spine, "head", Vector3(0, 0.38, 0))
	for side in [["left", 1.0], ["right", -1.0]]:
		var upper := _bone(spine, side[0] + "UpperArm", Vector3(0.18 * side[1], 0.25, 0))
		var lower := _bone(upper, side[0] + "LowerArm", Vector3(0.27 * side[1], 0, 0))
		_bone(lower, side[0] + "Hand", Vector3(0.25 * side[1], 0, 0))
		var thigh := _bone(hips, side[0] + "UpperLeg", Vector3(0.1 * side[1], -0.05, 0))
		var shin := _bone(thigh, side[0] + "LowerLeg", Vector3(0, -0.42, 0))
		_bone(shin, side[0] + "Foot", Vector3(0, -0.4, 0))
	return root


func _bone(parent: Node3D, name: String, at: Vector3) -> Node3D:
	var b := Node3D.new()
	b.name = name
	b.position = at
	parent.add_child(b)
	return b


func _eyes(head: Node3D, colour: Color, height: float) -> void:
	for x in [-0.045, 0.045]:
		_part(head, _sphere(0.018, 6, 4), _mat(colour), Vector3(x, height, 0.1), Vector3(1, 1.3, 0.6))


## Mittens point along +Z, the way the hands are held when the avatar faces forward.
func _mittens(root: Node3D, mat: Material) -> void:
	for side in ["leftHand", "rightHand"]:
		var hand: Node3D = root.find_child(side, true, false)
		_part(hand, Meshes.rounded_box(0.45, 2, 5), mat, Vector3(0, -0.01, -0.03), Vector3(0.07, 0.05, 0.11))


func _smock(root: Node3D, mat: Material) -> void:
	_part(root.find_child("spine", true, false), _cylinder(0.11, 0.2, 0.5, 10), mat, Vector3(0, -0.02, 0), Vector3(1, 1, 0.8))


func _part(bone: Node3D, mesh: Mesh, mat: Material, at: Vector3, size: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "%s_%d" % [bone.name, bone.get_child_count()]
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(0))
	am.surface_set_material(0, mat)
	mi.mesh = am
	mi.position = at
	mi.scale = size
	bone.add_child(mi)


func _sphere(r: float, segs: int, rings: int, half := false) -> Mesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = segs
	m.rings = rings
	m.is_hemisphere = half
	return m


func _cylinder(top: float, bottom: float, h: float, segs: int) -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = segs
	m.rings = 1
	return m


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	return m


func _tint() -> StandardMaterial3D:
	var m := _mat(Color(0.8, 0.5, 0.35))
	m.resource_name = "tint"
	return m
