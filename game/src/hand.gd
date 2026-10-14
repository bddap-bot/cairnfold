class_name Hand
extends XRController3D

## A controller and the tool it holds. Every tool's input code dispatches on `tool`, and the object on top
## of the controller and the selection ring show it, so they cannot disagree.

enum Tool { WALLS, PATH, FLOWERS, GRASS, TREES, TERRAIN, TELEPORT, DELETE, POND, FENCE, WINDOWS, DECORATIONS, STONE }

## The ring's contents: a tree, one level deep for now.
const MENU := [Tool.WALLS, Tool.FENCE, Tool.WINDOWS, Tool.DECORATIONS, Tool.PATH, Tool.STONE, Tool.FLOWERS, Tool.GRASS, Tool.TREES, Tool.TERRAIN, Tool.POND, Tool.TELEPORT, Tool.DELETE]
const TOP := Vector3(0, 0.0075, 0.045)
const RING_RADIUS := 0.11
const POP := 0.18

## Stick positions the driver injects, keyed by tracker.
static var injected_sticks := {}

var tool := Tool.WALLS
var picking := false
## After a pick the stick is still pushed toward the tool; locomotion ignores it until it recentres.
var _stick_free := true
var _choice := -1
var _buttons: Buttons
var _shown := -1
var _leaving := -1
var _pop_t := POP
var _models: Array[Node3D] = []
var _ring: Node3D
var _ring_items: Array[Node3D] = []
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
	_ring = Node3D.new()
	_ring.position = TOP + Vector3(0, 0.035, 0)
	_ring.visible = false
	add_child(_ring)
	for i in MENU.size():
		var m := ToolModels.build(MENU[i])
		var d := ring_dir(i)
		m.position = Vector3(d.x, 0, -d.y) * RING_RADIUS
		_ring.add_child(m)
		_ring_items.append(m)
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
	_buttons = Buttons.new(self).watch(["primary_click"])


## The thumbstick as locomotion reads it: still while the ring has it.
func stick() -> Vector2:
	return _raw_stick() if _stick_free and not picking else Vector2.ZERO


## The stick direction that points at ring entry `i`, clockwise from forward.
static func ring_dir(i: int) -> Vector2:
	var a := TAU * i / MENU.size()
	return Vector2(sin(a), cos(a))


## How many metres a thing pulled at `reach` metres moves per metre of hand, so far things keep up.
static func reach_gain(reach: float) -> float:
	return maxf(1.0, reach / 1.2)


func _raw_stick() -> Vector2:
	return injected_sticks.get(tracker, get_vector2("primary"))


## Tools call this each frame they point; the pointer hides on frames nobody does.
func point(hit: Variant, tint: Color, reach := 20.0) -> void:
	if not get_has_tracking_data():
		return
	var origin := global_position
	_beam.visible = true
	_beam.span(origin, hit if hit != null else origin - global_basis.z * reach)
	(_beam.material_override as StandardMaterial3D).albedo_color = tint
	_dot.visible = hit != null
	if hit != null:
		_dot.global_position = hit


func _process(delta: float) -> void:
	_beam.visible = false
	_dot.visible = false
	_select_input()
	_buttons.latch()
	_show_tool(delta)


## Hold the stick click to open the ring, move the stick toward a tool, let go of the click to take it.
func _select_input() -> void:
	if not _stick_free and _raw_stick().length() < 0.3:
		_stick_free = true
	if not picking:
		if _buttons.pressed("primary_click"):
			picking = true
			_choice = -1
			_ring.visible = true
		return
	var v := _raw_stick()
	if v.length() > 0.5:
		_choice = posmod(roundi(atan2(v.x, v.y) / (TAU / MENU.size())), MENU.size())
	for i in _ring_items.size():
		_ring_items[i].scale = Vector3.ONE * (1.3 if i == _choice else 0.7)
	if _buttons.released("primary_click"):
		if _choice >= 0:
			tool = MENU[_choice]
		picking = false
		_stick_free = false
		_ring.visible = false


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
