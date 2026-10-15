class_name WallTool
extends Node3D

## Walls, for whichever hand holds them: trigger draws a wall along the ground (a loop held closed snaps to a
## round tower), grip on a wall pulls its height and on a roof its pitch and curvature, and the right A cuts or
## fills an arch where a walls hand points or, on a wall's top, changes its style. A hand holding the house takes
## hold of one with its trigger or grip, where it points, and carries it; the other hand's grip joins in to turn it
## with the pair and stretch it along their span; letting go builds it. A path across a wall opens an arch where they cross,
## or an arcade where the crossing is wide: those arches follow from the paths standing, so they come and go
## with the path. A hand holding the fence draws fences the same way: posts and rails, a wooden arch where a
## path crosses. Every finished edit goes to the garden as a build command; this tool shows it until then.

const POINT_SPACING := 0.45
const REBUILD_EVERY := 0.06
const WALL_PICK := 0.7
const TINT := Color(1.0, 0.97, 0.9, 0.55)
## Seconds a stroke must stay closed into a loop before it snaps to a tower.
const LOOP_HOLD := 0.4
const TOWER_HEIGHT := 4.5
const HOUSE_HEIGHT := 2.4
## Bounds of a house's sides; the shorter side, under the ridge, stops at HOUSE_DEPTH.
const HOUSE_SIDES := Vector2(2.4, 14.0)
const HOUSE_DEPTH := 7.0
const HOUSE_SIZE := Vector2(4.5, 4.5)
const HOUSE_REACH := 6.0
const TOP_BAND := 0.4
const ROOF_STEP := 0.1

## A stone event for the soundscape, at the stones it moved.
signal built(kind: StringName, at: Vector3)


class Mason:
	var hand: Hand
	var buttons: Buttons
	var stroke: Stroke
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


## A stroke being drawn and the walls it builds, shown as it grows and kept on release.
class Stroke:
	var points: Array[Vector3] = []
	## Null once the stroke has snapped to a tower.
	var plan: WallPlan
	var walls: Array[Wall] = []
	var planned := false


var rig: Rig
var world: World
var flora: Flora
var paths: Paths
var masonry := Masonry.new(Wall.kinds())
var walls: Array[Wall] = []
var masons: Array[Mason] = []
## The house the hands are carrying, where it stands, and the hands holding it.
var house: Wall
var house_at := {}
var _holders: Array[Mason] = []
var _hold_start := {}
var _hold_from: Array[Transform3D] = []
var _hold_gain := 1.0
## Where the house stood for each footprint sent to be laid, so whichever is laid is carried to where it stands now.
var _laid_at: Array[Dictionary] = []
var _house_dirty := false
## True while the garden is swapped wholesale: walls come and go without a sound.
var quiet := false
var _since_rebuild := 0.0
var _dirty := false
var _arch_button: Buttons


func _init(player: Rig, garden: World, plants: Flora, ways: Paths) -> void:
	rig = player
	world = garden
	flora = plants
	paths = ways
	add_child(masonry)
	paths.laid.connect(relay_crossings)
	paths.taken.connect(relay_crossings)
	world.restored.connect(_forget)
	for h in [rig.right, rig.left]:
		var m := Mason.new()
		m.hand = h
		m.buttons = Buttons.new(h).watch(["trigger_click", "grip_click"])
		masons.append(m)
	_arch_button = Buttons.new(rig.right).watch(["ax_button"])


static func draws(hand: Hand) -> bool:
	return hand.tool == Hand.Tool.WALLS or hand.tool == Hand.Tool.FENCE


func mason(hand: Hand) -> Mason:
	for m in masons:
		if m.hand == hand:
			return m
	return null


func busy() -> bool:
	if house != null:
		return true
	for m in masons:
		if m.stroke != null or m.lifting != null or m.roofing != null:
			return true
	return false


func _process(delta: float) -> void:
	for m in masons:
		_handle(m, delta)
	_house_input()
	if house != null:
		_carry_laid()
	for m in _holders:
		m.hand.hold()
	if _arch_button.pressed("ax_button"):
		for m in masons:
			if not m.pick.is_empty() and m.hand.tool == Hand.Tool.WALLS and not m.pick.wall.layout.fence:
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
		if m.lifting != null or m.roofing != null:
			m.hand.hold()
		m.buttons.latch()
	_arch_button.latch()


