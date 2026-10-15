class_name ToolModels
extends RefCounted

## The small objects that stand for each tool on a controller: miniatures of what the tool makes,
## built from the same generators and meshes as the full-size things, standing on y = 0. The meadow's
## plant shaders lift each instance by the terrain under it, so these carry plain materials of their own.

## The camera model's lens, from the model's origin; PhotoTool takes photos from here.
const CAMERA_LENS := Vector3(0, 0.024, -0.0302)
const CAMERA_SCREEN := Vector2(0.048, 0.036)

static var _mats := {}
static var _camera_screen: StandardMaterial3D


static func build(tool: Hand.Tool) -> Node3D:
	var root := Node3D.new()
	match tool:
		Hand.Tool.WALLS:
			_wall(root)
		Hand.Tool.FENCE:
			_fence(root)
		Hand.Tool.WINDOWS:
			_windows(root)
		Hand.Tool.DECORATIONS:
			_decor(root)
		Hand.Tool.PATH:
			_path(root)
		Hand.Tool.FLOWERS:
			_flowers(root)
		Hand.Tool.GRASS:
			_grass(root)
		Hand.Tool.TREES:
			_tree(root)
		Hand.Tool.TERRAIN:
			_mound(root)
		Hand.Tool.DELETE:
			_spade(root)
		Hand.Tool.POND:
			_pond(root)
		Hand.Tool.STONE:
			_flagstones(root)
		Hand.Tool.VISIT:
			_figure(root)
		Hand.Tool.COLOUR:
			_palette(root)
		Hand.Tool.CAMERA:
			_camera(root)
	return root


## A painter's palette: a wooden board with a dab of each roof colour round its edge.
static func _palette(root: Node3D) -> void:
	var board := CylinderMesh.new()
	board.top_radius = 0.026
	board.bottom_radius = 0.026
	board.height = 0.003
	board.radial_segments = 24
	board.rings = 1
	var dab := SphereMesh.new()
	dab.radius = 0.0055
	dab.height = 0.004
	dab.radial_segments = 10
	dab.rings = 4
	var swatches: Array = Palette.SWATCHES[Palette.Element.ROOF]
	var parts := [[board, Vector3(0, 0.0015, 0), Color(0.62, 0.46, 0.3)]]
	for i in swatches.size():
		var a := TAU * (0.12 + 0.76 * i / (swatches.size() - 1))
		parts.append([dab, Vector3(cos(a), 0, sin(a)) * 0.018 + Vector3(0, 0.0035, 0), swatches[i]])
	for part in parts:
		var key := "palette_%s" % part[2].to_html()
		var mat: StandardMaterial3D = _mats.get(key)
		if mat == null:
			mat = StandardMaterial3D.new()
			mat.albedo_color = part[2]
			mat.roughness = 0.6
			_mats[key] = mat
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.position = part[1]
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


## The screen on the back of every camera model, one material PhotoTool shows the lens's view in.
static func camera_screen() -> StandardMaterial3D:
	if _camera_screen == null:
		_camera_screen = StandardMaterial3D.new()
		_camera_screen.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _camera_screen


## A small camera, its lens along the controller's aim and its screen toward the eye.
static func _camera(root: Node3D) -> void:
	var lens := CylinderMesh.new()
	lens.top_radius = 0.012
	lens.bottom_radius = 0.013
	lens.height = 0.018
	lens.radial_segments = 16
	lens.rings = 1
	var glass := CylinderMesh.new()
	glass.top_radius = 0.009
	glass.bottom_radius = 0.009
	glass.height = 0.001
	glass.radial_segments = 16
	glass.rings = 1
	var button := CylinderMesh.new()
	button.top_radius = 0.004
	button.bottom_radius = 0.0045
	button.height = 0.004
	button.radial_segments = 10
	button.rings = 1
	var facing := Basis(Vector3.RIGHT, PI * 0.5)
	var parts := [
		[Meshes.rounded_box(0.25, 2, 41), Transform3D(Basis().scaled(Vector3(0.064, 0.046, 0.026)), Vector3(0, 0.024, 0)), Color(0.84, 0.76, 0.62)],
		[Meshes.rounded_box(0.2, 2, 42), Transform3D(Basis().scaled(Vector3(0.054, 0.042, 0.002)), Vector3(0, 0.024, 0.013)), Color(0.16, 0.14, 0.13)],
		[lens, Transform3D(facing, Vector3(0, 0.024, -0.021)), Color(0.22, 0.2, 0.19)],
		[glass, Transform3D(facing, CAMERA_LENS), Color(0.08, 0.1, 0.16)],
		[button, Transform3D(Basis(), Vector3(0.019, 0.048, 0.002)), Color(0.72, 0.56, 0.3)],
	]
	for part in parts:
		var key := "camera_%s" % part[2].to_html()
		var mat: StandardMaterial3D = _mats.get(key)
		if mat == null:
			mat = StandardMaterial3D.new()
			mat.albedo_color = part[2]
			mat.roughness = 0.35 if part[0] == glass else 0.7
			_mats[key] = mat
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.transform = part[1]
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	var quad := QuadMesh.new()
	quad.size = CAMERA_SCREEN
	var screen := MeshInstance3D.new()
	screen.mesh = quad
	screen.position = Vector3(0, 0.024, 0.0141)
	screen.material_override = camera_screen()
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(screen)


