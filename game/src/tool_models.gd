class_name ToolModels
extends RefCounted

## The small objects that stand for each tool on a controller: miniatures of what the tool makes,
## built from the same generators and meshes as the full-size things, standing on y = 0. Their stones are
## the far stone: a few millimetres across, the full one's triangles cost the Frame milliseconds for nothing. The meadow's
## plant shaders lift each instance by the terrain under it, so these carry plain materials of their own.

## The camera model's lens, from the model's origin; PhotoTool takes photos from here.
const CAMERA_LENS := Vector3(0, 0.024, -0.0302)
## Where the wand's star and the spade's blade end, in their models' space.
const WAND_STAR := Vector3(0, 0, -0.055)
const SPADE_EDGE := Vector3(0, 0, -0.052)
const CAMERA_SCREEN := Vector2(0.048, 0.036)
## A camera's shutter button glows this colour while it records.
const RECORDING := Color(1.0, 0.12, 0.08)
## The selfie camera stands on a stalk this high so its shot frames the holder's face over their arm.
const SELFIE_LIFT := 0.08
## The selfie camera's lens, beside its screen and looking out of the back toward the holder.
const SELFIE_LENS := Vector3(0.02, 0.024 + SELFIE_LIFT, 0.0167)
const SELFIE_SCREEN := Vector2(0.036, 0.027)
const _SELFIE_SCREEN_X := -0.011
## The hand mirror: its oval glass's width and height, the rim round it, and its handle below, standing on y = 0.
const MIRROR_GLASS := Vector2(0.04, 0.06)
const MIRROR_RIM := 0.004
const MIRROR_HANDLE := 0.034
const MIRROR_CENTRE := Vector3(0, MIRROR_HANDLE + MIRROR_RIM + MIRROR_GLASS.y * 0.5, 0.003)
## Where a brush's tip is, from the controller it is held in: it reaches past the controller, so painting is done
## with the brush, not the hand.
const BRUSH_TIP := Vector3(0, 0.01, -0.27)
## A brush handle's radius at its widest, by the ferrule.
const HANDLE_RADIUS := 0.005
## A stick of charcoal is held leaned back this far from the controller's aim, its tip dropped, about where a hand
## grips it: aimed at the canvas it meets it at this angle, and a wrist turned down as far lays its side flat on it.
const STICK_LEAN := deg_to_rad(45.0)
const STICK_GRIP := Vector3(0, 0.01, -0.06)
## Whatever its length, a stick's back end rests in the hand this far along the aim, so a short stick's tip is nearer it.
const STICK_BUTT := -0.02
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
## The pieces of each build style's miniature, by `_style_key`, built on a worker thread: laid out on the frame, a
## Quest 2's first roof wheel held it 214 ms. `_lock` guards these and every cache the worker fills.
static var _styled := {}
## The miniatures each key's pieces are laid into when the worker brings them, held weakly: a wheel closed meanwhile
## frees its own.
static var _waiting := {}
## The keys the worker builds next, the one a wheel waits on first, and those it has built since `deliver` last ran.
static var _queue: Array = []
static var _built: Array = []
static var _building := false
## Its own thread at low priority, not the worker pool: a pool task held the pool's low-priority share, which compiles
## pipelines, and a Quest 2's first easel waited 11 s on them.
static var _thread: Thread
static var _lock := Mutex.new()
## Each mesh `bake` has read or built, by mesh, as its surface arrays: reading a mesh's arrays back from the GPU stalls
## the frame for every frame in flight, a Quest's style wheel hundreds of milliseconds on its first opening.
static var _arrays := {}
## The pieces of each masonry tool's miniature, by tool, kept from its first build: the hands build every tool as the
## game loads, and laying its walls out again for each other player who takes it held a Frame's frame 324 ms.
static var _masonry := {}
const MASONRY: Array[Hand.Tool] = [Hand.Tool.WALLS, Hand.Tool.HOUSE, Hand.Tool.TOWER, Hand.Tool.ARCH, Hand.Tool.FENCE]


static func build(tool: Hand.Tool) -> Node3D:
	var root := Node3D.new()
	var pieces: Variant = _masonry.get(tool)
	if pieces != null:
		_lay(root, pieces)
		return root
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
			_wall(root, WallLayout.Finish.BARE, WallLayout.Top.CAP, true)
		Hand.Tool.DECORATIONS:
			_decor(root)
		Hand.Tool.STAIRS:
			_stairs(root, "wood")
		Hand.Tool.PATH:
			_path(root)
		Hand.Tool.FLOWERS:
			_flowers(root)
		Hand.Tool.MOSS:
			var moss := _piece(root, Meshes.moss(), Transform3D(Basis.from_scale(Vector3.ONE * 0.14), Vector3.ZERO), _plain("moss", Color(0.3, 0.5, 0.08), {"roughness": 1.0}))
			moss.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
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
		Hand.Tool.MIRROR:
			mirror(root)
	if tool in [Hand.Tool.WALLS, Hand.Tool.HOUSE, Hand.Tool.TOWER, Hand.Tool.ARCH]:
		for part in root.get_children():
			part.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.22), Vector3.ZERO) * part.transform
	if tool in MASONRY:
		_masonry[tool] = root.get_children().map(func(mi: MeshInstance3D) -> Array: return [mi.mesh, mi.transform, mi.material_override])
	return root


