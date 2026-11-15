class_name Easels
extends Node3D

## An easel's local frame stands on the ground under it as the ground is now, the canvas facing +z.

## The canvas's top leans back, away from the painter.
const TILT := deg_to_rad(10.0)
const CANVAS_AT := Vector3(0, 1.32, 0)
const TRAY_Y := 0.72
const TRAY := AABB(Vector3(-0.82, TRAY_Y - 0.03, 0.035), Vector3(1.64, 0.03, 0.31))
const LIP := Vector2(0.035, 0.012)
const RAG := AABB(Vector3(-0.48, TRAY_Y + LIP.x, TRAY.end.z - LIP.y), Vector3(0.23, 0.008, LIP.y))
const RAG_EDGE := [
	Vector2(RAG.position.z - 0.035, TRAY_Y + 0.0005),
	Vector2(RAG.position.z, RAG.position.y + 0.0005),
	Vector2(RAG.end.z + 0.0005, RAG.position.y + 0.0005),
	Vector2(RAG.end.z + 0.0005, TRAY_Y - 0.09),
]
const POT := Vector3(-0.68, TRAY_Y, 0.2)
const JAR := Vector3(-0.54, TRAY_Y, 0.23)
## The middle stick's centre.
const CHARCOAL := Vector3(0.0, TRAY_Y, 0.19)
## Lets a reach from the front take one stick alone.
const STICK_GAP := 0.1
## The oil palette rests inside the tray's lip, CLEAR of the leg crossing the tray behind it.
const KITS := {
	Brushwork.Medium.WATER: Vector3(-0.32, TRAY_Y + 0.0105, 0.21),
	Brushwork.Medium.OIL: Vector3(TRAY.end.x - PALETTE_SIZE.x * 0.5 - CLEAR, TRAY_Y + 0.006, TRAY.end.z - LIP.y - PALETTE_SIZE.y * 0.5 - CLEAR),
}
const KIT_REACH := {Brushwork.Medium.WATER: 0.1, Brushwork.Medium.OIL: PALETTE_SIZE.x * 0.5}
const CLEAR := 0.01
const JAR_SIZE := Vector2(0.042, 0.1)
## x outer radius, y height.
const POT_SIZE := Vector2(0.055, 0.12)
const POT_WALL := 0.005
const POT_FLOOR := 0.01
const POT_GAP := 0.001
## Which way each brush leans (radians), turned from the painter toward their right.
const SPLAY := {Brushwork.Brush.SMALL: deg_to_rad(-80.0), Brushwork.Brush.FLAT: 0.0, Brushwork.Brush.BIG: deg_to_rad(80.0)}
const PALETTE_SIZE := Vector2(0.36, 0.24)
## In each palette's own frame: thumb hole at -x, paint toward +x.
const THUMB := Vector3(-0.12, 0, 0)
const MIX_AT := Vector3(0.1, 0.0075, 0)
const BOARD_TOP := 0.004
## Texels: a whole number of tiles a little larger than the board.
const BOARD := Vector2i(384, 256)
## Scales the oval paint may lie within.
const OPEN := 0.92
const THUMB_CLEAR := 0.026
const WELL_RADIUS := 0.018
const PAN := Vector2(0.02, 0.035)
## PANS: the x the pan rows run between. OIL_ARC: radians either way of the far end the oil paint spans.
const PANS := Vector2(-0.04, 0.056)
const OIL_ARC := 1.75
const PAN_TOP := 0.0105
const WELL_REACH := 0.025
## A y range; it runs on through the board since nothing stops a hand pushing there.
const WELL_DEPTH := Vector2(-0.05, 0.03)
## Behind the canvas's face, clear of its backing, so no leg crosses the painting.
const LEG_BACK := 0.07
## Wider than a leg, so a reach for one does not slip off.
const LEG_GRIP := 0.06
const SPACING := 1.4
## Bounds GPU memory: a canvas with its checkpoints takes up to about 230 MB.
const MAX := 4
## In the easel's frame.
const BOUNDS := AABB(Vector3(-0.82, 0.0, -0.75), Vector3(1.64, 2.0, 1.1))

const BOX_WHITE := Color(0.95, 0.95, 0.93)
const WATER := Color(0.38, 0.62, 0.86, 0.75)


var terrain: Terrain
var world: World
var quality: Quality
## Taken by the next placement; none at MAX, so no more canvases than that are ever on the GPU.
var _spare: Easel
var _making: Easel
var _made := 0
var _step_frame := 0
var _eye: Camera3D
var easels := {}


