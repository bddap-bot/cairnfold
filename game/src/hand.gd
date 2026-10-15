class_name Hand
extends XRController3D

## A controller and the tool it holds. Every tool's input code dispatches on `tool`, and the object on top
## of the controller and the selection wheel show it, so they cannot disagree.

enum Tool { WALLS, PATH, FLOWERS, GRASS, TREES, TERRAIN, DELETE, POND, FENCE, WINDOWS, DECORATIONS, STONE, VISIT, COLOUR, CAMERA, HOUSE }

## The wheel's contents, clockwise from the top; an Array is a subtree, null an empty slot. Subtrees sit
## on slots reached by a sideways swing, so their items open on the other side. Fixed, so every pick is a
## learnable motion.
const TREE := [
	Tool.COLOUR,
	Tool.CAMERA,
	[Tool.FLOWERS, Tool.GRASS, Tool.TREES, Tool.POND],
	Tool.VISIT,
	Tool.DELETE,
	[Tool.PATH, Tool.STONE, Tool.TERRAIN],
	[Tool.WALLS, Tool.FENCE, Tool.WINDOWS, Tool.DECORATIONS],
	Tool.HOUSE,
]
## Held to open the wheel: a face button nothing else takes on Touch-style or Frame controllers (left
## menu arrives as the Frame's View button, right B as its B, X and Y).
const WHEEL_BUTTON := {"left_hand": "menu_button", "right_hand": "by_button"}
const TOP := Vector3(0, 0.0075, 0.045)
const POP := 0.18
const HOT := 1.4
const IDLE := 0.8
## How far a wheel icon's model tips its top toward the eye.
const TILT := PI * 0.3
static var _disc: CylinderMesh

## Stick positions the driver injects, keyed by tracker.
static var injected_sticks := {}
## Hand positions in the wheel's plane the driver injects, keyed by tracker, in place of the hand's own.
static var injected_reach := {}

var tool := Tool.WALLS
## While its grip drags the sun (SunTool), the grip is the sun's alone.
var holds_sun := false
var picking := false
var _wheel: ToolWheel
var _wheel_button: String
var _holding := false
var _buttons: Buttons
var _shown := -1
var _leaving := -1
var _pop_t := POP
var _models: Array[Node3D] = []
var _wheel_root: Node3D
## Per wheel slot: its icon, and for a subtree the icons of its items.
var _slots: Array[Node3D] = []
var _subs: Array[Array] = []
var _beam: Beam
var _dot: MeshInstance3D


func _init(tracker_name: String, held: Tool) -> void:
	tracker = tracker_name
	pose = &"aim"
	tool = held
	process_priority = -10
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.rounded_box(0.3, 2, 7)
	mi.scale = Vector3(0.05, 0.035, 0.11)
	mi.position = Vector3(0, -0.01, 0.04)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.93, 0.9, 0.84)
	mat.roughness = 0.6
	mi.material_override = mat
	add_child(mi)
	for t in Tool.size():
		var m := ToolModels.build(t)
		m.position = TOP
		m.scale = Vector3.ZERO
		m.visible = false
		add_child(m)
		_models.append(m)
	_build_wheel()
	_beam = Beam.new(Color.WHITE)
	add_child(_beam)
	var dot := SphereMesh.new()
	dot.radius = 0.05
	dot.height = 0.1
	_dot = MeshInstance3D.new()
	_dot.mesh = dot
	_dot.material_override = _beam.material_override
	_dot.top_level = true
	_dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_dot)
	_wheel_button = WHEEL_BUTTON[tracker_name]
	_buttons = Buttons.new(self).watch([_wheel_button])


## A subtree's icon is its items in miniature, two by two.
func _build_wheel() -> void:
	_wheel_root = Node3D.new()
	_wheel_root.top_level = true
	_wheel_root.visible = false
	add_child(_wheel_root)
	var dirs := ToolWheel.ring_dirs()
	for k in TREE.size():
		var at := dirs[k] * ToolWheel.RADIUS
		var items: Array[Node3D] = []
		var model := Node3D.new()
		if TREE[k] is Array:
			var sub: Array = TREE[k]
			var fan := ToolWheel.fan_dirs(sub.size(), ToolWheel.side_after(dirs[k]))
			for j in sub.size():
				var mini := ToolModels.build(sub[j])
				mini.scale = Vector3.ONE * 0.5
				mini.position = Vector3((j % 2 - 0.5) * 0.03, 0, (floorf(j * 0.5) - 0.5) * 0.03)
				model.add_child(mini)
				var item := _wheel_icon(ToolModels.build(sub[j]), at + fan[j] * ToolWheel.RADIUS)
				item.visible = false
				items.append(item)
		elif TREE[k] != null:
			model = ToolModels.build(TREE[k])
		else:
			_wheel_root.add_child(model)
		_slots.append(_wheel_icon(model, at) if TREE[k] != null else model)
		_subs.append(items)


