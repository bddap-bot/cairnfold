class_name LessonScene
extends SubViewport

## One page's live picture: ghost controllers (Pad) act out the page's script (Lessons.PAGES) on a loop over a
## patch of meadow set with the game's own tool models, so the picture always shows the game as it is built.
## Its own small world, lit apart from the garden; the book renders it only while its page is in view. `wash` is
## the painted sky behind it and `fade` how far its loop has faded out, both for the page's paper (book_page.gdshader).

const SIZE := Vector2i(384, 288)
const REST := 0.7
const FADE_S := 0.35
## The picture's meadow lies this far under the eye, a diorama between the hands and the ground, so the hands and
## what they act on share one frame; its builds stand at K of the size of a tool model's PROP-fold.
const GROUND := -0.95
const K := 0.5
const PROP := 14.0 * K
## The ghost controllers are drawn this much larger than life, so their buttons read on a page.
const GHOST := 1.3
## How far the sun stands from the sky page's meadow.
const SUN := 1.4

var page: Dictionary
var index := 0
var t := 0.0
## Stepped by its owner rather than by the frame, as a capture steps it.
var manual := false
var wash := Color(0.72, 0.84, 0.92)
var fade := 1.0
var stage := Node3D.new()
var camera := Camera3D.new()
var pads := {}
var dish: MeshInstance3D
var props: Array[Node3D] = []
var _beam: Beam
var _mark: MeshInstance3D
var _sun_light := DirectionalLight3D.new()
var _fx := {}


func _init(i: int) -> void:
	index = i
	page = Lessons.PAGES[i]
	size = SIZE
	own_world_3d = true
	transparent_bg = true
	msaa_3d = Viewport.MSAA_2X
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(stage)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.84, 0.92)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = Look.EXPOSURE
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.3
	env.adjustment_contrast = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	stage.add_child(we)
	var day := Daylight.light(Daylight.DEFAULT)
	_sun_light.light_color = day.sun
	_sun_light.light_energy = day.energy * 1.15
	_sun_light.basis = Basis.looking_at(Vector3(-0.4, -0.75, -0.55))
	stage.add_child(_sun_light)
	camera.near = 0.01
	camera.far = 60.0
	stage.add_child(camera)
	_frame()
	camera.current = true
	_build_dish()
	for side in Lessons.hands(page):
		var pad := Pad.new(side == "right")
		pad.scale = Vector3.ONE * GHOST
		pad.hold(Lessons.tool(page.tools.get(side, "hands")))
		stage.add_child(pad)
		pads[side] = pad
	_beam = Beam.new(Color(1, 1, 1, 0.65))
	stage.add_child(_beam)
	_beam.visible = false
	_mark = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.16
	ring.outer_radius = 0.2
	_mark.mesh = ring
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.95, 0.8)
	_mark.material_override = glow
	_mark.visible = false
	stage.add_child(_mark)
	call("_build_" + page.effect)