## A little person: the visit tool goes to see other players.
static func _figure(root: Node3D) -> void:
	var a := Avatar.open(Avatar.BUILT_IN[0], Session.COLOURS[0])
	a.scale = Vector3.ONE * 0.026
	root.add_child(a)
	a.stand.call_deferred()


## A disc of stone ground as the stone tool lays it: the terrain's own flagstones and colours, fraying
## toward the rim into meadow as scattered slabs.
static func _flagstones(root: Node3D) -> void:
	var turf := CylinderMesh.new()
	turf.top_radius = 0.026
	turf.bottom_radius = 0.024
	turf.height = 0.004
	turf.radial_segments = 24
	turf.rings = 1
	var face := PlaneMesh.new()
	face.size = Vector2(0.052, 0.052)
	var mat: StandardMaterial3D = _mats.get("stone_ground")
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.albedo_texture = ImageTexture.create_from_image(_stone_ground_image())
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.roughness = 1.0
		_mats["stone_ground"] = mat
		var side := StandardMaterial3D.new()
		side.albedo_color = Meadow.GROUND[&"earth"]
		side.roughness = 1.0
		_mats["stone_ground_side"] = side
	for part in [[turf, Vector3(0, 0.002, 0), _mats["stone_ground_side"]], [face, Vector3(0, 0.0041, 0), mat]]:
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.position = part[1]
		mi.material_override = part[2]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


## The terrain shader's stone-ground colouring (terrain.gdshader), baked once over a disc of flagstones.
static func _stone_ground_image() -> Image:
	const SIZE := 96
	const SPAN := 0.35
	var slabs := Look.flagstones().get_image()
	slabs.clear_mipmaps()
	var rock: Color = Meadow.GROUND[&"rock"]
	var lush: Color = Meadow.GROUND[&"meadow_lush"]
	var meadow: Color = Meadow.GROUND[&"meadow_dry"].lerp(lush, 0.5)
	var joint: Color = Meadow.GROUND[&"earth"].lerp(lush, 0.35) * 0.8
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			var r := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(SIZE, SIZE) * 0.5) / (SIZE * 0.5)
			if r > 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var slab := slabs.get_pixel(int(x * SPAN * slabs.get_width() / SIZE), int(y * SPAN * slabs.get_height() / SIZE))
			var stony := 1.0 - smoothstep(0.5, 1.0, r)
			var lit := rock * (0.8 + slab.g * 0.28) * lerpf(0.8, 1.04, smoothstep(0.03, 0.25, slab.r))
			var threshold := 0.12 + slab.g * 0.7
			var laid := smoothstep(threshold - 0.04, threshold + 0.04, stony) * smoothstep(0.02, 0.06, slab.r)
			var c := meadow.lerp(joint, smoothstep(0.4, 0.95, stony)).lerp(lit, laid)
			c.a = 1.0
			img.set_pixel(x, y, c)
	return img


## A pond in small: a sandy dish holding a disc of glinting water inside a line of foam, pebbles on its bank.
static func _pond(root: Node3D) -> void:
	var sand: StandardMaterial3D = _mats.get("sand")
	if sand == null:
		sand = StandardMaterial3D.new()
		sand.albedo_color = Color(0.62, 0.53, 0.38)
		sand.roughness = 1.0
		_mats["sand"] = sand
		var water := StandardMaterial3D.new()
		water.albedo_color = Color(0.16, 0.48, 0.52)
		water.roughness = 0.08
		water.metallic_specular = 0.7
		_mats["water"] = water
		var foam := StandardMaterial3D.new()
		foam.albedo_color = Color(0.95, 0.97, 0.94)
		foam.roughness = 0.6
		_mats["foam"] = foam
		var pebble := StandardMaterial3D.new()
		pebble.albedo_color = Color(0.6, 0.6, 0.57)
		pebble.roughness = 0.9
		_mats["pebble"] = pebble
	var dish := CylinderMesh.new()
	dish.top_radius = 0.026
	dish.bottom_radius = 0.021
	dish.height = 0.006
	dish.radial_segments = 20
	dish.rings = 1
	var disc := CylinderMesh.new()
	disc.top_radius = 0.019
	disc.bottom_radius = 0.019
	disc.height = 0.001
	disc.radial_segments = 20
	disc.rings = 1
	var ring := TorusMesh.new()
	ring.inner_radius = 0.0185
	ring.outer_radius = 0.0205
	ring.rings = 24
	ring.ring_segments = 4
	var parts := [[dish, Vector3(0, 0.003, 0), Vector3.ONE, "sand"], [disc, Vector3(0, 0.0063, 0), Vector3.ONE, "water"], [ring, Vector3(0, 0.0064, 0), Vector3(1, 0.3, 1), "foam"]]
	for k in 3:
		var a := TAU * (0.1 + k * 0.13)
		parts.append([Meshes.rounded_box(0.3, 2, 5), Vector3(cos(a), 0, sin(a)) * 0.024 + Vector3(0, 0.0068, 0), Vector3(0.005, 0.003, 0.004) * (1.0 - k * 0.15), "pebble"])
	for part in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.position = part[1]
		mi.scale = part[2]
		mi.material_override = _mats[part[3]]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


