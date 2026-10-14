class_name WallTool
extends Node3D

## Walls, for whichever hand holds them: trigger draws a wall along the ground (a loop held closed snaps to a
## round tower), grip on a wall pulls its height and on a roof its pitch and curvature, and the right A cuts or
## fills an arch where a walls hand points or, on a wall's top, changes its style. With walls in both hands,
## both grips on the ground lay out a house between them.

const POINT_SPACING := 0.45
const REBUILD_EVERY := 0.06
const AUTO_ARCH_LENGTH := 5.0
const WALL_PICK := 0.7
const TINT := Color(1.0, 0.97, 0.9, 0.55)
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


class Mason:
	var hand: Hand
	var buttons: Buttons
	var drawing: Wall
	var lifting: Wall
	var roofing: Wall
	var lift_start := 0.0
	var curve_start := 0.0
	var lift_hand := Vector3.ZERO
	var lift_gain := 1.0
	var lift_at := Vector3.ZERO
	var lift_side := Vector3.RIGHT
	var loop := {}
	var loop_held := 0.0
	var pick := {}
	var ground: Variant = null


var rig: Rig
var history: History
var walls: Array[Wall] = []
var masons: Array[Mason] = []
var house: Wall
var _since_rebuild := 0.0
var _dirty := false
var _seed := 1
var _arch_button: Buttons


func _init(player: Rig, steps: History) -> void:
	rig = player
	history = steps
	for h in [rig.right, rig.left]:
		var m := Mason.new()
		m.hand = h
		m.buttons = Buttons.new(h).watch(["trigger_click", "grip_click"])
		masons.append(m)
	_arch_button = Buttons.new(rig.right).watch(["ax_button"])


func mason(hand: Hand) -> Mason:
	for m in masons:
		if m.hand == hand:
			return m
	return null


func busy() -> bool:
	if house != null:
		return true
	for m in masons:
		if m.drawing != null or m.lifting != null or m.roofing != null:
			return true
	return false


func _process(delta: float) -> void:
	for m in masons:
		_handle(m, delta)
	_house_input()
	if _arch_button.pressed("ax_button"):
		for m in masons:
			if not m.pick.is_empty():
				var p: Dictionary = m.pick
				if p.point.y - p.wall.layout.point_at(p.s).y > p.wall.layout.height - TOP_BAND:
					cycle_top(p.wall)
				else:
					toggle_arch(p.wall, p.s)
				break
	_since_rebuild += delta
	if _dirty and _since_rebuild >= REBUILD_EVERY:
		_flush()
	for m in masons:
		m.buttons.latch()
	_arch_button.latch()


func _handle(m: Mason, delta: float) -> void:
	m.pick = {}
	m.ground = null
	if m.hand.tool != Hand.Tool.WALLS or rig.aim_hand == m.hand:
		_let_go(m)
		return
	if m.buttons.released("trigger_click") and m.drawing != null:
		end_stroke(m)
	if m.buttons.released("grip_click"):
		if m.lifting != null:
			end_lift(m)
		if m.roofing != null:
			end_roof(m)
	if m.drawing != null and not m.loop.is_empty():
		m.loop_held += delta
		if m.loop_held >= LOOP_HOLD:
			snap_tower(m, m.loop.center, m.loop.radius)
	if not m.hand.get_has_tracking_data():
		return
	var hand := m.hand.global_transform
	var origin := hand.origin
	var dir := -hand.basis.z
	m.ground = Terrain.raycast(origin, dir)
	m.pick = pick_wall(origin, dir)
	var roof := pick_roof(origin, dir)
	var on_roof: bool = not roof.is_empty() and (m.pick.is_empty() or m.pick.distance > 0.2 or roof.along < m.pick.along)
	m.hand.point(roof.point if on_roof else m.ground if m.pick.is_empty() else m.pick.point, TINT)

	if m.buttons.pressed("trigger_click") and m.ground != null and not busy():
		begin_stroke(m, m.ground)
	elif m.buttons.held("trigger_click") and m.drawing != null and m.ground != null:
		extend_stroke(m, m.ground)

	if m.buttons.pressed("grip_click") and not busy() and not _other_grip_held(m):
		if on_roof:
			begin_roof(m, roof.wall, origin)
		elif not m.pick.is_empty():
			begin_lift(m, m.pick.wall, origin, m.pick.point)
	elif m.buttons.held("grip_click") and m.lifting != null:
		drag_lift(m, origin.y)
	elif m.buttons.held("grip_click") and m.roofing != null:
		drag_roof(m, origin)