## Looks over the hands at what they act on: from behind them along the line to it, beside and under the acting
## hand for a side view so its trigger and grip show, over it for a top view; widened to hold everything shown.
func _frame() -> void:
	var points: Array[Vector3] = []
	var hands: Array[Vector3] = []
	var target := _dish_at() + Vector3.UP * 0.12
	if has_method("_focus_" + page.effect):
		var extra: Array[Vector3] = call("_focus_" + page.effect)
		points.append_array(extra)
		for p in extra:
			target += (p - target) / (extra.size() + 1.0)
	if page.effect != "page":
		points.append(_dish_at())
	var t := 0.0
	while t <= page.length:
		for side in Lessons.hands(page):
			var at: Vector3 = Lessons.pose(page, side, t).at
			hands.append(Lessons.frame(Lessons.pose(page, "left", t)) * Book.local(1.0) * at if side in page.get("book", []) else at)
		t += 0.25
	var mid := Vector3.ZERO
	for h in hands:
		mid += h / hands.size()
	var along := (target - mid).normalized()
	var acting: String = page.press[0].hand if not page.press.is_empty() else "right"
	var outward := along.cross(Vector3.UP).normalized() * (1.0 if acting == "right" else -1.0)
	var lift := Vector3(0, 0.6, 0) if page.view.get("look", "top") == "top" else Vector3(0, -0.25, 0) + outward * 0.55
	var eye: Vector3 = Lessons._v(page.view.eye) if page.view.has("eye") else mid + (-along + lift).normalized() * page.view.back
	for h in hands:
		for c in [Vector3(-1, -1, -1), Vector3(1, 1, 1), Vector3(-1, 1, 1), Vector3(1, -1, -1), Vector3(1, -1, 1), Vector3(-1, 1, -1)]:
			points.append(h + c * 0.06 * GHOST)
	if page.effect != "page":
		for c in [Vector3(-0.42, 0, 0), Vector3(0.42, 0, 0), Vector3(0, 0, -0.35), Vector3(0, 0, 0.35)]:
			points.append(_dish_at() + c)
	var look := Vector3.ZERO
	for p in points:
		look += (p - eye).normalized()
	for pass_ in 2:
		camera.transform = Transform3D(Basis.looking_at(look, Vector3.UP if absf(look.normalized().y) < 0.95 else Vector3.BACK), eye)
		var lo := Vector2.INF
		var hi := -Vector2.INF
		for p in points:
			var q := camera.transform.affine_inverse() * p
			var a := Vector2(q.x, q.y) / maxf(-q.z, 0.05)
			lo = lo.min(a)
			hi = hi.max(a)
		var mid_a := (lo + hi) * 0.5
		look = camera.basis * Vector3(mid_a.x, mid_a.y, -1.0)
		var half := (hi - lo) * 0.5
		var aspect := float(SIZE.x) / SIZE.y
		camera.fov = clampf(rad_to_deg(2.0 * atan(maxf(half.y, half.x / aspect) * 1.18)), 24.0, 84.0)


func _ready() -> void:
	_pose(0.0)


func _process(delta: float) -> void:
	if not manual:
		advance(delta)


func advance(delta: float) -> void:
	t += delta
	if t >= page.length + REST:
		t = 0.0
		if has_method("_reset_" + page.effect):
			call("_reset_" + page.effect)
	fade = 1.0 - minf(smoothstep(0.0, FADE_S, t), 1.0 - smoothstep(page.length + REST - FADE_S, page.length + REST, t))
	_pose(minf(t, page.length))


func _pose(at: float) -> void:
	for side in pads:
		var pad: Pad = pads[side]
		var p := Lessons.pose(page, side, at)
		var f := Lessons.frame(p)
		if side in page.get("book", []):
			f = _book_frame() * f
		pad.transform = f.scaled_local(Vector3.ONE * GHOST)
		var tracker: String = side + "_hand"
		for press in page.press:
			if press.hand != side:
				continue
			var input := Controls.input(press.action, tracker)
			pad.show_input(input, Lessons.since(page, side, press.action, at), press.get("timed", 0.0))
	_beam.visible = false
	_mark.visible = false
	call("_play_" + page.effect, at)


## Where `side`'s pad points, along its aim to the meadow (y = GROUND) or `reach` metres.
func _aim_hit(side: String, reach := 6.0) -> Vector3:
	var f: Transform3D = pads[side].transform
	var d := -f.basis.z
	if d.y < -0.01:
		var k := (GROUND - f.origin.y) / d.y
		if k < reach:
			return f.origin + d * k
	return f.origin + d * reach


func _ray(side: String, to: Vector3) -> void:
	_beam.visible = true
	_beam.span(pads[side].global_position, to)


## Where the page's first press points, or ahead of the hands if that is the sky.
func _dish_at() -> Vector3:
	if _fx.has("dish"):
		return _fx.dish
	var side: String = page.press[0].hand if not page.press.is_empty() else Lessons.hands(page)[-1]
	var f := Lessons.frame(Lessons.pose(page, side, page.press[0].from if not page.press.is_empty() else 0.0))
	var d := -f.basis.z
	var at := Vector3(f.origin.x * 0.5, GROUND, -1.0)
	if d.y < -0.05:
		at = f.origin + d * minf((GROUND - f.origin.y) / d.y, 2.2)
		at.y = GROUND
	_fx.dish = at
	return at