static func _wall(root: Node3D) -> void:
	var layout := WallLayout.new()
	layout.seed = 4
	layout.height = 1.5
	layout.points = [Vector3(0, 0, -1.4), Vector3(0, 0, 1.4)]
	layout.build(_flat)
	_stones(root, layout.stones, 0.015)


static func _fence(root: Node3D) -> void:
	var layout := WallLayout.new()
	layout.seed = 6
	layout.fence = true
	layout.height = WallLayout.FENCE_HEIGHT
	layout.points = [Vector3(-1.2, 0, 0), Vector3(1.2, 0, 0)]
	layout.build(_flat)
	_stones(root, layout.stones, 0.021)


## A short wall pierced by a fused pair of windows, its face toward the eye.
static func _windows(root: Node3D) -> void:
	var layout := WallLayout.new()
	layout.seed = 5
	layout.height = 2.4
	layout.top = WallLayout.Top.CAP
	layout.points = [Vector3(-1.4, 0, 0), Vector3(1.4, 0, 0)]
	layout.windows = [Vector2(1.1, 1.5), Vector2(1.7, 1.5)]
	layout.build(_flat)
	_stones(root, layout.stones, 0.015)


## A low wall flying a flag, a lantern hung on its face.
static func _decor(root: Node3D) -> void:
	var layout := WallLayout.new()
	layout.seed = 8
	layout.height = 1.5
	layout.top = WallLayout.Top.CAP
	layout.points = [Vector3(-1.1, 0, 0), Vector3(1.1, 0, 0)]
	layout.flags = [1.1]
	layout.lanterns = [Vector3(1.1, 1.0, 1.0), Vector3(1.1, 1.0, -1.0)]
	layout.build(_flat)
	_stones(root, layout.stones, 0.015)
	var fittings := Fittings.new()
	fittings.lay(layout.flames, layout.cloths)
	fittings.scale = Vector3.ONE * 0.015
	root.add_child(fittings)


static func _flat(_x: float, _z: float) -> float:
	return 0.0


## A short bend of paving.
static func _path(root: Node3D) -> void:
	var layout := PathLayout.new()
	layout.seed = 3
	for p in [Vector3(-0.3, 0, -1.6), Vector3(0.25, 0, -0.5), Vector3(-0.2, 0, 0.6), Vector3(0.3, 0, 1.6)]:
		layout.add(p, 0.62)
	layout.build()
	_stones(root, layout.stones, 0.024)


static func _stones(root: Node3D, stones: Array[Dictionary], scale: float) -> void:
	var node := Stones.new()
	node.lay(stones)
	node.scale = Vector3.ONE * scale
	for mmi in node.get_children():
		(mmi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(node)


static func _flowers(root: Node3D) -> void:
	var spots := [Vector3(0, 0, 0), Vector3(0.09, 0, 0.05), Vector3(-0.07, 0, 0.07)]
	var sizes := [1.15, 0.8, 0.9]
	for i in 3:
		var mi := MeshInstance3D.new()
		mi.mesh = Meshes.flower(6, FloraLayout.FLOWER_COLORS[[4, 7, 1][i]])
		mi.material_override = _vertex_mat("flower", 0.8, true)
		mi.transform = Transform3D(Basis(Vector3.UP, i * 1.3).scaled(Vector3.ONE * sizes[i] * 0.17), spots[i] * 0.17)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


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
	var trunk_mm := _multimesh(trunk, 1)
	trunk_mm.set_instance_transform(0, t.trunk)
	trunk_mm.set_instance_color(0, Color.WHITE)
	var scale := 0.006
	_add(root, trunk_mm, bark, scale)
	var blobs := _multimesh(Meshes.blob(4), t.blobs.size())
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


static func _multimesh(mesh: Mesh, count: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
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