func _let_go(m: Mason) -> void:
	if m.drawing != null:
		end_stroke(m)
	if m.lifting != null:
		end_lift(m)
	if m.roofing != null:
		end_roof(m)


func _other_grip_held(m: Mason) -> bool:
	for o in masons:
		if o != m and o.hand.tool == Hand.Tool.WALLS and o.buttons.held("grip_click"):
			return true
	return false


func _house_input() -> void:
	var right := masons[0]
	var left := masons[1]
	var both := right.buttons.held("grip_click") and left.buttons.held("grip_click") and right.hand.tool == Hand.Tool.WALLS and left.hand.tool == Hand.Tool.WALLS
	if both and house == null and not busy() and right.ground != null and left.ground != null:
		begin_house(left.ground, right.ground)
	elif both and house != null and right.ground != null and left.ground != null:
		size_house(left.ground, right.ground)
	elif house != null and (right.buttons.released("grip_click") or left.buttons.released("grip_click") or right.hand.tool != Hand.Tool.WALLS or left.hand.tool != Hand.Tool.WALLS):
		end_house()


func _flush() -> void:
	for m in masons:
		for w in [m.drawing, m.lifting]:
			if w != null:
				w.rebuild(false)
		if m.roofing != null:
			m.roofing.rebuild_roof()
	if house != null:
		house.rebuild(false)
	_dirty = false
	_since_rebuild = 0.0


func _new_wall() -> Wall:
	var w := Wall.new(_seed)
	_seed += 1
	get_parent().add_child(w)
	return w


func begin_stroke(m: Mason, p: Vector3) -> void:
	m.drawing = _new_wall()
	m.drawing.layout.points = [p]
	m.loop = {}
	_dirty = true


func extend_stroke(m: Mason, p: Vector3) -> void:
	if m.drawing.layout.closed:
		return
	var pts := m.drawing.layout.points
	if pts.size() >= 2 and pts[-1].distance_to(pts[-2]) < POINT_SPACING:
		pts[-1] = p
	else:
		pts.append(p)
		built.emit(&"stone", p + Vector3.UP * m.drawing.layout.height * 0.5)
	_dirty = true
	m.loop = WallLayout.fit_loop(pts)
	if m.loop.is_empty():
		m.loop_held = 0.0


## The stroke becomes a round tower with a cone roof; the rest of the stroke is ignored.
func snap_tower(m: Mason, center: Vector3, radius: float) -> void:
	var layout := m.drawing.layout
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
	m.drawing.add_roof(roof)
	m.loop = {}
	_dirty = true
	built.emit(&"settle", center + Vector3.UP * TOWER_HEIGHT)


func end_stroke(m: Mason) -> Wall:
	var w := m.drawing
	m.drawing = null
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
	history.add(_take.bind(w), _put.bind(w), [w])


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


func begin_lift(m: Mason, w: Wall, hand: Vector3, at: Vector3) -> void:
	m.lifting = w
	m.lift_start = w.layout.height
	m.lift_hand = hand
	m.lift_gain = Hand.reach_gain(hand.distance_to(at))
	m.lift_at = at


func drag_lift(m: Mason, hand_y: float) -> void:
	var h := clampf(m.lift_start + (hand_y - m.lift_hand.y) * m.lift_gain, 0.9, 9.0)
	h = snappedf(h, WallLayout.COURSE)
	if not is_equal_approx(h, m.lifting.layout.height):
		m.lifting.layout.height = h
		_dirty = true
		built.emit(&"stone", Vector3(m.lift_at.x, Terrain.height_at(m.lift_at.x, m.lift_at.z) + h, m.lift_at.z))


func end_lift(m: Mason) -> void:
	var w := m.lifting
	m.lifting = null
	w.rebuild()
	if not is_equal_approx(w.layout.height, m.lift_start):
		history.add(_set_height.bind(w, m.lift_start), _set_height.bind(w, w.layout.height), [w])


## Grip on a roof: raising the hand raises the ridge, moving it sideways bows or sags the slopes.
func begin_roof(m: Mason, w: Wall, hand: Vector3) -> void:
	m.roofing = w
	m.lift_start = w.roof.pitch
	m.curve_start = w.roof.curve
	m.lift_hand = hand
	m.lift_at = w.roof.frame().mid + Vector3.UP * w.roof.pitch
	m.lift_gain = Hand.reach_gain(hand.distance_to(m.lift_at))
	var side := rig.head.global_basis.x
	side.y = 0.0
	m.lift_side = side.normalized() if side.length() > 0.01 else Vector3.RIGHT


