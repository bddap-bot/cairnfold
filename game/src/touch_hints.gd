class_name TouchHints
extends Node3D

## A finger resting on a control without pressing it shows, after REST, what that control does on this hand: one
## wheel icon (Hand.icon) per action, beside where the control lies on the controller (Controls.PLACES), facing the
## eye. Lifting the finger or pressing the control takes them away; a pressed control stays quiet until it is let go of
## and touched again, so a finger left on a button after using it does not bring its icon back.

const REST := 0.5
const FADE := 0.15
const SIZE := 0.5
## Where an icon stands from its control, in the right hand's aim pose, clear of the shell and the tool on top.
const BESIDE := {
	"ax_touch": Vector3(-0.045, 0.012, 0.012),
	"by_touch": Vector3(-0.045, 0.012, -0.012),
	"trigger_touch": Vector3(0.0, -0.012, -0.045),
	"primary_touch": Vector3(0.05, 0.012, 0.0),
}
## How far a stick direction's icon stands from the stick's, that way.
const SPREAD := 0.019

var hand: Hand
## Per touch: how long it has rested unpressed, whether its control was pressed while touched, how far its icons show.
var _rest := {}
var _pressed := {}
var _shown := {}
## Per touch: {action: icon}.
var _icons := {}
var _tool_icon := -1
static var _glow: StandardMaterial3D

func _init(of: Hand) -> void:
	hand = of
	for touch in Controls.TOUCHES:
		_rest[touch] = 0.0
		_pressed[touch] = false
		_shown[touch] = 0.0
		_icons[touch] = {}

## The icon showing `action` beside `touch`'s control if it shows, or null.
func showing(touch: String, action: String) -> Node3D:
	var i: Node3D = _icons[touch].get(action)
	return i if i != null and i.visible else null

func _process(delta: float) -> void:
	for touch in Controls.TOUCHES:
		var at := Controls.place(hand.profile, touch, hand.tracker)
		var resting := at != Vector3.INF and hand.tracked() and Buttons.down(hand, touch)
		if not resting:
			_pressed[touch] = false
			_rest[touch] = 0.0
		elif _pressing(touch):
			_pressed[touch] = true
		var on: bool = resting and not _pressed[touch] and not hand.picking
		if on:
			_rest[touch] += delta
		var target := 1.0 if on and _rest[touch] >= REST else 0.0
		_shown[touch] = move_toward(_shown[touch], target, delta / FADE)
		if _shown[touch] > 0.0 or not _icons[touch].is_empty():
			_show(touch, at, _shown[touch])

func _pressing(touch: String) -> bool:
	if touch == "primary_touch" and hand.stick().length() > Hand.LET_GO:
		return true
	return Controls.TOUCHES[touch].any(func(input: String) -> bool: return Buttons.down(hand, input))

func _show(touch: String, at: Vector3, k: float) -> void:
	for action in Controls.touched(touch, hand.tracker):
		var i: Node3D = _icons[touch].get(action)
		if k <= 0.0:
			if i != null:
				i.visible = false
			continue
		if action == "tool" and i != null and hand.tool != _tool_icon:
			i.queue_free()
			i = null
		if i == null:
			i = _build(action)
			add_child(i)
			_icons[touch][action] = i
		var side := Vector3(-1, 1, 1) if hand.tracker == "left_hand" else Vector3.ONE
		var way: Vector2 = Hand.FLICKS.get(Controls.input(action, hand.tracker), Vector2.ZERO)
		i.position = at + BESIDE[touch] * side + Vector3(way.x, 0, -way.y) * SPREAD
		i.visible = true
		var cam := get_viewport().get_camera_3d()
		var eye := cam.global_position if cam != null else to_global(Vector3.BACK)
		var grown := 1.0 - pow(1.0 - k, 3)
		i.global_basis = Basis.looking_at(i.global_position - eye, Vector3.UP).scaled(Vector3.ONE * SIZE * grown)

