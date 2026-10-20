class_name Easels
extends Node3D

## The garden's easels, each a big canvas on an A-frame with a tray in front holding a painter's kit for each medium: a
## box of watercolour pans beside a glass of water, a wooden oil palette with its paint squeezed out round the edge,
## sticks of charcoal, and a pot of brushes. `World` puts and takes them and hands them their strokes; `EaselTool`
## paints on them. An easel's local frame stands on the ground under it, the canvas facing +z.

## The canvas tilts its top back from the painter this far.
const TILT := deg_to_rad(10.0)
const CANVAS_AT := Vector3(0, 1.32, 0)
const TRAY_Y := 0.72
const TRAY := AABB(Vector3(-0.82, TRAY_Y - 0.03, 0.035), Vector3(1.64, 0.03, 0.31))
## The rail along the tray's front edge: height and thickness.
const LIP := Vector2(0.035, 0.012)
## Where each thing on the tray sits, on the tray's top.
const POT := Vector3(-0.68, TRAY_Y, 0.2)
const JAR := Vector3(-0.54, TRAY_Y, 0.23)
const STICK := Vector3(-0.14, TRAY_Y, 0.29)
## Each medium's palette where it rests: the watercolour box beside its water, the oil palette in the tray's far
## corner, inside its lip and clear of the leg crossing the tray behind it.
const KITS := {
	Brushwork.Medium.WATER: Vector3(-0.32, TRAY_Y + 0.0105, 0.21),
	Brushwork.Medium.OIL: Vector3(TRAY.end.x - PALETTE_SIZE.x * 0.5 - CLEAR, TRAY_Y + 0.006, TRAY.end.z - LIP.y - PALETTE_SIZE.y * 0.5 - CLEAR),
}
## How near its rest a grip takes or sets down each palette.
const KIT_REACH := {Brushwork.Medium.WATER: 0.1, Brushwork.Medium.OIL: PALETTE_SIZE.x * 0.5}
const CLEAR := 0.01
const JAR_SIZE := Vector2(0.042, 0.1)
## The brushes standing in the pot, by kind: where each one's tip stands above the pot.
const BRUSH_TIPS := {Brushwork.Brush.SMALL: Vector3(-0.022, 0.3, -0.012), Brushwork.Brush.BIG: Vector3(0.02, 0.32, -0.008), Brushwork.Brush.FLAT: Vector3(0.0, 0.28, 0.024)}
## Each palette, in its own frame: a thumb hole at its -x end, where a hand holds it, and its paint toward the +x end.
## The oil palette's paint lies round its far edge with its open board, the mixing field (`Mixing`), inside it; the
## box's pans lie in two rows beside a field showing the brush's own mix.
const PALETTE_SIZE := Vector2(0.36, 0.24)
const THUMB := Vector3(-0.12, 0, 0)
const MIX_AT := Vector3(0.1, 0.0075, 0)
## The oil palette's board top, where its mixing field lies.
const BOARD_TOP := 0.004
const WELL_RADIUS := 0.018
const PAN := Vector2(0.024, 0.035)
const PAN_TOP := 0.0105
## A tip is in a well anywhere over its paint or pushed on through the board, which nothing stops a hand doing.
const WELL_REACH := 0.025
const WELL_DEPTH := Vector2(-0.05, 0.03)
## The stand's legs run this far behind the canvas's face, clear of its backing, so none crosses the painting.
const LEG_BACK := 0.07
## Easels stand at least this far apart, and a garden holds at most so many: each canvas is a few tens of MB on the GPU.
const SPACING := 1.4
const MAX := 4
## The easel's bounds in its own frame, for the delete tool's beam.
const BOUNDS := AABB(Vector3(-0.82, 0.0, -0.75), Vector3(1.64, 2.0, 1.1))

## The watercolour box's white enamel, which its mixing field starts as.
const BOX_WHITE := Color(0.95, 0.95, 0.93)
## Clean water in the jar.
const WATER := Color(0.38, 0.62, 0.86, 0.75)

static var _mats := {}

var easels := {}


func _init() -> void:
	name = "Easels"
	# The shared geometry, the paint pipeline and the easel's draw pipelines are built as the game loads, by an easel
	# that stands hidden for its first frame, so not even the first placement in a session builds any of them.
	var warm := Easel.new()
	_build(warm)
	var look := ShaderMaterial.new()
	look.shader = preload("res://src/canvas.gdshader")
	warm.canvas_mesh.material_override = look
	warm.visible = false
	add_child(warm)
	warm.queue_free()
	Canvas.warm()