## A miniature of choice `i` of a style the style tool sets (`PaletteTool.styles`), a build's in its `finish`, a
## roof's over a house or a round tower, a face's on a house, a wall or a fence; a gable end's turned to face the
## eye. A build style's comes back empty until the worker has built it, then fills: nothing waits on it.
static func style(restyle: PaletteTool.Restyle, i: int, finish: WallLayout.Finish, round := false, boulder := false, house := false, fence := false) -> Node3D:
	if restyle not in BUILT_STYLES:
		return _style(restyle, i, finish, round, boulder, house, fence)
	var key := _style_key(restyle, i, finish, round, house, fence)
	var root := Node3D.new()
	_lock.lock()
	var pieces: Variant = _styled.get(key)
	if pieces == null:
		_waiting.get_or_add(key, []).append(weakref(root))
		_queue.erase(key)
		_queue.push_front(key)
	_lock.unlock()
	if pieces == null:
		_build_styles()
	else:
		_lay(root, pieces)
	return root


## The build styles whose miniatures the worker builds.
const BUILT_STYLES: Array[PaletteTool.Restyle] = [PaletteTool.Restyle.GABLE, PaletteTool.Restyle.ROOF, PaletteTool.Restyle.TOP, PaletteTool.Restyle.FACE, PaletteTool.Restyle.FOUNDATION, PaletteTool.Restyle.WINDOW]


## Queues every build style's miniature for the worker, so a wheel opened later finds it built.
static func prepare_styles() -> void:
	_lock.lock()
	for restyle in BUILT_STYLES:
		for i in PaletteTool.styles(restyle):
			for finish in WallLayout.Finish.values():
				for flags in 8:
					var key := _style_key(restyle, i, finish, flags & 1, flags & 2, flags & 4)
					if not _styled.has(key) and key not in _queue:
						_queue.append(key)
	_lock.unlock()
	_build_styles()


## Waits out the worker, its queue dropped: nothing it holds may outlive the game.
static func stop_styles() -> void:
	_lock.lock()
	_queue.clear()
	_lock.unlock()
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null


## The arguments a build style's miniature differs by: the finish shows on a house's or wall's faces, not a tower's,
## nor in a face's, foundation's or window's own choices, and a face's choice of house, fence or wall is its own.
static func _style_key(restyle: PaletteTool.Restyle, i: int, finish: WallLayout.Finish, round: bool, house: bool, fence: bool) -> Array:
	var tower := restyle == PaletteTool.Restyle.ROOF and round
	var face := restyle == PaletteTool.Restyle.FACE
	return [restyle, i, WallLayout.Finish.BARE if tower or restyle in [PaletteTool.Restyle.FACE, PaletteTool.Restyle.FOUNDATION, PaletteTool.Restyle.WINDOW] else finish, tower, house and face and not fence, fence and face]


static func _build_styles() -> void:
	_lock.lock()
	var start := not _building and not _queue.is_empty()
	_building = _building or start
	_lock.unlock()
	if not start:
		return
	if _thread != null:
		_thread.wait_to_finish()
	# Read back once here, on the main thread, the one mesh every stone is baked from.
	_arrays_of(Stones.far_mesh())
	_thread = Thread.new()
	_thread.start(_build_queued, Thread.PRIORITY_LOW)


static func _build_queued() -> void:
	while true:
		_lock.lock()
		var key: Variant = _queue.pop_front()
		while key != null and _styled.has(key):
			key = _queue.pop_front()
		_building = key != null
		_lock.unlock()
		if key == null:
			return
		var built := _style(key[0], key[1], key[2], key[3], false, key[4], key[5])
		var pieces := []
		for mi: MeshInstance3D in built.get_children():
			pieces.append([mi.mesh, mi.transform, mi.material_override])
		built.free()
		_lock.lock()
		_styled[key] = pieces
		_built.append(key)
		_lock.unlock()


## Lays what the worker has built into the miniatures waiting on it; called on the main thread every frame
## (`Warmup`), where the miniatures live.
static func deliver() -> void:
	_lock.lock()
	var due := []
	for key: Array in _built:
		due.append([_styled[key], _waiting.get(key, [])])
		_waiting.erase(key)
	_built.clear()
	_lock.unlock()
	for d: Array in due:
		for ref: WeakRef in d[1]:
			var root := ref.get_ref() as Node3D
			if root != null:
				_lay(root, d[0])


static func _lay(root: Node3D, pieces: Array) -> void:
	for piece: Array in pieces:
		_piece(root, piece[0], piece[1], piece[2])