func _handle(m: Mason, delta: float) -> void:
	m.pick = {}
	m.ground = null
	if not draws(m.hand) or rig.aim_hand == m.hand:
		_let_go(m)
		return
	if m.buttons.released("trigger_click") and m.stroke != null:
		end_stroke(m)
	if m.buttons.released("grip_click"):
		if m.lifting != null:
			end_lift(m)
		if m.roofing != null:
			end_roof(m)
	if m.stroke != null and not m.loop.is_empty():
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
	elif m.buttons.held("trigger_click") and m.stroke != null and m.ground != null:
		extend_stroke(m, m.ground)

	if m.hand.tool == Hand.Tool.FENCE:
		return
	if m.buttons.pressed("grip_click") and not busy():
		if on_roof:
			begin_roof(m, roof.wall, origin)
		elif not m.pick.is_empty() and not m.pick.wall.layout.fence:
			begin_lift(m, m.pick.wall, origin, m.pick.point)
	elif m.buttons.held("grip_click") and m.lifting != null:
		drag_lift(m, origin.y)
	elif m.buttons.held("grip_click") and m.roofing != null:
		drag_roof(m, origin)


func _let_go(m: Mason) -> void:
	if m.stroke != null:
		end_stroke(m)
	if m.lifting != null:
		end_lift(m)
	if m.roofing != null:
		end_roof(m)


func _flush() -> void:
	for m in masons:
		if m.stroke != null:
			_plan(m.stroke)
			for w in m.stroke.walls:
				w.rebuild(false)
		if m.lifting != null:
			m.lifting.rebuild(false)
		if m.roofing != null:
			m.roofing.rebuild_roof(true)
	if house != null and _house_dirty:
		house.rebuild(false)
		_house_dirty = false
	_dirty = false
	_since_rebuild = 0.0


func _new_wall() -> Wall:
	return _add_wall(Wall.new(randi(), masonry))


func _add_wall(w: Wall) -> Wall:
	get_parent().add_child(w)
	return w


func begin_stroke(m: Mason, p: Vector3) -> void:
	var standing: Array[WallLayout] = []
	for w in walls:
		standing.append(w.layout)
	m.stroke = Stroke.new()
	m.stroke.points = [p]
	m.stroke.plan = WallPlan.new(standing, flora.obstacles(), randi())
	m.stroke.plan.fence = m.hand.tool == Hand.Tool.FENCE
	m.loop = {}
	m.loop_held = 0.0
	_dirty = true


func extend_stroke(m: Mason, p: Vector3) -> void:
	var pts := m.stroke.points
	if m.stroke.plan == null or pts[-1].is_equal_approx(p) or Commands.length(pts) >= Commands.STROKE_LENGTH:
		return
	if pts.size() >= 2 and pts[-1].distance_to(pts[-2]) < POINT_SPACING:
		pts[-1] = p
	else:
		pts.append(p)
		built.emit(&"stone", p + Vector3.UP)
	m.stroke.planned = false
	_dirty = true
	m.loop = {} if m.stroke.plan.fence else WallLayout.fit_loop(pts)
	if m.loop.is_empty():
		m.loop_held = 0.0


func _plan(st: Stroke) -> void:
	if st.planned or st.plan == null:
		return
	st.planned = true
	var layouts := st.plan.pieces(st.points, Terrain.height_at)
	while st.walls.size() > layouts.size():
		st.walls.pop_back().queue_free()
	for i in layouts.size():
		if i == st.walls.size():
			st.walls.append(_add_wall(Wall.new(layouts[i].seed, masonry)))
		st.walls[i].layout = layouts[i]


## The stroke becomes a round tower with a cone roof; the rest of the stroke is ignored.
func snap_tower(m: Mason, center: Vector3, radius: float) -> void:
	for w in m.stroke.walls:
		w.queue_free()
	m.stroke.walls = [_new_wall()]
	m.stroke.plan = null
	var layout := m.stroke.walls[0].layout
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
	m.stroke.walls[0].add_roof(roof)
	m.loop = {}
	_dirty = true
	built.emit(&"settle", center + Vector3.UP * TOWER_HEIGHT)


