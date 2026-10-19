class_name ToolModels
extends RefCounted

## The small objects that stand for each tool on a controller: miniatures of what the tool makes,
## built from the same generators and meshes as the full-size things, standing on y = 0. Their stones are
## the far stone: a few millimetres across, the full one's triangles cost the Frame milliseconds for nothing. The meadow's
## plant shaders lift each instance by the terrain under it, so these carry plain materials of their own.

## The camera model's lens, from the model's origin; PhotoTool takes photos from here.
const CAMERA_LENS := Vector3(0, 0.024, -0.0302)
const CAMERA_SCREEN := Vector2(0.048, 0.036)
## Where a brush's tip is, from the controller it is held in: it reaches past the controller, so painting is done
## with the brush, not the hand.
const BRUSH_TIP := Vector3(0, 0.01, -0.27)
## The parts of each fitting, by the kind its generator files them under.
const FITTING_PARTS := {
	"window": ["glass", "frame"],
	"lantern": ["iron"],
	"post_lantern": ["iron"],
	"flag": ["pole", "finial"],
	"chimney": ["chimney", "pot"],
}

const SEED_COLOURS: Array[Color] = [Color(0.93, 0.8, 0.5), Color(0.12, 0.11, 0.1), Color(0.2, 0.19, 0.17)]

static var _mats := {}
static var _stars := {}
static var _camera_screen: StandardMaterial3D


static func build(tool: Hand.Tool) -> Node3D:
	var root := Node3D.new()
	match tool:
		Hand.Tool.WALLS:
			_wall(root)
		Hand.Tool.HOUSE:
			_house(root)
		Hand.Tool.FENCE:
			_fence(root)
		Hand.Tool.WINDOWS:
			_windows(root)
		Hand.Tool.DECORATIONS:
			_decor(root)
		Hand.Tool.STAIRS:
			var layout := StairLayout.new()
			layout.build({"a": Vector3.ZERO, "b": Vector3(0, 0.8, -1.5), "width": 1.2, "rail": "wood", "seed": 1})
			var stones := Stones.new()
			stones.lay(layout.stones)
			stones.scale = Vector3.ONE * 0.035
			root.add_child(stones)
		Hand.Tool.PATH:
			_path(root)
		Hand.Tool.DIRT_PATH:
			_path(root, true)
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
		Hand.Tool.STYLE:
			_wand(root)
		Hand.Tool.CAMERA:
			_camera(root)
		Hand.Tool.HANDS:
			_open_hand(root)
		Hand.Tool.SEEDS:
			_seeds(root)
		Hand.Tool.EASEL:
			_easel(root)
	if tool in [Hand.Tool.WALLS, Hand.Tool.HOUSE]:
		for part in root.get_children():
			part.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.22), Vector3.ZERO) * part.transform
	return root


## A miniature of choice `i` of a style the style tool sets (`PaletteTool.styles`), a build's in stone or plaster;
## a gable end's turned to face the eye.
static func style(restyle: PaletteTool.Restyle, i: int, plastered: bool) -> Node3D:
	var root := Node3D.new()
	if restyle == PaletteTool.Restyle.TREE:
		_tree(root, i as FloraLayout.Species)
		for part in root.get_children():
			part.scale *= 1.8
		return root
	match restyle:
		PaletteTool.Restyle.GABLE:
			_house(root, plastered, i as WallLayout.GableEnd)
		PaletteTool.Restyle.ROOF:
			var thatched: bool = i in [WallTool.RoofStyle.THATCHED, WallTool.RoofStyle.THATCHED_CONE]
			if i in [WallTool.RoofStyle.CONE, WallTool.RoofStyle.THATCHED_CONE]:
				_tower(root, plastered, thatched)
			else:
				_house(root, plastered, WallLayout.GableEnd.WALL, i == WallTool.RoofStyle.FLAT, 0, thatched)
		PaletteTool.Restyle.TOP:
			_wall(root, plastered, i as WallLayout.Top)
		PaletteTool.Restyle.FACE:
			if i >= PaletteTool.Face.ALSACE:
				_house(root, true, WallLayout.GableEnd.WALL, false, i - PaletteTool.Face.ALSACE)
			else:
				_wall(root, i >= PaletteTool.Face.PLASTER, WallLayout.Top.CAP, i % 2 == 1)
	var turn := Basis(Vector3.UP, PI * 0.38) if restyle == PaletteTool.Restyle.GABLE else Basis()
	for part in root.get_children():
		part.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.22) * turn, Vector3.ZERO) * part.transform
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


