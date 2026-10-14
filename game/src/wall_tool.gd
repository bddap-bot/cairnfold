class_name WallTool
extends Node3D

## Right hand: trigger draws a wall along the ground (a loop held closed snaps to a round tower), grip on a
## wall pulls its height and on a roof its pitch and curvature, A cuts or fills an arch or, on a wall's top,
## changes its style. Both grips on the ground lay out a house between the hands. Holding the left hand's
## lower button undoes the last wall.

const POINT_SPACING := 0.45
const REBUILD_EVERY := 0.06
const AUTO_ARCH_LENGTH := 5.0
const WALL_PICK := 0.7
## Seconds a stroke must stay closed into a loop before it snaps to a tower.
const LOOP_HOLD := 0.4
const TOWER_HEIGHT := 4.5
const HOUSE_HEIGHT := 2.4
const HOUSE_LENGTH := Vector2(3.2, 14.0)
const HOUSE_DEPTH := Vector2(2.4, 7.0)
const TOP_BAND := 0.4
const ROOF_STEP := 0.1

## A stone event for the soundscape, at the stones it moved.
signal built(kind: StringName, at: Vector3)

var rig: Rig
var walls: Array[Wall] = []
var drawing: Wall
var lifting: Wall
var roofing: Wall
var house: Wall
var _lift_start := 0.0
var _lift_hand := Vector3.ZERO
var _lift_gain := 1.0
var _lift_at := Vector3.ZERO
var _lift_side := Vector3.RIGHT
var _curve_start := 0.0
var _loop := {}
var _loop_held := 0.0
var _since_rebuild := 0.0
var _dirty := false
var _seed := 1
var _buttons: Buttons
var _left: Buttons

var _beam: Beam
var _dot: MeshInstance3D


func _init(player: Rig) -> void:
	rig = player
	_buttons = Buttons.new(rig.right).watch(["trigger_click", "grip_click", "ax_button"])
	_left = Buttons.new(rig.left).watch(["ax_button", "grip_click"])
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


func busy() -> bool:
	return drawing != null or lifting != null or roofing != null or house != null


func _process(delta: float) -> void:
	var hand := rig.right.global_transform
	var origin := hand.origin
	var dir := -hand.basis.z
	var ground: Variant = Terrain.raycast(origin, dir)
	var pick := pick_wall(origin, dir)
	var roof := pick_roof(origin, dir)
	var on_roof: bool = not roof.is_empty() and (pick.is_empty() or pick.distance > 0.2 or roof.along < pick.along)
	_beam.visible = rig.right.get_has_tracking_data()
	_show_beam(origin, roof.point if on_roof else ground if pick.is_empty() else pick.point)

	if _buttons.pressed("trigger_click") and ground != null and not busy():
		begin_stroke(ground)
	elif _buttons.held("trigger_click") and drawing != null and ground != null:
		extend_stroke(ground)
	elif _buttons.released("trigger_click") and drawing != null:
		end_stroke()

	if _buttons.pressed("grip_click") and not busy() and not _left.held("grip_click"):
		if on_roof:
			begin_roof(roof.wall, origin)
		elif not pick.is_empty():
			begin_lift(pick.wall, origin, pick.point)
	elif _buttons.held("grip_click") and lifting != null:
		drag_lift(origin.y)
	elif _buttons.held("grip_click") and roofing != null:
		drag_roof(origin)
	elif _buttons.released("grip_click") and lifting != null:
		end_lift()
	elif _buttons.released("grip_click") and roofing != null:
		end_roof()

	var left := rig.left.global_transform
	var left_ground: Variant = Terrain.raycast(left.origin, -left.basis.z)
	var both := _buttons.held("grip_click") and _left.held("grip_click")
	if both and house == null and not busy() and ground != null and left_ground != null:
		begin_house(left_ground, ground)
	elif both and house != null and ground != null and left_ground != null:
		size_house(left_ground, ground)
	elif house != null and (_buttons.released("grip_click") or _left.released("grip_click")):
		end_house()

	if _buttons.pressed("ax_button") and not pick.is_empty():
		if pick.point.y - pick.wall.layout.point_at(pick.s).y > pick.wall.layout.height - TOP_BAND:
			cycle_top(pick.wall)
		else:
			toggle_arch(pick.wall, pick.s)
	if _left.held_long("ax_button"):
		undo()

	if drawing != null and not _loop.is_empty():
		_loop_held += delta
		if _loop_held >= LOOP_HOLD:
			snap_tower(_loop.center, _loop.radius)
	_since_rebuild += delta
	if _dirty and _since_rebuild >= REBUILD_EVERY:
		_flush()
	_buttons.latch()
	_left.latch()


