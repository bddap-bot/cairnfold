class_name Book
extends Node3D

## Turned by touch, never a button, so no tool acts. Every LessonScene is built with the book so none builds as it
## first opens. Its frame: the spine along z at x 0, the right page over +x, y out of the page, z toward the reader.

const W := 0.15
const H := 0.15
const LEAF_T := 0.0028
const COVER_T := 0.0042
const OVER := 0.005
## sRGB, shared by its shaders and the wheel's icon.
const CLOTH := Color(0.27, 0.42, 0.33)
const LEATHER := Color(0.36, 0.21, 0.12)
const PAPER := Color(0.97, 0.91, 0.78)
const RIBBON := Color(0.55, 0.08, 0.16)
const TILT := deg_to_rad(68.0)
const OPEN_S := 0.85
const TURN_S := 0.7
const TUCK_S := 0.2
## Metres: a hand within NEAR of the page's face turns it once it sweeps SWEEP across.
const NEAR := 0.07
const SWEEP := 0.06
const TOUCH := 0.05
## Metres: a hand BEHIND the pages is reaching through, and turns the page it comes out over within THROUGH_MARGIN
## (x, z) of its edges.
const BEHIND := 0.02
const THROUGH_MARGIN := Vector2(0.03, 0.02)
## Metres between two frames' readings beyond which it is tracking or a teleport catching up, not a hand.
const STEP := 0.15
## Metres, up out of the gutter.
const BOW := 0.006
const BOARD := Vector3(W + OVER, COVER_T, H + OVER * 2.0)
const PAGE_HZ_DIVIDER := 2
## Opaque draws go in ascending render_priority, after the garden at 0: the top layer first, so what lies under it
## fails the depth test unshaded. Unordered, the open book cost about a millisecond of a Quest 2's frame.
enum Layer { SHEET = 1, BLOCK, INSIDE, BOARD }
## book.gdshader's `kind`.
enum Kind { COVER, BLOCK }
## book_paint.gdshader's `part`.
enum Part { FACE_PAINT, FACE_GRAIN, COVER_PAINT, COVER_ROUGH }
## Pages render only while the book lies within this cosine of where the head faces.
const LOOK_COS := 0.5
const PAINT_PX := 512

const COVER := "cover"
## Vector2i(page, 0 front or 1 back), page -1 the endpaper: [paint, grain]; COVER: [paint, roughness]. Filled by the
## first live book.
static var _paint := {}
static var _baking := false

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
var _last := Vector3.INF
var _last_frame := -1
var _reaching := false
var _cover: Node3D
var _left_block: MeshInstance3D
var _right_block: MeshInstance3D
var _back_cover: MeshInstance3D
var _sheets: Array[MeshInstance3D] = []
var _inside: MeshInstance3D
var _front: ShaderMaterial
var _ribbon: MeshInstance3D
var _ribbon_mat: ShaderMaterial
var _frame := 0
var _hidden_laid := false


## `live_pages` false makes a prop: its pages stay blank frames and nothing renders behind them.
func _init(live_pages := true) -> void:
	live = live_pages
	_back_cover = _board(false)
	_back_cover.position = Vector3(W * 0.5 + OVER * 0.5, -COVER_T * 0.5, 0)
	add_child(_back_cover)
	_cover = Node3D.new()
	add_child(_cover)
	var front := _board(true)
	_front = front.material_override
	front.position = Vector3(W * 0.5 + OVER * 0.5, COVER_T * 0.5, 0)
	_cover.add_child(front)
	_inside = _sheet()
	_inside.material_override.render_priority = Layer.INSIDE
	_inside.transform = Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0, -0.0003, 0))
	_cover.add_child(_inside)
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
	_ribbon_mat.set_shader_parameter("colour", RIBBON)
	_ribbon.material_override = _ribbon_mat
	_ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ribbon)
	if live:
		for page in Lessons.PAGES.size():
			var scene := LessonScene.new(page)
			add_child(scene)
			scenes[page] = scene
	_lay()


func _ready() -> void:
	# A book in no player's hands, a prop or a copy of one, moves only through a turn `turn_to` starts.
	if rig == null and _turn.is_empty():
		set_process(false)
	if live and not _baking and RenderingServer.get_rendering_device() != null:
		_baking = true
		_bake()