static func _style(restyle: PaletteTool.Restyle, i: int, finish: WallLayout.Finish, round: bool, boulder: bool, house: bool, fence: bool) -> Node3D:
	var root := Node3D.new()
	if restyle == PaletteTool.Restyle.DECORATION:
		var layout := DecorationLayout.new()
		var strung: bool = DecorationLayout.STYLES[i].get("string", false)
		layout.build(i, 0, 0.6, "span" if strung else "ground", Vector3(2.4, 0, 0), Vector2(1.6, 1.6))
		var model := decoration(layout)
		model.scale = Vector3.ONE * 0.035
		if strung:
			model.position = Vector3(-1.2, 1.6, 0) * 0.035
		root.add_child(model)
		return root
	if restyle == PaletteTool.Restyle.RAIL:
		_stairs(root, StairLayout.RAILS[i])
		return root
	if restyle == PaletteTool.Restyle.FLOOR:
		_floor(root, i == PaletteTool.Floor.PLANKS)
		return root
	if restyle == PaletteTool.Restyle.TREE:
		_tree(root, i as FloraLayout.Species)
		for part in root.get_children():
			part.scale *= 1.8
		return root
	match restyle:
		PaletteTool.Restyle.GABLE:
			_house(root, finish, i as WallLayout.GableEnd, false, false, RoofLayout.Deck.STONE, false)
		PaletteTool.Restyle.ROOF:
			var thatched := i == WallTool.RoofStyle.THATCHED
			var flat := i in [WallTool.RoofStyle.FLAT, WallTool.RoofStyle.BOARDED]
			var deck := RoofLayout.Deck.WOOD if i == WallTool.RoofStyle.BOARDED else RoofLayout.Deck.STONE
			if round:
				_tower(root, thatched, flat, deck)
			else:
				_house(root, finish, WallLayout.GableEnd.WALL, flat, thatched, deck, false)
		PaletteTool.Restyle.TOP:
			_wall(root, finish, i as WallLayout.Top)
		PaletteTool.Restyle.PATH:
			_path(root, i as PathLayout.Surface)
			for part in root.get_children():
				part.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.62).scaled(Vector3.ONE * 1.4), Vector3.ZERO) * part.transform
		PaletteTool.Restyle.STONE:
			if boulder:
				_boulder_style(root, i)
				return root
			# Turned from lying flat to face the eye, a little from above.
			_stone_ground(root, i)
			for part in root.get_children():
				part.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.62).scaled(Vector3.ONE * 1.4), Vector3.ZERO) * part.transform
		PaletteTool.Restyle.FACE:
			var face: Vector2 = PaletteTool.FACES[i]
			if fence:
				_fence(root, int(face.x) as WallLayout.Finish)
			elif house:
				_house(root, int(face.x) as WallLayout.Finish, WallLayout.GableEnd.WALL, false, false, RoofLayout.Deck.STONE, false, -1, face.y)
			else:
				_wall(root, int(face.x) as WallLayout.Finish, WallLayout.Top.CAP, false, face.y)
		PaletteTool.Restyle.FOUNDATION:
			_house(root, WallLayout.Finish.BARE, WallLayout.GableEnd.WALL, false, false, RoofLayout.Deck.STONE, false, i)
		PaletteTool.Restyle.WINDOW:
			_wall(root, WallLayout.Finish.BARE, WallLayout.Top.CAP, false, 0.0, WallLayout.WINDOW_FAMILIES[i])
	var turn := Basis(Vector3.UP, PI * 0.38) if restyle == PaletteTool.Restyle.GABLE else Basis(Vector3.UP, PI * 0.2) if house else Basis()
	for part in root.get_children():
		part.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.03 if house else -PI * 0.22) * turn, Vector3.ZERO) * part.transform
	return root


static func _stairs(root: Node3D, rail: String) -> void:
	var layout := StairLayout.new()
	layout.build({"a": Vector3.ZERO, "b": Vector3(0, 0.8, -1.5), "width": 1.2, "sag": 0.0, "rail": rail, "seed": 1, "paint": Palette.plain()})
	var stones := Stones.new()
	stones.lay(layout.stones)
	stones.scale = Vector3.ONE * 0.035
	root.add_child(stones)


## A painter's palette: a wooden board with a dab of each roof colour round its edge.
static func _palette(root: Node3D) -> void:
	var dab := SphereMesh.new()
	dab.radius = 0.0055
	dab.height = 0.004
	dab.radial_segments = 10
	dab.rings = 4
	var swatches: Array = Palette.SWATCHES[Palette.Element.ROOF]
	var parts := [[cylinder(0.026, 0.026, 0.003, 24), Vector3(0, 0.0015, 0), Color(0.62, 0.46, 0.3)]]
	for i in swatches.size():
		var a := TAU * (0.12 + 0.76 * i / (swatches.size() - 1))
		parts.append([dab, Vector3(cos(a), 0, sin(a)) * 0.018 + Vector3(0, 0.0035, 0), swatches[i]])
	for part in parts:
		_piece(root, part[0], Transform3D(Basis(), part[1]), _plain("palette_%s" % part[2].to_html(), part[2]))


## A wand pointing ahead with a star standing at its tip and two sparkles off it: it turns what it points at into
## another of its kind, and it is no build, so the icon cannot read as a thing it builds.
static func _wand(root: Node3D) -> void:
	var ahead := Basis(Vector3.RIGHT, -PI * 0.5)
	_piece(root, cylinder(0.0012, 0.0022, 0.062, 8), Transform3D(ahead, Vector3(0, 0, -0.021)), _plain("wand", Color(0.32, 0.2, 0.13)))
	var gold := _plain("star", Color(1.0, 0.82, 0.3))
	var upright := Basis(Vector3.RIGHT, PI * 0.5)
	_piece(root, _star(5, 0.009, 0.0038), Transform3D(upright, WAND_STAR), gold)
	for spark in [[Vector3(0.008, 0.006, -0.06), 0.003], [Vector3(-0.007, -0.004, -0.044), 0.0022]]:
		_piece(root, _star(4, spark[1], spark[1] * 0.35), Transform3D(upright, spark[0]), gold)


## Where a tool's sight stands, in its model's space: just past the wand's star or the spade's blade, and ahead of
## every other model.
static func tip(tool: Hand.Tool) -> Vector3:
	match tool:
		Hand.Tool.STYLE:
			return WAND_STAR + Vector3(0, 0, -0.006)
		Hand.Tool.DELETE:
			return SPADE_EDGE + Vector3(0, 0, -0.004)
	return Vector3(0, 0.02, -0.065)


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
	for x in [-0.014, 0.014]:
		var mi := _piece(root, box(Vector3(0.003, 0.06, 0.003)), Transform3D(Basis(Vector3.BACK, -x * 9.0), Vector3(x, 0.028, 0.004)), wood)
		mi.rotate_x(-0.2)
	var tilt := Basis(Vector3.RIGHT, -0.17)
	_piece(root, box(Vector3(0.04, 0.03, 0.002)), Transform3D(tilt, Vector3(0, 0.036, 0.0)), _plain("easel_canvas", Color(0.95, 0.93, 0.88)))
	var dab := SphereMesh.new()
	dab.radius = 0.006
	dab.height = 0.002
	dab.radial_segments = 10
	dab.rings = 3
	for d in [[Vector3(-0.009, 0.042, 0.0), 5], [Vector3(0.007, 0.037, 0.0), 1], [Vector3(-0.002, 0.029, 0.0), 6], [Vector3(0.011, 0.028, 0.0), 4]]:
		_piece(root, dab, Transform3D(tilt.scaled(Vector3(1, 1, 0.5)), tilt * (d[0] - Vector3(0, 0.036, 0)) + Vector3(0, 0.036, 0.0015)), _plain("easel_dab%d" % d[1], Brushwork.PIGMENTS[d[1]]))


