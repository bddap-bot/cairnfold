class_name Book
extends Node3D

## The picture book: a small cloth-bound book held in a hand that holds Hand.Tool.BOOK, whose pages teach the
## controls a player would not guess (Lessons). It comes shut, its ribbon glowing; the other hand touching the cover
## or the ribbon opens it, and a sweep of that hand across a page turns it, toward the spine for the next page and
## back for the one before. No button is pressed, so no tool acts. Picking another tool tucks it away; the wheel's
## book brings it back where it was left. Each page is a live LessonScene, and only the faces in view render.
##
## Its frame (`local`): the spine along z at x 0, the right page over +x, y out of the page, z toward the reader.

const W := 0.15
const H := 0.15
const LEAF_T := 0.0022
const COVER_T := 0.0042
const OVER := 0.005
const TILT := deg_to_rad(80.0)
const OPEN_S := 0.85
const TURN_S := 0.7
const TUCK_S := 0.2
## A hand counts as at the page within this of its face, and turns it once it sweeps this far across.
const NEAR := 0.07
const SWEEP := 0.06
const TOUCH := 0.05
const PAGE_HZ_DIVIDER := 2

var leaves := ceili(Lessons.PAGES.size() / 2.0)
## Leaves turned, the cover the first of them: 0 shut, 1 open at the first page.
var at := 0
var live := true
var rig: Rig
var holder: Hand
var scenes := {}
var _turn := {}
var _open_k := 0.0
var _shown_k := 0.0
var _sweep_from := INF
var _cover: Node3D
var _left_block: MeshInstance3D
var _right_block: MeshInstance3D
var _back_cover: MeshInstance3D
var _sheets: Array[MeshInstance3D] = []
var _ribbon: MeshInstance3D
var _ribbon_mat: ShaderMaterial
var _frame := 0


## `live` false makes the book a prop: its pages stay blank frames and nothing renders behind them.
func _init(live_pages := true) -> void:
	live = live_pages
	_back_cover = _board(false)
	_back_cover.position = Vector3(W * 0.5 + OVER * 0.5, -COVER_T * 0.5, 0)
	add_child(_back_cover)
	_cover = Node3D.new()
	add_child(_cover)
	var front := _board(true)
	front.position = Vector3(W * 0.5 + OVER * 0.5, COVER_T * 0.5, 0)
	_cover.add_child(front)
	var inside := _sheet()
	inside.transform = Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0, -0.0003, 0))
	_set_face(inside, true, -1)
	_set_face(inside, false, -1)
	_cover.add_child(inside)
	_left_block = _block()
	_right_block = _block()
	for i in 3:
		_sheets.append(_sheet())
		add_child(_sheets[i])
	_ribbon = MeshInstance3D.new()
	var strip := PlaneMesh.new()
	strip.size = Vector2(0.009, 0.07)
	strip.subdivide_depth = 10
	strip.center_offset = Vector3(0, 0, 0.035)
	_ribbon.mesh = strip
	_ribbon_mat = ShaderMaterial.new()
	_ribbon_mat.shader = preload("res://src/book_ribbon.gdshader")
	_ribbon.material_override = _ribbon_mat
	_ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ribbon)
	_lay()


## A shut book a few centimetres across, for the wheel and for a ghost hand that holds it.
static func miniature() -> Node3D:
	var root := Node3D.new()
	var b := Book.new(false)
	b.scale = Vector3.ONE * 0.28
	b.position = Vector3(-W * 0.14, 0, 0)
	b.set_process(false)
	root.add_child(b)
	return root


## Where the book sits in a hand holding it, `open_k` of the way from shut to open: tipped up toward the eye
## from the controller's top, the hand under its lower edge, under the spine once open.
static func local(open_k: float) -> Transform3D:
	var b := Basis(Vector3.RIGHT, TILT)
	return Transform3D(b, Vector3(0, 0.03, 0.01) + b * Vector3(lerpf(-W * 0.5, 0.0, open_k), 0.0, -H * 0.55))


## Opens the book at its first page.
func open() -> void:
	if at == 0 and _turn.is_empty():
		_begin(0, 1)


## Turns one leaf, `way` 1 forward and -1 back; back from the first page shuts it.
func turn(way: int) -> void:
	if not _turn.is_empty() or at == 0:
		return
	if way > 0 and at <= leaves:
		_begin(at, 1)
	elif way < 0 and at >= 1:
		_begin(at - 1, -1)