func _flush() -> void:
	for w in [drawing, house, lifting]:
		if w != null:
			w.rebuild(false)
	if roofing != null:
		roofing.rebuild_roof()
	_dirty = false
	_since_rebuild = 0.0


func _new_wall() -> Wall:
	var w := Wall.new(_seed)
	_seed += 1
	get_parent().add_child(w)
	return w


func begin_stroke(p: Vector3) -> void:
	drawing = _new_wall()
	drawing.layout.points = [p]
	_loop = {}
	_dirty = true


func extend_stroke(p: Vector3) -> void:
	if drawing.layout.closed:
		return
	var pts := drawing.layout.points
	if pts.size() >= 2 and pts[-1].distance_to(pts[-2]) < POINT_SPACING:
		pts[-1] = p
	else:
		pts.append(p)
		built.emit(&"stone", p + Vector3.UP * drawing.layout.height * 0.5)
	_dirty = true
	_loop = WallLayout.fit_loop(pts)
	if _loop.is_empty():
		_loop_held = 0.0


## The stroke becomes a round tower with a cone roof; the rest of the stroke is ignored.
func snap_tower(center: Vector3, radius: float) -> void:
	var layout := drawing.layout
	layout.points = WallLayout.circle(center, radius)
	layout.closed = true
	layout.top = WallLayout.Top.CAP
	layout.height = TOWER_HEIGHT
	var roof := RoofLayout.new()
	roof.kind = RoofLayout.Kind.CONE
	roof.center = center
	roof.radius = radius
	roof.pitch = clampf(radius * 1.6, RoofLayout.PITCH.x, RoofLayout.PITCH.y)
	roof.seed = layout.seed
	drawing.add_roof(roof)
	_loop = {}
	_dirty = true
	built.emit(&"settle", center + Vector3.UP * TOWER_HEIGHT)


func end_stroke() -> Wall:
	var w := drawing
	drawing = null
	w.layout.build(Terrain.height_at)
	if w.layout.length() < 1.0:
		w.queue_free()
		return null
	if not w.layout.closed and w.layout.length() >= AUTO_ARCH_LENGTH and w.layout.can_arch():
		w.layout.arches = [w.layout.length() * 0.5]
	_finish(w)
	return w


func _finish(w: Wall) -> void:
	w.finished = true
	w.rebuild()
	walls.append(w)
	built.emit(&"settle", _top(w, w.layout.length() * 0.5))


## A house between two pointed ground spots: they mark the ends of its ridge; its depth follows its length.
func begin_house(a: Vector3, b: Vector3) -> void:
	house = _new_wall()
	house.layout.closed = true
	house.layout.top = WallLayout.Top.CAP
	house.layout.height = HOUSE_HEIGHT
	var roof := RoofLayout.new()
	roof.seed = house.layout.seed
	house.add_roof(roof)
	size_house(a, b)


func size_house(a: Vector3, b: Vector3) -> void:
	var span := Vector2(b.x - a.x, b.z - a.z)
	if span.length() < 0.01:
		span = Vector2.RIGHT
	var length := clampf(span.length(), HOUSE_LENGTH.x, HOUSE_LENGTH.y)
	var mid := (a + b) * 0.5
	var half := Vector3(span.x, 0.0, span.y).normalized() * length * 0.5
	var depth := clampf(length * 0.62, HOUSE_DEPTH.x, HOUSE_DEPTH.y)
	var corners := WallLayout.rectangle(mid - half, mid + half, depth)
	var front := (corners[0] + corners[1]) * 0.5
	var back := (corners[2] + corners[3]) * 0.5
	house.layout.points = corners
	# The door goes in the downhill long wall: the house stands level on its lowest ground, so an uphill door would be buried.
	house.layout.arches = [length * 0.5 if Terrain.height_at(front.x, front.z) <= Terrain.height_at(back.x, back.z) else length * 1.5 + depth]
	house.roof.pitch = depth * 0.42
	_dirty = true