## A wheel icon at `at`: its model tipped toward the eye, as a controller's top is seen, on a pale disc
## facing the eye so it reads against the meadow.
func _wheel_icon(model: Node3D, at: Vector2) -> Node3D:
	if _disc == null:
		_disc = CylinderMesh.new()
		_disc.top_radius = 0.034
		_disc.bottom_radius = 0.034
		_disc.height = 0.001
		_disc.radial_segments = 24
		_disc.rings = 1
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1.0, 0.98, 0.92, 0.45)
		_disc.material = mat
	var icon := Node3D.new()
	icon.position = Vector3(at.x, at.y, 0)
	var back := MeshInstance3D.new()
	back.mesh = _disc
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	back.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, -0.025))
	icon.add_child(back)
	model.transform = Transform3D(Basis(Vector3.RIGHT, TILT), Vector3(0, -0.012, 0))
	icon.add_child(model)
	_wheel_root.add_child(icon)
	return icon


## The open wheel's frame: x to the player's right, y up, z toward the head.
func wheel_frame() -> Transform3D:
	return _wheel_root.global_transform


## The thumbstick as locomotion reads it.
func stick() -> Vector2:
	return injected_sticks.get(tracker, get_vector2("primary"))


## How many metres a thing pulled at `reach` metres moves per metre of hand, so far things keep up.
static func reach_gain(reach: float) -> float:
	return maxf(1.0, reach / 1.2)


## Tools call this each frame they point; the pointer hides on frames nobody does.
func point(hit: Variant, tint: Color, reach := 20.0) -> void:
	if not get_has_tracking_data():
		return
	if not ray(hit if hit != null else global_position - global_basis.z * reach, tint):
		return
	_dot.visible = hit != null
	if hit != null:
		_dot.global_position = hit


func ray(target: Vector3, tint: Color) -> bool:
	if _holding:
		return false
	_beam.visible = true
	_beam.span(global_position, target)
	(_beam.material_override as StandardMaterial3D).albedo_color = tint
	return true


func clear_pointer() -> void:
	_beam.visible = false
	_dot.visible = false


# A tool renews its hold each frame, so a cancelled gesture cannot leave a stale hidden pointer.
func hold() -> void:
	_holding = true
	clear_pointer()


func _process(delta: float) -> void:
	_holding = false
	clear_pointer()
	_select_input(delta)
	_buttons.latch()
	_show_tool(delta)


## Hold the wheel button and the wheel stands upright where the hand is, facing the head; sweep the hand
## onto a tool, or onto a subtree and on into it; let go to take the tool the hand is on.
func _select_input(delta: float) -> void:
	if _wheel == null:
		if not _buttons.pressed(_wheel_button):
			return
		_wheel = ToolWheel.new(TREE)
		picking = true
		var cam := get_viewport().get_camera_3d()
		var toward := (cam.global_position - global_position) if cam != null else global_basis.z
		toward.y = 0.0
		if toward.length() < 1e-3:
			toward = Vector3.BACK
		_wheel_root.global_transform = Transform3D(Basis.looking_at(-toward.normalized(), Vector3.UP), global_position)
		for icon in _wheel_root.get_children():
			icon.scale = Vector3.ZERO
		_wheel_root.visible = true
	var p: Vector2 = injected_reach.get(tracker, Vector2.INF)
	if p == Vector2.INF:
		var local := _wheel_root.global_transform.affine_inverse() * global_position
		p = Vector2(local.x, local.y)
	_wheel.move(p)
	_show_wheel(delta)
	if _buttons.released(_wheel_button):
		var pick: Variant = _wheel.chosen()
		if pick != null:
			tool = pick
		_wheel = null
		picking = false
		_wheel_root.visible = false


## Hot icons grow; inside a subtree only it and its items stay.
func _show_wheel(delta: float) -> void:
	var levels := _wheel.levels
	var k := 1.0 - exp(-delta * 20.0)
	var inside: bool = levels.size() > 1
	for i in _slots.size():
		var hot: bool = levels[0].hot == i
		var target := 0.0 if inside and not hot else (HOT if hot and not inside else IDLE)
		_slots[i].scale = _slots[i].scale.lerp(Vector3.ONE * target, k)
		for j in _subs[i].size():
			var item: Node3D = _subs[i][j]
			item.visible = inside and hot
			var s := (HOT if levels[1].hot == j else IDLE) if item.visible else 0.0
			item.scale = item.scale.lerp(Vector3.ONE * s, k) if item.visible else Vector3.ZERO


func _show_tool(delta: float) -> void:
	if tool != _shown:
		if _leaving >= 0:
			_models[_leaving].visible = false
		_leaving = _shown
		_shown = tool
		_pop_t = 0.0
		_models[_shown].visible = true
	if _pop_t >= POP:
		return
	_pop_t = minf(_pop_t + delta, POP)
	var out := clampf(_pop_t / (POP * 0.4), 0.0, 1.0)
	if _leaving >= 0:
		_models[_leaving].scale = Vector3.ONE * (1.0 - out)
		if out >= 1.0:
			_models[_leaving].visible = false
			_leaving = -1
	var k := clampf((_pop_t - POP * 0.3) / (POP * 0.7), 0.0, 1.0)
	var overshoot := 1.0 + 2.2 * pow(k - 1.0, 3) + 1.2 * pow(k - 1.0, 2)
	_models[_shown].scale = Vector3.ONE * overshoot
