class_name ToolModels
extends RefCounted

## The small objects that stand for each tool on a controller: miniatures of what the tool makes,
## built from the same generators and meshes as the full-size things, standing on y = 0. Their stones are
## the far stone: a few millimetres across, the full one's triangles cost the Frame milliseconds for nothing. The meadow's
## plant shaders lift each instance by the terrain under it, so these carry plain materials of their own.

## The camera model's lens, from the model's origin; PhotoTool takes photos from here.
const CAMERA_LENS := Vector3(0, 0.024, -0.0302)
const CAMERA_SCREEN := Vector2(0.048, 0.036)
## A camera's shutter button glows this colour while it records.
const RECORDING := Color(1.0, 0.12, 0.08)
## The selfie camera stands on a stalk this high so its shot frames the holder's face over their arm.
const SELFIE_LIFT := 0.08
## The selfie camera's lens, beside its screen and looking out of the back toward the holder.
const SELFIE_LENS := Vector3(0.02, 0.024 + SELFIE_LIFT, 0.0167)
const SELFIE_SCREEN := Vector2(0.036, 0.027)
const _SELFIE_SCREEN_X := -0.011
## Where a brush's tip is, from the controller it is held in: it reaches past the controller, so painting is done
## with the brush, not the hand.
const BRUSH_TIP := Vector3(0, 0.01, -0.27)
## A brush handle's radius at its widest, by the ferrule.
const HANDLE_RADIUS := 0.005
const CHARCOAL_LENGTH := 0.25
const CHARCOAL_RADIUS := 0.0065
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
static var _meshes := {}
static var _stars := {}
static var _boulder_preview: MultiMesh
## The pieces of each build style's miniature, by its `style` arguments: laying out its walls and roof in script on
## every opening of the style wheel held a Quest's frame for hundreds of milliseconds, and it is the same every time.
static var _styled := {}


static func build(tool: Hand.Tool) -> Node3D:
	var root := Node3D.new()
	match tool:
		Hand.Tool.WALLS:
			_wall(root)
		Hand.Tool.HOUSE:
			_house(root)
		Hand.Tool.TOWER:
			_tower(root)
		Hand.Tool.FENCE:
			_fence(root)
		Hand.Tool.WINDOWS:
			_windows(root)
		Hand.Tool.ARCH:
			_wall(root, false, WallLayout.Top.CAP, true)
		Hand.Tool.DECORATIONS:
			_decor(root)
		Hand.Tool.STAIRS:
			_stairs(root, "wood")
		Hand.Tool.DIRT_PATH:
			_path(root)
		Hand.Tool.FLOWERS:
			_flowers(root)
		Hand.Tool.MOSS:
			var mi := MeshInstance3D.new()
			mi.mesh = Meshes.moss()
			mi.scale = Vector3.ONE * 0.14
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.3, 0.5, 0.08)
			mi.material_override = mat
			root.add_child(mi)
		Hand.Tool.GRASS:
			_grass(root)
		Hand.Tool.TREES:
			_tree(root)
		Hand.Tool.BUSHES:
			_bush(root)
		Hand.Tool.BOULDER:
			_boulders(root)
		Hand.Tool.DELETE:
			_spade(root)
		Hand.Tool.POND:
			_pond(root)
		Hand.Tool.STONE:
			_stone_ground(root, 0)
		Hand.Tool.COLOUR:
			_palette(root)
		Hand.Tool.STYLE:
			_wand(root)
		Hand.Tool.CAMERA:
			_camera(root, false)
		Hand.Tool.SELFIE:
			_camera(root, true)
		Hand.Tool.SEEDS:
			_seeds(root)
		Hand.Tool.EASEL:
			_easel(root)
		Hand.Tool.BOOK:
			root.add_child(Book.miniature())
	if tool in [Hand.Tool.WALLS, Hand.Tool.HOUSE, Hand.Tool.TOWER, Hand.Tool.ARCH]:
		for part in root.get_children():
			part.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.22), Vector3.ZERO) * part.transform
	return root