func _init() -> void:
	name = "Easels"


## Godot compiles a pipeline only for what it draws, per MSAA level and foveation map, so the spare is drawn tiny before
## the eyes until `quality`'s rungs are primed; a Quest 2 otherwise compiled it in the first placement's frame.
func warm() -> void:
	var spare := _easel()
	add_child(spare)
	_spare = spare
	var eye := get_viewport().get_camera_3d()
	if eye != null and RenderingServer.get_rendering_device() != null:
		_eye = eye
		_follow()
		if quality != null and quality.priming():
			await quality.rungs_primed
		await RenderingServer.frame_post_draw
		_eye = null
	if _spare == spare:
		spare.visible = false


## Moved, not reparented: a canvas leaving the tree frees its paint.
func _follow() -> void:
	if _eye != null and _spare != null:
		_spare.global_transform = _eye.global_transform.translated_local(Vector3.FORWARD).scaled_local(Vector3.ONE * 0.01)


## Built a step a frame (`_process`): a whole easel in one frame, on top of the ~10 ms of script every frame runs,
## held a Quest 2 past its refresh.
func _restock() -> void:
	if _spare != null or _making != null or easels.size() >= MAX:
		return
	_making = Easel.new()
	_making.visible = false
	add_child(_making)
	_made = 0
	_step_frame = Engine.get_process_frames()


func _process(_delta: float) -> void:
	_follow()
	if _making == null or Engine.get_process_frames() == _step_frame:
		return
	_step_frame = Engine.get_process_frames()
	[_canvas, _board, _build][_made].call(_making)
	_made += 1
	if _made == 3:
		_spare = _making
		_making = null


func _easel() -> Easel:
	var e := Easel.new()
	_canvas(e)
	_board(e)
	_build(e)
	return e


## In `kit`'s palette's frame.
static func well(kit: Brushwork.Medium, i: int) -> Vector3:
	var n := Brushwork.PIGMENTS.size()
	if kit == Brushwork.Medium.WATER:
		var row := ceili(n / 2.0)
		return Vector3(PANS.x + (i % row) * (PANS.y - PANS.x) / (row - 1), PAN_TOP, (i / row - 0.5) * 0.044)
	var a := lerpf(-OIL_ARC, OIL_ARC, float(i) / (n - 1))
	return Vector3(cos(a) * PALETTE_SIZE.x * 0.38, 0.006, sin(a) * PALETTE_SIZE.y * 0.36)


## `local` is in `kit`'s palette's frame; -1 for no well.
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


## `point` is (x, z) in the oil palette's frame.
static func open_at(point: Vector2) -> bool:
	return Vector2(point.x / PALETTE_SIZE.x, point.y / PALETTE_SIZE.y).length() * 2.0 < OPEN and point.distance_to(Vector2(THUMB.x, THUMB.z)) > THUMB_CLEAR


class Easel:
	extends Node3D

	var id := -1
	var canvas: Canvas
	var canvas_mesh: MeshInstance3D
	## By Brushwork.Medium.
	var palettes := {}
	## wash: the watercolour box's mix field. board: the oil palette's paint.
	var wash: StandardMaterial3D
	var board: Canvas
	var board_mesh: MeshInstance3D
	var water: StandardMaterial3D
	## By Brushwork.Brush.
	var brushes := {}
	var rag: ShaderMaterial

	## x along the canvas, y up it, z out of it toward the painter, origin at its centre.
	func canvas_frame() -> Transform3D:
		return global_transform * Easels.canvas_local()

	## x, y as uv (0..1, v down), z the distance in front of the canvas's face.
	func on_canvas(point: Vector3) -> Vector3:
		var p := canvas_frame().affine_inverse() * point
		return Vector3(p.x / Brushwork.METRES.x + 0.5, 0.5 - p.y / Brushwork.METRES.y, p.z)

	## x toward the palette's paint, y across it against uv's v, z up out of its top, origin at its middle.
	func board_frame() -> Transform3D:
		return palettes[Brushwork.Medium.OIL].global_transform * Transform3D(Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP), Vector3(0, Easels.BOARD_TOP, 0))

	func surface(palette: bool) -> Canvas:
		return board if palette else canvas

	func frame(palette: bool) -> Transform3D:
		return board_frame() if palette else canvas_frame()

	func open(palette: bool, uv: Vector2) -> bool:
		if not palette:
			return true
		var at := (uv - Vector2(0.5, 0.5)) * board.metres
		return Easels.open_at(at) and Easels.well_at(Brushwork.Medium.OIL, Vector3(at.x, Easels.BOARD_TOP, at.y)) < 0

	func tray(at: Vector3) -> Vector3:
		return global_transform * at