## Where pigment `i` lies on `kit`'s palette, in its frame.
static func well(kit: Brushwork.Medium, i: int) -> Vector3:
	if kit == Brushwork.Medium.WATER:
		return Vector3(-0.035 + (i % 4) * 0.029, PAN_TOP, (i / 4 - 0.5) * 0.044)
	var a := lerpf(-1.5, 1.5, float(i) / (Brushwork.PIGMENTS.size() - 1))
	return Vector3(cos(a) * PALETTE_SIZE.x * 0.38, 0.006, sin(a) * PALETTE_SIZE.y * 0.36)


## The well a tip at `local`, in `kit`'s palette's frame, is in, or -1.
static func well_at(kit: Brushwork.Medium, local: Vector3) -> int:
	if local.y < WELL_DEPTH.x or local.y > WELL_DEPTH.y:
		return -1
	var best := -1
	var near := WELL_REACH
	for i in Brushwork.PIGMENTS.size():
		var w := well(kit, i)
		var d := Vector2(local.x - w.x, local.z - w.z).length()
		if d < near:
			near = d
			best = i
	return best


class Easel:
	extends Node3D

	var id := -1
	var canvas: Canvas
	var canvas_mesh: MeshInstance3D
	## Each medium's palette (by Brushwork.Medium) as it rests on the tray; a hand holding one carries it off
	## (EaselTool) and it comes back when let go.
	var palettes := {}
	## The watercolour box's field showing the brush's mix, and the oil palette's mixing field and what draws it.
	var wash: StandardMaterial3D
	var mixing := Mixing.new()
	var field: ImageTexture
	## The water in the jar, clouded by each rinse.
	var water: StandardMaterial3D
	var brushes := {}
	var stick: Node3D

	## The canvas's frame: x along it, y up it, z out of it toward the painter, origin at its centre.
	func canvas_frame() -> Transform3D:
		return global_transform * Easels.canvas_local()

	## Where `point` lies on the canvas: x, y as uv (0..1, v down), z its distance in front of the canvas's face.
	func on_canvas(point: Vector3) -> Vector3:
		var p := canvas_frame().affine_inverse() * point
		return Vector3(p.x / Brushwork.METRES.x + 0.5, 0.5 - p.y / Brushwork.METRES.y, p.z)

	func tray(at: Vector3) -> Vector3:
		return global_transform * at

	## Draws the mixing field as `mixing` holds it now.
	func show_mixing() -> void:
		field.update(Image.create_from_data(Mixing.SIZE.x, Mixing.SIZE.y, false, Image.FORMAT_RGBA8, mixing.bytes))


static func canvas_local() -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, -TILT), CANVAS_AT)


func find(id: int) -> Easel:
	return easels.get(id)


func put(id: int, data: Dictionary) -> Easel:
	take(id)
	var e := Easel.new()
	e.id = id
	e.name = "Easel%d" % id
	e.add_to_group("easel")
	e.transform = Transform3D(Basis(Vector3.UP, data.yaw), data.at)
	e.canvas = Canvas.new()
	e.add_child(e.canvas)
	_build(e)
	e.canvas_mesh.material_override = e.canvas.material
	add_child(e)
	easels[id] = e
	e.canvas.rebuild(data.strokes)
	mixed(id, data.mix, false)
	return e


func take(id: int) -> void:
	var e: Easel = easels.get(id)
	if e == null:
		return
	easels.erase(id)
	remove_child(e)
	e.queue_free()


func clear() -> void:
	for id in easels.keys():
		take(id)


## A stroke from the garden on easel `id`: the painter's own is on the canvas already; anyone else's plays as it was
## painted.
func painted(id: int, stroke: Dictionary, own: bool) -> void:
	var e := find(id)
	if e != null and not own:
		e.canvas.play(stroke, 0)


## Easel `id`'s oil palette's mixing field as `bytes` (`Mixing.bytes`), from the garden; the painter's own is on the
## palette already.
func mixed(id: int, bytes: PackedByteArray, own: bool) -> void:
	var e := find(id)
	if e != null and not own:
		e.mixing.load_bytes(bytes)
		e.show_mixing()


## Lays easel `id`'s painting again from its strokes, after one is taken back or a fresh sheet goes up.
func repaint(id: int, strokes: Array) -> void:
	var e := find(id)
	if e != null:
		e.canvas.rebuild(strokes)