## Where a held brush of `kind` lies in the controller's frame: a brush along the aim, a stick of charcoal leaned back
## (STICK_LEAN) with its back end in the hand (STICK_BUTT).
static func hold(kind: Brushwork.Brush) -> Transform3D:
	if not Brushwork.is_stick(kind):
		return Transform3D()
	var lean := Basis(Vector3.RIGHT, -STICK_LEAN)
	var back := Vector3(0, 0, STICK_BUTT - BRUSH_TIP.z - Brushwork.STICKS[kind].y)
	return Transform3D(lean, STICK_GRIP - lean * STICK_GRIP + lean * back)


## A brush of `kind` along its own -z, its tip at BRUSH_TIP; its bristles are the child named "tip", for the paint on
## it. A stick is a bare stick of charcoal as thick as its size, black from end to end.
static func brush(kind: Brushwork.Brush) -> Node3D:
	var root := Node3D.new()
	var along := Basis(Vector3.RIGHT, -PI * 0.5)
	var tip_z := BRUSH_TIP.z
	if Brushwork.is_stick(kind):
		var size: Vector2 = Brushwork.STICKS[kind]
		var stick := _piece(root, charcoal(size.y, size.x), Transform3D(along, Vector3(0, BRUSH_TIP.y, tip_z + size.y * 0.5)), charcoal_material())
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


static func bristle_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://src/bristles.gdshader")
	return mat


## Charcoal's matte black, which no sky glints off, coloured by vertex.
static func charcoal_material() -> StandardMaterial3D:
	return _plain("charcoal", Color.WHITE, {"roughness": 1.0, "metallic_specular": 0.0, "vertex_color_use_as_albedo": true, "vertex_color_is_srgb": true})


## A stick of willow charcoal `length` long along y and `radius` round, centred on its middle: six-sided and uneven,
## crooked toward z as the twig grew, so lying on its side it lies flat, mottled grey-black, its +y end worn grey.
static func charcoal(length: float, radius: float) -> ArrayMesh:
	return shared("charcoal %s %s" % [length, radius], _charcoal.bind(length, radius))


static func _charcoal(length: float, radius: float) -> ArrayMesh:
	var parts: Array = []
	var at := Vector3(0, -length * 0.5, 0)
	var bends := [0.0, 0.09, -0.07, 0.06, -0.05]
	var widths := [1.0, 0.86, 1.08, 0.94, 0.9, 0.6]
	var greys := [0.19, 0.23, 0.17, 0.22, 0.3]
	var seg := length / bends.size()
	for i in bends.size():
		var b := Basis(Vector3.RIGHT, bends[i])
		var c := cylinder(radius * widths[i + 1], radius * widths[i], seg + 0.002, 6)
		var grey: float = greys[i]
		parts.append([c, Transform3D(b.scaled(Vector3(1.0, 1.0, 0.8)), at + b.y * seg * 0.5), Color(grey, grey * 0.96, grey * 0.92)])
		at += b.y * seg
	return bake(parts)


## `parts` ([mesh, transform, colour] each, a null colour keeping the mesh's own) as one mesh coloured by vertex, drawn
## in one call.
static func bake(parts: Array) -> ArrayMesh:
	var arrays := bake_arrays(parts)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_lock.lock()
	_arrays[mesh] = arrays
	_lock.unlock()
	return mesh


## What `bake` makes of `parts`, as surface arrays.
static func bake_arrays(parts: Array) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var index := PackedInt32Array()
	for part: Array in parts:
		var arrays := _arrays_of(part[0])
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
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		for i: int in indices if indices != null else range(arrays[Mesh.ARRAY_VERTEX].size()):
			index.append(base + i)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = index
	return arrays


static func _arrays_of(mesh: Mesh) -> Array:
	_lock.lock()
	var arrays: Variant = _arrays.get(mesh)
	_lock.unlock()
	if arrays == null:
		arrays = (mesh as PrimitiveMesh).get_mesh_arrays() if mesh is PrimitiveMesh else mesh.surface_get_arrays(0)
		_lock.lock()
		_arrays[mesh] = arrays
		_lock.unlock()
	return arrays


## The mesh `make` builds, built once under `key`: every easel and hand holding the same kit shares its geometry, so
## setting one up in play builds and uploads none.
static func shared(key: String, make: Callable) -> Mesh:
	_lock.lock()
	var m: Mesh = _meshes.get(key)
	_lock.unlock()
	if m == null:
		m = make.call()
		_lock.lock()
		m = _meshes.get_or_add(key, m)
		_lock.unlock()
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


