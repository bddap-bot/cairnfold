class_name WallTool
extends Node3D

## Right hand: trigger draws a wall along the ground, grip on a wall pulls its height, A cuts or fills an arch, B undoes.

const POINT_SPACING := 0.45
const REBUILD_EVERY := 0.06
const AUTO_ARCH_LENGTH := 5.0
const WALL_PICK := 0.7

## A stone event for the soundscape, at the stones it moved.
signal built(kind: StringName, at: Vector3)

var rig: Rig
var walls: Array[Wall] = []
var drawing: Wall
var lifting: Wall
var _lift_start := 0.0
var _lift_hand_y := 0.0
var _lift_gain := 1.0
var _lift_at := Vector3.ZERO
var _since_rebuild := 0.0
var _dirty := false
var _seed := 1
var _buttons: Buttons

var _beam: Beam
var _dot: MeshInstance3D


func _init(player: Rig) -> void:
	rig = player
	_buttons = Buttons.new(rig.right).watch(["trigger_click", "grip_click", "ax_button", "by_button"])
	_beam = Beam.new(Color(1.0, 0.97, 0.9, 0.55))
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


func _process(delta: float) -> void:
	var hand := rig.right.global_transform
	var origin := hand.origin
	var dir := -hand.basis.z
	var ground: Variant = Terrain.raycast(origin, dir)
	var pick := pick_wall(origin, dir)
	_beam.visible = rig.right.get_has_tracking_data()
	_show_beam(origin, ground if pick.is_empty() else pick.point)

	if _buttons.pressed("trigger_click") and ground != null and lifting == null:
		begin_stroke(ground)
	elif _buttons.held("trigger_click") and drawing != null and ground != null:
		extend_stroke(ground)
	elif _buttons.released("trigger_click") and drawing != null:
		end_stroke()

	if _buttons.pressed("grip_click") and not pick.is_empty() and drawing == null:
		begin_lift(pick.wall, origin, pick.point)
	elif _buttons.held("grip_click") and lifting != null:
		drag_lift(origin.y)
	elif _buttons.released("grip_click"):
		lifting = null

	if _buttons.pressed("ax_button") and not pick.is_empty():
		toggle_arch(pick.wall, pick.s)
	if _buttons.pressed("by_button"):
		undo()

	_since_rebuild += delta
	if _dirty and _since_rebuild >= REBUILD_EVERY:
		_flush()
	_buttons.latch()


func _flush() -> void:
	for w in [drawing, lifting]:
		if w != null:
			w.rebuild()
	_dirty = false
	_since_rebuild = 0.0


func begin_stroke(p: Vector3) -> void:
	drawing = Wall.new(_seed)
	_seed += 1
	drawing.layout.points = [p]
	get_parent().add_child(drawing)
	_dirty = true


func extend_stroke(p: Vector3) -> void:
	var pts := drawing.layout.points
	if pts.size() >= 2 and pts[-1].distance_to(pts[-2]) < POINT_SPACING:
		pts[-1] = p
	else:
		pts.append(p)
		built.emit(&"stone", p + Vector3.UP * drawing.layout.height * 0.5)
	_dirty = true


func end_stroke() -> Wall:
	var w := drawing
	drawing = null
	w.layout.build(Terrain.height_at)
	if w.layout.length() < 1.0:
		w.queue_free()
		return null
	if w.layout.length() >= AUTO_ARCH_LENGTH and w.layout.can_arch():
		w.layout.arches = [w.layout.length() * 0.5]
	w.rebuild()
	w.grow_ivy()
	walls.append(w)
	built.emit(&"settle", _top(w, w.layout.length() * 0.5))
	return w


func begin_lift(w: Wall, hand: Vector3, at: Vector3) -> void:
	lifting = w
	_lift_start = w.layout.height
	_lift_hand_y = hand.y
	_lift_gain = maxf(1.0, hand.distance_to(at) / 1.2)
	_lift_at = at


func drag_lift(hand_y: float) -> void:
	var h := clampf(_lift_start + (hand_y - _lift_hand_y) * _lift_gain, 0.9, 9.0)
	h = snappedf(h, WallLayout.COURSE)
	if not is_equal_approx(h, lifting.layout.height):
		lifting.layout.height = h
		_dirty = true
		built.emit(&"stone", Vector3(_lift_at.x, Terrain.height_at(_lift_at.x, _lift_at.z) + h, _lift_at.z))


func toggle_arch(w: Wall, s: float) -> void:
	var arches := w.layout.arches
	for i in arches.size():
		if absf(arches[i] - s) < WallLayout.ARCH_HALF * 2.0:
			arches.remove_at(i)
			w.rebuild()
			built.emit(&"settle", _top(w, s))
			return
	for a in arches:
		if absf(a - s) < (WallLayout.ARCH_HALF + WallLayout.RING) * 2.0 + 0.4:
			return
	arches.append(s)
	w.rebuild()
	built.emit(&"arch", w.layout.point_at(s) + Vector3.UP * w.layout.spring())


func undo() -> void:
	if walls.is_empty():
		return
	var w: Wall = walls.pop_back()
	built.emit(&"crumble", _top(w, w.layout.length() * 0.5))
	w.queue_free()


func _top(w: Wall, s: float) -> Vector3:
	return w.layout.point_at(s) + Vector3.UP * w.layout.height


func pick_wall(origin: Vector3, dir: Vector3) -> Dictionary:
	var best := {}
	var best_d := WALL_PICK
	for w in walls:
		var hit := w.ray_distance(origin, dir)
		if hit.distance < best_d:
			best_d = hit.distance
			best = {"wall": w, "s": hit.s, "point": hit.point}
	return best


func _show_beam(origin: Vector3, hit: Variant) -> void:
	_beam.span(origin, hit if hit != null else origin + (-rig.right.global_transform.basis.z) * 20.0)
	_dot.visible = hit != null and _beam.visible
	if hit != null:
		_dot.global_position = hit