## Once into textures, rather than shading every pixel every frame.
func _bake() -> void:
	var vp := SubViewport.new()
	vp.disable_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var rect := ColorRect.new()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://src/book_paint.gdshader")
	mat.set_shader_parameter("board", BOARD)
	mat.set_shader_parameter("paper", PAPER)
	_bind(mat)
	rect.material = mat
	vp.size = Vector2i.ONE * PAINT_PX
	rect.size = vp.size
	vp.add_child(rect)
	add_child(vp)
	var parts := {COVER: [Part.COVER_PAINT, Part.COVER_ROUGH]}
	for page in range(-1, Lessons.PAGES.size()):
		for back in ([0, 1] if page < 0 else [page % 2]):
			parts[Vector2i(page, back)] = [Part.FACE_PAINT, Part.FACE_GRAIN]
	for key in parts:
		if key is Vector2i:
			mat.set_shader_parameter("face_seed", float(key.x) * 1.7 + 0.3)
			mat.set_shader_parameter("face_drawn", key.x >= 0)
			mat.set_shader_parameter("back_face", key.y == 1)
		var art: Array[Texture2D] = []
		for part: int in parts[key]:
			mat.set_shader_parameter("part", part)
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE
			await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image()
			img.generate_mipmaps()
			art.append(ImageTexture.create_from_image(img))
		_paint[key] = art
	vp.queue_free()


## Each material's meta is how Hand.unlit draws it.
static func miniature() -> Node3D:
	var root := Node3D.new()
	var b := Book.new(false)
	b.scale = Vector3.ONE * 0.28
	b.position = Vector3(-W * 0.14, 0, 0)
	b.set_process(false)
	root.add_child(b)
	for mi: MeshInstance3D in b.find_children("*", "MeshInstance3D", true, false):
		var mat: ShaderMaterial = mi.material_override
		if mat.get_shader_parameter("cloth") != null:
			var icon := ShaderMaterial.new()
			icon.shader = preload("res://src/book_icon.gdshader")
			icon.set_shader_parameter("size", BOARD)
			icon.set_shader_parameter("front", mat.get_shader_parameter("front"))
			_bind(icon)
			mat.set_meta("icon_material", icon)
		else:
			mat.set_meta("icon_colour", RIBBON if mat == b._ribbon_mat else PAPER)
	return root


## In the holding hand's frame, `open_k` 0 shut to 1 open: tipped toward the eye, the hand under its lower edge,
## under the spine once open.
static func local(open_k: float) -> Transform3D:
	var b := Basis(Vector3.RIGHT, TILT)
	return Transform3D(b, Vector3(0, 0.018, 0.01) + b * Vector3(lerpf(-W * 0.5, 0.0, open_k), 0.0, -H * 0.47))


func open() -> void:
	if at == 0 and _turn.is_empty():
		_begin(0, 1)


## `way` 1 forward, -1 back; back from the first page shuts it.
func turn(way: int) -> void:
	if not _turn.is_empty() or at == 0:
		return
	if way > 0 and at <= leaves:
		_begin(at, 1)
	elif way < 0:
		_begin(at - 1, -1)


func page() -> int:
	return _turn.get("to", at)


## For a prop following another player's book.
func turn_to(to: int) -> void:
	if not _turn.is_empty():
		at = _turn.to
		_turn.clear()
	if absi(to - at) == 1:
		_begin(mini(at, to), to - at)
	else:
		at = to
	set_process(not _turn.is_empty())
	_lay()


## `tip` is global. A sweep or a pass turns one leaf: the hand leaves the pages (`_sweep_from` NAN until then) before
## it turns another, so the stroke back from a turn never undoes it.
func feel(tip: Vector3) -> void:
	var p := global_transform.affine_inverse() * tip
	var through := _through(p)
	if at == 0:
		var on_cover := p.x > -0.01 and p.x < W + 0.01 and absf(p.z) < H * 0.5 + 0.01 and absf(p.y - _stack_top()) < TOUCH
		var on_ribbon := _ribbon.visible and _ribbon.global_position.distance_to(tip) < TOUCH + 0.03
		if on_cover or on_ribbon:
			open()
		return
	if through != 0 and _turn.is_empty():
		turn(through)
		_sweep_from = NAN
		return
	var near := absf(p.z) < H * 0.5 + 0.02 and p.y > -0.01 and p.y < NEAR and absf(p.x) < W + 0.02
	if not near:
		_sweep_from = INF
	elif _sweep_from == INF:
		_sweep_from = p.x
	elif _turn.is_empty() and absf(p.x - _sweep_from) > SWEEP:
		turn(1 if p.x < _sweep_from else -1)
		_sweep_from = NAN