## Reads a fingertip at `tip` (global) touching the book: on the shut cover or the ribbon it opens it; swept
## across an open page it turns it.
func feel(tip: Vector3) -> void:
	if not _turn.is_empty():
		_sweep_from = INF
		return
	var p := global_transform.affine_inverse() * tip
	if at == 0:
		var on_cover := p.x > -0.01 and p.x < W + 0.01 and absf(p.z) < H * 0.5 + 0.01 and absf(p.y - _stack_top()) < TOUCH
		var on_ribbon := _ribbon.visible and _ribbon.global_position.distance_to(tip) < TOUCH + 0.03
		if on_cover or on_ribbon:
			open()
		return
	var near := absf(p.z) < H * 0.5 + 0.02 and p.y > -0.01 and p.y < NEAR and absf(p.x) < W + 0.02
	if not near:
		_sweep_from = INF
		return
	if _sweep_from == INF:
		_sweep_from = p.x
	if _sweep_from > W * 0.3 and p.x < _sweep_from - SWEEP:
		_sweep_from = INF
		turn(1)
	elif _sweep_from < -W * 0.3 and p.x > _sweep_from + SWEEP:
		_sweep_from = INF
		turn(-1)


## The page indices whose faces are in view, each rendering.
func faces_in_view() -> Array[int]:
	var out: Array[int] = []
	if not visible or _shown_k < 0.99:
		return out
	for f in [_sheets[0].get_meta("back", -1) if _sheets[0].visible else -1, _sheets[1].get_meta("front", -1) if _sheets[1].visible else -1,
			_sheets[2].get_meta("front", -1) if _sheets[2].visible else -1, _sheets[2].get_meta("back", -1) if _sheets[2].visible else -1]:
		if f >= 0 and not f in out:
			out.append(f)
	return out


func _process(delta: float) -> void:
	_frame += 1
	if rig != null:
		_follow(delta)
	if not _turn.is_empty():
		_turn.t += delta
		if _turn.t >= _turn.span:
			at = _turn.to
			_turn.clear()
	_lay()
	_render_pages()


## Rides in the hand that holds the book, and is felt by the other; shrinks away when no hand holds it.
func _follow(delta: float) -> void:
	var held: Hand = null
	for h in rig.hands:
		if h.tool == Hand.Tool.BOOK:
			held = h
	if held != null:
		holder = held
	var target := 0.0 if held == null else 1.0
	_shown_k = move_toward(_shown_k, target, delta / TUCK_S)
	visible = _shown_k > 0.0
	if holder == null or not visible:
		return
	_open_k = move_toward(_open_k, 1.0 if at > 0 or not _turn.is_empty() else 0.0, delta / OPEN_S)
	var k := ease(_shown_k, 0.4)
	global_transform = holder.global_transform * local(smoothstep(0.0, 1.0, _open_k)) * Transform3D(Basis.from_scale(Vector3.ONE * maxf(k, 0.01)), Vector3.ZERO)
	if held != null:
		for h in rig.hands:
			if h != held and h.tracked():
				feel(h.global_position)


func _begin(leaf: int, way: int) -> void:
	_turn = {"leaf": leaf, "way": way, "t": 0.0, "span": OPEN_S if leaf == 0 else TURN_S, "to": at + way}
	Cues.play(Cues.Act.WHEEL_HOVER, global_position, holder)


## Each leaf's angle now: turned ones lie on the left (PI).
func _angle(leaf: int) -> float:
	if not _turn.is_empty() and leaf == _turn.leaf:
		var k: float = _turn.t / _turn.span
		var s := _settle(k) if leaf == 0 else smoothstep(0.0, 1.0, k)
		return PI * (s if _turn.way > 0 else 1.0 - s)
	return PI if leaf < at else 0.0


## A cover swung open overshoots a little and settles, as a board does.
static func _settle(k: float) -> float:
	var c := 1.6
	var x := k - 1.0
	return 1.0 + (c + 1.0) * x * x * x + c * x * x


func _stack_top() -> float:
	return leaves * LEAF_T


## How thick the pages stand, all of them.
static func leaves_t() -> float:
	return ceili(Lessons.PAGES.size() / 2.0) * LEAF_T


func _lay() -> void:
	var turning: int = _turn.get("leaf", -1)
	var left_n := 0
	var right_n := 0
	for j in range(1, leaves + 1):
		if j == turning:
			continue
		if _angle(j) > PI * 0.5:
			left_n += 1
		else:
			right_n += 1
	var cover_a := _angle(0)
	_cover.transform = Transform3D(Basis(Vector3.BACK, cover_a), Vector3(0, _stack_top() * (1.0 - cover_a / PI), 0))
	_place_block(_right_block, right_n, 1.0)
	_place_block(_left_block, left_n, -1.0)
	var top_right := -1
	for j in range(1, leaves + 1):
		if j != turning and _angle(j) < PI * 0.5:
			top_right = j
			break
	var top_left := -1
	for j in range(leaves, 0, -1):
		if j != turning and _angle(j) > PI * 0.5:
			top_left = j
			break
	_show_sheet(_sheets[0], top_left, PI, left_n)
	_show_sheet(_sheets[1], top_right if top_right >= 0 else leaves + 1, 0.0, right_n)
	_sheets[1].visible = cover_a > 0.02
	if turning >= 1:
		var a := _angle(turning)
		_show_sheet(_sheets[2], turning, a, lerpf(right_n, left_n, a / PI))
		(_sheets[2].material_override as ShaderMaterial).set_shader_parameter("bend", 0.55)
	else:
		_sheets[2].visible = false
	_ribbon.visible = at == 0 and _turn.is_empty()
	_ribbon.position = Vector3(W * 0.62, _stack_top() * 0.5, H * 0.5 - 0.002)
	_ribbon_mat.set_shader_parameter("glow", 1.0 if live else 0.0)