func end_stroke(m: Mason) -> void:
	_plan(m.stroke)
	var built_walls := m.stroke.walls
	m.stroke = null
	if not built_walls.is_empty():
		_finish(built_walls)


## Sends a stroke's walls to the garden as one step; they stand as drawn until the command comes back.
func _finish(ws: Array[Wall]) -> void:
	world.submit({"op": "wall", "walls": ws.map(func(w: Wall) -> Dictionary: return w.data())}, func() -> void:
		for w in ws:
			w.queue_free())


## The garden is being swapped: walls in hand belong to the old one.
func _forget() -> void:
	for m in masons:
		if m.stroke != null:
			for w in m.stroke.walls:
				w.queue_free()
		m.stroke = null
		m.lifting = null
		m.roofing = null
	if house != null:
		house.queue_free()
		house = null
		_holders.clear()


## Who holds the house: a hand holding the house tool by its trigger or grip takes it up, and once it is up the other
## hand's grip holds it too. Each change of hands starts the carry afresh from where the house stands.
func _house_input() -> void:
	var holders: Array[Mason] = []
	var starting := false
	for m in masons:
		if m.hand.tool != Hand.Tool.HOUSE or rig.aim_hand == m.hand or not m.hand.get_has_tracking_data():
			continue
		if m.buttons.held("trigger_click") or m.buttons.held("grip_click"):
			holders.append(m)
			starting = starting or m.buttons.pressed("trigger_click") or m.buttons.pressed("grip_click")
		elif house == null:
			m.hand.point(Terrain.raycast(m.hand.global_position, -m.hand.global_basis.z), TINT)
	if house == null and (not starting or busy()):
		return
	if not holders.is_empty() or house != null:
		for m in masons:
			if not m in holders and m.buttons.held("grip_click") and m.hand.get_has_tracking_data() and m.stroke == null and m.lifting == null and m.roofing == null:
				holders.append(m)
	if house == null:
		var lead := holders[0].hand
		var at: Variant = Terrain.raycast(lead.global_position, -lead.global_basis.z)
		if at == null:
			var ahead := -rig.head.global_basis.z
			ahead.y = 0.0
			at = Terrain.ground(rig.head.global_position.x + ahead.normalized().x * HOUSE_REACH, rig.head.global_position.z + ahead.normalized().z * HOUSE_REACH)
		begin_house(at, angle(rig.head.global_basis.x))
	if holders.is_empty():
		if not _holders.is_empty():
			end_house()
		return
	var now: Array[Transform3D] = []
	for m in holders:
		now.append(m.hand.global_transform)
	if holders != _holders:
		_holders = holders
		_hold_start = house_at.duplicate()
		_hold_from = now
		var mid := Vector3.ZERO
		for t in now:
			mid += t.origin / now.size()
		_hold_gain = Hand.reach_gain(mid.distance_to(house_at.center))
	var to := carry(_hold_start, _hold_from, now, _hold_gain)
	if not to.center.is_equal_approx(house_at.center) or not is_equal_approx(to.yaw, house_at.yaw) or not to.size.is_equal_approx(house_at.size):
		place_house(to.center, to.yaw, to.size)


## A square house standing at `at`, its front square to `yaw`, until it is placed and let go.
func begin_house(at: Vector3, yaw: float) -> void:
	house = _new_wall()
	house.layout.closed = true
	house.layout.top = WallLayout.Top.CAP
	house.layout.height = HOUSE_HEIGHT
	var roof := RoofLayout.new()
	roof.seed = house.layout.seed
	house.add_roof(roof)
	_holders.clear()
	_laid_at.clear()
	house_at = {}
	place_house(at, yaw, HOUSE_SIZE)