## The easel a ray from `origin` along `dir` meets first, and where: {easel, along, point}, or {}.
func pick(origin: Vector3, dir: Vector3) -> Dictionary:
	var best := {}
	for e: Easel in easels.values():
		var inv := e.global_transform.affine_inverse()
		var hit: Variant = BOUNDS.intersects_ray(inv * origin, inv.basis * dir)
		if hit == null:
			continue
		var point: Vector3 = e.global_transform * hit
		var along := (point - origin).dot(dir.normalized())
		if best.is_empty() or along < best.along:
			best = {"easel": e, "along": along, "point": point}
	return best


## The easel standing nearest `at` across the ground, or null.
func nearest(at: Vector3) -> Easel:
	var best: Easel = null
	for e: Easel in easels.values():
		if best == null or _flat(e.global_position, at) < _flat(best.global_position, at):
			best = e
	return best


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Whether an easel may stand at `at` among `standing` ({at, ...} by id).
static func room_at(at: Vector3, standing: Dictionary) -> bool:
	return crowded(at, standing).is_empty()


## Why no easel may stand at `at` among `standing`, or "" if one may.
static func crowded(at: Vector3, standing: Dictionary) -> String:
	if standing.size() >= MAX:
		return "the garden holds its %d easels" % MAX
	if not standing.values().all(func(d: Dictionary) -> bool: return _flat(d.at, at) >= SPACING):
		return "another easel stands within %.1f m" % SPACING
	return ""


## The yaw that turns an easel at `at` to face `toward`.
static func facing(at: Vector3, toward: Vector3) -> float:
	return atan2(toward.x - at.x, toward.z - at.z)


static func _mat(key: String, colour: Color, roughness := 0.7) -> StandardMaterial3D:
	var m: StandardMaterial3D = _mats.get(key)
	if m == null:
		m = StandardMaterial3D.new()
		m.albedo_color = colour
		m.roughness = roughness
		_mats[key] = m
	return m