## A wand lying flat with a star at its tip and two sparkles off it: it turns what it points at into another
## of its kind, and it is no build, so the icon cannot read as a thing it builds.
static func _wand(root: Node3D) -> void:
	var along := Vector3(1, 0, -1).normalized()
	var stick := CylinderMesh.new()
	stick.top_radius = 0.0022
	stick.bottom_radius = 0.003
	stick.height = 0.042
	stick.radial_segments = 8
	stick.rings = 1
	_piece(root, stick, Transform3D(Basis(Quaternion(Vector3.UP, along)), along * -0.004 + Vector3(0, 0.0025, 0)), _plain("wand", Color(0.32, 0.2, 0.13)))
	var gold := _plain("star", Color(1.0, 0.82, 0.3))
	_piece(root, _star(5, 0.012, 0.005), Transform3D(Basis(), along * 0.019 + Vector3(0, 0.003, 0)), gold)
	for spark in [[Vector3(0.02, 0.003, 0.007), 0.004], [Vector3(-0.002, 0.003, -0.029), 0.003]]:
		_piece(root, _star(4, spark[1], spark[1] * 0.35), Transform3D(Basis(), spark[0]), gold)


## A flat star of `points` points, `outer` to their tips and `inner` to the notches between, 3 mm thick.
static func _star(points: int, outer: float, inner: float) -> ArrayMesh:
	var key := "%d_%s_%s" % [points, outer, inner]
	if _stars.has(key):
		return _stars[key]
	var rim: Array[Vector3] = []
	for i in points * 2:
		var a := PI * i / points
		rim.append(Vector3(sin(a), 0, -cos(a)) * (outer if i % 2 == 0 else inner))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var up := Vector3(0, 0.0015, 0)
	for i in rim.size():
		var a := rim[i]
		var b := rim[(i + 1) % rim.size()]
		for tri in [[up, a + up, b + up], [-up, b - up, a - up], [a + up, b - up, b + up], [a + up, a - up, b - up]]:
			for v in tri:
				st.add_vertex(v)
	st.generate_normals()
	var mesh := st.commit()
	_stars[key] = mesh
	return mesh


## A little easel holding a painted canvas.
static func _easel(root: Node3D) -> void:
	var wood := _plain("easel_wood", Color(0.62, 0.45, 0.3))
	var leg := BoxMesh.new()
	leg.size = Vector3(0.003, 0.06, 0.003)
	for x in [-0.014, 0.014]:
		var mi := _piece(root, leg, Transform3D(Basis(Vector3.BACK, -x * 9.0), Vector3(x, 0.028, 0.004)), wood)
		mi.rotate_x(-0.2)
	var canvas := BoxMesh.new()
	canvas.size = Vector3(0.04, 0.03, 0.002)
	var tilt := Basis(Vector3.RIGHT, -0.17)
	_piece(root, canvas, Transform3D(tilt, Vector3(0, 0.036, 0.0)), _plain("easel_canvas", Color(0.95, 0.93, 0.88)))
	var dab := SphereMesh.new()
	dab.radius = 0.006
	dab.height = 0.002
	dab.radial_segments = 10
	dab.rings = 3
	for d in [[Vector3(-0.009, 0.042, 0.0), 5], [Vector3(0.007, 0.037, 0.0), 1], [Vector3(-0.002, 0.029, 0.0), 6], [Vector3(0.011, 0.028, 0.0), 4]]:
		_piece(root, dab, Transform3D(tilt.scaled(Vector3(1, 1, 0.5)), tilt * (d[0] - Vector3(0, 0.036, 0)) + Vector3(0, 0.036, 0.0015)), _plain("easel_dab%d" % d[1], Brushwork.PIGMENTS[d[1]]))


