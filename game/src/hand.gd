class_name Hand
extends XRController3D

## A controller and the tool it holds. Every tool's input code dispatches on `tool`, and the object on top
## of the controller and the selection wheel show it, so they cannot disagree.

enum Tool { WALLS, PATH, FLOWERS, GRASS, TREES, DELETE, POND, FENCE, WINDOWS, DECORATIONS, STONE, VISIT, COLOUR, CAMERA, HOUSE, HANDS, SEEDS, DIRT_PATH, STYLE, STAIRS, EASEL, TOWER, ARCH, BOOK }

## The wheel's contents, clockwise from the top; an Array is a subtree, null an empty slot. Fixed, so every
## pick is a learnable motion.
const TREE := [
	[Tool.COLOUR, Tool.STYLE],
	[Tool.HANDS, Tool.CAMERA, Tool.SEEDS, Tool.EASEL],
	[Tool.FLOWERS, Tool.GRASS, Tool.TREES, Tool.POND],
	[Tool.VISIT, Tool.BOOK],
	Tool.DELETE,
	[Tool.PATH, Tool.DIRT_PATH, Tool.STONE, Tool.STAIRS],
	[Tool.WALLS, Tool.FENCE, Tool.WINDOWS, Tool.ARCH],
	[Tool.HOUSE, Tool.TOWER, Tool.DECORATIONS],
]
const TOP := Vector3(0, 0.0075, 0.045)
const POP := 0.18
const HOT := 1.4
const IDLE := 0.8
## How far a wheel icon's model tips its top toward the eye.
const TILT := PI * 0.3
static var _disc: CylinderMesh
static var _unshaded := {}

## The stick pushed one way, as the input named for it: past PUSH, along whichever way it is pushed most, it
## holds that way until it comes back inside LET_GO, so one flick is one input.
const FLICKS := {"primary_up": Vector2(0, 1), "primary_down": Vector2(0, -1), "primary_left": Vector2(-1, 0), "primary_right": Vector2(1, 0)}
const PUSH := 0.7
const LET_GO := 0.3

## Stick positions the driver injects, keyed by tracker.
static var injected_sticks := {}
## Hand positions in the wheel's plane the driver injects, keyed by tracker, in place of the hand's own.
static var injected_reach := {}

var tool := Tool.WALLS
## The way the stick is flicked (a FLICKS key), or "".
var flick := ""
var picking := false
## What the hand's tool shows would not fit the frame budget: its pointer shows it refused (BudgetBar).
var capped := false
var _wheel: ToolWheel
var _profile := ""
var _holding := false
## Desktop only: the driver holds this hand where tracking would put it.
var held_still := false
var _buttons: Buttons
## The hand as seen, with the tool on top: HandStop holds it at what the controller pushes into.
var body := Node3D.new()
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
	add_child(body)
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.rounded_box(0.3, 2, 7)
	mi.scale = Vector3(0.05, 0.035, 0.11)
	mi.position = Vector3(0, -0.01, 0.04)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.93, 0.9, 0.84)
	mat.roughness = 0.6
	mi.material_override = mat
	body.add_child(mi)
	for t in Tool.size():
		var m := Node3D.new() if t in [Tool.HANDS, Tool.EASEL, Tool.BOOK] else ToolModels.build(t)
		m.position = TOP
		m.scale = Vector3.ZERO
		m.visible = false
		body.add_child(m)
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
	_buttons = Buttons.new(self).watch(["wheel"])


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
			var fan := ToolWheel.fan_dirs(sub.size(), dirs[k])
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
	for v in _wheel_root.find_children("*", "VisualInstance3D", true, false):
		(v as VisualInstance3D).layers = Rig.WHEEL_LAYER
		if v is MeshInstance3D:
			_unshade(v)
	var day := Daylight.light(Daylight.DEFAULT)
	var light := DirectionalLight3D.new()
	light.light_cull_mask = Rig.WHEEL_LAYER
	light.light_color = day.sun
	light.light_energy = day.energy
	light.basis = Basis.looking_at(Vector3(0.3, -0.6, -1.0))
	_wheel_root.add_child(light)