func end_house() -> Wall:
	var w := house
	house = null
	_finish(w)
	return w


func begin_lift(w: Wall, hand: Vector3, at: Vector3) -> void:
	lifting = w
	_lift_start = w.layout.height
	_lift_hand = hand
	_lift_gain = maxf(1.0, hand.distance_to(at) / 1.2)
	_lift_at = at


func drag_lift(hand_y: float) -> void:
	var h := clampf(_lift_start + (hand_y - _lift_hand.y) * _lift_gain, 0.9, 9.0)
	h = snappedf(h, WallLayout.COURSE)
	if not is_equal_approx(h, lifting.layout.height):
		lifting.layout.height = h
		_dirty = true
		built.emit(&"stone", Vector3(_lift_at.x, Terrain.height_at(_lift_at.x, _lift_at.z) + h, _lift_at.z))


func end_lift() -> void:
	lifting.rebuild()
	lifting = null


## Grip on a roof: raising the hand raises the ridge, moving it sideways bows or sags the slopes.
func begin_roof(w: Wall, hand: Vector3) -> void:
	roofing = w
	_lift_start = w.roof.pitch
	_curve_start = w.roof.curve
	_lift_hand = hand
	_lift_at = w.roof.frame().mid + Vector3.UP * w.roof.pitch
	_lift_gain = maxf(1.0, hand.distance_to(_lift_at) / 1.2)
	var side := rig.head.global_basis.x
	side.y = 0.0
	_lift_side = side.normalized() if side.length() > 0.01 else Vector3.RIGHT


func drag_roof(hand: Vector3) -> void:
	var move := (hand - _lift_hand) * _lift_gain
	shape_roof(roofing, _lift_start + move.y, _curve_start + move.dot(_lift_side) * 0.8)


func shape_roof(w: Wall, pitch: float, curve: float) -> void:
	var r := w.roof
	pitch = snappedf(clampf(pitch, RoofLayout.PITCH.x, RoofLayout.PITCH.y), ROOF_STEP)
	curve = snappedf(clampf(curve, -RoofLayout.CURVE, RoofLayout.CURVE), ROOF_STEP)
	if is_equal_approx(pitch, r.pitch) and is_equal_approx(curve, r.curve):
		return
	r.pitch = pitch
	r.curve = curve
	_dirty = true
	built.emit(&"stone", r.frame().mid + Vector3.UP * pitch)


func end_roof() -> void:
	roofing.rebuild_roof()
	roofing = null


func cycle_top(w: Wall) -> void:
	if w.roof != null:
		return
	w.layout.top = ((w.layout.top + 1) % WallLayout.Top.size()) as WallLayout.Top
	w.rebuild()
	built.emit(&"settle", _top(w, w.layout.length() * 0.5))


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
	if not w.layout.live_arches.has(s):
		arches.pop_back()
		return
	built.emit(&"arch", w.layout.point_at(s) + Vector3.UP * w.layout.spring())


func undo() -> void:
	if walls.is_empty() or busy():
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
			best = {"wall": w, "s": hit.s, "point": hit.point, "along": hit.along, "distance": hit.distance}
	return best


func pick_roof(origin: Vector3, dir: Vector3) -> Dictionary:
	var best := {}
	for w in walls:
		if w.roof == null:
			continue
		var t := w.roof.ray_hit(origin, dir)
		if t < best.get("along", INF):
			best = {"wall": w, "along": t, "point": origin + dir * t}
	return best


func _show_beam(origin: Vector3, hit: Variant) -> void:
	_beam.span(origin, hit if hit != null else origin + (-rig.right.global_transform.basis.z) * 20.0)
	_dot.visible = hit != null and _beam.visible
	if hit != null:
		_dot.global_position = hit