## The material under `key`, made once: `colour`, roughness 0.6, then each of `extra`'s properties.
static func _plain(key: String, colour: Color, extra := {}) -> StandardMaterial3D:
	_lock.lock()
	var mat: StandardMaterial3D = _mats.get(key)
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.albedo_color = colour
		mat.roughness = 0.6
		for property: String in extra:
			mat.set(property, extra[property])
		_mats[key] = mat
	_lock.unlock()
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
	var lens := cylinder(0.008, 0.008, 0.006, 16) if selfie else cylinder(0.012, 0.013, 0.018, 16)
	var glass := cylinder(0.006 if selfie else 0.009, 0.006 if selfie else 0.009, 0.001, 16)
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
		_piece(root, part[0], part[1], _plain("camera_%s" % part[2].to_html(), part[2], {"roughness": 0.35 if part[0] == glass else 0.7}))
	if selfie:
		_piece(root, cylinder(0.006, 0.007, SELFIE_LIFT, 10), Transform3D(Basis(), Vector3(0, SELFIE_LIFT * 0.5, 0)), _plain("camera_%s" % Color(0.22, 0.2, 0.19).to_html(), Color(0.22, 0.2, 0.19)))
	var shutter := StandardMaterial3D.new()
	shutter.albedo_color = Color(0.72, 0.56, 0.3)
	shutter.roughness = 0.7
	shutter.emission_enabled = true
	shutter.emission = Color.BLACK
	shutter.emission_energy_multiplier = 2.0
	_piece(root, cylinder(0.004, 0.0045, 0.004, 10), Transform3D(Basis(), Vector3(0.019, y + 0.024, 0.002)), shutter).name = "Button"
	var quad := QuadMesh.new()
	quad.size = size
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = PhotoTool.DARK
	_piece(root, quad, Transform3D(Basis(), Vector3(screen_x, y, 0.0141)), glow).name = "Screen"


## A hand mirror, its glass facing +z over a turned handle: the mirror in the hand, the avatars' icon, and, made large,
## the mirror that stands in the garden (MirrorTool). Returns the glass, an oval (`MIRROR_GLASS` its
## width and height about `MIRROR_CENTRE`) and faces +z.
static func mirror(root: Node3D) -> MeshInstance3D:
	var wood := _plain("mirror_wood", Color(0.42, 0.27, 0.16), {"roughness": 0.55})
	var facing := Basis(Vector3.RIGHT, PI * 0.5)
	var rim := MIRROR_GLASS * 0.5 + Vector2.ONE * MIRROR_RIM
	_piece(root, cylinder(0.0035, 0.0045, MIRROR_HANDLE, 10), Transform3D(Basis(), Vector3(0, MIRROR_HANDLE * 0.5, 0)), wood)
	_piece(root, cylinder(1.0, 1.0, 0.005, 32), Transform3D(Basis.from_scale(Vector3(rim.x, rim.y, 1)) * facing, MIRROR_CENTRE - Vector3(0, 0, 0.003)), wood)
	var glass := _piece(root, cylinder(1.0, 1.0, 0.001, 32), Transform3D(Basis.from_scale(Vector3(MIRROR_GLASS.x * 0.5, MIRROR_GLASS.y * 0.5, 1)) * facing, MIRROR_CENTRE),
		_plain("mirror_glass", Color(0.74, 0.82, 0.86), {"metallic": 0.6, "roughness": 0.12}))
	glass.name = "Glass"
	return glass


## A garden gate standing on y = 0, `width` wide between its stone posts, under a wooden lintel, its picket leaf swung
## in on its left hinge so whoever stands behind it (-z) shows through.
static func gate(root: Node3D, width: float) -> void:
	var stone := _plain("gate_stone", Color(0.52, 0.48, 0.42), {"roughness": 0.9})
	var wood := _plain("mirror_wood", Color(0.42, 0.27, 0.16), {"roughness": 0.55})
	var post := Vector3(0.007, 0.036, 0.007)
	for side in [-1.0, 1.0]:
		_piece(root, box(post), Transform3D(Basis(), Vector3(side * (width + post.x) * 0.5, post.y * 0.5, 0)), stone)
	_piece(root, box(Vector3(width + post.x * 2.6, 0.004, 0.009)), Transform3D(Basis(), Vector3(0, post.y + 0.002, 0)), wood)
	var leaf := Node3D.new()
	leaf.transform = Transform3D(Basis(Vector3.UP, PI * 0.42), Vector3(-width * 0.5, 0.002, 0))
	root.add_child(leaf)
	for i in 4:
		var x := (i + 0.5) * width / 4.0
		_piece(leaf, box(Vector3(0.003, 0.022 + (0.002 if i % 2 == 0 else 0.0), 0.0015)), Transform3D(Basis(), Vector3(x, 0.011, 0)), wood)
	for y in [0.005, 0.017]:
		_piece(leaf, box(Vector3(width, 0.0025, 0.0015)), Transform3D(Basis(), Vector3(width * 0.5, y, -0.0015)), wood)


## A little person: the wheel's people, the avatars to wear and the gardens to join.
static func _figure(root: Node3D) -> void:
	var a := Avatar.open(Avatar.built_in(0), Session.COLOURS[0])
	a.scale = Vector3.ONE * 0.026
	root.add_child(a)
	a.stand.call_deferred()


## A disc of stone ground as the stone tool lays it in `style`, shaded as the ground shades it, fraying toward the rim
## into meadow as scattered stones.
static func _stone_ground(root: Node3D, style: int) -> void:
	var turf := cylinder(0.026, 0.024, 0.004, 24)
	var face := shared("stone_ground_face", func() -> ArrayMesh:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_normal(Vector3.UP)
		for i in turf.radial_segments:
			for a in [-1.0, float(i), float(i + 1)]:
				var at := Vector2.ZERO if a < 0.0 else Vector2.from_angle(TAU * a / turf.radial_segments)
				st.set_uv(at * 0.5 + Vector2.ONE * 0.5)
				st.add_vertex(Vector3(at.x, 0.0, at.y) * turf.top_radius)
		return st.commit())
	var key := "stone_ground_%d" % style
	_lock.lock()
	var mat: ShaderMaterial = _mats.get(key)
	_lock.unlock()
	if mat == null:
		mat = _stone_disc(preload("res://src/stone_disc.gdshader"), style)
		mat.set_meta("icon_material", _stone_disc(preload("res://src/stone_disc_icon.gdshader"), style))
		_lock.lock()
		_mats[key] = mat
		_lock.unlock()
	_piece(root, turf, Transform3D(Basis(), Vector3(0, 0.002, 0)), _plain("stone_ground_side", Meadow.GROUND[&"earth"], {"roughness": 1.0}))
	_piece(root, face, Transform3D(Basis(), Vector3(0, 0.0041, 0)), mat)