func drag_roof(m: Mason, hand: Vector3) -> void:
	var move := (hand - m.lift_hand) * m.lift_gain
	shape_roof(m.roofing, m.lift_start + move.y, m.curve_start + move.dot(m.lift_side) * 0.8)


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


func end_roof(m: Mason) -> void:
	var w := m.roofing
	m.roofing = null
	w.rebuild_roof()
	if not is_equal_approx(w.roof.pitch, m.lift_start) or not is_equal_approx(w.roof.curve, m.curve_start):
		history.add(_set_roof.bind(w, m.lift_start, m.curve_start), _set_roof.bind(w, w.roof.pitch, w.roof.curve), [w])


func cycle_top(w: Wall) -> void:
	if w.roof != null:
		return
	var before := w.layout.top
	_set_top(w, ((w.layout.top + 1) % WallLayout.Top.size()) as WallLayout.Top)
	history.add(_set_top.bind(w, before), _set_top.bind(w, w.layout.top), [w])


func toggle_arch(w: Wall, s: float) -> void:
	var before := w.layout.arches.duplicate()
	var arches := w.layout.arches
	for i in arches.size():
		if absf(arches[i] - s) < WallLayout.ARCH_HALF * 2.0:
			arches.remove_at(i)
			w.rebuild()
			built.emit(&"settle", _top(w, s))
			_record_arches(w, before)
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
	_record_arches(w, before)


## Takes one wall down, as the delete tool does; undo puts it back.
func remove(w: Wall) -> void:
	_take(w)
	history.add(_put.bind(w), _take.bind(w), [w])


func _take(w: Wall) -> void:
	built.emit(&"crumble", _top(w, w.layout.length() * 0.5))
	walls.erase(w)
	w.get_parent().remove_child(w)


## The ground may have moved while the wall was away.
func _put(w: Wall) -> void:
	get_parent().add_child(w)
	w.rebuild()
	walls.append(w)
	built.emit(&"settle", _top(w, w.layout.length() * 0.5))


func _set_height(w: Wall, h: float) -> void:
	w.layout.height = h
	w.rebuild()
	built.emit(&"settle", _top(w, w.layout.length() * 0.5))


func _set_roof(w: Wall, pitch: float, curve: float) -> void:
	w.roof.pitch = pitch
	w.roof.curve = curve
	w.rebuild_roof()
	built.emit(&"stone", w.roof.frame().mid + Vector3.UP * pitch)


func _set_top(w: Wall, top: WallLayout.Top) -> void:
	w.layout.top = top
	w.rebuild()
	built.emit(&"settle", _top(w, w.layout.length() * 0.5))


func _record_arches(w: Wall, before: Array[float]) -> void:
	history.add(_set_arches.bind(w, before), _set_arches.bind(w, w.layout.arches.duplicate()), [w])


func _set_arches(w: Wall, arches: Array[float]) -> void:
	w.layout.arches = arches.duplicate()
	w.rebuild()
	built.emit(&"arch", _top(w, w.layout.length() * 0.5))


func _held(w: Wall) -> bool:
	for m in masons:
		if m.lifting == w or m.roofing == w:
			return true
	return false


## Lays again every wall standing on ground that moved; ivy waits for `settled`.
func reground(area: Rect2, settled: bool) -> void:
	for w in walls:
		if w.footprint().intersects(area):
			w.rebuild(settled)


func _top(w: Wall, s: float) -> Vector3:
	return w.layout.point_at(s) + Vector3.UP * w.layout.height


func pick_wall(origin: Vector3, dir: Vector3) -> Dictionary:
	var best := {}
	var best_d := WALL_PICK
	for w in walls:
		if _held(w):
			continue
		var hit := w.ray_distance(origin, dir)
		if hit.distance < best_d:
			best_d = hit.distance
			best = {"wall": w, "s": hit.s, "point": hit.point, "along": hit.along, "distance": hit.distance}
	return best


func pick_roof(origin: Vector3, dir: Vector3) -> Dictionary:
	var best := {}
	for w in walls:
		if w.roof == null or _held(w):
			continue
		var t := w.roof.ray_hit(origin, dir)
		if t < best.get("along", INF):
			best = {"wall": w, "along": t, "point": origin + dir * t}
	return best