func _place_block(block: MeshInstance3D, n: int, side: float) -> void:
	block.visible = n > 0
	var t := maxf(n * LEAF_T, 0.0005)
	block.scale = Vector3(W - 0.002, t, H - 0.002)
	block.position = Vector3(side * W * 0.5, t * 0.5 - 0.0002, 0)
	(block.material_override as ShaderMaterial).set_shader_parameter("size", block.scale)


## Lays `sheet` as leaf `leaf` (leaves + 1: the back cover's inside) at `a`, on a stack `under` leaves deep.
func _show_sheet(sheet: MeshInstance3D, leaf: int, a: float, under: float) -> void:
	sheet.visible = leaf >= 1
	if not sheet.visible:
		return
	sheet.position = Vector3(0, under * LEAF_T + 0.0004, 0)
	var mat := sheet.material_override as ShaderMaterial
	mat.set_shader_parameter("angle", a)
	mat.set_shader_parameter("bend", 0.0)
	_set_face(sheet, true, _face(leaf, false))
	_set_face(sheet, false, _face(leaf, true))


## The page on a leaf's face: leaf 1's front is page 0; a back past the last page, and the back cover, are endpaper (-1).
func _face(leaf: int, back: bool) -> int:
	if leaf > leaves:
		return -1
	var i := 2 * (leaf - 1) + (1 if back else 0)
	return i if i < Lessons.PAGES.size() else -1


func _set_face(sheet: MeshInstance3D, front: bool, page: int) -> void:
	var key := "front" if front else "back"
	if sheet.get_meta(key, -2) == page:
		return
	sheet.set_meta(key, page)
	var mat := sheet.material_override as ShaderMaterial
	mat.set_shader_parameter(key + "_drawn", page >= 0)
	mat.set_shader_parameter(key + "_seed", float(page) * 1.7 + 0.3)
	if page >= 0 and live:
		mat.set_shader_parameter(key + "_picture", _scene(page).get_texture())


func _scene(page: int) -> LessonScene:
	if not scenes.has(page):
		var s := LessonScene.new(page)
		add_child(s)
		scenes[page] = s
	return scenes[page]


## Faces in view render every PAGE_HZ_DIVIDER-th frame, the rest not at all, their scenes paused.
func _render_pages() -> void:
	var shown: Array[int] = faces_in_view() if live else ([] as Array[int])
	var due := _frame % PAGE_HZ_DIVIDER == 0
	for page in scenes:
		var s: LessonScene = scenes[page]
		var on: bool = page in shown
		s.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
		s.render_target_update_mode = SubViewport.UPDATE_ONCE if on and due else SubViewport.UPDATE_DISABLED
	for sheet in _sheets:
		var mat := sheet.material_override as ShaderMaterial
		for key in ["front", "back"]:
			var page: int = sheet.get_meta(key, -1)
			if scenes.has(page):
				mat.set_shader_parameter(key + "_wash", scenes[page].wash)
				mat.set_shader_parameter(key + "_fade", scenes[page].fade)


static var _page_mesh: PlaneMesh
static var _board_mesh: BoxMesh
static var _block_mesh: BoxMesh


func _sheet() -> MeshInstance3D:
	if _page_mesh == null:
		_page_mesh = PlaneMesh.new()
		_page_mesh.size = Vector2(W, H)
		_page_mesh.subdivide_width = 14
		_page_mesh.center_offset = Vector3(W * 0.5, 0, 0)
	var mi := MeshInstance3D.new()
	mi.mesh = _page_mesh
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://src/book_page.gdshader")
	mat.set_shader_parameter("width", W)
	mi.material_override = mat
	mi.extra_cull_margin = W
	return mi


func _board(front: bool) -> MeshInstance3D:
	if _board_mesh == null:
		_board_mesh = BoxMesh.new()
		_board_mesh.size = Vector3(W + OVER, COVER_T, H + OVER * 2.0)
	var mi := MeshInstance3D.new()
	mi.mesh = _board_mesh
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://src/book.gdshader")
	mat.set_shader_parameter("size", _board_mesh.size)
	mat.set_shader_parameter("front", front)
	mi.material_override = mat
	return mi


func _block() -> MeshInstance3D:
	if _block_mesh == null:
		_block_mesh = BoxMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _block_mesh
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://src/book.gdshader")
	mat.set_shader_parameter("kind", 1)
	mi.material_override = mat
	add_child(mi)
	return mi