func _build_dish() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.8, 2.8)
	plane.subdivide_width = 28
	plane.subdivide_depth = 28
	dish = MeshInstance3D.new()
	dish.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://src/lesson_dish.gdshader")
	for k in Meadow.GRASS:
		mat.set_shader_parameter(k, Meadow.GRASS[k])
	mat.set_shader_parameter("earth", Meadow.GROUND[&"earth"])
	dish.material_override = mat
	dish.position = _dish_at()
	dish.scale = Vector3(K, 1.0, K)
	stage.add_child(dish)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 + index
	for i in 14:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 1.15 * K
		var tuft := ToolModels.build(Hand.Tool.GRASS if i % 3 else Hand.Tool.FLOWERS)
		tuft.scale = Vector3.ONE * rng.randf_range(5.0, 8.0) * K
		tuft.position = dish.position + Vector3(cos(a) * r, 0, sin(a) * r)
		tuft.rotation.y = rng.randf() * TAU
		stage.add_child(tuft)


func _prop(tool: Hand.Tool, at: Vector3, scale_k := 1.0, yaw := 0.0) -> Node3D:
	var m := ToolModels.build(tool)
	for part in m.get_children():
		if part is Node3D:
			part.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.22), Vector3.ZERO) * part.transform if tool in [Hand.Tool.WALLS, Hand.Tool.HOUSE] else part.transform
	m.scale = Vector3.ONE * PROP * scale_k
	m.position = at
	m.rotation.y = yaw
	m.set_meta("scale", PROP * scale_k)
	stage.add_child(m)
	props.append(m)
	return m


static func _pop(k: float) -> float:
	k = clampf(k, 0.0, 1.0)
	return 1.0 + 2.2 * pow(k - 1.0, 3) + 1.2 * pow(k - 1.0, 2)


# The page that teaches turning the page: a little open book in the left hand, turned by the right's sweep.
func _build_page() -> void:
	dish.visible = false
	pads.left.visible = false
	var b := Book.new(false)
	b.at = 1
	stage.add_child(b)
	_fx.book = b


func _focus_page() -> Array[Vector3]:
	var f := Lessons.frame(Lessons.pose(page, "left", 0.0)) * Book.local(1.0)
	return [f * Vector3(-Book.W, 0, -Book.H * 0.5), f * Vector3(Book.W, 0, -Book.H * 0.5), f * Vector3(-Book.W, 0, Book.H * 0.5), f * Vector3(Book.W, 0, Book.H * 0.5)]


func _book_frame() -> Transform3D:
	return pads.left.transform * Book.local(1.0)


func _reset_page() -> void:
	_fx.book.at = 1
	_fx.book._turn.clear()


func _play_page(_at: float) -> void:
	var b: Book = _fx.book
	b.transform = _book_frame()
	b.feel(pads.right.global_position)


# Picking a tool: the wheel opens at the hand while its button is held, the slot the hand moves onto grows, and
# letting go stands that tool on the controller.
func _build_tool() -> void:
	var wheel := Node3D.new()
	stage.add_child(wheel)
	_fx.wheel = wheel
	_fx.icons = []
	var dirs := ToolWheel.ring_dirs()
	for k in Hand.TREE.size():
		var item: Variant = Hand.TREE[k]
		var icon := Node3D.new()
		var disc := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.034
		cyl.bottom_radius = 0.034
		cyl.height = 0.002
		disc.mesh = cyl
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(1.0, 0.98, 0.92, 0.5)
		disc.material_override = m
		disc.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, -0.025))
		icon.add_child(disc)
		var model := ToolModels.build(item[0] if item is Array else item)
		model.transform = Transform3D(Basis(Vector3.RIGHT, Hand.TILT), Vector3(0, -0.012, 0))
		icon.add_child(model)
		icon.position = Vector3(dirs[k].x, dirs[k].y, 0) * ToolWheel.RADIUS
		wheel.add_child(icon)
		_fx.icons.append(icon)
	_reset_tool()


func _reset_tool() -> void:
	pads.right.hold(Lessons.tool(page.tools.right))
	_fx.opened = null


func _focus_tool() -> Array[Vector3]:
	var at: Vector3 = Lessons.pose(page, "right", 0.0).at
	var r := ToolWheel.RADIUS * 1.3
	return [at + Vector3(0, r, 0), at + Vector3(0, -r, 0), at + Vector3(r, 0, 0), at + Vector3(-r, 0, 0)]