static func _stone_disc(shader: Shader, style: int) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	StoneStyles.apply(mat)
	mat.set_shader_parameter("style", style)
	mat.set_shader_parameter("earth", Meadow.GROUND[&"earth"])
	mat.set_shader_parameter("meadow", Meadow.GRASS[&"root_color"].lerp(Meadow.GRASS[&"tip_lush"].lerp(Meadow.GRASS[&"tip_dry"], 0.5), 0.6))
	return mat


## A pond in small: a sandy dish holding a disc of glinting water inside a line of foam, pebbles on its bank.
static func _pond(root: Node3D) -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = 0.0185
	ring.outer_radius = 0.0205
	ring.rings = 24
	ring.ring_segments = 4
	var parts := [
		[cylinder(0.026, 0.021, 0.006, 20), Vector3(0, 0.003, 0), Vector3.ONE, _plain("sand", Color(0.62, 0.53, 0.38), {"roughness": 1.0})],
		[cylinder(0.019, 0.019, 0.001, 20), Vector3(0, 0.0063, 0), Vector3.ONE, _plain("water", Color(0.16, 0.48, 0.52), {"roughness": 0.08, "metallic_specular": 0.7})],
		[ring, Vector3(0, 0.0064, 0), Vector3(1, 0.3, 1), _plain("foam", Color(0.95, 0.97, 0.94))],
	]
	for k in 3:
		var a := TAU * (0.1 + k * 0.13)
		parts.append([Meshes.rounded_box(0.3, 2, 5), Vector3(cos(a), 0, sin(a)) * 0.024 + Vector3(0, 0.0068, 0), Vector3(0.005, 0.003, 0.004) * (1.0 - k * 0.15), _plain("pebble", Color(0.6, 0.6, 0.57), {"roughness": 0.9})])
	for part in parts:
		_piece(root, part[0], Transform3D(Basis.from_scale(part[2]), part[1]), part[3])


static func _wall(root: Node3D, finish := WallLayout.Finish.BARE, top := WallLayout.Top.CRENEL, arched := false, wear := 0.0, window := -1) -> void:
	var layout := WallLayout.new()
	layout.finish = finish
	layout.wear = wear
	layout.seed = 4
	layout.height = 2.4 if arched or wear > 0.0 or window >= 0 else 1.5
	layout.top = top
	layout.points = [Vector3(-1.4, 0, 0), Vector3(1.4, 0, 0)]
	if arched:
		layout.openings = [WallLayout.archway(1.4)]
	if window >= 0:
		layout.openings = [Vector4(1.4, WallLayout.lowest(window) + 0.15, window, 1.0)]
	layout.build(Terrain.flat)
	_stones(root, layout.stones, 0.015)


## A square of a house's floor, flags or `planks` on their bed, turned from lying flat to face the eye a little from above.
static func _floor(root: Node3D, planks: bool) -> void:
	var layout := WallLayout.new()
	layout.planks = planks
	layout.seed = 5
	layout.height = 2.4
	layout.closed = true
	layout.top = WallLayout.Top.CAP
	layout.cover = WallLayout.Cover.ROOF
	layout.points = WallLayout.rectangle(Vector3(-1.4, 0, 0), Vector3(1.4, 0, 0), 2.8)
	layout.build(Terrain.flat)
	var floor: Array[Dictionary] = layout.stones.filter(func(s: Dictionary) -> bool: return s.kind in WallLayout.FLOOR_KINDS)
	_stones(root, floor, 0.017)
	root.get_child(0).transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.36), Vector3.ZERO) * root.get_child(0).transform


## A cottage: stone walls with a door toward the eye under a tiled gable roof, or a flat one decked in `deck`; with a
## `foundation` choice, raised on it.
static func _house(root: Node3D, finish := WallLayout.Finish.BARE, gable_end := WallLayout.GableEnd.WALL, flat := false, thatched := false, deck := RoofLayout.Deck.STONE, arched := true, foundation := -1, wear := 0.0) -> void:
	var layout := WallLayout.new()
	if foundation >= 0:
		layout.rise = 1.5
		layout.foundation = foundation as WallLayout.Foundation
	layout.finish = finish
	layout.wear = wear
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
	roof.stepped = layout.gable_kind() == WallLayout.GableEnd.STEPS
	roof.thatch = thatched
	roof.deck = deck
	layout.gable = roof
	layout.build(Terrain.flat)
	roof.base = layout.samples[0].y + layout.height + WallLayout.CAP
	roof.build()
	layout.fit_under(roof)
	_roofed(root, layout, roof, layout.plastered())


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
	layout.build(Terrain.flat)
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
		_piece(root, coat, Transform3D(Basis.from_scale(Vector3.ONE * 0.012), Vector3.ZERO), _vertex_mat("thatch", 0.95, false))
	if not plastered:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in roof.gable_faces:
		st.add_vertex(p * 0.012)
	st.generate_normals()
	_piece(root, st.commit(), Transform3D(), _plain("plaster", WallLayout.PLASTER, {"roughness": 0.9}))


static func _fence(root: Node3D, finish := WallLayout.Finish.BARE) -> void:
	var layout := WallLayout.new()
	layout.seed = 6
	layout.fence = true
	layout.finish = finish
	layout.height = WallLayout.FENCE_HEIGHT
	layout.points = [Vector3(-1.2, 0, 0), Vector3(1.2, 0, 0)]
	layout.build(Terrain.flat)
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
## wall's centre line, a post lantern's foot, or where a chimney rises through the slope: the one `on` would lay next
## at `spot`, or one through a small roof's ridge.
static func fitting(what: String, on: RoofLayout = null, spot := Vector2.ZERO, index := 0) -> Node3D:
	var laid := fitting_parts(what, on, spot, index)
	var root := Node3D.new()
	var stones := Stones.new()
	stones.lay(laid.parts)
	root.add_child(stones)
	if not laid.flames.is_empty() or not laid.cloths.is_empty():
		var lit := Fittings.new()
		lit.lay(laid.flames, laid.cloths)
		root.add_child(lit)
	for g in root.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