static func canvas_local() -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, -TILT), CANVAS_AT)


func find(id: int) -> Easel:
	return easels.get(id)


func put(id: int, data: Dictionary) -> Easel:
	take(id)
	var e := _spare
	_spare = null
	if e == null:
		e = _easel()
		add_child(e)
	e.id = id
	e.name = "Easel%d" % id
	e.add_to_group("easel")
	e.transform = on_ground(data.at, data.yaw)
	e.visible = true
	easels[id] = e
	e.canvas.rebuild(data.strokes)
	e.board.rebuild(data.palette)
	_restock()
	return e


func take(id: int) -> void:
	var e: Easel = easels.get(id)
	if e == null:
		return
	easels.erase(id)
	remove_child(e)
	e.queue_free()
	_restock()


## The painter's own stroke is there already; anyone else's plays as it was painted.
func painted(id: int, stroke: Dictionary, own: bool, palette := false) -> void:
	var e := find(id)
	if e != null and not own:
		e.surface(palette).play(stroke, 0)


func repaint(id: int, strokes: Array, palette := false) -> void:
	var e := find(id)
	if e != null:
		e.surface(palette).rebuild(strokes)


func stand(id: int, at: Vector3, yaw: float) -> void:
	var e := find(id)
	if e != null:
		e.transform = on_ground(at, yaw)


func show_reshaped(id: int, data := {}) -> void:
	if find(id) != null:
		var shown := World.reshaped(world.state.easels[id], data)
		stand(id, shown.at, shown.yaw)


func reseat(area: Rect2) -> void:
	for e: Easel in easels.values():
		if area.grow(Terrain.STEP).has_point(Vector2(e.position.x, e.position.z)):
			e.position.y = terrain.shown_at(e.position.x, e.position.z)


func on_ground(at: Vector3, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, terrain.height_at(at.x, at.z), at.z))


## The first stand (legs or tray) hit within `reach` that no canvas in front hides: {easel, along, point}, or {}.
func pick_stand(origin: Vector3, dir: Vector3, reach := INF) -> Dictionary:
	var best := {}
	var d := dir.normalized()
	for e: Easel in easels.values():
		var inv := e.global_transform.affine_inverse()
		var t := stand_hit(inv * origin, inv.basis * d, minf(reach, best.get("along", INF)))
		if t < INF:
			best = {"easel": e, "along": t, "point": origin + d * t}
	return best


## In an easel's frame, `d` a unit vector: the distance to the stand within `reach`; INF if none or the canvas nearer.
static func stand_hit(o: Vector3, d: Vector3, reach: float) -> float:
	var near := reach
	for leg: Array in legs():
		var t := _rod_hit(o, d, leg[0], leg[1], LEG_GRIP)
		if t < near:
			near = t
	var tray: Variant = TRAY.intersects_ray(o, d)
	if tray != null:
		near = minf(near, maxf((tray as Vector3 - o).dot(d), 0.0))
	if near >= reach:
		return INF
	var canvas := canvas_local()
	var c := canvas.affine_inverse()
	var face: Variant = Plane(Vector3.BACK, 0.0).intersects_ray(c * o, c.basis * d)
	if face != null:
		var on: Vector3 = face
		if absf(on.x) <= Brushwork.METRES.x * 0.5 + 0.015 and absf(on.y) <= Brushwork.METRES.y * 0.5 + 0.015 and (canvas * on - o).dot(d) < near:
			return INF
	return near


## Each [foot, top, thickness], in the easel's frame.
static func legs() -> Array:
	var frame := canvas_local()
	var top := Brushwork.METRES.y * 0.5 + 0.08
	var out := []
	for side in [-1.0, 1.0]:
		out.append([_foot(side * 0.62), frame * Vector3(side * 0.1, top, -LEG_BACK), 0.045])
	out.append([Vector3(0, 0, -0.7), frame * Vector3(0, top - 0.04, -LEG_BACK - 0.04), 0.04])
	return out