## A miniature of choice `i` of a style the style tool sets (`PaletteTool.styles`), a build's in stone or plaster,
## a roof's over a house or a round tower; a gable end's turned to face the eye.
static func style(restyle: PaletteTool.Restyle, i: int, plastered: bool, round := false, boulder := false, house := false) -> Node3D:
	if restyle not in [PaletteTool.Restyle.GABLE, PaletteTool.Restyle.ROOF, PaletteTool.Restyle.TOP, PaletteTool.Restyle.FACE]:
		return _style(restyle, i, plastered, round, boulder, house)
	var key := [restyle, i, plastered, round, house]
	if not _styled.has(key):
		var built := _style(restyle, i, plastered, round, boulder, house)
		var pieces := []
		for mi: MeshInstance3D in built.get_children():
			pieces.append([mi.mesh, mi.transform, mi.material_override])
		built.free()
		_styled[key] = pieces
	var root := Node3D.new()
	for piece: Array in _styled[key]:
		_piece(root, piece[0], piece[1], piece[2])
	return root


static func _style(restyle: PaletteTool.Restyle, i: int, plastered: bool, round: bool, boulder: bool, house: bool) -> Node3D:
	var root := Node3D.new()
	if restyle == PaletteTool.Restyle.DECORATION:
		var layout := DecorationLayout.new()
		layout.build(i, 0)
		var model := decoration(layout, 0)
		model.scale = Vector3.ONE * 0.035
		root.add_child(model)
		return root
	if restyle == PaletteTool.Restyle.RAIL:
		_stairs(root, StairLayout.RAILS[i])
		return root
	if restyle == PaletteTool.Restyle.TREE:
		_tree(root, i as FloraLayout.Species)
		for part in root.get_children():
			part.scale *= 1.8
		return root
	match restyle:
		PaletteTool.Restyle.GABLE:
			_house(root, plastered, i as WallLayout.GableEnd, false, false, RoofLayout.Deck.STONE, false)
		PaletteTool.Restyle.ROOF:
			var thatched := i == WallTool.RoofStyle.THATCHED
			var flat := i in [WallTool.RoofStyle.FLAT, WallTool.RoofStyle.BOARDED]
			var deck := RoofLayout.Deck.WOOD if i == WallTool.RoofStyle.BOARDED else RoofLayout.Deck.STONE
			if round:
				_tower(root, thatched, flat, deck)
			else:
				_house(root, plastered, WallLayout.GableEnd.WALL, flat, thatched, deck, false)
		PaletteTool.Restyle.TOP:
			_wall(root, plastered, i as WallLayout.Top)
		PaletteTool.Restyle.STONE:
			if boulder:
				_boulder_style(root, i)
				return root
			# Turned from lying flat to face the eye, a little from above.
			_stone_ground(root, i)
			for part in root.get_children():
				part.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.62).scaled(Vector3.ONE * 1.4), Vector3.ZERO) * part.transform
		PaletteTool.Restyle.FACE:
			if house:
				_house(root, i != PaletteTool.Face.STONE, WallLayout.GableEnd.WALL, false, false, RoofLayout.Deck.STONE, false, 0 if i == PaletteTool.Face.TIMBER else -1)
			elif i == PaletteTool.Face.TIMBER:
				_house(root, true)
			else:
				_wall(root, i == PaletteTool.Face.PLASTER, WallLayout.Top.CAP)
	var turn := Basis(Vector3.UP, PI * 0.38) if restyle == PaletteTool.Restyle.GABLE else Basis(Vector3.UP, PI * 0.2) if house else Basis()
	for part in root.get_children():
		part.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.03 if house else -PI * 0.22) * turn, Vector3.ZERO) * part.transform
	return root


