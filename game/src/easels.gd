class_name Easels
extends Node3D

## The garden's easels, each a big canvas on an A-frame with a tray in front: a pot of brushes, a jar of water, a tin of
## oil, a stick of charcoal and a palette of colour wells. `World` puts and takes them and hands them their strokes;
## `EaselTool` paints on them. An easel's local frame stands on the ground under it, the canvas facing +z.

## The canvas tilts its top back from the painter this far.
const TILT := deg_to_rad(10.0)
const CANVAS_AT := Vector3(0, 1.32, 0)
const TRAY_Y := 0.72
## Where each thing on the tray sits, on the tray's top.
const POT := Vector3(-0.64, TRAY_Y, 0.2)
const JAR := Vector3(-0.47, TRAY_Y, 0.2)
const TIN := Vector3(-0.33, TRAY_Y, 0.2)
const STICK := Vector3(-0.2, TRAY_Y, 0.22)
const PALETTE := Vector3(0.48, TRAY_Y + 0.006, 0.2)
const JAR_SIZE := Vector2(0.045, 0.11)
const TIN_SIZE := Vector2(0.05, 0.055)
## The brushes standing in the pot, by kind: where each one's tip stands above the pot.
const BRUSH_TIPS := {Brushwork.Brush.SMALL: Vector3(-0.022, 0.3, -0.012), Brushwork.Brush.BIG: Vector3(0.02, 0.32, -0.008), Brushwork.Brush.FLAT: Vector3(0.0, 0.28, 0.024)}
## The palette, in its own frame: a thumb hole at its -x end, where a hand holds it, and a well of each pigment round
## the far, +x end; the brush's own mix shows between them.
const PALETTE_SIZE := Vector2(0.36, 0.24)
const THUMB := Vector3(-0.12, 0, 0)
const MIX_AT := Vector3(0.02, 0.006, 0)
const WELL_RADIUS := 0.018
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

static var _mats := {}

var easels := {}


func _init() -> void:
	name = "Easels"


static func well(i: int) -> Vector3:
	var a := lerpf(-1.5, 1.5, float(i) / (Brushwork.PIGMENTS.size() - 1))
	return Vector3(cos(a) * PALETTE_SIZE.x * 0.38, 0.006, sin(a) * PALETTE_SIZE.y * 0.36)


## The well a tip at `local`, in the palette's frame, is in, or -1.
static func well_at(local: Vector3) -> int:
	if local.y < WELL_DEPTH.x or local.y > WELL_DEPTH.y:
		return -1
	var best := -1
	var near := WELL_REACH
	for i in Brushwork.PIGMENTS.size():
		var w := well(i)
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
	## The palette as it rests on the tray; a hand holding it carries it off (EaselTool) and it comes back when let go.
	var palette: Node3D
	var mix: StandardMaterial3D
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
	add_child(e)
	easels[id] = e
	e.canvas.rebuild(data.strokes)
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


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _cylinder(radius: float, height: float, segments := 16) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = segments
	c.rings = 1
	return c