## `d` a unit vector; INF where the ray never comes within `radius` of the rod.
static func _rod_hit(o: Vector3, d: Vector3, a: Vector3, b: Vector3, radius: float) -> float:
	var u := b - a
	var w := o - a
	var uu := u.dot(u)
	var ud := u.dot(d)
	var den := uu - ud * ud
	var s := clampf((u.dot(w) - ud * d.dot(w)) / den if den > 1e-9 else 0.0, 0.0, 1.0)
	var p := a + u * s
	var t := maxf((p - o).dot(d), 0.0)
	var miss := (o + d * t).distance_to(p)
	if miss >= radius:
		return INF
	return maxf(t - sqrt(radius * radius - miss * miss), 0.0)


## {easel, along, point}, or {}.
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


func nearest(at: Vector3) -> Easel:
	var best: Easel = null
	for e: Easel in easels.values():
		if best == null or _flat(e.global_position, at) < _flat(best.global_position, at):
			best = e
	return best


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## `standing`: {at, ...} by id.
static func room_at(at: Vector3, standing: Dictionary) -> bool:
	return crowded(at, standing).is_empty()


## "" when an easel may stand at `at`.
static func crowded(at: Vector3, standing: Dictionary) -> String:
	if standing.size() >= MAX:
		return "the garden holds its %d easels" % MAX
	if not standing.values().all(func(d: Dictionary) -> bool: return _flat(d.at, at) >= SPACING):
		return "another easel stands within %.1f m" % SPACING
	return ""


static func facing(at: Vector3, toward: Vector3) -> float:
	return atan2(toward.x - at.x, toward.z - at.z)


static func _cylinder(radius: float, height: float, segments := 16) -> CylinderMesh:
	return ToolModels.cylinder(radius, radius, height, segments)


static func _beam(root: Node3D, from: Vector3, to: Vector3, thickness: float, mat: Material) -> void:
	var along := to - from
	var y := along.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	ToolModels.piece(root, ToolModels.box(Vector3(thickness, along.length(), thickness)), Transform3D(Basis(x, y, x.cross(y)), (from + to) * 0.5), mat, true)


## In their parent's frame: the easel's own, and the easel tool's ghost of it.
static func lay_frame(stand: Node3D, board: Node3D) -> void:
	var wood := ToolModels.plain("easel/wood", Color(0.62, 0.45, 0.3), {"roughness": 0.7})
	var dark := ToolModels.plain("easel/dark_wood", Color(0.42, 0.3, 0.2), {"roughness": 0.7})
	var frame := canvas_local()
	for leg: Array in legs():
		_beam(stand, leg[0], leg[1], leg[2], wood)
	ToolModels.piece(stand, ToolModels.box(TRAY.size), Transform3D(Basis(), TRAY.get_center()), wood, true)
	ToolModels.piece(stand, ToolModels.box(Vector3(TRAY.size.x, LIP.x, LIP.y)), Transform3D(Basis(), Vector3(0, TRAY_Y + LIP.x * 0.5, TRAY.end.z - LIP.y * 0.5)), dark, true)
	ToolModels.piece(stand, ToolModels.box(Vector3(0.3, 0.05, 0.03)), frame * Transform3D(Basis(), Vector3(0, Brushwork.METRES.y * 0.5 + 0.02, -0.048)), dark, true)
	ToolModels.piece(board, ToolModels.box(Vector3(Brushwork.METRES.x + 0.03, Brushwork.METRES.y + 0.03, 0.03)), frame * Transform3D(Basis(), Vector3(0, 0, -0.017)), ToolModels.plain("easel/linen", Color(0.86, 0.82, 0.74), {"roughness": 0.9}), true)


func _canvas(e: Easel) -> void:
	e.canvas = Canvas.new()
	e.add_child(e.canvas)


func _board(e: Easel) -> void:
	e.board = Canvas.new(BOARD, preload("res://src/board.gdshader"), false)
	e.board.name = "Board"
	e.board.material.set_shader_parameter("board", PALETTE_SIZE)
	e.board.material.set_shader_parameter("open", OPEN)
	e.board.material.set_shader_parameter("thumb", Vector2(THUMB.x, THUMB.z))
	e.board.material.set_shader_parameter("thumb_clear", THUMB_CLEAR)
	e.add_child(e.board)


static func rag_distance(point: Vector3) -> float:
	if point.x < RAG.position.x - 0.008 or point.x > RAG.end.x + 0.008:
		return INF
	var yz := Vector2(point.z, point.y)
	var distance := INF
	for i in RAG_EDGE.size() - 1:
		distance = minf(distance, yz.distance_to(Geometry2D.get_closest_point_to_segment(yz, RAG_EDGE[i], RAG_EDGE[i + 1])))
	return distance