static func _stairs(root: Node3D, rail: String) -> void:
	var layout := StairLayout.new()
	layout.build({"a": Vector3.ZERO, "b": Vector3(0, 0.8, -1.5), "width": 1.2, "rail": rail, "seed": 1, "paint": Palette.plain()})
	var stones := Stones.new()
	stones.lay(layout.stones)
	stones.scale = Vector3.ONE * 0.035
	root.add_child(stones)


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
## the paint on it. The stick is a bare stick of charcoal, black from end to end.
static func brush(kind: Brushwork.Brush) -> Node3D:
	var root := Node3D.new()
	var along := Basis(Vector3.RIGHT, -PI * 0.5)
	var tip_z := BRUSH_TIP.z
	if kind == Brushwork.Brush.STICK:
		var stick := _piece(root, charcoal(CHARCOAL_LENGTH), Transform3D(along, Vector3(0, BRUSH_TIP.y, tip_z + CHARCOAL_LENGTH * 0.5)), charcoal_material())
		stick.name = "tip"
		return root
	_piece(root, cylinder(HANDLE_RADIUS, 0.0035, 0.2, 10), Transform3D(along, Vector3(0, BRUSH_TIP.y, tip_z + 0.155)), _plain("brush_handle", Color(0.75, 0.28, 0.2)))
	var flat := Basis().scaled(Vector3(2.2, 1, 0.45)) if kind == Brushwork.Brush.FLAT else Basis()
	var ferrule := cylinder(0.0045 if kind == Brushwork.Brush.SMALL else 0.0075, 0.005, 0.03, 10)
	_piece(root, ferrule, Transform3D(along * flat, Vector3(0, BRUSH_TIP.y, tip_z + 0.04)), _plain("ferrule", Color(0.78, 0.76, 0.7)))
	var r: float = {Brushwork.Brush.SMALL: 0.003, Brushwork.Brush.BIG: 0.008, Brushwork.Brush.FLAT: 0.007}[kind]
	var hair := cylinder(r, r * (0.15 if kind != Brushwork.Brush.FLAT else 0.9), 0.026, 10)
	var tip := _piece(root, hair, Transform3D(along * flat, Vector3(0, BRUSH_TIP.y, tip_z + 0.013)), _plain("bristles", Color(0.86, 0.78, 0.62)))
	tip.name = "tip"
	return root


static func bend(model: Node3D, kind: Brushwork.Brush, offset: Vector3) -> void:
	var flat := Basis().scaled(Vector3(2.2, 1, 0.45)) if kind == Brushwork.Brush.FLAT else Basis()
	var along := Basis(Vector3.RIGHT, -PI * 0.5) * flat
	along.y = (Vector3(0, 0, -0.026) + offset) / 0.026
	var tip: Node3D = model.get_node("tip")
	tip.transform = Transform3D(along, BRUSH_TIP + Vector3(0, 0, 0.013) + offset * 0.5)


## Charcoal's matte black, which no sky glints off, coloured by vertex.
static func charcoal_material() -> StandardMaterial3D:
	var mat: StandardMaterial3D = _mats.get("charcoal")
	if mat == null:
		mat = _plain("charcoal", Color.WHITE)
		mat.roughness = 1.0
		mat.metallic_specular = 0.0
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true
	return mat


## A stick of willow charcoal `length` long along y, centred on its middle: six-sided and uneven, crooked toward z as
## the twig grew, so lying on its side it lies flat, mottled grey-black, its +y end worn grey.
static func charcoal(length: float) -> ArrayMesh:
	return shared("charcoal %s" % length, _charcoal.bind(length))


static func _charcoal(length: float) -> ArrayMesh:
	var parts: Array = []
	var at := Vector3(0, -length * 0.5, 0)
	var bends := [0.0, 0.09, -0.07, 0.06, -0.05]
	var widths := [1.0, 0.86, 1.08, 0.94, 0.9, 0.6]
	var greys := [0.19, 0.23, 0.17, 0.22, 0.3]
	var seg := length / bends.size()
	for i in bends.size():
		var b := Basis(Vector3.RIGHT, bends[i])
		var c := cylinder(CHARCOAL_RADIUS * widths[i + 1], CHARCOAL_RADIUS * widths[i], seg + 0.002, 6)
		var grey: float = greys[i]
		parts.append([c, Transform3D(b.scaled(Vector3(1.0, 1.0, 0.8)), at + b.y * seg * 0.5), Color(grey, grey * 0.96, grey * 0.92)])
		at += b.y * seg
	return bake(parts)