func _play_tool(at: float) -> void:
	var wheel: Node3D = _fx.wheel
	var held := Lessons.held(page, "right", "wheel", at)
	var hand: Vector3 = pads.right.position
	if held and _fx.opened == null:
		_fx.opened = hand
		wheel.transform = Transform3D(ToolWheel.facing(hand, Vector3.ZERO, Vector3.FORWARD), hand)
	wheel.visible = held
	if not held and _fx.opened != null:
		_fx.opened = null
		pads.right.hold(Lessons.tool(page.to))
	if not held:
		return
	var local: Vector3 = wheel.transform.affine_inverse() * hand
	var p := Vector2(local.x, local.y)
	var hot := -1
	if p.length() > ToolWheel.DEAD:
		var best := -1.0
		for k in ToolWheel.SLOTS:
			var d := p.normalized().dot(ToolWheel.ring_dirs()[k])
			if d > best:
				best = d
				hot = k
	var open_k := clampf(Lessons.since(page, "right", "wheel", at) / 0.15, 0.0, 1.0)
	for k in _fx.icons.size():
		var s := (Hand.HOT if k == hot else Hand.IDLE) * _pop(open_k)
		_fx.icons[k].scale = _fx.icons[k].scale.lerp(Vector3.ONE * s, 0.3)


# Teleporting: the left stick pushed forward casts a ray to a ring on the meadow; letting go hops there.
func _build_teleport() -> void:
	_fx.home = camera.transform


func _reset_teleport() -> void:
	camera.transform = _fx.home


func _play_teleport(at: float) -> void:
	var press: Dictionary = page.press[0]
	if at < press.to:
		camera.transform = _fx.home
		_fx.target = _aim_hit("left", 9.0)
		if Lessons.held(page, "left", "teleport", at):
			_ray("left", _fx.target)
			_mark.visible = true
			_mark.position = _fx.target + Vector3.UP * 0.02
		return
	var hop := Vector3(_fx.target.x, 0.0, _fx.target.z + 0.45) * 0.8
	var k := smoothstep(0.0, 0.1, at - press.to)
	camera.transform = Transform3D(_fx.home.basis, _fx.home.origin + hop * k)
	for side in pads:
		pads[side].position += hop * k
	fade = maxf(fade, 1.0 - absf(at - press.to - 0.05) / 0.12)


# Undo and redo: the left hand's lower face button takes the last build away, the right's puts it back.
func _build_undo() -> void:
	_fx.wall = _prop(Hand.Tool.WALLS, _dish_at() + K * Vector3(0, 0, 0.1), 1.2)


func _play_undo(at: float) -> void:
	var undo: Dictionary = page.press[0]
	var redo: Dictionary = page.press[1]
	var w: Node3D = _fx.wall
	var k := 1.0
	if at >= redo.from:
		k = _pop((at - redo.from) / 0.25)
	elif at >= undo.from:
		k = 1.0 - smoothstep(0.0, 0.15, at - undo.from)
	w.scale = Vector3.ONE * w.get_meta("scale") * maxf(k, 0.001)
	w.visible = k > 0.002


# Shaping the ground: the grip takes the meadow where the hand points, and the hand raised pulls a hill.
func _build_hill() -> void:
	_fx.from = INF


func _reset_hill() -> void:
	_fx.from = INF


func _play_hill(at: float) -> void:
	var mat := dish.material_override as ShaderMaterial
	var holding := Lessons.held(page, "right", "grab", at)
	var y: float = pads.right.position.y
	if holding and _fx.from == INF:
		_fx.from = y
		_fx.point = _aim_hit("right")
	if not holding and at < page.press[0].from:
		_fx.from = INF
		mat.set_shader_parameter("hill_height", 0.0)
	if _fx.from == INF:
		var hit := _aim_hit("right")
		_ray("right", hit)
		_mark.visible = true
		_mark.position = hit + Vector3.UP * 0.02
		return
	var point: Vector3 = _fx.point
	var lift: float = (y - _fx.from) * Hand.reach_gain(point.distance_to(pads.right.position)) * K * 1.6 if holding else mat.get_shader_parameter("hill_height")
	mat.set_shader_parameter("hill_at", Vector2(point.x - dish.position.x, point.z - dish.position.z) / K)
	mat.set_shader_parameter("hill_height", maxf(lift, 0.0))
	if holding:
		_ray("right", point + Vector3.UP * maxf(lift, 0.0))