## A brush of `kind` along the controller's aim, its tip at BRUSH_TIP; its bristles are the child named "tip", for
## the paint on it. The stick is charcoal in a holder.
static func brush(kind: Brushwork.Brush) -> Node3D:
	var root := Node3D.new()
	var handle := CylinderMesh.new()
	handle.top_radius = 0.005
	handle.bottom_radius = 0.0035
	handle.height = 0.2
	handle.radial_segments = 10
	handle.rings = 1
	var along := Basis(Vector3.RIGHT, -PI * 0.5)
	var tip_z := BRUSH_TIP.z
	var stick := kind == Brushwork.Brush.STICK
	_piece(root, handle, Transform3D(along, Vector3(0, BRUSH_TIP.y, tip_z + 0.155)), _plain("brush_handle" if not stick else "holder", Color(0.75, 0.28, 0.2) if not stick else Color(0.3, 0.27, 0.25)))
	var ferrule := CylinderMesh.new()
	ferrule.top_radius = 0.0045 if kind == Brushwork.Brush.SMALL else 0.0075
	ferrule.bottom_radius = 0.005
	ferrule.height = 0.03
	ferrule.radial_segments = 10
	ferrule.rings = 1
	var flat := Basis().scaled(Vector3(2.2, 1, 0.45)) if kind == Brushwork.Brush.FLAT else Basis()
	_piece(root, ferrule, Transform3D(along * flat, Vector3(0, BRUSH_TIP.y, tip_z + 0.04)), _plain("ferrule", Color(0.78, 0.76, 0.7)))
	var hair := CylinderMesh.new()
	var r: float = {Brushwork.Brush.SMALL: 0.003, Brushwork.Brush.BIG: 0.008, Brushwork.Brush.FLAT: 0.007, Brushwork.Brush.STICK: 0.003}[kind]
	hair.top_radius = r
	hair.bottom_radius = r * (0.15 if kind != Brushwork.Brush.FLAT and not stick else 0.9)
	hair.height = 0.026
	hair.radial_segments = 10
	hair.rings = 1
	var tip := _piece(root, hair, Transform3D(along * flat, Vector3(0, BRUSH_TIP.y, tip_z + 0.013)), _plain("charcoal" if stick else "bristles", Color(0.12, 0.11, 0.11) if stick else Color(0.86, 0.78, 0.62)))
	tip.name = "tip"
	return root


static func _plain(key: String, colour: Color) -> StandardMaterial3D:
	var mat: StandardMaterial3D = _mats.get(key)
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.albedo_color = colour
		mat.roughness = 0.6
		_mats[key] = mat
	return mat


