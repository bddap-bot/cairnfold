class_name ToolModels
extends RefCounted

## The small objects that stand for each tool on a controller: miniatures of what the tool makes,
## built from the same generators and meshes as the full-size things, standing on y = 0. The meadow's
## plant shaders lift each instance by the terrain under it, so these carry plain materials of their own.

static var _mats := {}


static func build(tool: Hand.Tool) -> Node3D:
	var root := Node3D.new()
	match tool:
		Hand.Tool.WALLS:
			_wall(root)
		Hand.Tool.FLOWERS:
			_flowers(root)
		Hand.Tool.GRASS:
			_grass(root)
		Hand.Tool.TREES:
			_tree(root)
		Hand.Tool.TERRAIN:
			_mound(root)
		Hand.Tool.TELEPORT:
			_teleport(root)
		Hand.Tool.DELETE:
			_spade(root)
	return root


static func _wall(root: Node3D) -> void:
	var layout := WallLayout.new()
	layout.seed = 4
	layout.height = 1.5
	layout.points = [Vector3(0, 0, -1.4), Vector3(0, 0, 1.4)]
	layout.build(func(_x: float, _z: float) -> float: return 0.0)
	var meshes := Wall.stone_meshes()
	var buckets: Array[Array] = [[], [], []]
	for s in layout.stones:
		buckets[s.variant].append(s)
	for v in meshes.size():
		var mm := _multimesh(meshes[v], buckets[v].size(), true)
		for i in buckets[v].size():
			mm.set_instance_transform(i, buckets[v][i].xform)
			mm.set_instance_color(i, buckets[v][i].color)
			mm.set_instance_custom_data(i, Color(buckets[v][i].ao, 0, 0, 0))
		_add(root, mm, Wall.shared_material(), 0.015)


static func _flowers(root: Node3D) -> void:
	var mm := _multimesh(Meshes.flower(6), 3, false)
	var spots := [Vector3(0, 0, 0), Vector3(0.09, 0, 0.05), Vector3(-0.07, 0, 0.07)]
	var sizes := [1.15, 0.8, 0.9]
	for i in 3:
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, i * 1.3).scaled(Vector3.ONE * sizes[i]), spots[i]))
		mm.set_instance_color(i, FloraLayout.FLOWER_COLORS[[2, 1, 0][i]])
	_add(root, mm, _vertex_mat("flower", 0.8, true), 0.17)


static func _grass(root: Node3D) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.grass_clump(16, 3)
	mi.scale = Vector3.ONE * 0.16
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat: StandardMaterial3D = _mats.get("grass")
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.36, 0.6, 0.16)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.roughness = 0.9
		_mats["grass"] = mat
	mi.material_override = mat
	root.add_child(mi)