# Turning the sky: the grip on open sky holds it, and turning the pointer carries the sun along its arc.
func _build_sky() -> void:
	var sun := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.16
	ball.height = 0.32
	sun.mesh = ball
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.82, 0.4)
	sun.material_override = m
	stage.add_child(sun)
	_fx.sun = sun
	_prop(Hand.Tool.HOUSE, _dish_at() + K * Vector3(0.3, 0, 0.2), 1.0, 0.4)
	_prop(Hand.Tool.TREES, _dish_at() + K * Vector3(-0.5, 0, -0.1), 1.0)


func _focus_sky() -> Array[Vector3]:
	var from := Vector3(-0.35, 0.75, -0.55).normalized()
	var start: Vector3 = Lessons.pose(page, "right", 0.0).aim
	var end: Vector3 = Lessons.pose(page, "right", page.length).aim
	var up := _dish_at() + Vector3.UP * 0.2
	var out: Array[Vector3] = []
	for p in [up + from * SUN, up + Quaternion(start.normalized(), end.normalized()) * from * SUN]:
		out.append_array([p + Vector3.UP * 0.2, p + Vector3.RIGHT * 0.2, p - Vector3.RIGHT * 0.2])
	return out


func _play_sky(at: float) -> void:
	var start: Vector3 = Lessons.pose(page, "right", 0.0).aim
	var aim: Vector3 = -pads.right.transform.basis.z
	var from := Vector3(-0.35, 0.75, -0.55).normalized()
	var to_sun := Quaternion(start.normalized(), aim.normalized()) * from
	var sun: Node3D = _fx.sun
	sun.position = _dish_at() + Vector3.UP * 0.2 + to_sun * SUN
	var time := Daylight.DEFAULT + 0.12 * (to_sun.x + 0.35)
	var l := Daylight.light(time)
	_sun_light.light_color = l.sun
	_sun_light.light_energy = l.energy
	_sun_light.basis = Basis.looking_at(-to_sun)
	(sun.get("material_override") as StandardMaterial3D).albedo_color = (l.glow as Color).lerp(Color(1.0, 0.85, 0.45), 0.5)
	wash = (l.zenith as Color).lerp(l.horizon, 0.45)
	if Lessons.held(page, "right", "grab", at):
		_ray("right", sun.position)


# Recolouring: the trigger on a wall opens a wheel of its colours, and the wrist's twist turns it.
func _build_colour() -> void:
	_fx.house = _prop(Hand.Tool.HOUSE, _dish_at() + K * Vector3(0, 0, 0.1), 1.3, 0.3)
	_fx.wheel = Node3D.new()
	stage.add_child(_fx.wheel)
	_fx.swatches = []
	var n := Palette.count(Palette.Element.PLASTER)
	for i in n:
		var disc := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.016
		cyl.bottom_radius = 0.016
		cyl.height = 0.004
		disc.mesh = cyl
		var m := StandardMaterial3D.new()
		m.albedo_color = Palette.swatch(Palette.Element.PLASTER, i)
		disc.material_override = m
		_fx.wheel.add_child(disc)
		_fx.swatches.append(disc)
	_fx.tint = StandardMaterial3D.new()
	_fx.tint.vertex_color_use_as_albedo = true


func _reset_colour() -> void:
	_tint(_fx.house, null)


func _tint(n: Node, mat: Material) -> void:
	for c in n.find_children("*", "GeometryInstance3D", true, false):
		(c as GeometryInstance3D).material_overlay = mat


func _play_colour(at: float) -> void:
	var hit: Vector3 = (_fx.house as Node3D).position + Vector3(0, 0.35, 0)
	var holding := Lessons.held(page, "right", "tool", at)
	var wheel: Node3D = _fx.wheel
	wheel.visible = holding
	if not holding:
		if at < page.press[0].from:
			_ray("right", hit)
		return
	var f: Transform3D = pads.right.transform
	var twist := deg_to_rad(Lessons.pose(page, "right", at).roll)
	var n: int = _fx.swatches.size()
	wheel.transform = Transform3D(f.basis, f * PaletteTool.WHEEL_AT)
	var chosen := posmod(roundi(-rad_to_deg(twist) / Palette.TWIST_STEP), n)
	for i in n:
		var a := float(i - chosen) / n * TAU + twist + float(chosen) / n * TAU * 0.0
		var d: MeshInstance3D = _fx.swatches[i]
		d.position = Vector3(sin(a), cos(a), 0) * PaletteTool.WHEEL_RADIUS
		d.rotation = Vector3(PI * 0.5, 0, 0)
		d.scale = Vector3.ONE * (1.5 if i == chosen else 1.0)
	var m: StandardMaterial3D = _fx.tint
	m.albedo_color = Color(Palette.swatch(Palette.Element.PLASTER, chosen), 0.45)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tint(_fx.house, m)
	_ray("right", hit)