## What `fitting` draws, as {parts, flames, cloths} about its mount.
static func fitting_parts(what: String, on: RoofLayout = null, spot := Vector2.ZERO, index := 0) -> Dictionary:
	var parts: Array[Dictionary] = []
	var flames: Array[Transform3D] = []
	var cloths: Array[Dictionary] = []
	var mount := Vector3.ZERO
	if what == "chimney":
		var roof := on
		if roof == null:
			roof = RoofLayout.new()
			roof.corners = [Vector3(-2, 0, -1.5), Vector3(2, 0, -1.5), Vector3(2, 0, 1.5), Vector3(-2, 0, 1.5)]
		parts = roof.chimney_parts(spot, index)
		var f := roof.frame()
		mount = f.mid + f.along * spot.x + f.across * spot.y + Vector3.UP * roof.spot_height(spot)
	else:
		var layout := WallLayout.new()
		layout.seed = 5
		layout.height = 2.4
		layout.top = WallLayout.Top.CAP
		layout.fence = what == "post_lantern"
		layout.points = [Vector3(-2, 0, 0), Vector3(2, 0, 0)]
		layout.resample(Terrain.flat)
		var s := layout.nearest_post(2.0) if layout.fence else 2.0
		match what:
			"window":
				layout.openings = [Vector4(s, 1.5, WallLayout.Family.COTTAGE, 1.0)]
			"lantern", "post_lantern":
				layout.lanterns = [Vector3(s, 1.5, 1.0)]
			"flag":
				layout.flags = [s]
		layout.build(Terrain.flat)
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
	var kept: Array[Dictionary] = []
	for p in parts:
		if p.kind in FITTING_PARTS[what]:
			var q := p.duplicate()
			q.xform = Transform3D(p.xform.basis, p.xform.origin - mount)
			kept.append(q)
	var moved_flames: Array[Transform3D] = []
	for f in flames:
		moved_flames.append(Transform3D(f.basis, f.origin - mount))
	var moved_cloths: Array[Dictionary] = []
	for c in cloths:
		moved_cloths.append({"xform": Transform3D(c.xform.basis, c.xform.origin - mount), "color": c.color})
	return {"parts": kept, "flames": moved_flames, "cloths": moved_cloths}


## A short stroke of the path tool in `surface`: a strip of dirt, of sand, or of a bed's dark earth sprouting a row of
## greens either side; cobbles and flagstones are the stone tool's disc of their style.
static func _path(root: Node3D, surface := PathLayout.Surface.DIRT) -> void:
	if PathLayout.wears(surface) == Ground.Kind.STONE:
		_stone_ground(root, PathLayout.look(surface))
		return
	var layout := PathLayout.new()
	layout.seed = 3
	for p in [Vector3(-0.3, 0, -1.6), Vector3(0.25, 0, -0.5), Vector3(-0.2, 0, 0.6), Vector3(0.3, 0, 1.6)]:
		layout.add(p, 0.62)
	layout.plan()
	var colour: Color = Meadow.GROUND[{PathLayout.Surface.SAND: &"sand", PathLayout.Surface.BED: &"tilled"}.get(surface, &"trodden")]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in layout.samples.size() - 1:
		var a := layout.frame_at(layout.lengths[i])
		var b := layout.frame_at(layout.lengths[i + 1])
		var across_a: Vector3 = a.along.cross(Vector3.UP) * a.half
		var across_b: Vector3 = b.along.cross(Vector3.UP) * b.half
		for v in [a.point - across_a, b.point - across_b, a.point + across_a, a.point + across_a, b.point - across_b, b.point + across_b]:
			st.set_normal(Vector3.UP)
			st.set_color(colour)
			st.add_vertex(v * 0.024)
	_piece(root, st.commit(), Transform3D(), _vertex_mat("dirt", 1.0, false))
	if surface != PathLayout.Surface.BED:
		return
	var sprout := shared("bed_sprout", func() -> ArrayMesh:
		var ball := SphereMesh.new()
		ball.radius = 0.004
		ball.height = 0.005
		ball.radial_segments = 8
		ball.rings = 3
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ball.get_mesh_arrays())
		return mesh)
	var green := _plain("bed_sprout", Color(0.36, 0.58, 0.22), {"roughness": 0.9})
	for k in 7:
		var f := layout.frame_at(layout.length() * (k + 0.5) / 7.0)
		for edge in [-0.5, 0.5]:
			var at: Vector3 = f.point + f.along.cross(Vector3.UP) * f.half * edge
			_piece(root, sprout, Transform3D(Basis(), at * 0.024 + Vector3.UP * 0.002), green)


static func _stones(root: Node3D, stones: Array[Dictionary], scale: float) -> void:
	if stones.is_empty():
		return
	var mesh := shared("tool_stones_%s" % hash(stones), func() -> ArrayMesh:
		var parts := []
		for stone in stones:
			var at: Transform3D = stone.xform
			at.basis *= Stones.FLIPS[stone.get("variant", 0)]
			var colour: Color = WallLayout.GLASS if stone.kind == "glass" else stone.color
			colour *= Color(stone.ao, stone.ao, stone.ao)
			parts.append([Stones.far_mesh(), at, colour])
		var imported := ImporterMesh.new()
		imported.add_surface(Mesh.PRIMITIVE_TRIANGLES, bake_arrays(parts))
		imported.generate_lods(60.0, 25.0, [])
		return imported.get_mesh())
	_piece(root, mesh, Transform3D(Basis.from_scale(Vector3.ONE * scale), Vector3.ZERO), _vertex_mat("tool_stone", 0.9, false))