static func _tree(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var t := FloraLayout.tree(Vector3(0, 0.2, 0), rng)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.16
	trunk.bottom_radius = 0.3
	trunk.height = 1.0
	trunk.radial_segments = 8
	trunk.rings = 1
	var bark: StandardMaterial3D = _mats.get("bark")
	if bark == null:
		bark = StandardMaterial3D.new()
		bark.albedo_color = Color(0.36, 0.27, 0.2)
		bark.roughness = 1.0
		_mats["bark"] = bark
	var trunk_mm := _multimesh(trunk, 1, false)
	trunk_mm.set_instance_transform(0, t.trunk)
	trunk_mm.set_instance_color(0, Color.WHITE)
	var scale := 0.006
	_add(root, trunk_mm, bark, scale)
	var blobs := _multimesh(Meshes.blob(4), t.blobs.size(), false)
	for i in t.blobs.size():
		blobs.set_instance_transform(i, t.blobs[i][0])
		blobs.set_instance_color(i, t.blobs[i][1])
	var leaf := _vertex_mat("leaf", 1.0, false)
	leaf.backlight_enabled = true
	leaf.backlight = Color(0.25, 0.35, 0.08)
	_add(root, blobs, leaf, scale)


## A round grassy hill on a rim of earth, raised by the same bell the terrain tool pulls.
static func _mound(root: Node3D) -> void:
	var r := 0.028
	var rings := 6
	var sides := 20
	var low := Color(0.2, 0.4, 0.1)
	var high := Color(0.36, 0.56, 0.15)
	var earth := Color(0.4, 0.3, 0.2)
	var base := 0.005
	var rise := 0.022
	var at := func(k: int, a: int) -> Vector3:
		var t := float(k) / rings
		var ang := TAU * a / sides
		return Vector3(cos(ang) * r * t, base + rise * Terrain.bell(t * 0.92), sin(ang) * r * t)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in rings:
		for a in sides:
			var q: Array[Vector3] = [at.call(k, a), at.call(k + 1, a), at.call(k, a + 1), at.call(k + 1, a + 1)]
			for v in [q[0], q[2], q[1], q[1], q[2], q[3]]:
				st.set_color(low.lerp(high, (v.y - base) / rise))
				st.add_vertex(v)
	for a in sides:
		var p: Vector3 = at.call(rings, a)
		var n: Vector3 = at.call(rings, a + 1)
		for v in [p, n, Vector3(p.x, 0, p.z), Vector3(p.x, 0, p.z), n, Vector3(n.x, 0, n.z)]:
			st.set_color(earth)
			st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _vertex_mat("mound", 1.0, true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## A ring on a pole over a ring on the ground: the air-teleport marker in small.
static func _teleport(root: Node3D) -> void:
	var glow: StandardMaterial3D = _mats.get("glow")
	if glow == null:
		glow = StandardMaterial3D.new()
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.albedo_color = Color(0.8, 0.95, 1.0)
		_mats["glow"] = glow
	var ring := TorusMesh.new()
	ring.inner_radius = 0.012
	ring.outer_radius = 0.016
	ring.rings = 20
	ring.ring_segments = 6
	var pole := CylinderMesh.new()
	pole.top_radius = 0.0016
	pole.bottom_radius = 0.0016
	pole.height = 0.03
	pole.radial_segments = 6
	pole.rings = 1
	for part in [[ring, 0.002], [pole, 0.017], [ring, 0.034]]:
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.position.y = part[1]
		mi.material_override = glow
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


## A garden spade, blade down: it digs things up.
static func _spade(root: Node3D) -> void:
	var steel: StandardMaterial3D = _mats.get("steel")
	if steel == null:
		steel = StandardMaterial3D.new()
		steel.albedo_color = Color(0.62, 0.64, 0.66)
		steel.metallic = 0.6
		steel.roughness = 0.4
		_mats["steel"] = steel
		var wood := StandardMaterial3D.new()
		wood.albedo_color = Color(0.55, 0.38, 0.22)
		wood.roughness = 0.9
		_mats["wood"] = wood
	var tilt := Node3D.new()
	tilt.rotation = Vector3(0, 0.6, -0.35)
	root.add_child(tilt)
	var blade := BoxMesh.new()
	blade.size = Vector3(0.02, 0.022, 0.003)
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.0022
	shaft.bottom_radius = 0.0022
	shaft.height = 0.026
	shaft.radial_segments = 6
	shaft.rings = 1
	var grip := CylinderMesh.new()
	grip.top_radius = 0.002
	grip.bottom_radius = 0.002
	grip.height = 0.012
	grip.radial_segments = 6
	grip.rings = 1
	for part in [[blade, Vector3(0, 0.011, 0), Vector3.ZERO, "steel"], [shaft, Vector3(0, 0.035, 0), Vector3.ZERO, "wood"], [grip, Vector3(0, 0.049, 0), Vector3(0, 0, PI / 2), "wood"]]:
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.position = part[1]
		mi.rotation = part[2]
		mi.material_override = _mats[part[3]]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tilt.add_child(mi)


static func _multimesh(mesh: Mesh, count: int, custom: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = custom
	mm.mesh = mesh
	mm.instance_count = count
	return mm


static func _add(root: Node3D, mm: MultiMesh, mat: Material, scale: float) -> void:
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.scale = Vector3.ONE * scale
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)


static func _vertex_mat(key: String, roughness: float, two_sided: bool) -> StandardMaterial3D:
	var mat: StandardMaterial3D = _mats.get(key)
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = roughness
		if two_sided:
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats[key] = mat
	return mat