## `parts` ([mesh, transform, colour] each, a null colour keeping the mesh's own) as one mesh coloured by vertex, drawn
## in one call.
static func bake(parts: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var index := PackedInt32Array()
	for part: Array in parts:
		var arrays := (part[0] as Mesh).surface_get_arrays(0)
		var t: Transform3D = part[1]
		var normal := t.basis.inverse().transposed()
		var base := verts.size()
		for v: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
			verts.append(t * v)
		if part[2] == null:
			colours.append_array(arrays[Mesh.ARRAY_COLOR])
		else:
			for v in arrays[Mesh.ARRAY_VERTEX].size():
				colours.append(part[2])
		for n: Vector3 in arrays[Mesh.ARRAY_NORMAL]:
			normals.append((normal * n).normalized())
		for i: int in arrays[Mesh.ARRAY_INDEX]:
			index.append(base + i)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = index
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The mesh `make` builds, built once under `key`: every easel and hand holding the same kit shares its geometry, so
## setting one up in play builds and uploads none.
static func shared(key: String, make: Callable) -> Mesh:
	var m: Mesh = _meshes.get(key)
	if m == null:
		m = make.call()
		_meshes[key] = m
	return m


static func cylinder(top: float, bottom: float, height: float, segments: int) -> CylinderMesh:
	return shared("cylinder %s %s %s %d" % [top, bottom, height, segments], func() -> CylinderMesh:
		var c := CylinderMesh.new()
		c.top_radius = top
		c.bottom_radius = bottom
		c.height = height
		c.radial_segments = segments
		c.rings = 1
		return c)


static func box(size: Vector3) -> BoxMesh:
	return shared("box %s" % size, func() -> BoxMesh:
		var b := BoxMesh.new()
		b.size = size
		return b)


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


## The screen of a camera model built by `build`, its own material, which PhotoTool shows that camera's lens's view in.
static func screen(camera: Node3D) -> StandardMaterial3D:
	return (camera.get_node("Screen") as MeshInstance3D).material_override


## The shutter button of a camera model built by `build`, its own material. Its emission stays enabled, black until
## the camera records, so lighting it changes a parameter rather than compiling another shader in play.
static func button(camera: Node3D) -> StandardMaterial3D:
	return (camera.get_node("Button") as MeshInstance3D).material_override


## A small camera, its screen toward the eye and its lens along the controller's aim, or for a selfie beside the
## screen, looking back at the holder.
static func _camera(root: Node3D, selfie: bool) -> void:
	var lens := CylinderMesh.new()
	lens.top_radius = 0.008 if selfie else 0.012
	lens.bottom_radius = 0.008 if selfie else 0.013
	lens.height = 0.006 if selfie else 0.018
	lens.radial_segments = 16
	lens.rings = 1
	var glass := CylinderMesh.new()
	glass.top_radius = 0.006 if selfie else 0.009
	glass.bottom_radius = glass.top_radius
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
	var y := SELFIE_LENS.y if selfie else CAMERA_LENS.y
	var size := SELFIE_SCREEN if selfie else CAMERA_SCREEN
	var screen_x := _SELFIE_SCREEN_X if selfie else 0.0
	var parts := [
		[Meshes.rounded_box(0.25, 2, 41), Transform3D(Basis().scaled(Vector3(0.064, 0.046, 0.026)), Vector3(0, y, 0)), Color(0.84, 0.76, 0.62)],
		[Meshes.rounded_box(0.2, 2, 42), Transform3D(Basis().scaled(Vector3(size.x + 0.006, size.y + 0.006, 0.002)), Vector3(screen_x, y, 0.013)), Color(0.16, 0.14, 0.13)],
		[lens, Transform3D(facing, SELFIE_LENS - Vector3(0, 0, 0.0035) if selfie else Vector3(0, y, -0.021)), Color(0.22, 0.2, 0.19)],
		[glass, Transform3D(facing, SELFIE_LENS if selfie else CAMERA_LENS), Color(0.08, 0.1, 0.16)],
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
	if selfie:
		var stalk := CylinderMesh.new()
		stalk.top_radius = 0.006
		stalk.bottom_radius = 0.007
		stalk.height = SELFIE_LIFT
		stalk.radial_segments = 10
		stalk.rings = 1
		var mi := MeshInstance3D.new()
		mi.mesh = stalk
		mi.position = Vector3(0, SELFIE_LIFT * 0.5, 0)
		mi.material_override = _mats["camera_%s" % Color(0.22, 0.2, 0.19).to_html()]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	var shutter := StandardMaterial3D.new()
	shutter.albedo_color = Color(0.72, 0.56, 0.3)
	shutter.roughness = 0.7
	shutter.emission_enabled = true
	shutter.emission = Color.BLACK
	shutter.emission_energy_multiplier = 2.0
	var press := MeshInstance3D.new()
	press.name = "Button"
	press.mesh = button
	press.position = Vector3(0.019, y + 0.024, 0.002)
	press.material_override = shutter
	press.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(press)
	var quad := QuadMesh.new()
	quad.size = size
	var screen := MeshInstance3D.new()
	screen.name = "Screen"
	screen.mesh = quad
	screen.position = Vector3(screen_x, y, 0.0141)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = PhotoTool.DARK
	screen.material_override = glow
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(screen)


## A little person: the visit tool goes to see other players.
static func _figure(root: Node3D) -> void:
	var a := Avatar.open(Avatar.built_in(0), Session.COLOURS[0])
	a.scale = Vector3.ONE * 0.026
	root.add_child(a)
	a.stand.call_deferred()


## A disc of stone ground as the stone tool lays it in `style`, shaded as the ground shades it, fraying toward the rim
## into meadow as scattered stones.
static func _stone_ground(root: Node3D, style: int) -> void:
	var turf := CylinderMesh.new()
	turf.top_radius = 0.026
	turf.bottom_radius = 0.024
	turf.height = 0.004
	turf.radial_segments = 24
	turf.rings = 1
	var face := PlaneMesh.new()
	face.size = Vector2(0.052, 0.052)
	var key := "stone_ground_%d" % style
	var mat: ShaderMaterial = _mats.get(key)
	if mat == null:
		mat = ShaderMaterial.new()
		mat.shader = preload("res://src/stone_disc.gdshader")
		StoneStyles.apply(mat)
		mat.set_shader_parameter("style", style)
		mat.set_shader_parameter("detail", Look.detail_noise())
		mat.set_shader_parameter("earth", Meadow.GROUND[&"earth"])
		mat.set_shader_parameter("meadow", Meadow.GRASS[&"root_color"].lerp(Meadow.GRASS[&"tip_lush"].lerp(Meadow.GRASS[&"tip_dry"], 0.5), 0.6))
		_mats[key] = mat
	if not _mats.has("stone_ground_side"):
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
	layout.height = 2.4 if arched else 1.5
	layout.top = top
	layout.points = [Vector3(-1.4, 0, 0), Vector3(1.4, 0, 0)]
	if arched:
		layout.openings = [WallLayout.archway(1.4)]
	layout.build(_flat)
	_stones(root, layout.stones, 0.015)


## A cottage: stone walls with a door toward the eye under a tiled gable roof, or a flat one decked in `deck`.
static func _house(root: Node3D, plastered := false, gable_end := WallLayout.GableEnd.WALL, flat := false, thatched := false, deck := RoofLayout.Deck.STONE, arched := true, timber_style := 0) -> void:
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
	if arched:
		layout.openings = [WallLayout.archway(3.2 * 1.5 + 2.6)]
	var roof := RoofLayout.new()
	roof.seed = 7
	roof.corners = layout.points
	roof.pitch = 0.0 if flat else 1.8
	roof.stepped = gable_end == WallLayout.GableEnd.STEPS
	roof.thatch = thatched
	roof.deck = deck
	layout.gable = roof
	layout.build(_flat)
	roof.base = layout.samples[0].y + layout.height + WallLayout.CAP
	roof.build()
	layout.fit_under(roof)
	_roofed(root, layout, roof, plastered)


## A round tower under a cone roof, or a flat one decked in `deck`.
static func _tower(root: Node3D, thatched := false, flat := false, deck := RoofLayout.Deck.STONE) -> void:
	var layout := WallLayout.new()
	layout.seed = 9
	layout.height = 3.2
	layout.top = WallLayout.Top.CAP
	layout.closed = true
	layout.cover = WallLayout.Cover.DECK if flat else WallLayout.Cover.ROOF
	layout.points = WallLayout.circle(Vector3.ZERO, 1.2)
	var roof := RoofLayout.new()
	roof.seed = 9
	roof.kind = RoofLayout.Kind.CONE
	roof.radius = 1.2
	roof.pitch = 0.0 if flat else WallTool.pitch_for({"round": true, "size": Vector2(2.4, 2.4)})
	roof.thatch = thatched
	roof.deck = deck
	layout.gable = roof
	layout.build(_flat)
	roof.base = layout.samples[0].y + layout.height + WallLayout.CAP
	roof.build()
	layout.fit_under(roof)
	_roofed(root, layout, roof, false)


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
				layout.openings = [Vector4(s, 1.5, WallLayout.DoorStyle.PLAIN, 1.0)]
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
				var o := layout.apertures[0]
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


## A short dirt stroke.
static func _path(root: Node3D) -> void:
	var layout := PathLayout.new()
	layout.seed = 3
	for p in [Vector3(-0.3, 0, -1.6), Vector3(0.25, 0, -0.5), Vector3(-0.2, 0, 0.6), Vector3(0.3, 0, 1.6)]:
		layout.add(p, 0.62)
	layout.plan()
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
	if stones.is_empty():
		return
	var mesh := shared("tool_stones_%s" % hash(stones), func() -> ArrayMesh:
		var parts := []
		for stone in stones:
			var at: Transform3D = stone.xform
			at.basis *= Stones.FLIPS[stone.get("variant", 0)]
			var colour: Color = stone.color
			colour *= Color(stone.ao, stone.ao, stone.ao)
			parts.append([Stones.far_mesh(), at, colour])
		var imported := ImporterMesh.new()
		imported.add_surface(Mesh.PRIMITIVE_TRIANGLES, bake(parts).surface_get_arrays(0))
		imported.generate_lods(60.0, 25.0, [])
		return imported.get_mesh())
	_piece(root, mesh, Transform3D(Basis.from_scale(Vector3.ONE * scale), Vector3.ZERO), _vertex_mat("tool_stone", 0.9, false))


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
	_add(root, blobs, _leaf(), scale)


static func _bush(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var spots := [Vector3(0, 0, 0), Vector3(0.7, 0, 0.4), Vector3(-0.6, 0, 0.5)]
	var blobs := multimesh(Meshes.blob(4), spots.size())
	for i in spots.size():
		var b := FloraLayout.bush(spots[i], rng)
		blobs.set_instance_transform(i, b[0])
		blobs.set_instance_color(i, b[1])
	_add(root, blobs, _leaf(), 0.022)


static func _leaf() -> StandardMaterial3D:
	var leaf := _vertex_mat("leaf", 1.0, false)
	leaf.backlight_enabled = true
	leaf.backlight = Color(0.25, 0.35, 0.08)
	return leaf


## The placed boulder's builder and stone material, sharing one miniature mesh across styles and wheels.
static func _boulder_style(root: Node3D, style: int) -> void:
	var shape := BoulderLayout.shape(7)
	var model: MultiMeshInstance3D
	if _boulder_preview == null:
		model = Boulders._instance(shape, BoulderLayout.FAR + 1)
		model.multimesh.set_instance_color(0, Color.WHITE)
		_boulder_preview = model.multimesh
	else:
		model = MultiMeshInstance3D.new()
		model.multimesh = _boulder_preview
		model.material_override = Stones.shared_material()
	model.set_instance_shader_parameter("stone_style", style)
	model.set_instance_shader_parameter("miniature", true)
	model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.12), Vector3.ZERO) * BoulderLayout.rest(shape, Quaternion.IDENTITY, 0.065, 0, 0, _flat)
	root.add_child(model)


## A boulder with a pebble beside it, in wall stone.
static func _boulders(root: Node3D) -> void:
	var stone: StandardMaterial3D = _mats.get("boulder")
	if stone == null:
		stone = StandardMaterial3D.new()
		stone.albedo_color = WallLayout.STONE
		stone.roughness = 0.9
		_mats["boulder"] = stone
	for b in [[7, Vector3(-0.004, 0, 0), 0.042], [3, Vector3(0.024, 0, 0.008), 0.016]]:
		var shape := BoulderLayout.shape(b[0])
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, BoulderLayout.arrays(shape, BoulderLayout.FAR + 1))
		var m := MeshInstance3D.new()
		m.mesh = mesh
		m.material_override = stone
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.transform = BoulderLayout.rest(shape, Quaternion.IDENTITY, b[2], b[1].x, b[1].z, func(_x: float, _z: float) -> float: return b[1].y)
		root.add_child(m)


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


static func decoration(layout: DecorationLayout, seed: int) -> Node3D:
	var root := Node3D.new()
	var stones := Stones.new()
	stones.lay(layout.parts)
	root.add_child(stones)
	if not layout.flames.is_empty():
		var fire := Fittings.new()
		fire.lay(layout.flames, [])
		var glow := ShaderMaterial.new()
		glow.shader = preload("res://src/flame.gdshader")
		fire._flames.material_override = glow
		root.add_child(fire)
	if not layout.flowers.is_empty():
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in layout.flowers.size():
			var mesh := Meshes.flower(6, FloraLayout.FLOWER_COLORS[posmod(seed + i, FloraLayout.FLOWER_COLORS.size())])
			surface.append_from(mesh, 0, layout.flowers[i])
		var flower := MeshInstance3D.new()
		flower.mesh = surface.commit()
		flower.material_override = _vertex_mat("decoration_flowers", 0.8, true)
		root.add_child(flower)
	return root