## 1 right, -1 left, else 0; `p` local. The crossing is found on the segment from the last frame's reading, so a
## fast pass that no reading catches near the page still counts.
func _through(p: Vector3) -> int:
	var from := _last if _frame - _last_frame <= 1 and _last.distance_to(p) < STEP else Vector3.INF
	_last = p
	_last_frame = _frame
	if p.y < -BEHIND:
		_reaching = true
	if p.y < 0.0 or not _reaching:
		return 0
	_reaching = false
	if not from.y < 0.0:
		return 0
	var c := from.lerp(p, from.y / (from.y - p.y))
	if absf(c.x) > W + THROUGH_MARGIN.x or absf(c.z) > H * 0.5 + THROUGH_MARGIN.y:
		return 0
	return 1 if c.x > 0.0 else -1


func faces_in_view() -> Array[int]:
	var out: Array[int] = []
	if not visible or _shown_k < 0.99:
		return out
	if rig != null and (global_position - rig.head.global_position).normalized().dot(-rig.head.global_basis.z) < LOOK_COS:
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
			if rig == null:
				set_process(false)
	if not visible and _hidden_laid:
		return
	_hidden_laid = not visible
	_lay()
	_render_pages()


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
	Cues.play(Cues.Act.BOOK_PAGE, global_position, holder)


## Radians; turned leaves lie on the left, at PI.
func _angle(leaf: int) -> float:
	if not _turn.is_empty() and leaf == _turn.leaf:
		var k: float = _turn.t / _turn.span
		var s := _settle(k) if leaf == 0 else smoothstep(0.0, 1.0, k)
		return PI * (s if _turn.way > 0 else 1.0 - s)
	return PI if leaf < at else 0.0


## Overshoots a little and settles, as a board does.
static func _settle(k: float) -> float:
	var c := 1.6
	var x := k - 1.0
	return 1.0 + (c + 1.0) * x * x * x + c * x * x


func _stack_top() -> float:
	return leaves * LEAF_T


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
	_place_block(_right_block, right_n, 1.0, _sheets[1])
	_place_block(_left_block, left_n, -1.0, _sheets[0])
	if turning >= 1:
		var a := _angle(turning)
		_show_sheet(_sheets[2], turning, a, lerpf(right_n, left_n, a / PI))
		(_sheets[2].material_override as ShaderMaterial).set_shader_parameter("bend", 0.55)
	else:
		_sheets[2].visible = false
	_inside.visible = left_n == 0
	_set_face(_inside, true, -1)
	_set_face(_inside, false, -1)
	if not _front.get_shader_parameter("baked") and _paint.has(COVER):
		_front.set_shader_parameter("cover_paint", _paint[COVER][0])
		_front.set_shader_parameter("cover_rough", _paint[COVER][1])
		_front.set_shader_parameter("baked", true)
	var shut := at == 0 and _turn.is_empty()
	_ribbon.position = Vector3(W * 0.62, _stack_top() * 0.5, H * 0.5 - 0.002) if shut else Vector3(0.004, _stack_top() * 0.5 + 0.002, H * 0.5 - 0.002)
	_ribbon_mat.set_shader_parameter("glow", 1.0 if live and shut else 0.0)


## `top`: the resting leaf on it, whose bow it takes.
func _place_block(block: MeshInstance3D, n: int, side: float, top: MeshInstance3D) -> void:
	block.visible = n > 0
	var t := maxf(n * LEAF_T, 0.0005)
	block.scale = Vector3(W - 0.002, t, H - 0.002)
	block.position = Vector3(side * W * 0.5, t * 0.5 - 0.0002, 0)
	(block.material_override as ShaderMaterial).set_shader_parameter("size", block.scale)
	(block.material_override as ShaderMaterial).set_shader_parameter("fore_side", side)
	(block.material_override as ShaderMaterial).set_shader_parameter("gutter_bow", BOW if top.visible else 0.0)