static func _part(root: Node3D, mesh: Mesh, at: Transform3D, mat: Material, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = at
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi


static func _cylinder(radius: float, height: float, segments := 16) -> CylinderMesh:
	return ToolModels.cylinder(radius, radius, height, segments)


## A square beam `thickness` across from `from` to `to`.
static func _beam(root: Node3D, from: Vector3, to: Vector3, thickness: float, mat: Material) -> void:
	var along := to - from
	var y := along.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	_part(root, ToolModels.box(Vector3(thickness, along.length(), thickness)), Transform3D(Basis(x, y, x.cross(y)), (from + to) * 0.5), mat)


func _build(e: Easel) -> void:
	var wood := _mat("wood", Color(0.62, 0.45, 0.3))
	var dark := _mat("dark_wood", Color(0.42, 0.3, 0.2))
	var frame := canvas_local()
	var stand := Node3D.new()
	stand.name = "stand"
	e.add_child(stand)
	var top := Brushwork.METRES.y * 0.5 + 0.08
	for side in [-1.0, 1.0]:
		_beam(stand, _foot(side * 0.62), frame * Vector3(side * 0.1, top, -LEG_BACK), 0.045, wood)
	_beam(stand, Vector3(0, 0, -0.7), frame * Vector3(0, top - 0.04, -LEG_BACK - 0.04), 0.04, wood)
	_part(stand, ToolModels.box(TRAY.size), Transform3D(Basis(), TRAY.get_center()), wood)
	_part(stand, ToolModels.box(Vector3(TRAY.size.x, LIP.x, LIP.y)), Transform3D(Basis(), Vector3(0, TRAY_Y + LIP.x * 0.5, TRAY.end.z - LIP.y * 0.5)), dark)
	_part(stand, ToolModels.box(Vector3(0.3, 0.05, 0.03)), frame * Transform3D(Basis(), Vector3(0, Brushwork.METRES.y * 0.5 + 0.02, -0.048)), dark)
	_part(e, ToolModels.box(Vector3(Brushwork.METRES.x + 0.03, Brushwork.METRES.y + 0.03, 0.03)), frame * Transform3D(Basis(), Vector3(0, 0, -0.017)), _mat("linen", Color(0.86, 0.82, 0.74), 0.9))
	e.canvas_mesh = _part(e, _quad("canvas", Brushwork.METRES), frame, null, false)
	var implements := Node3D.new()
	implements.name = "implements"
	e.add_child(implements)
	var glass := _mat("glass", Color(0.86, 0.93, 0.96, 0.22), 0.04)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.rim_enabled = true
	glass.rim = 0.6
	glass.render_priority = 1
	var rim := ToolModels.shared("jar_rim", func() -> TorusMesh:
		var t := TorusMesh.new()
		t.inner_radius = JAR_SIZE.x - 0.003
		t.outer_radius = JAR_SIZE.x + 0.002
		t.rings = 16
		t.ring_segments = 6
		return t)
	_part(implements, _cylinder(JAR_SIZE.x, JAR_SIZE.y, 20), Transform3D(Basis(), JAR + Vector3(0, JAR_SIZE.y * 0.5, 0)), glass, false)
	_part(implements, rim, Transform3D(Basis(), JAR + Vector3(0, JAR_SIZE.y, 0)), _mat("glass_rim", Color(0.9, 0.95, 0.97), 0.05), false)
	e.water = _clean_water().duplicate()
	_part(implements, _cylinder(JAR_SIZE.x - 0.003, JAR_SIZE.y * 0.72, 20), Transform3D(Basis(), JAR + Vector3(0, 0.002 + JAR_SIZE.y * 0.36, 0)), e.water, false)
	_part(implements, _cylinder(0.055, 0.12), Transform3D(Basis(), POT + Vector3(0, 0.06, 0)), _mat("pot", Color(0.66, 0.36, 0.26)))
	_part(implements, _cylinder(0.047, 0.002), Transform3D(Basis(), POT + Vector3(0, 0.12, 0)), _mat("pot_inside", Color(0.24, 0.13, 0.1)), false)
	for kind in BRUSH_TIPS:
		var b := ToolModels.brush(kind)
		var tip: Vector3 = POT + BRUSH_TIPS[kind]
		b.transform = Transform3D(Basis.looking_at(Vector3.UP, Vector3.BACK), tip + Vector3.UP * ToolModels.BRUSH_TIP.z)
		implements.add_child(b)
		e.brushes[kind] = b
	e.stick = ToolModels.brush(Brushwork.Brush.STICK)
	e.stick.transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), STICK + Vector3(0, ToolModels.CHARCOAL_RADIUS - ToolModels.BRUSH_TIP.y, 0))
	implements.add_child(e.stick)
	_part(implements, ToolModels.shared("tray_charcoal", _tray_charcoal), Transform3D(), ToolModels.charcoal_material())
	for kit in KITS:
		var palette := watercolours() if kit == Brushwork.Medium.WATER else oils()
		palette.name = Brushwork.Medium.keys()[kit].to_lower()
		palette.position = KITS[kit]
		implements.add_child(palette)
		e.palettes[kit] = palette
	e.wash = e.palettes[Brushwork.Medium.WATER].get_meta("mix")
	e.field = ImageTexture.create_from_image(Image.create_from_data(Mixing.SIZE.x, Mixing.SIZE.y, false, Image.FORMAT_RGBA8, e.mixing.bytes))
	var film := ShaderMaterial.new()
	film.shader = preload("res://src/mixing.gdshader")
	film.set_shader_parameter("field", e.field)
	_part(e.palettes[Brushwork.Medium.OIL], _quad("oil_field", PALETTE_SIZE), Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, BOARD_TOP + 0.0003, 0)), film, false)


static func _quad(key: String, size: Vector2) -> QuadMesh:
	return ToolModels.shared(key, func() -> QuadMesh:
		var q := QuadMesh.new()
		q.size = size
		return q)


static func _tray_charcoal() -> ArrayMesh:
	var sticks: Array = []
	for piece: Array in [[0.05, -0.021, 0.17], [0.02, -0.04, 0.12], [0.07, -0.06, 0.09]]:
		var along := Basis(Vector3.UP, piece[0] - 0.04) * Basis(Vector3.BACK, -PI * 0.5)
		sticks.append([ToolModels.charcoal(piece[2]), Transform3D(along, Vector3(STICK.x + piece[0] + piece[2] * 0.5, TRAY_Y + ToolModels.CHARCOAL_RADIUS, STICK.z + piece[1])), null])
	return ToolModels.bake(sticks)


## Where a leg standing `x` along the canvas, LEG_BACK behind it, meets the ground.
static func _foot(x: float) -> Vector3:
	var frame := canvas_local()
	var at := frame * Vector3(x, 0, -LEG_BACK)
	return at - frame.basis.y * (at.y / frame.basis.y.y)


## An oil palette: a wooden board with its eight colours squeezed out round its far end and a thumb hole at its near
## one; its mixing field is laid on it per easel.
static func oils() -> Node3D:
	var root := Node3D.new()
	_part(root, ToolModels.shared("oil_board", _oil_board), Transform3D(), _baked("oil_board", 0.45), false)
	_part(root, ToolModels.shared("oil_paint", _oil_paint), Transform3D(), _baked("oil_paint", 0.12), false)
	return root