static func _piece(root: Node3D, mesh: Mesh, at: Transform3D, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = at
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi


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


## An open hand, palm up and fingers spread: the hand holds nothing.
static func _open_hand(root: Node3D) -> void:
	var skin: StandardMaterial3D = _mats.get("skin")
	if skin == null:
		skin = StandardMaterial3D.new()
		skin.albedo_color = Color(0.93, 0.78, 0.66)
		skin.roughness = 0.8
		_mats["skin"] = skin
	var hand := Node3D.new()
	hand.scale = Vector3.ONE * 1.7
	root.add_child(hand)
	var palm := MeshInstance3D.new()
	palm.mesh = Meshes.rounded_box(0.3, 2, 7)
	palm.scale = Vector3(0.026, 0.007, 0.024)
	palm.position = Vector3(0, 0.0035, 0)
	palm.material_override = skin
	palm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hand.add_child(palm)
	# Base on the palm's rim, splay about the up axis, length: four fingers, then the thumb.
	for f in [[Vector3(-0.009, 0.0045, -0.011), 0.22, 0.017], [Vector3(-0.003, 0.0045, -0.012), 0.07, 0.020], [Vector3(0.003, 0.0045, -0.012), -0.07, 0.019], [Vector3(0.009, 0.0045, -0.011), -0.22, 0.015], [Vector3(-0.012, 0.004, 0.002), 1.0, 0.015]]:
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.0033
		capsule.height = f[2]
		capsule.radial_segments = 8
		capsule.rings = 2
		var along := Vector3.FORWARD.rotated(Vector3.UP, f[1])
		var mi := MeshInstance3D.new()
		mi.mesh = capsule
		mi.transform = Transform3D(Basis(Vector3.UP, f[1]) * Basis(Vector3.RIGHT, -PI * 0.5), f[0] + along * f[2] * 0.5)
		mi.material_override = skin
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hand.add_child(mi)


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
	var meadow: Color = Meadow.GRASS[&"root_color"].lerp(Meadow.GRASS[&"tip_lush"].lerp(Meadow.GRASS[&"tip_dry"], 0.5), 0.6)
	var joint: Color = Meadow.GROUND[&"earth"].lerp(meadow, 0.35) * 0.8
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


static func _wall(root: Node3D, plastered := false, top := WallLayout.Top.CRENEL, arched := false) -> void:
	var layout := WallLayout.new()
	layout.plaster = plastered
	layout.seed = 4
	layout.height = 2.1 if arched else 1.5
	layout.top = top
	layout.points = [Vector3(-1.4, 0, 0), Vector3(1.4, 0, 0)]
	if arched:
		layout.arches = [1.4]
	layout.build(_flat)
	_stones(root, layout.stones, 0.015)


## A cottage: stone walls with a door toward the eye under a tiled gable roof, or a flat one.
static func _house(root: Node3D, plastered := false, gable_end := WallLayout.GableEnd.WALL, flat := false, timber_style := 0, thatched := false) -> void:
	var layout := WallLayout.new()
	layout.timber_style = timber_style
	layout.plaster = plastered
	layout.seed = 7
	layout.height = 2.4
	layout.top = WallLayout.Top.CAP
	layout.closed = true
	layout.gable_end = gable_end
	layout.cover = WallLayout.Cover.DECK if flat else WallLayout.Cover.ROOF
	layout.points = WallLayout.rectangle(Vector3(-1.6, 0, 0), Vector3(1.6, 0, 0), 2.6)
	layout.arches = [3.2 * 1.5 + 2.6]
	var roof := RoofLayout.new()
	roof.seed = 7
	roof.corners = layout.points
	roof.pitch = 0.0 if flat else 1.8
	roof.stepped = gable_end == WallLayout.GableEnd.STEPS
	roof.thatch = thatched
	layout.gable = roof
	layout.build(_flat)
	roof.base = layout.samples[0].y + layout.height + WallLayout.CAP
	roof.build()
	_roofed(root, layout, roof, plastered)


## A round tower under a cone roof.
static func _tower(root: Node3D, plastered := false, thatched := false) -> void:
	var layout := WallLayout.new()
	layout.plaster = plastered
	layout.seed = 9
	layout.height = 3.2
	layout.top = WallLayout.Top.CAP
	layout.closed = true
	layout.cover = WallLayout.Cover.ROOF
	layout.points = WallLayout.circle(Vector3.ZERO, 1.2)
	var roof := RoofLayout.new()
	roof.seed = 9
	roof.kind = RoofLayout.Kind.CONE
	roof.radius = 1.2
	roof.pitch = WallTool.pitch_for({"round": true, "size": Vector2(2.4, 2.4)})
	roof.thatch = thatched
	layout.gable = roof
	layout.build(_flat)
	roof.base = layout.samples[0].y + layout.height + WallLayout.CAP
	roof.build()
	_roofed(root, layout, roof, plastered)


static func _roofed(root: Node3D, layout: WallLayout, roof: RoofLayout, plastered: bool) -> void:
	_stones(root, layout.stones, 0.012)
	_stones(root, roof.tiles, 0.012)
	if not roof.coat.is_empty():
		var coat := ArrayMesh.new()
		coat.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, roof.coat)
		var straw: StandardMaterial3D = _mats.get("thatch")
		if straw == null:
			straw = StandardMaterial3D.new()
			straw.vertex_color_use_as_albedo = true
			straw.roughness = 0.95
			_mats["thatch"] = straw
		var mi := MeshInstance3D.new()
		mi.mesh = coat
		mi.scale = Vector3.ONE * 0.012
		mi.material_override = straw
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	if not plastered:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in roof.gable_faces:
		st.add_vertex(p * 0.012)
	st.generate_normals()
	var plaster: StandardMaterial3D = _mats.get("plaster")
	if plaster == null:
		plaster = StandardMaterial3D.new()
		plaster.albedo_color = WallLayout.PLASTER
		plaster.roughness = 0.9
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
## FITTING_PARTS. Its face looks along +z, and its mount is the origin: the back of a window
## (centred on it), where a lantern's bracket or a flag's pole leaves the
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
			"lantern", "post_lantern":
				layout.lanterns = [Vector3(s, 1.5, 1.0)]
			"flag":
				layout.flags = [s]
		layout.build(_flat)
		parts = layout.stones
		flames = layout.flames
		cloths = layout.cloths
		match what:
			"window":
				var o := layout.openings[0]
				mount = Vector3(0, (o.sill + o.head) * 0.5, INF)
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
static func _path(root: Node3D, dirt := false) -> void:
	var layout := PathLayout.new()
	layout.seed = 3
	layout.style = "dirt" if dirt else "cobble"
	for p in [Vector3(-0.3, 0, -1.6), Vector3(0.25, 0, -0.5), Vector3(-0.2, 0, 0.6), Vector3(0.3, 0, 1.6)]:
		layout.add(p, 0.62)
	layout.build()
	if not dirt:
		_stones(root, layout.stones, 0.024)
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in layout.samples.size() - 1:
		var a := layout.frame_at(layout.lengths[i])
		var b := layout.frame_at(layout.lengths[i + 1])
		var across_a: Vector3 = a.along.cross(Vector3.UP) * a.half
		var across_b: Vector3 = b.along.cross(Vector3.UP) * b.half
		for v in [a.point - across_a, b.point - across_b, a.point + across_a, a.point + across_a, b.point - across_b, b.point + across_b]:
			st.set_normal(Vector3.UP)
			st.set_color(Color(0.48, 0.31, 0.16))
			st.add_vertex(v * 0.024)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _vertex_mat("dirt", 1.0, false)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


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
	for mmi: MultiMeshInstance3D in node.get_children():
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mmi.multimesh.mesh == Stones.mesh():
			mmi.multimesh.mesh = Stones.far_mesh()
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


