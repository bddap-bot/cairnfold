class_name ToolModels
extends RefCounted

## The small objects that stand for each tool on a controller: miniatures of what the tool makes,
## built from the same generators and meshes as the full-size things, standing on y = 0. The meadow's
## plant shaders lift each instance by the terrain under it, so these carry plain materials of their own.

## The camera model's lens, from the model's origin; PhotoTool takes photos from here.
const CAMERA_LENS := Vector3(0, 0.024, -0.0302)
const CAMERA_SCREEN := Vector2(0.048, 0.036)
## The parts of each fitting, by the kind its generator files them under.
const FITTING_PARTS := {
	"window": ["glass", "frame"],
	"door": ["door", "iron"],
	"lantern": ["iron"],
	"post_lantern": ["iron"],
	"flag": ["pole", "finial"],
	"chimney": ["chimney", "pot"],
}

static var _mats := {}
static var _camera_screen: StandardMaterial3D


static func build(tool: Hand.Tool) -> Node3D:
	var root := Node3D.new()
	match tool:
		Hand.Tool.WALLS, Hand.Tool.PLASTER_WALLS:
			_wall(root, tool == Hand.Tool.PLASTER_WALLS)
		Hand.Tool.HOUSE, Hand.Tool.PLASTER_HOUSE:
			_house(root, tool == Hand.Tool.PLASTER_HOUSE)
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
	if tool in [Hand.Tool.WALLS, Hand.Tool.PLASTER_WALLS, Hand.Tool.HOUSE, Hand.Tool.PLASTER_HOUSE]:
		for part in root.get_children():
			part.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.22), Vector3.ZERO) * part.transform
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
	var a := Avatar.open(Avatar.built_in(0), Session.COLOURS[0])
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


static func _wall(root: Node3D, plastered := false) -> void:
	var layout := WallLayout.new()
	layout.plaster = plastered
	layout.seed = 4
	layout.height = 1.5
	layout.points = [Vector3(-1.4, 0, 0), Vector3(1.4, 0, 0)]
	layout.build(_flat)
	_stones(root, layout.stones, 0.015)


## A cottage: stone walls with a door toward the eye under a tiled gable roof.
static func _house(root: Node3D, plastered := false) -> void:
	var layout := WallLayout.new()
	layout.plaster = plastered
	layout.seed = 7
	layout.height = 2.4
	layout.top = WallLayout.Top.CAP
	layout.closed = true
	layout.cover = WallLayout.Cover.ROOF
	layout.points = WallLayout.rectangle(Vector3(-1.6, 0, 0), Vector3(1.6, 0, 0), 2.6)
	layout.arches = [3.2 * 1.5 + 2.6]
	layout.build(_flat)
	var roof := RoofLayout.new()
	roof.seed = 7
	roof.corners = layout.points
	roof.base = layout.samples[0].y + layout.height + WallLayout.CAP
	roof.pitch = 1.8
	roof.build()
	_stones(root, layout.stones, 0.012)
	_stones(root, roof.tiles, 0.012)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in roof.gable_faces:
		st.add_vertex(p * 0.012)
	st.generate_normals()
	var plaster: StandardMaterial3D = _mats.get("plaster")
	if plaster == null:
		plaster = StandardMaterial3D.new()
		plaster.albedo_color = Color(0.8, 0.73, 0.6)
		plaster.roughness = 0.9
		plaster.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats["plaster"] = plaster
	var gables := MeshInstance3D.new()
	gables.mesh = st.commit()
	gables.material_override = plaster
	gables.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(gables)


static func _fence(root: Node3D) -> void:
	var layout := WallLayout.new()
	layout.seed = 6
	layout.fence = true
	layout.height = WallLayout.FENCE_HEIGHT
	layout.points = [Vector3(-1.2, 0, 0), Vector3(1.2, 0, 0)]
	layout.build(_flat)
	_stones(root, layout.stones, 0.021)


## A window on its own: a casement, no wall round it.
static func _windows(root: Node3D) -> void:
	var w := fitting("window")
	w.scale = Vector3.ONE * 0.05
	w.position.y = 0.025
	root.add_child(w)