## `leaf` leaves + 1 is the back cover's inside; `under` is the stack's depth in leaves.
func _show_sheet(sheet: MeshInstance3D, leaf: int, a: float, under: float) -> void:
	sheet.visible = leaf >= 1
	if not sheet.visible:
		return
	sheet.position = Vector3(0, under * LEAF_T + 0.0004, 0)
	var mat := sheet.material_override as ShaderMaterial
	mat.set_shader_parameter("angle", a)
	mat.set_shader_parameter("bend", 0.0)
	mat.set_shader_parameter("gutter_bow", BOW if sheet != _sheets[2] else 0.0)
	_set_face(sheet, true, _face(leaf, false))
	_set_face(sheet, false, _face(leaf, true))


## Leaf 1's front is page 0; a back past the last page, and the back cover, are endpaper (-1).
func _face(leaf: int, back: bool) -> int:
	if leaf > leaves:
		return -1
	var i := 2 * (leaf - 1) + (1 if back else 0)
	return i if i < Lessons.PAGES.size() else -1


func _set_face(sheet: MeshInstance3D, front: bool, page: int) -> void:
	var key := "front" if front else "back"
	var mat := sheet.material_override as ShaderMaterial
	if sheet.get_meta(key, -2) != page:
		sheet.set_meta(key, page)
		sheet.set_meta(key + "_painted", false)
		mat.set_shader_parameter(key + "_seed", float(page) * 1.7 + 0.3)
		if page >= 0 and live:
			mat.set_shader_parameter(key + "_picture", scenes[page].get_texture())
	var art := Vector2i(page if live else -1, 0 if front else 1)
	if not sheet.get_meta(key + "_painted") and _paint.has(art):
		sheet.set_meta(key + "_painted", true)
		mat.set_shader_parameter(key + "_paint", _paint[art][0])
		mat.set_shader_parameter(key + "_grain", _paint[art][1])


## Every page renders on the book's first frame, so none compiles its pipelines when first opened.
func _render_pages() -> void:
	var shown: Array[int] = faces_in_view() if live else ([] as Array[int])
	var due := _frame % PAGE_HZ_DIVIDER == 0
	for page in scenes:
		var s: LessonScene = scenes[page]
		var on: bool = page in shown
		s.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
		s.render_target_update_mode = SubViewport.UPDATE_ONCE if on and due or _frame == 1 else SubViewport.UPDATE_DISABLED
	for sheet in _sheets:
		var mat := sheet.material_override as ShaderMaterial
		for key in ["front", "back"]:
			var page: int = sheet.get_meta(key, -1)
			if scenes.has(page):
				mat.set_shader_parameter(key + "_wash", scenes[page].wash)
				mat.set_shader_parameter(key + "_horizon", scenes[page].horizon)
				mat.set_shader_parameter(key + "_fade", scenes[page].fade)


static var _page_mesh: PlaneMesh
## Whole boxes, though a page covers a block's top and a board's inside: a page bowing out of the gutter shows what
## lies under it, and drawn after the pages (Layer) the covered faces fail the depth test unshaded.
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
	mat.set_shader_parameter("paper", PAPER)
	mat.render_priority = Layer.SHEET
	mi.material_override = mat
	mi.extra_cull_margin = W
	return mi


func _board(front: bool) -> MeshInstance3D:
	if _board_mesh == null:
		_board_mesh = BoxMesh.new()
		_board_mesh.size = BOARD
	var mi := MeshInstance3D.new()
	mi.mesh = _board_mesh
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://src/book.gdshader")
	mat.set_shader_parameter("size", BOARD)
	mat.set_shader_parameter("front", front)
	_bind(mat)
	mat.render_priority = Layer.BOARD
	mi.material_override = mat
	return mi


static func _bind(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("cloth", Vector3(CLOTH.r, CLOTH.g, CLOTH.b))
	mat.set_shader_parameter("leather", Vector3(LEATHER.r, LEATHER.g, LEATHER.b))


func _block() -> MeshInstance3D:
	if _block_mesh == null:
		_block_mesh = BoxMesh.new()
		_block_mesh.subdivide_width = 14
	var mi := MeshInstance3D.new()
	mi.mesh = _block_mesh
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://src/book.gdshader")
	mat.set_shader_parameter("kind", Kind.BLOCK)
	mat.set_shader_parameter("paper", PAPER)
	mat.set_shader_parameter("leaf_width", W)
	mat.render_priority = Layer.BLOCK
	mi.extra_cull_margin = BOW
	mi.material_override = mat
	add_child(mi)
	return mi