static func rag_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in RAG_EDGE.size() - 1:
		for uv in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]:
			var yz: Vector2 = RAG_EDGE[i + int(uv.y)]
			st.set_uv(Vector2(uv.x, (i + uv.y) / (RAG_EDGE.size() - 1)))
			st.add_vertex(Vector3(lerpf(RAG.position.x, RAG.end.x, uv.x), yz.y, yz.x))
	st.generate_normals()
	st.index()
	return st.commit()


func _build(e: Easel) -> void:
	var stand := Node3D.new()
	stand.name = "stand"
	e.add_child(stand)
	lay_frame(stand, e)
	e.canvas_mesh = ToolModels.piece(e, _quad("canvas", Brushwork.METRES), canvas_local(), e.canvas.material)
	var implements := Node3D.new()
	implements.name = "implements"
	e.add_child(implements)
	e.rag = ShaderMaterial.new()
	e.rag.shader = preload("res://src/rag.gdshader")
	ToolModels.piece(implements, ToolModels.shared("rag", rag_mesh), Transform3D.IDENTITY, e.rag)
	var glass := ToolModels.plain("easel/glass", Color(0.86, 0.93, 0.96, 0.22), {"roughness": 0.04})
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
	ToolModels.piece(implements, _cylinder(JAR_SIZE.x, JAR_SIZE.y, 20), Transform3D(Basis(), JAR + Vector3(0, JAR_SIZE.y * 0.5, 0)), glass)
	ToolModels.piece(implements, rim, Transform3D(Basis(), JAR + Vector3(0, JAR_SIZE.y, 0)), ToolModels.plain("easel/glass_rim", Color(0.9, 0.95, 0.97), {"roughness": 0.05}))
	e.water = _clean_water().duplicate()
	ToolModels.piece(implements, _cylinder(JAR_SIZE.x - 0.003, JAR_SIZE.y * 0.72, 20), Transform3D(Basis(), JAR + Vector3(0, 0.002 + JAR_SIZE.y * 0.36, 0)), e.water)
	ToolModels.piece(implements, _cylinder(POT_SIZE.x, POT_SIZE.y), Transform3D(Basis(), POT + Vector3(0, POT_SIZE.y * 0.5, 0)), ToolModels.plain("easel/pot", Color(0.66, 0.36, 0.26), {"roughness": 0.7}), true)
	ToolModels.piece(implements, _cylinder(POT_SIZE.x - POT_WALL, 0.002), Transform3D(Basis(), POT + Vector3(0, POT_SIZE.y, 0)), ToolModels.plain("easel/pot_inside", Color(0.24, 0.13, 0.1), {"roughness": 0.7}))
	for kind in SPLAY:
		var b := ToolModels.brush(kind)
		b.transform = in_pot(kind)
		implements.add_child(b)
		e.brushes[kind] = b
	for kind: Brushwork.Brush in Brushwork.STICKS:
		var b := ToolModels.brush(kind)
		b.transform = on_tray(kind)
		implements.add_child(b)
		e.brushes[kind] = b
	for kit in KITS:
		var palette := watercolours() if kit == Brushwork.Medium.WATER else oils()
		palette.name = Brushwork.Medium.keys()[kit].to_lower()
		palette.position = KITS[kit]
		implements.add_child(palette)
		e.palettes[kit] = palette
	e.wash = e.palettes[Brushwork.Medium.WATER].get_meta("mix")
	e.board_mesh = ToolModels.piece(e.palettes[Brushwork.Medium.OIL], _quad("oil_board_paint", Canvas.metres_of(BOARD)), Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, BOARD_TOP + 0.0003, 0)), e.board.material)


static func _quad(key: String, size: Vector2) -> QuadMesh:
	return ToolModels.shared(key, func() -> QuadMesh:
		var q := QuadMesh.new()
		q.size = size
		return q)


## In the easel's frame.
static func on_tray(kind: Brushwork.Brush) -> Transform3D:
	var across := STICK_GAP * (Brushwork.STICKS.keys().find(kind) - (Brushwork.STICKS.size() - 1) * 0.5)
	var size: Vector2 = Brushwork.STICKS[kind]
	return Transform3D(Basis(), CHARCOAL + Vector3(across, size.x - ToolModels.BRUSH_TIP.y, -ToolModels.BRUSH_TIP.z - size.y * 0.5))