## `action`'s icon: the held tool's own wheel icon for "tool", else a glowing mark of what it does.
func _build(action: String) -> Node3D:
	var model: Node3D
	match action:
		"tool":
			model = ToolModels.build(hand.tool)
			_tool_icon = hand.tool
		"wheel":
			model = _wheel_mark()
		"undo":
			model = _mark(_arrow(30.0, 310.0, 0.016))
		"redo":
			model = _mark(_arrow(150.0, -130.0, 0.016))
		"teleport":
			model = _ring()
		"turn_left":
			model = _mark(_arrow(50.0, 130.0, 0.03), Vector3(0, 0, 0.026))
		"turn_right":
			model = _mark(_arrow(130.0, 50.0, 0.03), Vector3(0, 0, 0.026))
		_:
			assert(false, "no hint icon for %s" % action)
	var out := Hand.icon(model)
	for v in out.find_children("*", "MeshInstance3D", true, false):
		Hand.unshade(v)
		(v as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return out

static func _glow_mat() -> StandardMaterial3D:
	if _glow == null:
		_glow = StandardMaterial3D.new()
		_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow.albedo_color = Pad.GLOW
		_glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _glow

static func _mark(mesh: Mesh, at := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _glow_mat()
	mi.position = at
	return mi

## The wheel's eight slots, in miniature, as one mesh.
static func _wheel_mark() -> MeshInstance3D:
	var dot := SphereMesh.new()
	dot.radius = 0.006
	dot.height = 0.012
	dot.radial_segments = 8
	dot.rings = 4
	var st := SurfaceTool.new()
	for d in ToolWheel.ring_dirs():
		st.append_from(dot, 0, Transform3D(Basis.IDENTITY, Vector3(d.x, 0, -d.y) * 0.022))
	return _mark(st.commit())


## The teleport ring as it lands on the ground.
static func _ring() -> MeshInstance3D:
	var ring := TorusMesh.new()
	ring.inner_radius = 0.015
	ring.outer_radius = 0.022
	ring.rings = 20
	ring.ring_segments = 6
	return _mark(ring)


## A tube along an arc of `radius` lying flat, from `from` to `to` degrees (counterclockwise seen from above), its head
## at `to`.
static func _arrow(from: float, to: float, radius: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tube := 0.0032
	var steps := 16
	var around := 6
	var dir := signf(to - from)
	var point := func(deg: float) -> Vector3: return Vector3(cos(deg_to_rad(deg)), 0, -sin(deg_to_rad(deg))) * radius
	var head := tube * 5.0
	var end := to - dir * rad_to_deg(head / radius)
	var rings: Array = []
	for j in steps + 1:
		var a := lerpf(from, end, float(j) / steps)
		var out: Vector3 = point.call(a).normalized()
		var ring: Array[Vector3] = []
		for k in around:
			var phi := TAU * k / around
			ring.append(point.call(a) + (out * cos(phi) + Vector3.UP * sin(phi)) * tube)
		rings.append(ring)
	for j in steps:
		for k in around:
			var k2 := (k + 1) % around
			_quad(st, rings[j][k], rings[j][k2], rings[j + 1][k2], rings[j + 1][k])
	var base: Vector3 = point.call(end)
	var tip: Vector3 = point.call(to)
	var radial := base.normalized()
	for k in around:
		var p0 := base + (radial * cos(TAU * k / around) + Vector3.UP * sin(TAU * k / around)) * tube * 2.4
		var p1 := base + (radial * cos(TAU * (k + 1) / around) + Vector3.UP * sin(TAU * (k + 1) / around)) * tube * 2.4
		st.add_vertex(tip)
		st.add_vertex(p0)
		st.add_vertex(p1)
		st.add_vertex(base)
		st.add_vertex(p1)
		st.add_vertex(p0)
	return st.commit()

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for v in [a, b, c, a, c, d]:
		st.add_vertex(v)