# Two hands on a house: the trigger takes it up, the other hand's grip joins, and spreading the hands stretches it.
func _build_house() -> void:
	_fx.house = _prop(Hand.Tool.HOUSE, _dish_at(), 1.0)
	_fx.house.visible = false
	_fx.spread = INF


func _reset_house() -> void:
	_fx.house.visible = false
	_fx.spread = INF


func _play_house(at: float) -> void:
	var h: Node3D = _fx.house
	var taking := Lessons.held(page, "right", "tool", at)
	var both := taking and Lessons.held(page, "left", "grab", at)
	if not taking and at < page.press[0].from:
		_ray("right", _aim_hit("right"))
		return
	h.visible = true
	var hit := _aim_hit("right")
	if taking:
		h.position = Vector3(hit.x, GROUND, hit.z)
		_ray("right", hit)
	var apart: float = pads.left.position.distance_to(pads.right.position)
	if both and _fx.spread == INF:
		_fx.spread = apart
	var s: float = h.get_meta("scale")
	if _fx.spread != INF:
		var k: float = apart / _fx.spread
		h.scale = Vector3(s * k, s, s)
	if not taking:
		var k := _pop((at - page.press[0].to) / 0.25)
		h.scale.y = s * lerpf(0.9, 1.0, k)


# The wipe: the delete tool held up at the sky for its whole hold swells an orb, then takes the garden away.
func _build_wipe() -> void:
	_prop(Hand.Tool.HOUSE, _dish_at() + K * Vector3(0.35, 0, 0.1), 1.0, 0.5)
	_prop(Hand.Tool.WALLS, _dish_at() + K * Vector3(-0.4, 0, 0.3), 0.9, -0.3)
	_prop(Hand.Tool.TREES, _dish_at() + K * Vector3(-0.5, 0, -0.45), 1.1)
	_prop(Hand.Tool.TREES, _dish_at() + K * Vector3(0.6, 0, -0.5), 0.8)
	var orb := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.22
	ball.height = 0.44
	orb.mesh = ball
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	orb.material_override = m
	stage.add_child(orb)
	_fx.orb = orb


func _reset_wipe() -> void:
	for p in props:
		p.visible = true
		p.scale = Vector3.ONE * p.get_meta("scale")


func _focus_wipe() -> Array[Vector3]:
	var f := Lessons.frame(Lessons.pose(page, "right", page.length))
	var orb := f.origin - f.basis.z * 0.5
	return [orb + Vector3.UP * 0.24, orb + Vector3.RIGHT * 0.24, orb - Vector3.RIGHT * 0.24]


func _play_wipe(at: float) -> void:
	var held := Lessons.since(page, "right", "tool", at)
	var orb: MeshInstance3D = _fx.orb
	var k := held / DeleteTool.WIPE_HOLD
	orb.visible = held >= 0.0 and k < 1.0
	var aim: Vector3 = -pads.right.transform.basis.z
	if orb.visible:
		orb.position = pads.right.position + aim * 0.5
		orb.scale = Vector3.ONE * maxf(k * k, 0.02)
		(orb.material_override as StandardMaterial3D).albedo_color = Color(DeleteTool.TINT, lerpf(0.15, 0.85, k))
		_ray("right", orb.position)
	var gone: float = at - (page.press[0].from + DeleteTool.WIPE_HOLD)
	for i in props.size():
		var p := props[i]
		var s := 1.0 - smoothstep(0.0, 0.18, gone - i * 0.06) if gone >= 0.0 else 1.0
		p.scale = Vector3.ONE * p.get_meta("scale") * maxf(s, 0.001)
		p.visible = s > 0.002