## In the easel's frame, leaning as far as keeps the handle POT_GAP inside the wall at floor and mouth.
static func in_pot(kind: Brushwork.Brush) -> Transform3D:
	var inside := POT_SIZE.x - POT_WALL - POT_GAP
	var deep := POT_SIZE.y - POT_FLOOR
	var lean := atan2(inside * 2.0, deep) - asin(ToolModels.HANDLE_RADIUS * 2.0 / Vector2(deep, inside * 2.0).length())
	var out := Vector3(sin(SPLAY[kind]), 0, cos(SPLAY[kind]))
	var basis := Basis.looking_at(out * sin(lean) + Vector3.UP * cos(lean), out)
	return Transform3D(basis, POT + Vector3(0, POT_FLOOR, 0) - out * deep * tan(lean) * 0.5 - basis.y * ToolModels.BRUSH_TIP.y)


## In the brush's frame: a pot brush by the middle of what stands out of the pot, a charcoal stick by its middle.
static func grip(kind: Brushwork.Brush) -> Vector3:
	if Brushwork.is_stick(kind):
		return ToolModels.BRUSH_TIP + Vector3(0, 0, Brushwork.STICKS[kind].y * 0.5)
	var t := in_pot(kind)
	var out := (t.basis * Vector3.FORWARD).y
	var rim := (POT_SIZE.y - POT_FLOOR) / out
	return Vector3(0, ToolModels.BRUSH_TIP.y, -(rim - ToolModels.BRUSH_TIP.z) * 0.5)


## `x` along the canvas.
static func _foot(x: float) -> Vector3:
	var frame := canvas_local()
	var at := frame * Vector3(x, 0, -LEG_BACK)
	return at - frame.basis.y * (at.y / frame.basis.y.y)


## The paint on its open board is added per easel (`_build`).
static func oils() -> Node3D:
	var root := Node3D.new()
	ToolModels.piece(root, ToolModels.shared("oil_board", _oil_board), Transform3D(), _baked("oil_board", 0.45))
	ToolModels.piece(root, ToolModels.shared("oil_paint", _oil_paint), Transform3D(), _baked("oil_paint", 0.12))
	return root


static func _oil_board() -> ArrayMesh:
	return ToolModels.bake([
		[_cylinder(0.5, 0.008, 32), Transform3D(Basis().scaled(Vector3(PALETTE_SIZE.x, 1.0, PALETTE_SIZE.y)), Vector3.ZERO), Color(0.86, 0.68, 0.46)],
		[_cylinder(0.016, 0.0085, 12), Transform3D(Basis(), THUMB + Vector3(0, 0.0003, 0)), Color(0.3, 0.22, 0.16)],
	])


static func _oil_paint() -> ArrayMesh:
	var blob := ToolModels.sphere(0.015, 0.012, 12, 5)
	var curl := ToolModels.sphere(0.007, 0.009, 8, 4)
	var paint: Array = []
	for i in Brushwork.PIGMENTS.size():
		var w := well(Brushwork.Medium.OIL, i)
		paint.append([blob, Transform3D(Basis(Vector3.UP, i * 1.3).scaled(Vector3(1.15, 1, 0.9)), w), Brushwork.PIGMENTS[i]])
		paint.append([curl, Transform3D(Basis(Vector3.UP, i * 1.3), w + Vector3(0.003, 0.006, -0.002)), Brushwork.PIGMENTS[i]])
	return ToolModels.bake(paint)


static func watercolours() -> Node3D:
	var root := Node3D.new()
	ToolModels.piece(root, ToolModels.shared("watercolours", _watercolours), Transform3D(), _baked("watercolours", 0.7))
	var mix := StandardMaterial3D.new()
	mix.albedo_color = BOX_WHITE
	mix.roughness = 0.35
	ToolModels.piece(root, ToolModels.sphere(0.022, 0.006, 16, 4), Transform3D(Basis().scaled(Vector3(1.3, 1, 0.9)), MIX_AT), mix)
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


## Kept for the game's life: Godot frees a shader with its last material, and recompiling it per easel stalled every
## placement made while no easel stood.
static func _clean_water() -> StandardMaterial3D:
	var m := ToolModels.plain("easel/water", WATER, {"roughness": 0.02, "metallic_specular": 0.9, "transparency": BaseMaterial3D.TRANSPARENCY_ALPHA})
	m.get_rid()
	return m


static func _baked(key: String, roughness: float) -> StandardMaterial3D:
	return ToolModels.plain("easel/" + key, Color.WHITE, {"roughness": roughness, "vertex_color_use_as_albedo": true, "vertex_color_is_srgb": true})