static func _tree(root: Node3D, species := FloraLayout.Species.OAK) -> void:
	var t := FloraLayout.tree(Vector3(0, 0.2, 0), 11, species)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.16
	trunk.bottom_radius = 0.3
	trunk.height = 1.0
	trunk.radial_segments = 8
	trunk.rings = 1
	var bark := _vertex_mat("bark", 1.0, false)
	var trunk_mm := multimesh(trunk, 1)
	trunk_mm.set_instance_transform(0, t.trunk)
	trunk_mm.set_instance_color(0, t.bark)
	var scale := 0.006
	_add(root, trunk_mm, bark, scale)
	var blobs := multimesh(Meshes.blob(4), t.blobs.size())
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


## A small clay dish heaped with bird seed: striped sunflower seeds among round millet.
static func _seeds(root: Node3D) -> void:
	var dish := CylinderMesh.new()
	dish.top_radius = 0.022
	dish.bottom_radius = 0.016
	dish.height = 0.007
	dish.radial_segments = 20
	dish.rings = 1
	var clay: StandardMaterial3D = _mats.get("clay")
	if clay == null:
		clay = StandardMaterial3D.new()
		clay.albedo_color = Color(0.72, 0.42, 0.28)
		clay.roughness = 0.85
		_mats["clay"] = clay
	var mi := MeshInstance3D.new()
	mi.mesh = dish
	mi.position = Vector3(0, 0.0035, 0)
	mi.material_override = clay
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 34:
		var r := sqrt(rng.randf()) * 0.018
		var a := rng.randf() * TAU
		var at := Vector3(cos(a) * r, 0.0085 + 0.007 * (1.0 - r / 0.018) + rng.randf() * 0.001, sin(a) * r)
		var turn := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, PI * 0.5 + rng.randf_range(-0.5, 0.5))
		if i % 3 == 0:
			Meshes.ellipsoid(st, 0, at, Vector3.ONE * 0.0022, SEED_COLOURS[0], 3, 6)
		else:
			var dark := SEED_COLOURS[1] if i % 2 else SEED_COLOURS[2]
			Meshes.ellipsoid(st, 0, at, Vector3(0.0022, 0.0055, 0.0014), dark, 3, 6, Callable(), turn)
			Meshes.ellipsoid(st, 0, at + turn * Vector3(0, 0, 0.0009), Vector3(0.0007, 0.0052, 0.0007), Color(0.86, 0.84, 0.78), 2, 4, Callable(), turn)
	var heap := MeshInstance3D.new()
	heap.mesh = st.commit()
	heap.material_override = seed_material()
	heap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(heap)


static func seed_material() -> StandardMaterial3D:
	return _vertex_mat("seeds", 0.7, false)


static func multimesh(mesh: Mesh, count: int) -> MultiMesh:
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