static func _oil_board() -> ArrayMesh:
	return ToolModels.bake([
		[_cylinder(0.5, 0.008, 32), Transform3D(Basis().scaled(Vector3(PALETTE_SIZE.x, 1.0, PALETTE_SIZE.y)), Vector3.ZERO), Color(0.86, 0.68, 0.46)],
		[_cylinder(0.016, 0.0085, 12), Transform3D(Basis(), THUMB + Vector3(0, 0.0003, 0)), Color(0.3, 0.22, 0.16)],
	])


static func _oil_paint() -> ArrayMesh:
	var blob := SphereMesh.new()
	blob.radius = 0.015
	blob.height = 0.012
	blob.radial_segments = 12
	blob.rings = 5
	var curl := SphereMesh.new()
	curl.radius = 0.007
	curl.height = 0.009
	curl.radial_segments = 8
	curl.rings = 4
	var paint: Array = []
	for i in Brushwork.PIGMENTS.size():
		var w := well(Brushwork.Medium.OIL, i)
		paint.append([blob, Transform3D(Basis(Vector3.UP, i * 1.3).scaled(Vector3(1.15, 1, 0.9)), w), Brushwork.PIGMENTS[i]])
		paint.append([curl, Transform3D(Basis(Vector3.UP, i * 1.3), w + Vector3(0.003, 0.006, -0.002)), Brushwork.PIGMENTS[i]])
	return ToolModels.bake(paint)


## A box of watercolour pans: black enamel outside, white inside, two rows of pans of dry colour and a white mixing
## field, with a thumb ring at its near end.
static func watercolours() -> Node3D:
	var root := Node3D.new()
	_part(root, ToolModels.shared("watercolours", _watercolours), Transform3D(), _baked("watercolours", 0.7), false)
	var mix := StandardMaterial3D.new()
	mix.albedo_color = BOX_WHITE
	mix.roughness = 0.35
	var smear := ToolModels.shared("smear", func() -> SphereMesh:
		var m := SphereMesh.new()
		m.radius = 0.022
		m.height = 0.006
		m.radial_segments = 16
		m.rings = 4
		return m)
	_part(root, smear, Transform3D(Basis().scaled(Vector3(1.3, 1, 0.9)), MIX_AT), mix, false)
	root.set_meta("mix", mix)
	return root


static func _watercolours() -> ArrayMesh:
	var black := Color(0.08, 0.08, 0.09)
	var parts: Array = [
		[ToolModels.box(Vector3(0.19, 0.016, 0.11)), Transform3D(Basis(), Vector3(0.035, -0.002, 0)), black],
		[ToolModels.box(Vector3(0.08, 0.006, 0.05)), Transform3D(Basis(), Vector3(-0.1, -0.007, 0)), black],
		[ToolModels.box(Vector3(0.182, 0.002, 0.102)), Transform3D(Basis(), Vector3(0.035, 0.0065, 0)), BOX_WHITE],
		[_cylinder(0.012, 0.0065, 12), Transform3D(Basis(), THUMB + Vector3(0, -0.0068, 0)), Color(0.3, 0.3, 0.3)],
	]
	for i in Brushwork.PIGMENTS.size():
		var w := well(Brushwork.Medium.WATER, i)
		parts.append([ToolModels.box(Vector3(PAN.x + 0.004, 0.003, PAN.y + 0.004)), Transform3D(Basis(), w - Vector3(0, 0.0025, 0)), BOX_WHITE.darkened(0.06)])
		parts.append([ToolModels.box(Vector3(PAN.x, 0.002, PAN.y)), Transform3D(Basis(), w - Vector3(0, 0.001, 0)), Brushwork.PIGMENTS[i].darkened(0.12)])
	return ToolModels.bake(parts)


## The jar's water as it starts, which each easel's water copies. Kept for the game's life: Godot frees a material's
## shader with its last material, and compiling it again for each easel's water stalled every placement made while
## no easel stood.
static func _clean_water() -> StandardMaterial3D:
	var m: StandardMaterial3D = _mats.get("water")
	if m == null:
		m = _mat("water", WATER, 0.02)
		m.metallic_specular = 0.9
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.get_rid()
	return m


static func _baked(key: String, roughness: float) -> StandardMaterial3D:
	var m := _mat(key, Color.WHITE, roughness)
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	return m