## Moving or turning the house carries the stones laid as they are, walls, roof and all; only a new size lays them again.
func place_house(at: Vector3, yaw: float, size: Vector2) -> void:
	var resized: bool = house_at.is_empty() or not size.is_equal_approx(house_at.size)
	house_at = {"center": Terrain.ground(at.x, at.z), "yaw": yaw, "size": size}
	if resized:
		_lay_house()


func _lay_house() -> void:
	var span := footprint(house_at.center, house_at.yaw, house_at.size)
	var corners := WallLayout.rectangle(span.a, span.b, span.depth)
	var front := (corners[0] + corners[1]) * 0.5
	var back := (corners[2] + corners[3]) * 0.5
	house.layout.points = corners
	# The door goes in the downhill long wall: the house stands level on its lowest ground, so an uphill door would be buried.
	house.layout.arches = [span.length * 0.5 if Terrain.height_at(front.x, front.z) <= Terrain.height_at(back.x, back.z) else span.length * 1.5 + span.depth]
	house.roof.pitch = span.depth * 0.42
	_laid_at.append({"points": corners, "center": house_at.center, "yaw": house_at.yaw})
	_house_dirty = true
	_dirty = true


func _carry_laid() -> void:
	var laid := house.layout.laid_points
	var i := _laid_at.find_custom(func(e: Dictionary) -> bool: return e.points == laid)
	if i < 0:
		return
	_laid_at = _laid_at.slice(i)
	var was: Dictionary = _laid_at[0]
	var lift := _lowest(footprint(house_at.center, house_at.yaw, house_at.size)) - _lowest(footprint(was.center, was.yaw, house_at.size))
	var from := Transform3D(Basis(Vector3.UP, was.yaw), Vector3(was.center.x, 0.0, was.center.z))
	var to := Transform3D(Basis(Vector3.UP, house_at.yaw), Vector3(house_at.center.x, lift, house_at.center.z))
	house.transform = to * from.affine_inverse()


static func _lowest(span: Dictionary) -> float:
	var low := INF
	for c in WallLayout.rectangle(span.a, span.b, span.depth):
		low = minf(low, Terrain.height_at(c.x, c.z))
	return low


func end_house() -> void:
	if house_at.center != _laid_at[-1].center or house_at.yaw != _laid_at[-1].yaw:
		_lay_house()
	var w := house
	house = null
	_holders.clear()
	_finish([w])


## The ridge's ends `a` and `b`, its `length` and the house's `depth`: `size` is the footprint along `yaw` and
## across it, and the ridge runs the longer way.
static func footprint(center: Vector3, yaw: float, size: Vector2) -> Dictionary:
	var along := Vector3.RIGHT.rotated(Vector3.UP, yaw)
	var ridge := along if size.x >= size.y else along.cross(Vector3.UP)
	var length := maxf(size.x, size.y)
	return {"a": center - ridge * length * 0.5, "b": center + ridge * length * 0.5, "length": length, "depth": minf(size.x, size.y)}


## Where a house held from `start` stands once the hands holding it move from poses `from` to `to`: one hand carries
## it and turns it with its own turn; two carry it by their midpoint, turn it with the line between them, and
## stretch it along that line by how far they spread. `gain` scales the carry, so a far house keeps up.
static func carry(start: Dictionary, from: Array[Transform3D], to: Array[Transform3D], gain: float) -> Dictionary:
	var out := start.duplicate()
	if from.size() == 1:
		out.center = start.center + _flat(to[0].origin - from[0].origin) * gain
		out.yaw = start.yaw + angle_difference(angle(from[0].basis.x), angle(to[0].basis.x))
		return out
	var span0 := _flat(from[1].origin - from[0].origin)
	var span1 := _flat(to[1].origin - to[0].origin)
	out.center = start.center + _flat((to[0].origin + to[1].origin - from[0].origin - from[1].origin) * 0.5) * gain
	out.yaw = start.yaw + angle_difference(angle(span0), angle(span1))
	var stretch := span1.length() / maxf(span0.length(), 0.05) - 1.0
	var across: float = angle(span0) - start.yaw
	var size: Vector2 = start.size * Vector2(1.0 + stretch * cos(across) ** 2, 1.0 + stretch * sin(across) ** 2)
	size = size.clamp(Vector2.ONE * HOUSE_SIDES.x, Vector2.ONE * HOUSE_SIDES.y)
	if size.x < size.y:
		size.x = minf(size.x, HOUSE_DEPTH)
	else:
		size.y = minf(size.y, HOUSE_DEPTH)
	out.size = size
	return out


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## The turn about the vertical that takes the x axis to `v`'s direction on the ground.
static func angle(v: Vector3) -> float:
	return atan2(-v.z, v.x)