## A lantern on its wall bracket beside a flag on its pole, with nothing to hang from.
static func _decor(root: Node3D) -> void:
	var flag := fitting("flag")
	flag.scale = Vector3.ONE * 0.025
	flag.position.x = -0.016
	root.add_child(flag)
	var lantern := fitting("lantern")
	lantern.scale = Vector3.ONE * 0.05
	lantern.position = Vector3(-0.006, 0.006, 0)
	lantern.rotation.y = PI * 0.5
	root.add_child(lantern)


## A fitting on its own at full size, laid by the generator that lays it on a wall or roof: a key of
## FITTING_PARTS. Its face looks along +z, and its mount is the origin: the back of a window or door
## (centred on the window, at the foot of the door), where a lantern's bracket or a flag's pole leaves the
## wall's centre line, a post lantern's foot, or where a chimney rises through the ridge.
static func fitting(what: String) -> Node3D:
	var parts: Array[Dictionary] = []
	var flames: Array[Transform3D] = []
	var cloths: Array[Dictionary] = []
	var mount := Vector3.ZERO
	if what == "chimney":
		var roof := RoofLayout.new()
		roof.corners = [Vector3(-2, 0, -1.5), Vector3(2, 0, -1.5), Vector3(2, 0, 1.5), Vector3(-2, 0, 1.5)]
		roof._lay_chimney(Vector2.ZERO, RandomNumberGenerator.new())
		parts = roof.tiles
		mount = roof.frame().mid + Vector3.UP * roof.rise(1.0)
	else:
		var layout := WallLayout.new()
		layout.seed = 5
		layout.height = 2.4
		layout.top = WallLayout.Top.CAP
		layout.fence = what == "post_lantern"
		layout.points = [Vector3(-2, 0, 0), Vector3(2, 0, 0)]
		layout.resample(_flat)
		var s := layout.nearest_post(2.0) if layout.fence else 2.0
		match what:
			"window":
				layout.windows = [Vector2(s, 1.5)]
			"door":
				layout.windows = [Vector2(s, 0.5)]
			"lantern", "post_lantern":
				layout.lanterns = [Vector3(s, 1.5, 1.0)]
			"flag":
				layout.flags = [s]
		layout.build(_flat)
		parts = layout.stones
		flames = layout.flames
		cloths = layout.cloths
		match what:
			"window", "door":
				var o := layout.openings[0]
				mount = Vector3(0, 0.0 if o.door else (o.sill + o.head) * 0.5, INF)
				for p in parts:
					if p.kind in FITTING_PARTS[what]:
						mount.z = minf(mount.z, p.xform.origin.z - p.xform.basis.z.length() * 0.5)
			"lantern":
				mount = Vector3(0, 1.5, 0)
			"post_lantern":
				mount = layout.frame_at(s).point + Vector3.UP * (WallLayout.FENCE_HEIGHT + 0.25)
			"flag":
				mount = Vector3(0, layout.height + WallLayout.CAP, 0)
	var root := Node3D.new()
	var kept: Array[Dictionary] = []
	for p in parts:
		if p.kind in FITTING_PARTS[what]:
			var q := p.duplicate()
			q.xform = Transform3D(p.xform.basis, p.xform.origin - mount)
			kept.append(q)
	var stones := Stones.new()
	stones.lay(kept)
	root.add_child(stones)
	if not flames.is_empty() or not cloths.is_empty():
		var moved_flames: Array[Transform3D] = []
		for f in flames:
			moved_flames.append(Transform3D(f.basis, f.origin - mount))
		var moved_cloths: Array[Dictionary] = []
		for c in cloths:
			moved_cloths.append({"xform": Transform3D(c.xform.basis, c.xform.origin - mount), "color": c.color})
		var lit := Fittings.new()
		lit.lay(moved_flames, moved_cloths)
		root.add_child(lit)
	for g in root.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


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
	node.lay(stones.filter(func(s: Dictionary) -> bool: return s.get("kind", "") != "plaster"))
	var panels := stones.filter(func(s: Dictionary) -> bool: return s.get("kind", "") == "plaster")
	if not panels.is_empty():
		var kind := Wall.kinds()[Wall.Part.MORTAR]
		var mi := kind.instance()
		mi.multimesh.instance_count = panels.size()
		var buffer := PackedFloat32Array()
		buffer.resize(panels.size() * kind.stride())
		for i in panels.size():
			var panel: Dictionary = panels[i]
			kind.write(buffer, i, panel.xform, panel.color, panel.ao, Palette.code("plaster"))
		mi.multimesh.buffer = buffer
		node.add_child(mi)
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