## Swaps `mi`'s standard materials for unshaded copies: under the mobile renderer they never took the
## wheel's light, which reaches only its shader materials.
static func _unshade(mi: MeshInstance3D) -> void:
	for i in mi.get_surface_override_material_count():
		var mat := mi.get_active_material(i) as BaseMaterial3D
		if mat == null or mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
			continue
		if not _unshaded.has(mat):
			_unshaded[mat] = mat.duplicate()
			_unshaded[mat].shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		if mi.material_override == mat:
			mi.material_override = _unshaded[mat]
		else:
			mi.set_surface_override_material(i, _unshaded[mat])


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


## The open wheel's frame: x to the player's right, y the player's up, z toward the head.
func wheel_frame() -> Transform3D:
	return _wheel_root.global_transform


## The thumbstick as locomotion reads it.
func stick() -> Vector2:
	return injected_sticks.get(tracker, get_vector2("primary"))


## How many metres a thing pulled at `reach` metres moves per metre of hand, so far things keep up.
static func reach_gain(reach: float) -> float:
	return maxf(1.0, reach / 1.2)


func tracked() -> bool:
	return held_still or get_has_tracking_data()


## Tools call this each frame they point; the pointer hides on frames nobody does.
func point(hit: Variant, tint: Color, reach := 20.0) -> void:
	if not tracked():
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
	_beam.span(body.global_position, target)
	(_beam.material_override as StandardMaterial3D).albedo_color = BudgetBar.REFUSED if capped else tint
	return true


## Whether a tool already holds this hand this frame.
func taken() -> bool:
	return _holding


func clear_pointer() -> void:
	_beam.visible = false
	_dot.visible = false


# A tool renews its hold each frame, so a cancelled gesture cannot leave a stale hidden pointer.
func hold() -> void:
	_holding = true
	clear_pointer()


func _process(delta: float) -> void:
	_log_profile()
	_flick_input()
	_holding = false
	clear_pointer()
	_select_input(delta)
	_buttons.latch()
	_show_tool(delta)


func _flick_input() -> void:
	var s := stick()
	if flick != "":
		if s.length() < LET_GO:
			flick = ""
		return
	if s.length() <= PUSH:
		return
	for way in FLICKS:
		if s.dot(FLICKS[way]) >= s.length() * cos(PI / 4):
			flick = way


## The interaction profile the runtime bound this hand to, logged with the wheel's input on each change, so a
## device's log shows which of its controls the controls table landed on.
func _log_profile() -> void:
	var t := XRServer.get_tracker(tracker) as XRPositionalTracker
	var profile := t.profile if t != null else ""
	if profile != _profile:
		_profile = profile
		print("controls: %s on %s, wheel %s" % [tracker, profile, Controls.input("wheel", tracker)])


## Hold the wheel button and the wheel opens where the hand is, facing the head; sweep the hand
## onto a tool, or onto a subtree and on into it; let go to take the tool the hand is on.
func _select_input(delta: float) -> void:
	if _wheel == null:
		if not _buttons.pressed("wheel"):
			return
		_wheel = ToolWheel.new(TREE)
		print("wheel: %s opened" % tracker)
		picking = true
		var cam := get_viewport().get_camera_3d()
		var head := cam.global_position if cam != null else global_position + global_basis.z
		var forward := -cam.global_basis.z if cam != null else -global_basis.z
		_wheel_root.global_transform = Transform3D(ToolWheel.facing(global_position, head, forward), global_position)
		for icon in _wheel_root.get_children():
			icon.scale = Vector3.ZERO
		_wheel_root.visible = true
		Cues.play(Cues.Act.WHEEL_OPEN, global_position, self)
	var p: Vector2 = injected_reach.get(tracker, Vector2.INF)
	if p == Vector2.INF:
		var local := _wheel_root.global_transform.affine_inverse() * global_position
		p = Vector2(local.x, local.y)
	var was: Array = [_wheel.levels.size(), _wheel.levels[-1].hot]
	_wheel.move(p)
	if _wheel.levels[-1].hot >= 0 and [_wheel.levels.size(), _wheel.levels[-1].hot] != was:
		Cues.play(Cues.Act.WHEEL_HOVER, global_position, self)
	_show_wheel(delta)
	if _buttons.released("wheel"):
		var pick: Variant = _wheel.chosen()
		if pick != null:
			tool = pick
			Cues.play(Cues.Act.WHEEL_PICK, global_position, self)
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
		# Shrunk to nothing, an icon would still run its vertices.
		_slots[i].visible = target > 0.0 or _slots[i].scale.x > 0.01
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