static func _flowers(root: Node3D) -> void:
	var spots := [Vector3(0, 0, 0), Vector3(0.09, 0, 0.05), Vector3(-0.07, 0, 0.07)]
	var sizes := [1.15, 0.8, 0.9]
	for i in 3:
		_piece(root, Meshes.flower(6, FloraLayout.FLOWER_COLORS[[4, 7, 1][i]]), Transform3D(Basis(Vector3.UP, i * 1.3).scaled(Vector3.ONE * sizes[i] * 0.17), spots[i] * 0.17), _vertex_mat("flower", 0.8, true))


static func _grass(root: Node3D) -> void:
	_piece(root, Meshes.grass_clump(16, 3), Transform3D(Basis.from_scale(Vector3.ONE * 0.16), Vector3.ZERO), _plain("grass", Color(0.36, 0.6, 0.16), {"cull_mode": BaseMaterial3D.CULL_DISABLED, "roughness": 0.9}))


static func _tree(root: Node3D, species := FloraLayout.Species.OAK) -> void:
	var t := FloraLayout.tree(Vector3(0, 0.2, 0), 11, species)
	var bark := _vertex_mat("bark", 1.0, false)
	var trunk_mm := multimesh(cylinder(0.16, 0.3, 1.0, 8), 1)
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
	model.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.12), Vector3.ZERO) * BoulderLayout.rest(shape, Quaternion.IDENTITY, 0.065, 0, 0, Terrain.flat)
	root.add_child(model)


## A boulder with a pebble beside it, in wall stone.
static func _boulders(root: Node3D) -> void:
	var stone := _plain("boulder", WallLayout.STONE, {"roughness": 0.9})
	for b in [[7, Vector3(-0.004, 0, 0), 0.042], [3, Vector3(0.024, 0, 0.008), 0.016]]:
		var shape := BoulderLayout.shape(b[0])
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, BoulderLayout.arrays(shape, BoulderLayout.FAR + 1))
		_piece(root, mesh, BoulderLayout.rest(shape, Quaternion.IDENTITY, b[2], b[1].x, b[1].z, func(_x: float, _z: float) -> float: return b[1].y), stone)


## A garden spade held blade ahead: it digs things up.
static func _spade(root: Node3D) -> void:
	var wood := _plain("wood", Color(0.55, 0.38, 0.22), {"roughness": 0.9})
	_piece(root, box(Vector3(0.02, 0.0015, 0.024)), Transform3D(Basis(), SPADE_EDGE + Vector3(0, 0, 0.012)), _plain("steel", Color(0.62, 0.64, 0.66), {"metallic": 0.6, "roughness": 0.4}))
	_piece(root, cylinder(0.0022, 0.0022, 0.04, 6), Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, -0.008)), wood)
	_piece(root, cylinder(0.002, 0.002, 0.012, 6), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, 0, 0.012)), wood)


## A small clay dish heaped with bird seed: striped sunflower seeds among round millet.
static func _seeds(root: Node3D) -> void:
	_piece(root, cylinder(0.022, 0.016, 0.007, 20), Transform3D(Basis(), Vector3(0, 0.0035, 0)), _plain("clay", Color(0.72, 0.42, 0.28), {"roughness": 0.85}))
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
	_piece(root, st.commit(), Transform3D(), seed_material())


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
	return _plain(key, Color.WHITE, {"vertex_color_use_as_albedo": true, "roughness": roughness, "cull_mode": BaseMaterial3D.CULL_DISABLED if two_sided else BaseMaterial3D.CULL_BACK})


## A decoration as `layout` lays it, its flames burning in `look` (a Palette.Element.LANTERN swatch).
static func decoration(layout: DecorationLayout, look := 0) -> Node3D:
	var root := Node3D.new()
	var stones := Stones.new()
	stones.lay(layout.parts)
	root.add_child(stones)
	if not layout.flames.is_empty():
		var fire := Fittings.new()
		fire.lay(layout.flames, [], look)
		root.add_child(fire)
	if not layout.flowers.is_empty():
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for f in layout.flowers:
			surface.append_from(Meshes.flower(6, f.color), 0, f.xform)
		var flower := MeshInstance3D.new()
		flower.mesh = surface.commit()
		flower.material_override = _vertex_mat("decoration_flowers", 0.8, true)
		root.add_child(flower)
	if not layout.pictures.is_empty():
		var drawn := MeshInstance3D.new()
		drawn.mesh = bake(layout.pictures.map(func(x: Transform3D) -> Array: return [picture(Hand.Tool.STYLE), x, null]))
		var mat := _vertex_mat("decoration_picture", 0.6, false)
		# The picture's colours are the wand's albedos, which are sRGB.
		mat.vertex_color_is_srgb = true
		drawn.material_override = mat
		drawn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(drawn)
	return root


## `tool`'s own model (`build`) as one mesh, each piece in its material's colour, so a picture of it is the tool.
static func picture(tool: Hand.Tool) -> ArrayMesh:
	return shared("picture_%d" % tool, func() -> ArrayMesh:
		var model := build(tool)
		var parts := []
		var pending: Array[Node] = [model]
		while not pending.is_empty():
			var n: Node = pending.pop_back()
			pending.append_array(n.get_children())
			if n is MeshInstance3D:
				var mi := n as MeshInstance3D
				parts.append([mi.mesh, _within(model, mi), (mi.material_override as BaseMaterial3D).albedo_color])
		model.free()
		return bake(parts))


static func _within(root: Node3D, n: Node3D) -> Transform3D:
	var x := Transform3D.IDENTITY
	while n != root:
		x = n.transform * x
		n = n.get_parent()
	return x