func begin_lift(m: Mason, w: Wall, hand: Vector3, at: Vector3) -> void:
	m.lifting = w
	m.lift_start = w.layout.height
	m.lift_hand = hand
	m.lift_gain = Hand.reach_gain(hand.distance_to(at))
	m.lift_at = at


func drag_lift(m: Mason, hand_y: float) -> void:
	var h := clampf(m.lift_start + (hand_y - m.lift_hand.y) * m.lift_gain, WallLayout.HEIGHTS.x, WallLayout.HEIGHTS.y)
	h = snappedf(h, WallLayout.COURSE)
	if not is_equal_approx(h, m.lifting.layout.height):
		m.lifting.layout.height = h
		_dirty = true
		built.emit(&"stone", Vector3(m.lift_at.x, Terrain.height_at(m.lift_at.x, m.lift_at.z) + h, m.lift_at.z))


func end_lift(m: Mason) -> void:
	var w := m.lifting
	m.lifting = null
	if is_equal_approx(w.layout.height, m.lift_start):
		_relay(w)
	else:
		world.submit({"op": "reshape", "id": w.id, "data": {"height": w.layout.height}}, settle.bind(w.id))


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
	pitch = RoofLayout.snap_pitch(pitch, ROOF_STEP)
	curve = snappedf(clampf(curve, -RoofLayout.CURVE, RoofLayout.CURVE), ROOF_STEP)
	if is_equal_approx(pitch, r.pitch) and is_equal_approx(curve, r.curve):
		return
	r.pitch = pitch
	r.curve = curve
	_dirty = true
	built.emit(&"settle" if r.flat() else &"stone", r.frame().mid + Vector3.UP * pitch)


func end_roof(m: Mason) -> void:
	var w := m.roofing
	m.roofing = null
	if is_equal_approx(w.roof.pitch, m.lift_start) and is_equal_approx(w.roof.curve, m.curve_start):
		_relay(w)
	else:
		world.submit({"op": "reshape", "id": w.id, "data": {"roof": {"pitch": w.roof.pitch, "curve": w.roof.curve}}}, settle.bind(w.id))


func cycle_top(w: Wall) -> void:
	if w.roof == null or w.roof.flat():
		world.submit({"op": "reshape", "id": w.id, "data": {"top": (w.layout.top + 1) % WallLayout.Top.size()}})


## Fills the wall's own arch nearest `s`, or cuts one there if it fits among the arches standing.
func toggle_arch(w: Wall, s: float) -> void:
	var own := Array(world.state.walls[w.id].arches)
	for i in own.size():
		if absf(w.layout.offset(own[i], s)) < WallLayout.ARCH_HALF * 2.0:
			own.remove_at(i)
			_set_arches(w, own)
			return
	for a in w.layout.live_arches:
		if absf(w.layout.offset(a, s)) < WallLayout.ARCADE_GAP:
			return
	if w.layout.can_arch() and w.layout.fits_arch(s, w.layout.live_arches):
		own.append(s)
		_set_arches(w, own)


## A pulled height, roof or erased stretch shows as pulled until its command comes back, or goes back if it is
## turned down.
func settle(id: int) -> void:
	var w := find(id)
	if w != null and not _held(w):
		_relay(w)


func _set_arches(w: Wall, arches: Array) -> void:
	world.submit({"op": "reshape", "id": w.id, "data": {"arches": PackedFloat32Array(arches)}})


## Lays a wall as the garden has it, with the arches the paths standing open in it.
func _relay(w: Wall) -> void:
	w.set_data(world.state.walls[w.id])
	w.layout.resample(Terrain.height_at)
	for p in paths.layouts:
		_cut_crossings(w, p)
	w.rebuild()