## A square beam `thickness` across from `from` to `to`.
static func _beam(root: Node3D, from: Vector3, to: Vector3, thickness: float, mat: Material) -> void:
	var along := to - from
	var y := along.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	_part(root, _box(Vector3(thickness, along.length(), thickness)), Transform3D(Basis(x, y, x.cross(y)), (from + to) * 0.5), mat)


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
	_part(stand, _box(Vector3(1.64, 0.03, 0.27)), Transform3D(Basis(), Vector3(0, TRAY_Y - 0.015, 0.17)), wood)
	_part(stand, _box(Vector3(1.64, 0.035, 0.012)), Transform3D(Basis(), Vector3(0, TRAY_Y + 0.0175, 0.3)), dark)
	_part(stand, _box(Vector3(0.3, 0.05, 0.03)), frame * Transform3D(Basis(), Vector3(0, Brushwork.METRES.y * 0.5 + 0.02, -0.048)), dark)
	_part(e, _box(Vector3(Brushwork.METRES.x + 0.03, Brushwork.METRES.y + 0.03, 0.03)), frame * Transform3D(Basis(), Vector3(0, 0, -0.017)), _mat("linen", Color(0.86, 0.82, 0.74), 0.9))
	var face := QuadMesh.new()
	face.size = Brushwork.METRES
	e.canvas_mesh = _part(e, face, frame, e.canvas.material, false)
	var glass := _mat("glass", Color(0.78, 0.86, 0.9, 0.35), 0.1)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_part(e, _cylinder(JAR_SIZE.x, JAR_SIZE.y), Transform3D(Basis(), JAR + Vector3(0, JAR_SIZE.y * 0.5, 0)), glass, false)
	_part(e, _cylinder(JAR_SIZE.x * 0.94, JAR_SIZE.y * 0.7), Transform3D(Basis(), JAR + Vector3(0, JAR_SIZE.y * 0.35, 0)), _mat("water", Color(0.62, 0.74, 0.8), 0.15), false)
	_part(e, _cylinder(TIN_SIZE.x, TIN_SIZE.y), Transform3D(Basis(), TIN + Vector3(0, TIN_SIZE.y * 0.5, 0)), _mat("tin", Color(0.7, 0.7, 0.72), 0.35))
	_part(e, _cylinder(TIN_SIZE.x * 0.9, 0.004), Transform3D(Basis(), TIN + Vector3(0, TIN_SIZE.y - 0.006, 0)), _mat("oil", Color(0.72, 0.56, 0.22), 0.2), false)
	_part(e, _cylinder(0.055, 0.12), Transform3D(Basis(), POT + Vector3(0, 0.06, 0)), _mat("pot", Color(0.66, 0.36, 0.26)))
	for kind in BRUSH_TIPS:
		var b := ToolModels.brush(kind)
		var tip: Vector3 = POT + BRUSH_TIPS[kind]
		b.transform = Transform3D(Basis.looking_at(Vector3.UP, Vector3.BACK), tip + Vector3.UP * ToolModels.BRUSH_TIP.z)
		e.add_child(b)
		e.brushes[kind] = b
	e.stick = ToolModels.brush(Brushwork.Brush.STICK)
	e.stick.transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), STICK + Vector3(0, 0.007, 0))
	e.add_child(e.stick)
	e.palette = palette()
	e.mix = e.palette.get_meta("mix")
	e.palette.position = PALETTE
	e.add_child(e.palette)


## Where a leg standing `x` along the canvas, LEG_BACK behind it, meets the ground.
static func _foot(x: float) -> Vector3:
	var frame := canvas_local()
	var at := frame * Vector3(x, 0, -LEG_BACK)
	return at - frame.basis.y * (at.y / frame.basis.y.y)


## A palette: a wooden board with a well of each pigment round its far end and a thumb hole at its near one, its
## middle showing the brush's mix.
static func palette() -> Node3D:
	var root := Node3D.new()
	var board := _cylinder(0.5, 0.008, 32)
	_part(root, board, Transform3D(Basis().scaled(Vector3(PALETTE_SIZE.x, 1.0, PALETTE_SIZE.y)), Vector3.ZERO), _mat("palette", Color(0.7, 0.52, 0.34), 0.5), false)
	_part(root, _cylinder(0.016, 0.0085, 12), Transform3D(Basis(), THUMB + Vector3(0, 0.0003, 0)), _mat("hole", Color(0.3, 0.22, 0.16)), false)
	var blob := SphereMesh.new()
	blob.radius = WELL_RADIUS
	blob.height = 0.01
	blob.radial_segments = 12
	blob.rings = 4
	for i in Brushwork.PIGMENTS.size():
		_part(root, blob, Transform3D(Basis(), well(i)), _mat("pigment%d" % i, Brushwork.PIGMENTS[i], 0.35), false)
	var mix := StandardMaterial3D.new()
	mix.albedo_color = Color(0.7, 0.52, 0.34)
	mix.roughness = 0.35
	var smear := SphereMesh.new()
	smear.radius = 0.035
	smear.height = 0.006
	smear.radial_segments = 16
	smear.rings = 4
	_part(root, smear, Transform3D(Basis().scaled(Vector3(1.3, 1, 0.9)), MIX_AT), mix, false)
	root.set_meta("mix", mix)
	return root