## Wall chemistry: a path laid or lifted opens or closes arches in every wall it crosses.
func relay_crossings(path: PathLayout) -> void:
	for w in walls:
		if not path.crossings(w.layout).is_empty() and not _held(w):
			_relay(w)
			_sound(&"arch", _top(w, w.layout.length() * 0.5))


## Adds the arches `path` makes in `w` and returns them. A crossing already inside an opening needs none; one whose ring
## would overlap an arch there stands a pitch from it as an arcade instead, on the crossing's side if that
## fits, else the other, so no opening closes.
func _cut_crossings(w: Wall, path: PathLayout) -> Array[float]:
	var opened: Array[float] = []
	var layout := w.layout
	if not layout.can_arch():
		return opened
	var arches := layout.arches.duplicate()
	for a in path.crossings(layout):
		a = layout.wrap(a)
		var past := INF
		for e in arches:
			if absf(layout.offset(a, e)) < absf(past):
				past = layout.offset(a, e)
		if absf(past) < WallLayout.ARCH_HALF:
			continue
		var tries := [a]
		if absf(past) < WallLayout.ARCH_SPACING:
			var side := signf(past) * WallLayout.ARCADE_PITCH
			tries = [layout.wrap(a - past + side), layout.wrap(a - past - side)]
		for t in tries:
			if layout.fits_arch(t, arches):
				arches.append(t)
				layout.arches.append(t)
				opened.append(t)
				break
	return opened


func _sound(kind: StringName, at: Vector3) -> void:
	if not quiet:
		built.emit(kind, at)


## The garden's side of a wall going up, from any player.
func put(id: int) -> void:
	var w := _new_wall()
	w.id = id
	w.finished = true
	walls.append(w)
	_relay(w)
	_sound(&"settle", _top(w, w.layout.length() * 0.5))


func take(id: int) -> void:
	var w := find(id)
	for m in masons:
		if m.lifting == w:
			m.lifting = null
		if m.roofing == w:
			m.roofing = null
	_sound(&"crumble", _top(w, w.layout.length() * 0.5))
	walls.erase(w)
	w.queue_free()


## A wall someone here is pulling keeps following their hand; it catches up when they let go.
func restyle(id: int, changed: Array) -> void:
	var w := find(id)
	if _held(w):
		return
	_relay(w)
	if "ruins" in changed:
		_sound(&"crumble", _top(w, w.layout.length() * 0.5))
	elif "arches" in changed:
		_sound(&"arch", _top(w, w.layout.length() * 0.5))
	elif "roof" in changed:
		_sound(&"stone", w.roof.frame().mid + Vector3.UP * w.roof.pitch)
	else:
		_sound(&"settle", _top(w, w.layout.length() * 0.5))


func find(id: int) -> Wall:
	for w in walls:
		if w.id == id:
			return w
	return null


func _held(w: Wall) -> bool:
	for m in masons:
		if m.lifting == w or m.roofing == w:
			return true
	return false


## Lays again every wall standing on ground that moved; ivy waits for `settled`.
func reground(area: Rect2, settled: bool) -> void:
	for w in walls:
		if w.footprint().intersects(area):
			if not settled or _held(w):
				w.rebuild(settled)
			else:
				w.settle_when_laid()


func _top(w: Wall, s: float) -> Vector3:
	return w.layout.point_at(s) + Vector3.UP * w.layout.height


## The wall a ray points at: the nearest along it of those it passes through, else the one it passes closest to.
func pick_wall(origin: Vector3, dir: Vector3) -> Dictionary:
	var best := {}
	var best_key := Vector2(1.0, WALL_PICK)
	for w in walls:
		if _held(w):
			continue
		if w.pick_bounds.grow(WALL_PICK).intersects_ray(origin, dir) == null:
			continue
		var hit := w.ray_distance(origin, dir)
		var through: bool = hit.distance < (0.1 if w.layout.fence else WallLayout.THICKNESS * 0.5)
		var key := Vector2(0.0, hit.along) if through else Vector2(1.0, hit.distance)
		if key < best_key:
			best_key = key
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
