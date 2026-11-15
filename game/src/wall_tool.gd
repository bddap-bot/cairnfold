class_name WallTool
extends Node3D

## How builds stand on builds and join: docs/design.md, "Buildings on buildings".

const POINT_SPACING := 0.45
const REBUILD_EVERY := 0.06
const WALL_PICK := 0.7
const TINT := Color(1.0, 0.97, 0.9, 0.55)
const HOUSE_HEIGHT := 2.4
const TOWER_HEIGHT := 4.5
const HOUSE_SIDE := 2.4
enum RoofStyle { PITCHED, FLAT, THATCHED, BOARDED }
enum Pair { WALLS, ROOF, EAVES }

const HOUSE_SIZE := Vector2(4.5, 4.5)
const TOWER_SIZE := Vector2(3.4, 3.4)
const HOUSE_REACH := 6.0
const TOP_BAND := 0.4
const ROOF_STEP := 0.1
## Metres carried between two scrape cues.
const CARRY_STEP := 0.12

signal built


class Sizing:
	var scale: Callable = func() -> float: return 1.0
	var limits := Vector2.ONE
	var current: Callable
	var show: Callable = func(_size: float) -> void: pass
	## Returns {} while the garden already has what is shown.
	var command: Callable
	var settle: Callable
	var take: Callable
	var follow: Callable


class StairGrip:
	var id: int


class EaselGrip:
	var id: int


class Mason:
	var hand: Hand
	var stroke: Stroke
	var took_roof := false
	## Zero unless the grip took an eave past the walls.
	var eave_out := Vector3.ZERO
	var growing: Object
	var sizing: Sizing
	var took := Transform3D()
	var gain := 1.0
	var partner: Mason
	## This and lift_start: the hands' span and the scale when the second hand joined.
	var pair_span := 0.0
	var lift_start := 0.0
	var lift_at := Vector3.ZERO


class Stroke:
	var points: Array[Vector3] = []
	var plan: WallPlan
	var walls: Array[Wall] = []
	var planned := false
	var on := PackedInt32Array()
	## NAN on the ground.
	var level := NAN


var rig: Rig
var world: World
var flora: Flora
var paths: Paths
var masonry := Masonry.new(Wall.kinds(), true)
var walls: Array[Wall] = []
## New builds' styles: the ones last turned to on this machine.
var paint := Palette.plain()
var gable_end := WallLayout.GableEnd.WALL
var finish := WallLayout.Finish.BARE
var wear := 0.0
var fence_finish := WallLayout.Finish.BARE
var window_family := WallLayout.Family.COTTAGE
var planks := false
var foundation := WallLayout.Foundation.PILLARS
var thatch := false
var deck := RoofLayout.Deck.STONE
var masons: Array[Mason] = []
## Easel kit keeps its grips ahead of anything a ray from the hand would carry (`EaselTool.claims`).
var painting := func(_hand: Hand) -> bool: return false
var held: Wall
var held_at := {}
var _held_was := {}
var _riders := {}
var _holders: Array[Mason] = []
var _pair := Pair.WALLS
var _hold_start := {}
var _hold_from: Array[Transform3D] = []
var _hold_gain := 1.0
## One per footprint sent, so whichever is laid is carried to where the house stands now.
var _laid_at: Array[Dictionary] = []
var _held_dirty := false
## Builds let go, not yet laid as the garden has them: their stones are carried to `at` until laid again.
var _settling := {}
## A held piece's node stands until its build is drawn with the piece.
var _held_clutter := {}
## A hand held still trembles: a carry or turn under these, in metres and radians, leaves a house where it stood.
const NUDGE := 0.05
const TURN_NUDGE := 0.02
var quiet := false
var _since_rebuild := 0.0
var _dirty := false
var _path_openings := {}
## Kept up as walls are laid, so no frame of a stroke indexes them all.
var _walls_at := {}
var _walls_at_from := {}
var walls_at_rev := 0
## A wall the stroke's moving end is not near keeps its previewed arches.
var _previewed := {}
var _previewed_rev := -1
var _previewed_paths: Array = []
## Stand-ins the garden's walls take over in `put`.
var _handing: Array[Wall] = []
var _handing_hand: Hand
var _carried := 0.0


func _init(player: Rig, garden: World, plants: Flora, ways: Paths) -> void:
	rig = player
	world = garden
	flora = plants
	paths = ways
	add_child(masonry)
	paths.laid.connect(relay_crossings)
	paths.taken.connect(relay_crossings)
	paths.previewed.connect(_preview_crossings)
	world.restored.connect(_forget)
	for h in [rig.right, rig.left]:
		var m := Mason.new()
		m.hand = h
		masons.append(m)


static func draws(hand: Hand) -> bool:
	return hand.tool in [Hand.Tool.WALLS, Hand.Tool.FENCE]


func mason(hand: Hand) -> Mason:
	for m in masons:
		if m.hand == hand:
			return m
	return null


func busy(hand: Hand = null) -> bool:
	if held != null and hand == null:
		return true
	for m in masons:
		if (hand == null or m.hand == hand) and (m.stroke != null or m.growing != null or m in _holders):
			return true
	return false


func _process(delta: float) -> void:
	Wall.reap()
	walls_by_cell()
	_let_go_handed()
	for m in masons:
		_handle(m)
	_place_input()
	_hold_build()
	# At the end of the frame, after the walls, so a carried build is placed for the stones it laid this frame.
	_place_carried.call_deferred()
	_since_rebuild += delta
	if _dirty and _since_rebuild >= REBUILD_EVERY:
		_flush()
	_settle_clutter()
	for m in masons:
		if m.growing != null or m in _holders:
			m.hand.hold()
		_preview(m)


func _handle(m: Mason) -> void:
	if rig.aim_hand == m.hand:
		_let_go(m)
		return
	if m.stroke != null and (not draws(m.hand) or m.hand.buttons.released("tool")):
		end_stroke(m)
	if m.hand.buttons.released("grab") and m.growing != null:
		end_grow(m)
	if not m.hand.tracked():
		return
	var hand := m.hand.global_transform
	var origin := hand.origin
	var dir := -hand.basis.z
	if draws(m.hand):
		var aimed := aim(origin, dir) if m.stroke == null or is_nan(m.stroke.level) else _at_level(origin, dir, m.stroke.level)
		var at: Variant = aimed.get("point")
		var building := pick_building(origin, dir)
		m.hand.point(at if building.is_empty() else building.point, TINT)
		if m.hand.buttons.pressed("tool") and at != null and not busy(m.hand):
			begin_stroke(m, at, aimed.get("on", -1))
		elif m.hand.buttons.held("tool") and m.stroke != null and at != null:
			extend_stroke(m, at)

	if m.hand.buttons.pressed("grab") and not m.hand.taken() and not busy(m.hand) and not painting.call(m.hand):
		var on_held := _held_hit(origin, dir) if held != null else {}
		var ground: Variant = world.terrain.raycast(origin, dir)
		var nearest: float = origin.distance_to(ground) if ground != null else INF
		var hits := grip_hits(origin, dir, nearest)
		var pick: Dictionary = hits.get(World.Kind.HELD_TARGET, {})
		var before := nearest
		for kind: World.Kind in hits:
			if kind != World.Kind.HELD_TARGET:
				before = hits[kind].along
		var first: int = hits.keys().back() if not hits.is_empty() else -1
		var hit: Dictionary = hits.get(first, {})
		if not on_held.is_empty() and on_held.along < (before if pick.get("wall") == held else minf(before, pick.get("along", INF))):
			_join_build(m, on_held.roof, on_held.eave)
		elif first == World.Kind.STAND:
			grip_easel(m, hit.easel.id, hand, hit.point)
		elif first == World.Kind.STAIRS:
			begin_grow(m, _stair_grip(hit.stair), hand, hit.point)
		elif first == World.Kind.BOULDER:
			begin_grow(m, hit.boulder, hand, hit.point)
		elif first == World.Kind.PLANT:
			begin_grow(m, hit.plants[0], hand, hit.point)
		elif pick.has("fitting") and pick.what != "tower_flag":
			var grip := _fitting_grip(pick)
			if grip != null:
				begin_grow(m, grip, hand, pick.point)
		elif not pick.is_empty():
			if held != null or not world.state.walls.has(pick.wall.id):
				m.hand.hold()
			else:
				var roof: bool = pick.get("surface") == "roof"
				take_build(pick.wall)
				_join_build(m, roof, pick.wall.roof.eave_way(pick.point) if roof else Vector3.ZERO)
	elif m.hand.buttons.held("grab") and m.growing != null:
		if m.partner == null:
			m.sizing.follow.call(m, hand)
		elif m.pair_span > 0.0:
			drag_pair(m, m.partner.hand.global_position, origin)


## Nearest last (World's `pick`).
func grip_hits(from: Vector3, dir: Vector3, reach: float) -> Dictionary:
	return world.pick(from, dir, {World.Kind.PLANT: reach, World.Kind.HELD_TARGET: reach, World.Kind.BOULDER: reach, World.Kind.STAIRS: reach, World.Kind.STAND: reach}, {}, [World.Kind.HELD_TARGET])


func _preview(m: Mason) -> void:
	var change := {}
	if m.stroke != null:
		change = world.change_of({"op": "wall", "walls": m.stroke.walls.map(func(w: Wall) -> Dictionary: return w.data())})
	elif m.growing != null and m.sizing.current.call() and not m.sizing.command.call().is_empty():
		change = world.change_of(m.sizing.command.call())
	elif not _holders.is_empty() and m == _holders[0]:
		change = world.change_of({"op": "reshape", "of": "walls", "id": held.id, "data": _build_change(held_at)})
	if not change.is_empty():
		world.preview(m.hand, change)


func _let_go(m: Mason) -> void:
	if m.stroke != null:
		end_stroke(m)
	if m.growing != null:
		end_grow(m)


func _flush() -> void:
	for m in masons:
		if m.stroke != null:
			_plan(m.stroke)
			for w in m.stroke.walls:
				w.rebuild(false)
	if held != null and _held_dirty:
		held.rebuild(false)
		_held_dirty = false
	_dirty = false
	_since_rebuild = 0.0


func _new_wall() -> Wall:
	return _add_wall(Wall.new(randi(), masonry, world.terrain))


func _add_wall(w: Wall) -> Wall:
	w.paint = paint.duplicate()
	get_parent().add_child(w)
	return w


func begin_stroke(m: Mason, p: Vector3, on := -1) -> void:
	m.stroke = Stroke.new()
	m.stroke.points = [p]
	if on >= 0:
		m.stroke.on = PackedInt32Array([on])
		m.stroke.level = p.y
	var standing: Array[WallLayout] = []
	for w in walls:
		if w.on.has(on) or (on < 0 and w.on.is_empty()):
			standing.append(w.layout)
	m.stroke.plan = WallPlan.new(standing, flora.obstacles() if on < 0 else PackedVector3Array(), randi())
	m.stroke.plan.fence = m.hand.tool == Hand.Tool.FENCE
	m.stroke.plan.finish = fence_finish if m.stroke.plan.fence else finish
	m.stroke.plan.wear = 0.0 if m.stroke.plan.fence else wear
	m.stroke.plan.planks = planks
	m.stroke.plan.supports = _solids(m.stroke.on)
	_dirty = true


func extend_stroke(m: Mason, p: Vector3) -> void:
	var pts := m.stroke.points
	if pts[-1].is_equal_approx(p) or Commands.length(pts) >= Commands.STROKE_LENGTH:
		return
	if pts.size() >= 2 and pts[-1].distance_to(pts[-2]) < POINT_SPACING:
		pts[-1] = p
	else:
		pts.append(p)
		_cue(Cues.Act.WALL_LAY, p + Vector3.UP, [m.hand])
	if not is_nan(m.stroke.level):
		_rest_on(m.stroke, p)
	m.stroke.planned = false
	_dirty = true


func _plan(st: Stroke, commit := false) -> void:
	if st.planned and not commit:
		return
	st.planned = true
	var layouts := st.plan.pieces(st.points, world.terrain.height_at, commit)
	while st.walls.size() > layouts.size():
		st.walls.pop_back().queue_free()
	for i in layouts.size():
		if i == st.walls.size():
			st.walls.append(_add_wall(Wall.new(layouts[i].seed, masonry, world.terrain)))
		st.walls[i].layout = layouts[i]
		st.walls[i].on = st.on
		_meet(st.walls[i])


func end_stroke(m: Mason) -> void:
	_plan(m.stroke, true)
	var built_walls := m.stroke.walls
	m.stroke = null
	if not built_walls.is_empty():
		build(built_walls, m.hand)


func build(ws: Array[Wall], hand: Hand = null) -> void:
	world.submit({"op": "wall", "walls": ws.map(func(w: Wall) -> Dictionary: return w.data())}, func() -> void:
		_let_go_handed()
		_handing = ws
		_handing_hand = hand, hand)


## The garden is being swapped: what is in hand belongs to the old one.
func _forget() -> void:
	_let_go_handed()
	_path_openings.clear()
	_previewed.clear()
	_previewed_paths = []
	for m in masons:
		if m.stroke != null:
			for w in m.stroke.walls:
				w.queue_free()
		m.stroke = null
		m.eave_out = Vector3.ZERO
		m.growing = null
		m.sizing = null
		m.partner = null
	held = null
	_holders.clear()
	_riders.clear()
	_settling.clear()
	for e: Dictionary in _held_clutter.values():
		e.node.queue_free()
	_held_clutter.clear()


func _place_input() -> void:
	for m in masons:
		if not m.hand.tool in [Hand.Tool.HOUSE, Hand.Tool.TOWER] or rig.aim_hand == m.hand or not m.hand.tracked() or m in _holders:
			continue
		var aimed := aim(m.hand.global_position, -m.hand.global_basis.z)
		m.hand.point(aimed.get("point"), TINT)
		if not m.hand.buttons.pressed("tool") or busy(m.hand):
			continue
		var at: Variant = aimed.get("point")
		if at == null:
			var ahead := -rig.head.global_basis.z
			ahead.y = 0.0
			at = rig.head.global_position + ahead.normalized() * HOUSE_REACH
		var on := aimed.get("on", -1) as int
		build([new_house(stance(world.terrain.ground(at.x, at.z), angle(rig.head.global_basis.x), m.hand.tool == Hand.Tool.TOWER), PackedInt32Array([on]) if on >= 0 else PackedInt32Array())], m.hand)


static func stance(center: Vector3, yaw: float, round := false) -> Dictionary:
	var out := {"center": center, "yaw": yaw, "size": TOWER_SIZE if round else HOUSE_SIZE, "round": round, "rise": 0.0,
		"height": TOWER_HEIGHT if round else HOUSE_HEIGHT, "curve": 0.0, "overhang": RoofLayout.OVERHANG}
	out.pitch = pitch_for(out)
	return out


func new_house(at: Dictionary, on := PackedInt32Array()) -> Wall:
	var w := _new_wall()
	w.on = on
	w.layout.finish = WallLayout.Finish.BARE if at.round else finish
	w.layout.wear = 0.0 if at.round else wear
	w.layout.planks = planks
	w.layout.foundation = foundation
	w.layout.gable_end = gable_end
	w.layout.closed = true
	w.layout.top = WallLayout.Top.CAP
	w.layout.height = at.height
	w.layout.rise = at.rise
	w.layout.points = outline(at)
	var roof := RoofLayout.new()
	roof.kind = RoofLayout.Kind.CONE if at.round else RoofLayout.Kind.GABLE
	roof.seed = w.layout.seed
	roof.thatch = thatch
	roof.deck = deck
	w.add_roof(roof)
	roof.pitch = at.pitch
	roof.curve = at.curve
	roof.overhang = at.overhang
	roof.center = at.center
	roof.radius = at.size.x * 0.5
	_meet(w)
	return w


## One flush takes the held build's and its riders' stones out of the glade's.
func take_build(w: Wall) -> void:
	held = w
	var d: Dictionary = world.state.walls[w.id]
	_held_was = house_of(d)
	if _held_was.is_empty():
		_held_was = line_of(d)
	_held_was.grounded = w.on.is_empty() and _held_was.has("size")
	var was: Dictionary = _settling.get(w.id, {})
	held_at = (_held_was if was.is_empty() or was.back else was.at).duplicate()
	_hold_start = held_at.duplicate()
	_laid_at = _resettled(w, d.points, d.rise)
	w.draw_live()
	_riders.clear()
	for o in walls:
		if o != w and _below(o.on).has(w.id):
			_riders[o] = _resettled(o, world.state.walls[o.id].points, o.layout.laid_rise)
			o.draw_live()
	masonry.flush()
	_holders.clear()
	_carried = 0.0


func _resettled(w: Wall, points: PackedVector3Array, rise: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = _settling.get(w.id, {}).get("laid_at", [] as Array[Dictionary])
	_settling.erase(w.id)
	var laid: Array[Vector3] = []
	laid.assign(Array(points))
	out.append({"points": laid, "laid_rise": rise, "center": _held_was.center, "yaw": _held_was.yaw, "rise": _held_was.rise})
	return out


func _join_build(m: Mason, roof: bool, eave: Vector3) -> void:
	m.took_roof = roof
	m.eave_out = eave
	_holders.append(m)
	m.hand.hold()
	_restart_hold()
	if _holders.size() == 1:
		Cues.play(Cues.Act.HOUSE_TAKE, held_at.center, m.hand)


func _restart_hold() -> void:
	_hold_start = held_at.duplicate()
	_hold_from.clear()
	var mid := Vector3.ZERO
	for m in _holders:
		_hold_from.append(m.hand.global_transform)
		mid += m.hand.global_position / _holders.size()
	_hold_gain = Hand.reach_gain(mid.distance_to(held_at.center))
	_pair = Pair.WALLS
	if _holders.size() == 2 and held.roof != null and _holders.all(func(m: Mason) -> bool: return m.took_roof):
		_pair = Pair.EAVES if _holders.all(func(m: Mason) -> bool: return m.eave_out != Vector3.ZERO) else Pair.ROOF


func _hold_build() -> void:
	if _holders.is_empty():
		return
	var holding := _holders.filter(func(m: Mason) -> bool: return m.hand.buttons.held("grab") and m.hand.tracked() and rig.aim_hand != m.hand)
	if holding.is_empty():
		end_build(_holders[0].hand)
		return
	if holding.size() != _holders.size():
		_holders.assign(holding)
		_restart_hold()
	var now: Array[Transform3D] = []
	for m in _holders:
		now.append(m.hand.global_transform)
	if now.size() == 1:
		stand_build(carry(_hold_start, _hold_from[0], now[0], _hold_gain))
	elif not _hold_start.has("size"):
		stand_build(stretch_line(_hold_start, _hold_from, now, _hold_gain))
	elif _pair == Pair.ROOF:
		stand_build(bend(_hold_start, _hold_from, now, _hold_gain))
	elif _pair == Pair.EAVES:
		var out: Array[Vector3] = [_holders[0].eave_out, _holders[1].eave_out]
		stand_build(pull_eaves(_hold_start, _hold_from, now, out, _hold_gain, held.roof.reach()))
	else:
		stand_build(resize(_hold_start, _hold_from, now, _hold_gain))


func stand_build(to: Dictionary) -> void:
	to.center = world.terrain.ground(to.center.x, to.center.z)
	var hands := _holders.map(func(m: Mason) -> Hand: return m.hand)
	var top: Vector3 = to.center + Vector3.UP * (to.rise + to.height)
	var changed := func(k: String) -> bool: return to.has(k) and to[k] != held_at[k]
	if ["size", "length", "height"].any(changed):
		_cue(Cues.Act.HOUSE_STRETCH, top, hands, Cues.stretch(_extent(_hold_start), _extent(to)))
	elif changed.call("rise"):
		_cue(Cues.Act.WALL_LIFT, to.center, hands)
	elif ["pitch", "curve", "overhang"].any(changed):
		_cue(Cues.Act.ROOF_FLAT if to.pitch <= 0.0 else Cues.Act.ROOF_SHAPE, top + Vector3.UP * to.pitch, hands)
	else:
		_carried += to.center.distance_to(held_at.center) + absf(angle_difference(to.yaw, held_at.yaw)) * _extent(to) * 0.25
		if _carried > CARRY_STEP:
			_carried = 0.0
			_cue(Cues.Act.HOUSE_MOVE, to.center, hands)
	var relay := ["size", "length", "rise", "height", "pitch", "curve", "overhang"].any(changed)
	held_at = to
	if relay:
		_lay_build()


static func _extent(at: Dictionary) -> float:
	return at.height + (at.size.length() if at.has("size") else at.run * at.length)


func _lay_build() -> void:
	held.set_data(World.reshaped(world.state.walls[held.id], _build_change(held_at)))
	_meet(held)
	_laid_at.append({"points": held.layout.points.duplicate(), "laid_rise": held_at.rise, "center": held_at.center, "yaw": held_at.yaw, "rise": held_at.rise})
	_held_dirty = true
	_dirty = true


func _build_change(at: Dictionary) -> Dictionary:
	var d: Dictionary = world.state.walls[held.id]
	return reshape_house(d, at) if at.has("size") else reshape_line(d, at)


func _place_carried() -> void:
	if held != null:
		_carry(held, _laid_at, held_at)
		for r: Wall in _riders:
			_carry(r, _riders[r], held_at)
	_settle_builds()


func _carry(w: Wall, laid_at: Array[Dictionary], at: Dictionary) -> void:
	var laid := w.layout.laid_points
	var i := laid_at.find_custom(func(e: Dictionary) -> bool: return e.points == laid and e.laid_rise == w.layout.laid_rise)
	if i < 0:
		return
	for k in i:
		laid_at.pop_front()
	var was: Dictionary = laid_at[0]
	var lift: float = 0.0 if not at.grounded else _lowest(outline(at), world.terrain.shown_at) - _lowest(outline({"center": was.center, "yaw": was.yaw, "size": at.size, "round": at.round}), world.terrain.shown_at) + at.rise - was.rise
	var from := _footing(was)
	var to := Transform3D(Basis(Vector3.UP, at.yaw), Vector3(at.center.x, lift, at.center.z))
	_place_laid(w, to * from.affine_inverse())


func _place_laid(w: Wall, x: Transform3D) -> void:
	if w.transform.is_equal_approx(x):
		return
	w.transform = x
	if world.decorations != null:
		world.decorations.place()


func end_build(hand: Hand = null) -> void:
	var w := held
	var at := held_at
	var moved := _moved(_held_was, at)
	var carried := _moved(_held_was, _held_was.merged({"center": at.center, "yaw": at.yaw}, true))
	var cmds: Array = [{"op": "reshape", "of": "walls", "id": w.id, "data": _build_change(at)}] if moved else []
	var ids := [w.id]
	var x := _footing(at) * _footing(_held_was).affine_inverse()
	for r: Wall in _riders:
		if carried:
			cmds.append({"op": "reshape", "of": "walls", "id": r.id, "data": carried_by(world.state.walls[r.id], x)})
		_settling[r.id] = {"laid_at": _riders[r], "at": at, "back": not carried}
		ids.append(r.id)
	_settling[w.id] = {"laid_at": _laid_at, "at": at, "back": not moved}
	held = null
	_holders.clear()
	_riders.clear()
	_laid_at = []
	if cmds.is_empty():
		_relay(w)
	else:
		world.submit(cmds[0] if cmds.size() == 1 else {"op": "batch", "cmds": cmds}, _build_back.bind(ids), hand)


static func _moved(was: Dictionary, at: Dictionary) -> bool:
	if Vector2(at.center.x - was.center.x, at.center.z - was.center.z).length() > NUDGE or absf(angle_difference(at.yaw, was.yaw)) > TURN_NUDGE:
		return true
	if at.has("size") and not at.size.is_equal_approx(was.size):
		return true
	return ["rise", "height", "pitch", "curve", "overhang", "length"].any(func(k: String) -> bool: return at.has(k) and absf(at[k] - was[k]) > 0.01)


static func _footing(at: Dictionary) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, at.yaw), _flat(at.center))


static func carried_by(d: Dictionary, x: Transform3D) -> Dictionary:
	var points := PackedVector3Array()
	for p: Vector3 in d.points:
		var q := x * _flat(p)
		points.append(Vector3(q.x, p.y, q.z))
	var out := {"points": points}
	if d.has("roof"):
		var c := x * _flat(d.roof.center)
		out["roof"] = {"center": Vector3(c.x, d.roof.center.y, c.z)}
	return out


## The garden answers before it applies what it took, hence the deferred relay.
func _build_back(ids: Array) -> void:
	for id: int in ids:
		if _settling.has(id):
			_settling[id].back = true
	_relay_unlike_garden.call_deferred(ids)


func _relay_unlike_garden(ids: Array) -> void:
	for id: int in ids:
		var w := find(id)
		if w != null and not _held(w) and world.state.walls.has(id) and not _shows_garden(w):
			_relay(w)


func _shows_garden(w: Wall) -> bool:
	var d: Dictionary = world.state.walls[w.id]
	if PackedVector3Array(w.layout.points) != d.points or w.layout.rise != d.rise or w.layout.height != d.height:
		return false
	return w.roof == null or (w.roof.pitch == d.roof.pitch and w.roof.curve == d.roof.curve and w.roof.overhang == d.roof.overhang and w.roof.center == d.roof.center)


func _settle_builds() -> void:
	for id: int in _settling.keys():
		var w := find(id)
		var s: Dictionary = _settling[id]
		if w == null or not world.state.walls.has(id):
			_settling.erase(id)
		elif s.back and not w.laying() and PackedVector3Array(w.layout.laid_points) == world.state.walls[id].points and w.layout.laid_rise == world.state.walls[id].rise:
			_place_laid(w, Transform3D.IDENTITY)
			w.occlude_shown()
			_settling.erase(id)
		else:
			_carry(w, s.laid_at, s.at)


static func _lowest(points: Array[Vector3], height: Callable) -> float:
	var low := INF
	for c in points:
		low = minf(low, height.call(c.x, c.z))
	return low


static func footprint(center: Vector3, yaw: float, size: Vector2) -> Dictionary:
	var along := Vector3.RIGHT.rotated(Vector3.UP, yaw)
	return {"a": center - along * size.x * 0.5, "b": center + along * size.x * 0.5, "length": size.x, "depth": size.y}


static func outline(at: Dictionary) -> Array[Vector3]:
	if at.round:
		return WallLayout.circle(at.center, at.size.x * 0.5)
	var span := footprint(at.center, at.yaw, at.size)
	return WallLayout.rectangle(span.a, span.b, span.depth)


static func pitch_for(at: Dictionary) -> float:
	if at.round:
		return at.size.x * 0.8
	return at.size.y * 0.42


static func roof_options(pitch: float) -> Array:
	return [RoofStyle.FLAT, RoofStyle.BOARDED] if pitch <= 0.0 else [RoofStyle.PITCHED, RoofStyle.THATCHED]


static func roof_style(d: Dictionary) -> RoofStyle:
	if d.roof.pitch <= 0.0:
		return RoofStyle.BOARDED if d.roof.deck == RoofLayout.Deck.WOOD else RoofStyle.FLAT
	return RoofStyle.THATCHED if d.roof.thatch else RoofStyle.PITCHED


## A flat roof keeps its covering, thatch or tiles, for when pulled up, a pitched one its deck for when pushed flat.
static func restyle_roof(d: Dictionary, style: RoofStyle) -> Dictionary:
	if style not in roof_options(d.roof.pitch):
		return {}
	if d.roof.pitch <= 0.0:
		return {"roof": {"deck": RoofLayout.Deck.WOOD if style == RoofStyle.BOARDED else RoofLayout.Deck.STONE}}
	return {"roof": {"thatch": style == RoofStyle.THATCHED}}


static func house_of(d: Dictionary) -> Dictionary:
	if not d.has("roof") or not d.closed:
		return {}
	if d.roof.kind == RoofLayout.Kind.CONE:
		return _with_roof(d, {"center": d.roof.center, "yaw": 0.0, "size": Vector2.ONE * d.roof.radius * 2.0, "round": true})
	var p: PackedVector3Array = d.points
	if p.size() != 4:
		return {}
	return _with_roof(d, {"center": (p[0] + p[2]) * 0.5, "yaw": angle(p[1] - p[0]), "size": Vector2(_flat(p[1] - p[0]).length(), _flat(p[3] - p[0]).length()), "round": false})


static func _with_roof(d: Dictionary, at: Dictionary) -> Dictionary:
	return at.merged({"rise": d.rise, "height": d.height, "pitch": d.roof.pitch, "curve": d.roof.curve, "overhang": d.roof.overhang})


static func reshape_house(d: Dictionary, to: Dictionary) -> Dictionary:
	var from := house_of(d)
	var was: Array[Vector3] = []
	was.assign(Array(d.points))
	var now := outline(to)
	var fits := _fittings_moved(d, func(s: float) -> float: return _loop_s(now, _scaled(from, to, _loop_point(was, s))))
	var roof := {}
	if to.round:
		roof = {"center": to.center, "radius": to.size.x * 0.5}
	else:
		var r0 := _ridge_of(from)
		var r1 := _ridge_of(to)
		var moved_on := func(spots: PackedVector2Array) -> PackedVector2Array:
			var out := PackedVector2Array()
			for c: Vector2 in spots:
				var o: Vector3 = _scaled(from, to, from.center + r0 * c.x + r0.cross(Vector3.UP) * c.y) - to.center
				out.append(Vector2(o.dot(r1), o.dot(r1.cross(Vector3.UP))))
			return out
		roof = {"chimneys": moved_on.call(d.roof.chimneys), "dormers": moved_on.call(d.roof.dormers), "hatches": moved_on.call(d.roof.hatches)}
	roof.merge({"pitch": to.pitch, "curve": to.curve, "overhang": to.overhang})
	return {"points": PackedVector3Array(now), "rise": to.rise, "height": to.height, "openings": fits.openings, "lanterns": fits.lanterns, "flags": fits.flags, "roof": roof}


static func _fittings_moved(d: Dictionary, moved: Callable) -> Dictionary:
	var openings := PackedVector4Array()
	for o: Vector4 in d.openings:
		openings.append(Vector4(moved.call(o.x), o.y, o.z, o.w))
	var lanterns := PackedVector3Array()
	for l: Vector3 in d.lanterns:
		lanterns.append(Vector3(moved.call(l.x), l.y, l.z))
	var flags := PackedFloat32Array()
	for f: float in d.flags:
		flags.append(moved.call(f))
	return {"openings": openings, "lanterns": lanterns, "flags": flags}


static func _ridge_of(at: Dictionary) -> Vector3:
	var span := footprint(at.center, at.yaw, at.size)
	return _flat(span.b - span.a).normalized()


static func _scaled(from: Dictionary, to: Dictionary, p: Vector3) -> Vector3:
	var x := Vector3.RIGHT.rotated(Vector3.UP, from.yaw)
	var z := x.cross(Vector3.UP)
	var q := _flat(p - from.center)
	var k: Vector2 = to.size / from.size
	var tx := Vector3.RIGHT.rotated(Vector3.UP, to.yaw)
	return to.center + tx * q.dot(x) * k.x + tx.cross(Vector3.UP) * q.dot(z) * k.y


## Measured as `WallLayout` lays a loop.
static func _loop_point(points: Array[Vector3], s: float) -> Vector3:
	var n := points.size()
	s = fposmod(s, Commands.length(points + [points[0]]))
	for i in n:
		var a := points[i]
		var b := points[(i + 1) % n]
		var l := _flat(b - a).length()
		if s <= l:
			return a.lerp(b, s / maxf(l, 1e-6))
		s -= l
	return points[0]


static func _loop_s(points: Array[Vector3], p: Vector3) -> float:
	var n := points.size()
	var best := INF
	var out := 0.0
	var acc := 0.0
	for i in n:
		var a := _flat(points[i])
		var b := _flat(points[(i + 1) % n])
		var l := a.distance_to(b)
		var t := clampf((_flat(p) - a).dot(b - a) / maxf(l * l, 1e-9), 0.0, 1.0)
		var d := _flat(p).distance_to(a.lerp(b, t))
		if d < best:
			best = d
			out = acc + t * l
		acc += l
	return out


## `length`: times `run`, the length it stands at.
static func line_of(d: Dictionary) -> Dictionary:
	var mid := Vector3.ZERO
	for p: Vector3 in d.points:
		mid += p / d.points.size()
	return {"center": mid, "yaw": 0.0, "length": 1.0, "run": Commands.length(d.points), "height": d.height, "rise": d.rise, "fence": d.fence, "grounded": false}


static func reshape_line(d: Dictionary, to: Dictionary) -> Dictionary:
	var from := line_of(d)
	var turn := Basis(Vector3.UP, to.yaw)
	var k: float = to.length
	var points := PackedVector3Array()
	for p: Vector3 in d.points:
		var q: Vector3 = to.center + turn * (_flat(p - from.center) * k)
		points.append(Vector3(q.x, p.y, q.z))
	var fits := _fittings_moved(d, func(s: float) -> float: return s * k)
	var ruins := PackedVector2Array()
	for r: Vector2 in d.ruins:
		ruins.append(r * k)
	return {"points": points, "height": to.height, "openings": fits.openings, "lanterns": fits.lanterns, "flags": fits.flags, "ruins": ruins}


static func stretch_line(start: Dictionary, from: Array[Transform3D], to: Array[Transform3D], gain: float) -> Dictionary:
	var out := start.duplicate()
	var span0 := _flat(from[1].origin - from[0].origin).length()
	var run: float = start.run * start.length * _flat(to[1].origin - to[0].origin).length() / maxf(span0, 0.05)
	out.length = clampf(run, 1.0, Commands.MAX_LENGTH) / start.run
	if not start.fence:
		out.height = maxf(start.height + snappedf(_upright(from, to) * gain, WallLayout.COURSE), WallLayout.MIN_HEIGHT)
	return out


static func carry(start: Dictionary, from: Transform3D, to: Transform3D, gain: float) -> Dictionary:
	var out := start.duplicate()
	out.center = start.center + _flat(to.origin - from.origin) * gain
	out.yaw = start.yaw + turned(from, to)
	if start.grounded:
		out.rise = maxf(snappedf(start.rise + (to.origin.y - from.origin.y) * gain, WallLayout.COURSE), 0.0)
	return out


static func stretched(start: Dictionary, span: Vector3, ratio: float) -> Vector2:
	var grows := Vector2.ONE
	if not start.round:
		var across: float = angle(span) - start.yaw
		grows = Vector2.RIGHT if absf(cos(across)) >= absf(sin(across)) else Vector2.DOWN
	var kept: Vector2 = start.size * (Vector2.ONE - grows)
	var size: Vector2 = kept + grows * maxf(start.size[grows.max_axis_index()] * ratio, HOUSE_SIDE)
	var run := _run_at(start, size)
	if run <= Commands.MAX_LENGTH:
		return size
	var was := _run_at(start, start.size)
	while run > Commands.MAX_LENGTH and size != start.size:
		size = start.size + (size - start.size) * maxf(Commands.STRETCH_LENGTH - was, 0.0) / (run - was)
		run = _run_at(start, size)
	return size


static func _run_at(at: Dictionary, size: Vector2) -> float:
	return Commands.length(outline(at.merged({"size": size}, true)))


## Grows toward the hand that moved, so a hand held still keeps its wall.
static func resize(start: Dictionary, from: Array[Transform3D], to: Array[Transform3D], gain := 1.0) -> Dictionary:
	var out := start.duplicate()
	var span0 := _flat(from[1].origin - from[0].origin)
	out.size = stretched(start, span0, _flat(to[1].origin - to[0].origin).length() / maxf(span0.length(), 0.05))
	var axis := span0.normalized()
	var grown: float = out.size.x - start.size.x
	if not start.round and out.size.y != start.size.y:
		axis = Vector3.RIGHT.rotated(Vector3.UP, start.yaw).cross(Vector3.UP)
		grown = out.size.y - start.size.y
	elif not start.round:
		axis = Vector3.RIGHT.rotated(Vector3.UP, start.yaw)
	axis *= signf(span0.dot(axis))
	var d0 := (to[0].origin - from[0].origin).dot(axis)
	var d1 := (to[1].origin - from[1].origin).dot(axis)
	var toward := clampf((d0 + d1) / (d1 - d0), -1.0, 1.0) if absf(d1 - d0) > 1e-4 else 0.0
	out.center = start.center + axis * grown * 0.5 * toward
	out.height = maxf(start.height + snappedf(_upright(from, to) * gain, WallLayout.COURSE), WallLayout.MIN_HEIGHT)
	out.pitch = start.pitch * (out.size.x / start.size.x if start.round else out.size.y / start.size.y)
	return out


static func bend(start: Dictionary, from: Array[Transform3D], to: Array[Transform3D], gain: float) -> Dictionary:
	var out := start.duplicate()
	var pitch: float = start.pitch + snappedf(_upright(from, to) * gain, ROOF_STEP)
	out.pitch = 0.0 if pitch < RoofLayout.FLAT_SNAP else pitch
	var spread := _flat(to[1].origin - to[0].origin).length() - _flat(from[1].origin - from[0].origin).length()
	out.curve = clampf(start.curve + spread * 2.0, -RoofLayout.CURVE, RoofLayout.CURVE)
	return out


static func pull_eaves(start: Dictionary, from: Array[Transform3D], to: Array[Transform3D], out: Array[Vector3], gain: float, reach: float) -> Dictionary:
	var pulled := 0.0
	for i in 2:
		pulled += (to[i].origin - from[i].origin).dot(out[i]) * 0.5
	var at := start.duplicate()
	at.overhang = clampf(snappedf(minf(start.overhang, reach) + pulled * gain, ROOF_STEP), 0.0, reach)
	return at


static func _upright(from: Array[Transform3D], to: Array[Transform3D]) -> float:
	return absf(to[1].origin.y - to[0].origin.y) - absf(from[1].origin.y - from[0].origin.y)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


static func angle(v: Vector3) -> float:
	return atan2(-v.z, v.x)


static func turned(from: Transform3D, to: Transform3D) -> float:
	return angle_difference(angle(from.basis.x), angle(to.basis.x))


func _held_hit(origin: Vector3, dir: Vector3) -> Dictionary:
	var x := held.transform.affine_inverse()
	var o := x * origin
	var d := x.basis * dir
	var best := {}
	var wall := held.ray_hit(o, d)
	if not wall.is_empty():
		best = {"along": wall.along, "roof": false, "eave": Vector3.ZERO}
	if held.roof == null:
		return best
	var t := held.roof.ray_hit(o, d)
	if t < best.get("along", INF):
		best = {"along": t, "roof": true, "eave": held.transform.basis * held.roof.eave_way(o + d * t)}
	t = held.roof.gable_hit(o, d)
	if t < best.get("along", INF):
		best = {"along": t, "roof": false, "eave": Vector3.ZERO}
	return best


func begin_grow(m: Mason, target: Object, hand: Transform3D, at: Vector3) -> void:
	m.growing = target
	m.lift_at = at
	for o in masons:
		if o != m and o.growing == target:
			m.sizing = o.sizing
			m.partner = o
			o.partner = m
			m.lift_start = m.sizing.scale.call()
			m.pair_span = o.hand.global_position.distance_to(hand.origin)
			return
	m.sizing = _sizing(target)
	_take(m, hand)


func _take(m: Mason, hand: Transform3D) -> void:
	m.took = hand
	m.gain = Hand.reach_gain(hand.origin.distance_to(m.lift_at))
	m.sizing.take.call()


func drag_pair(m: Mason, a: Vector3, b: Vector3) -> void:
	if m.sizing.current.call():
		_size(m, m.lift_start * a.distance_to(b) / m.pair_span)


func _size(m: Mason, scale: float) -> void:
	var s := m.sizing
	var was: float = s.scale.call()
	s.show.call(clampf(snappedf(scale, 0.01), s.limits.x, s.limits.y))
	if not is_equal_approx(was, s.scale.call()):
		_cue(Cues.Act.WALL_STRETCH, m.lift_at, [m.hand] + ([m.partner.hand] if m.partner != null else []), Cues.stretch(m.lift_start, s.scale.call()))


func end_grow(m: Mason) -> void:
	var s := m.sizing
	var other := m.partner
	m.growing = null
	m.sizing = null
	m.partner = null
	m.pair_span = 0.0
	if other != null:
		other.partner = null
		other.pair_span = 0.0
		_take(other, other.hand.global_transform)
		return
	if not s.current.call():
		s.settle.call()
		return
	# Shown once more with no hand holding it: a carried boulder drops onto the ground.
	s.show.call(s.scale.call())
	var cmd: Dictionary = s.command.call()
	if cmd.is_empty():
		s.settle.call()
	else:
		world.submit(cmd, s.settle, m.hand)


func _sizing(target: Object) -> Sizing:
	var s := Sizing.new()
	var in_hand := func() -> bool: return masons.any(func(o: Mason) -> bool: return o.growing == target)
	if target is FittingGrip:
		return _fitting_sizing(target, s, in_hand)
	if target is Boulders.Boulder:
		return _boulder_grip(target, s, in_hand)
	if target is StairGrip:
		return _stair_sizing(target, s, in_hand)
	if target is EaselGrip:
		return _easel_sizing(target, s, in_hand)
	return _plant_grip(target, s, in_hand)


func _plant_grip(first: Flora.Plant, s: Sizing, in_hand: Callable) -> Sizing:
	var tree := first.pool == flora.trunks
	var placed := func() -> Vector3:
		return world.state.groups.get(first.group, {}).get("places", {}).get(first.index, flora.home_of(first))
	var turned_to := func() -> float:
		return world.state.groups.get(first.group, {}).get("turns", {}).get(first.index, 0.0)
	var hold := {"from": Vector3.ZERO, "turn": 0.0}
	if tree:
		s.scale = flora.scale_of.bind(first)
		s.limits = FloraLayout.SCALES
	s.current = first.current
	s.show = func(scale: float) -> void:
		if tree:
			flora.set_look(first, flora.species_of(first) as FloraLayout.Species, scale)
	s.command = func() -> Dictionary:
		var g: Dictionary = world.state.groups.get(first.group, {})
		var at := first.foot()
		if g.is_empty() or Water.drowned(world.terrain, at):
			return {}
		var cmd := {"op": "tree", "group": first.group, "index": first.index}
		var was: Vector3 = placed.call()
		if Vector2(at.x - was.x, at.z - was.z).length() >= NUDGE:
			cmd.at = world.terrain.ground(at.x, at.z)
		if absf(angle_difference(turned_to.call(), flora.turn_of(first))) >= TURN_NUDGE:
			cmd.turn = flora.turn_of(first)
		if tree and not is_equal_approx(flora.scale_of(first), g.scale.get(first.index, 1.0)):
			cmd.scale = flora.scale_of(first)
		return {} if cmd.size() == 3 else cmd
	s.take = func() -> void:
		hold.from = first.foot()
		hold.turn = flora.turn_of(first)
	s.follow = func(m: Mason, hand: Transform3D) -> void:
		flora.move(first, hold.from + (hand.origin - m.took.origin) * m.gain)
		flora.turn_to(first, wrapf(hold.turn + turned(m.took, hand), -PI, PI))
	s.settle = func() -> void:
		var g: Dictionary = world.state.groups.get(first.group, {})
		if first.current() and not g.is_empty() and not in_hand.call():
			flora.move(first, placed.call())
			flora.turn_to(first, turned_to.call())
			if tree:
				flora.set_look(first, g.species.get(first.index, FloraLayout.Species.OAK), g.scale.get(first.index, 1.0))
	return s


func _boulder_grip(b: Boulders.Boulder, s: Sizing, in_hand: Callable) -> Sizing:
	var rocks := world.boulders
	var standing := func() -> bool: return is_instance_valid(b) and rocks.find(b.id) == b
	var grip := {"pose": b.pose(), "scale": b.size, "from": b.pose()}
	var data := func() -> Dictionary:
		var p: Transform3D = grip.pose
		var turn := p.basis.get_rotation_quaternion().normalized()
		return {"at": world.terrain.ground(p.origin.x, p.origin.z), "turn": turn, "sink": BoulderLayout.sink(b.shape, turn, grip.scale, p.origin, world.terrain.height_at), "scale": grip.scale}
	s.scale = func() -> float: return grip.scale
	s.limits = Vector2(BoulderLayout.LEAST, BoulderLayout.MOST)
	s.current = standing
	s.show = func(scale: float) -> void:
		grip.scale = scale
		if in_hand.call():
			rocks.show_held(b.id, grip.pose, scale)
		else:
			var from_y := b.position.y
			rocks.show_reshaped(b.id, data.call())
			built.emit()
			b.landed(from_y)
	s.command = func() -> Dictionary:
		var d: Dictionary = data.call()
		var was: Dictionary = world.state.boulders[b.id]
		if is_equal_approx(d.scale, was.scale) and d.turn.is_equal_approx(was.turn) and is_equal_approx(d.sink, was.sink) and is_equal_approx(d.at.x, was.at.x) and is_equal_approx(d.at.z, was.at.z):
			return {}
		return {"op": "reshape", "of": "boulders", "id": b.id, "data": d}
	s.take = func() -> void: grip.from = grip.pose
	s.follow = func(m: Mason, hand: Transform3D) -> void:
		grip.pose = Boulders.carried(grip.from, m.took, hand, m.gain)
		rocks.show_held(b.id, grip.pose, grip.scale)
	s.settle = func() -> void:
		if standing.call() and not in_hand.call():
			rocks.show_reshaped(b.id)
	return s


func _stair_sizing(grip: StairGrip, s: Sizing, in_hand: Callable) -> Sizing:
	var stairs := world.stairs
	var was: Dictionary = world.state.stairs[grip.id].duplicate()
	var shown := {"a": was.a, "b": was.b, "width": was.width, "sag": was.sag}
	var from := shown.duplicate()
	var current := func() -> bool:
		var now: Dictionary = world.state.stairs.get(grip.id, {})
		return not now.is_empty() and now.a == was.a and now.b == was.b and now.width == was.width
	s.scale = func() -> float: return shown.width
	s.limits = StairLayout.WIDTH
	s.current = current
	s.show = func(width: float) -> void:
		shown.width = width
		shown.sag = stair_sag(shown)
		stairs.show_reshaped(grip.id, shown)
	s.command = func() -> Dictionary:
		var same: bool = shown.a.is_equal_approx(was.a) and shown.b.is_equal_approx(was.b) and is_equal_approx(shown.width, was.width)
		return {} if same else {"op": "reshape", "of": "stairs", "id": grip.id, "data": shown.merged({"on": stair_supports(shown)})}
	s.take = func() -> void: from.merge(shown, true)
	s.follow = func(m: Mason, hand: Transform3D) -> void:
		shown.merge(carry_stairs(from, m.took, hand, m.gain, world.terrain.height_at), true)
		shown.sag = stair_sag(shown)
		stairs.show_reshaped(grip.id, shown)
	s.settle = func() -> void:
		if world.state.stairs.has(grip.id) and not in_hand.call():
			stairs.show_reshaped(grip.id)
	return s


static func carry_stairs(at: Dictionary, from: Transform3D, to: Transform3D, gain: float, height: Callable) -> Dictionary:
	var mid: Vector3 = (at.a + at.b) * 0.5
	var turn := Basis(Vector3.UP, turned(from, to))
	var move := (to.origin - from.origin) * gain
	var a: Vector3 = mid + move + turn * (at.a - mid)
	var b: Vector3 = mid + move + turn * (at.b - mid)
	var low := a if a.y < b.y else b
	var under := maxf(height.call(low.x, low.z) - low.y, 0.0)
	return {"a": a + Vector3.UP * under, "b": b + Vector3.UP * under, "width": at.width}


func stair_sag(d: Dictionary) -> float:
	return StairLayout.sag_over(d.a, d.b, d.width, func(p: Vector3) -> float: return floor_under(p + Vector3.UP * 0.05), world.terrain.water_at)


## Builds that take the stairs with them when they go.
func stair_supports(d: Dictionary) -> PackedInt32Array:
	var on := PackedInt32Array()
	for p: Vector3 in [d.a, d.b]:
		var ids: Array[int] = [aim(p + Vector3.UP * TOP_BAND, Vector3.DOWN).get("on", -1)]
		for w in walls:
			if w.roof != null and absf(w.layout.floor_under(p) - p.y) < TOP_BAND:
				ids.append(w.id)
		for id in ids:
			if id >= 0 and not on.has(id) and on.size() < Commands.MAX_SUPPORTS:
				on.append(id)
	return on


## A second hand takes nothing: two hands size no easel.
func grip_easel(m: Mason, id: int, hand: Transform3D, at: Vector3) -> void:
	if masons.any(func(o: Mason) -> bool: return o.growing is EaselGrip and o.growing.id == id):
		m.hand.hold()
		return
	var grip := EaselGrip.new()
	grip.id = id
	begin_grow(m, grip, hand, at)


func _easel_sizing(grip: EaselGrip, s: Sizing, in_hand: Callable) -> Sizing:
	var stands := world.easels
	var was: Dictionary = world.state.easels[grip.id]
	var start := {"at": was.at, "yaw": was.yaw}
	var shown := start.duplicate()
	var from := start.duplicate()
	s.current = func() -> bool:
		var now: Dictionary = world.state.easels.get(grip.id, {})
		return not now.is_empty() and now.at == start.at and now.yaw == start.yaw
	s.show = func(_scale: float) -> void: stands.stand(grip.id, shown.at, shown.yaw)
	s.command = func() -> Dictionary:
		if shown.at.distance_to(start.at) < NUDGE and absf(angle_difference(shown.yaw, start.yaw)) < TURN_NUDGE:
			return {}
		return {"op": "reshape", "of": "easels", "id": grip.id, "data": shown.duplicate()}
	s.take = func() -> void: from.merge(shown, true)
	s.follow = func(m: Mason, hand: Transform3D) -> void:
		shown.merge(carry_easel(from, m.took, hand, m.gain, world.terrain.height_at), true)
		stands.stand(grip.id, shown.at, shown.yaw)
	s.settle = func() -> void:
		if not in_hand.call():
			stands.show_reshaped(grip.id)
	return s


static func carry_easel(at: Dictionary, from: Transform3D, to: Transform3D, gain: float, height: Callable) -> Dictionary:
	var move: Vector3 = at.at + (to.origin - from.origin) * gain
	return {"at": Vector3(move.x, height.call(move.x, move.z), move.z), "yaw": wrapf(at.yaw + turned(from, to), -PI, PI)}


## Shared with a hand already holding them, so a second grip joins it.
func _stair_grip(id: int) -> StairGrip:
	for m in masons:
		if m.growing is StairGrip and m.growing.id == id:
			return m.growing
	var grip := StairGrip.new()
	grip.id = id
	return grip


func _fitting_sizing(grip: FittingGrip, s: Sizing, in_hand: Callable) -> Sizing:
	if grip.decoration >= 0:
		return _decoration_grip(grip.decoration, s, in_hand)
	if grip.key == "clutter":
		return _clutter_sizing(grip, s, in_hand)
	var w := grip.wall
	var key := grip.key
	var stored := func() -> Array:
		if not is_instance_valid(w) or find(w.id) != w or not world.state.walls.has(w.id):
			return []
		var d: Dictionary = world.state.walls[w.id]
		return Array((d.roof if grip.on_roof else d)[key])
	var start: Variant = stored.call()[grip.index]
	var shown := {"value": start, "laid": start}
	var hold := {"from": start}
	var others := func() -> Array:
		var rest: Array = stored.call()
		rest.remove_at(grip.index)
		return rest
	var data := func(v: Variant) -> Dictionary:
		var placed: Array = stored.call()
		placed[grip.index] = v
		return FittingGrip.data(key, FittingGrip.packed(key, placed), grip.on_roof)
	var fits := func(v: Variant) -> bool:
		var rest: Array = others.call()
		return FittingGrip.fits(w, key, v, rest, standing_openings(w, rest) if key == "openings" else ([] as Array[Vector4]))
	var lay := func() -> void:
		if shown.value != shown.laid:
			shown.laid = shown.value
			_relay(w, data.call(shown.value))
	var current := func() -> bool:
		var now: Array = stored.call()
		return now.size() > grip.index and now[grip.index] == start
	s.current = current
	if key == "openings":
		s.scale = func() -> float: return shown.value.w
		s.limits = Vector2(WallLayout.MIN_SIZE, INF)
	s.show = func(size: float) -> void:
		if key == "openings":
			var at: Vector4 = shown.value
			if size > at.w:
				size = w.layout.largest_fit(at, standing_openings(w, others.call()), size)
			var sized := Vector4(at.x, at.y, at.z, size)
			if not is_nan(size) and not is_equal_approx(size, at.w) and fits.call(sized):
				shown.value = sized
		lay.call()
	s.take = func() -> void: hold.from = shown.value
	s.follow = func(m: Mason, hand: Transform3D) -> void:
		var by: Vector3 = FittingGrip.step((hand.origin - m.took.origin) * m.gain, 0.0)[0]
		var v: Variant = FittingGrip.moved(w, key, hold.from, by)
		if v != shown.value and fits.call(v):
			shown.value = v
		lay.call()
	s.command = func() -> Dictionary: return {} if shown.value == start else {"op": "reshape", "of": "walls", "id": w.id, "data": data.call(shown.value)}
	s.settle = func() -> void:
		if current.call() and not in_hand.call():
			show_reshaped(w.id)
	return s


## The build is laid once without held pieces, which stand apart, so a step moves only the piece's node.
func _clutter_sizing(grip: FittingGrip, s: Sizing, in_hand: Callable) -> Sizing:
	var of := "walls" if grip.path < 0 else "paths"
	var id: int = grip.wall.id if grip.path < 0 else grip.path
	var stood := func() -> bool: return world.state[of].has(id) and (grip.path >= 0 or is_instance_valid(grip.wall) and find(id) == grip.wall)
	var current := func() -> bool:
		if not stood.call():
			return false
		var list: PackedVector4Array = world.state[of][id].clutter
		return grip.copy or list.size() > grip.index and list[grip.index] == grip.start
	var hold := {"from": grip.start}
	var lay := func() -> void:
		if stood.call():
			_hold_clutter(grip, of, id)
	s.current = current
	s.show = func(_size: float) -> void: lay.call()
	s.take = func() -> void:
		hold.from = grip.shown
		if stood.call():
			_show_clutter(of, id)
		lay.call()
	s.follow = func(m: Mason, hand: Transform3D) -> void:
		if not stood.call():
			return
		var step: Array = FittingGrip.step((hand.origin - m.took.origin) * m.gain, turned(m.took, hand))
		var v := _carried_clutter(grip, hold.from, step[0], step[1])
		if v != grip.shown and _clutter_stands(grip, v):
			grip.shown = v
		lay.call()
	s.command = func() -> Dictionary:
		if not current.call() or grip.shown == grip.start:
			return {}
		return {"op": "reshape", "of": of, "id": id, "data": {"clutter": _clutter_with(of, id, [grip])}}
	s.settle = func() -> void:
		if not in_hand.call() and _held_clutter.has(grip):
			_held_clutter[grip].let_go = true
	return s


func _carried_clutter(grip: FittingGrip, from: Vector4, by: Vector3, turn: float) -> Vector4:
	if grip.path < 0:
		var l := grip.wall.layout
		var v := FittingGrip.shifted(from, l.frame_at(l.wrap(from.x)).tangent, by, turn, ClutterLayout.OUT.x, ClutterLayout.OUT.y)
		v.x = l.wrap(v.x)
		return v
	var path := paths.layout(grip.path)
	var f := path.frame_at(from.x)
	var v := FittingGrip.shifted(from, f.along, by, turn, f.half + ClutterLayout.OUT.x, f.half + ClutterLayout.PAST_PATH)
	v.x = clampf(v.x, 0.0, path.length())
	return v


func _clutter_stands(grip: FittingGrip, v: Vector4) -> bool:
	if grip.path < 0:
		return grip.wall.layout.clutter_frame(v, world.terrain.shown_at) != null
	var path := paths.layout(grip.path)
	return path != null and path.clutter_frame(v, world.terrain.height_at) != null


func _clutter_with(of: String, id: int, grips: Array) -> PackedVector4Array:
	var list := PackedVector4Array(world.state[of][id].clutter)
	var copies := PackedVector4Array()
	for g: FittingGrip in grips:
		if g.copy:
			copies.append(g.shown)
		elif g.index < list.size() and list[g.index] == g.start:
			list[g.index] = g.shown
	list.append_array(copies)
	return list


func _show_clutter(of: String, id: int) -> void:
	var garden: PackedVector4Array = world.state[of][id].clutter
	var grips := _clutter_grips(of, id)
	var carried := {}
	for g in grips:
		if not g.copy and g.index < garden.size() and garden[g.index] == g.start:
			carried[g.index] = true
	var list := PackedVector4Array()
	for i in garden.size():
		if not carried.has(i):
			list.append(garden[i])
	if of == "paths":
		paths.show_reshaped(id, {} if grips.is_empty() else {"clutter": list})
		return
	var w := find(id)
	if w == null:
		return
	var data := w.reshaped.duplicate()
	data.erase("clutter")
	if not grips.is_empty():
		data.clutter = list
	if PackedVector4Array(w.layout.clutter) != data.get("clutter", garden) or w.reshaped != data:
		_relay(w, data)


func _clutter_grips(of: String, id: int) -> Array[FittingGrip]:
	var out: Array[FittingGrip] = []
	for m in masons:
		var g: Variant = m.growing
		if g is FittingGrip and g.key == "clutter" and (g.path == id if of == "paths" else g.path < 0 and is_instance_valid(g.wall) and g.wall.id == id) and not out.has(g):
			out.append(g)
	return out


func _hold_clutter(grip: FittingGrip, of: String, id: int) -> void:
	var x: Variant = _clutter_place(grip, grip.shown)
	if not _held_clutter.has(grip):
		var seed: int = paths.layout(id).seed if of == "paths" else grip.wall.layout.seed
		var colours: PackedInt32Array = Palette.plain() if of == "paths" else grip.wall.paint
		var parts: Array[Dictionary] = []
		for part in ClutterLayout.parts(grip.shown, Transform3D.IDENTITY, seed):
			part.color = Wall._painted_as(part, colours)
			parts.append(part)
		var piece := Stones.new()
		piece.lay(parts)
		add_child(piece)
		_held_clutter[grip] = {"node": piece, "of": of, "id": id, "let_go": false, "shown": false}
	var node: Node3D = _held_clutter[grip].node
	# Until its build is drawn without it, the build still shows it where it was taken.
	node.visible = x != null and _clutter_drawn(of, id)
	if x != null:
		node.global_transform = x


func _clutter_drawn(of: String, id: int) -> bool:
	if of == "paths":
		return not paths.laying(id) and masonry.drawn(Masonry.build_owner(id))
	var w := find(id)
	return not w.laying() and masonry.drawn(w.get_instance_id())


func _clutter_place(grip: FittingGrip, v: Vector4) -> Variant:
	if grip.path >= 0:
		var path := paths.layout(grip.path)
		return null if path == null else path.clutter_frame(v, world.terrain.height_at)
	var x: Variant = grip.wall.layout.clutter_frame(v, world.terrain.shown_at)
	return null if x == null else grip.wall.global_transform * x


## Let go, a build is shown as the garden has it only once the garden applied the hand's edit, so it is laid once.
func _settle_clutter() -> void:
	for grip: FittingGrip in _held_clutter.keys():
		var e: Dictionary = _held_clutter[grip]
		var gone: bool = not world.state[e.of].has(e.id) or (e.of == "walls" and find(e.id) == null) or (e.of == "paths" and paths.layout(e.id) == null)
		if not gone and not (e.let_go and e.shown):
			_show_clutter(e.of, e.id)
			if e.let_go:
				e.shown = true
			else:
				_hold_clutter(grip, e.of, e.id)
		elif gone or _clutter_drawn(e.of, e.id):
			e.node.queue_free()
			_held_clutter.erase(grip)


func held_clutter_targets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for grip: FittingGrip in _held_clutter:
		var e: Dictionary = _held_clutter[grip]
		if e.let_go or not e.node.visible:
			continue
		var x: Transform3D = e.node.global_transform
		var box := ClutterLayout.bounds(grip.shown)
		var target := {"wall": null if grip.path >= 0 else grip.wall, "fitting": true, "what": "clutter", "key": "clutter", "index": grip.index, "value": grip.shown, "bounds": x * box, "box": box, "inverse": x.affine_inverse(), "on_roof": false}
		if grip.path >= 0:
			target.path = grip.path
		out.append(target)
	return out


func _decoration_grip(id: int, s: Sizing, in_hand: Callable) -> Sizing:
	var decorations := world.decorations
	var start: Dictionary = world.state.decorations[id].duplicate()
	var shown := {"d": start}
	var hold := {"from": start}
	var current := func() -> bool: return world.state.decorations.get(id) == start
	s.current = current
	s.take = func() -> void: hold.from = shown.d
	s.follow = func(m: Mason, hand: Transform3D) -> void:
		var step: Array = FittingGrip.step((hand.origin - m.took.origin) * m.gain, turned(m.took, hand))
		var d := FittingGrip.carried(hold.from, find(start.wall), step[0], step[1])
		if d != shown.d and decorations.frame(d) != null:
			shown.d = d
			decorations.show_held(id, d)
	s.command = func() -> Dictionary:
		var d: Dictionary = shown.d
		var data := {"at": d.at, "turn": d.turn, "s": d.s}
		if d.has("to"):
			data.to = d.to
		return {} if d == start else {"op": "reshape", "of": "decorations", "id": id, "data": data}
	s.settle = func() -> void:
		if not in_hand.call():
			decorations.show_reshaped(id)
	return s


func _fitting_grip(pick: Dictionary) -> FittingGrip:
	var grip := FittingGrip.new()
	if not pick.has("decoration"):
		grip.wall = pick.wall
		grip.path = pick.get("path", -1)
		grip.key = pick.key
	for m in masons:
		var g: Variant = m.growing
		if g is FittingGrip and g.beside(grip) and g.shown == pick.value:
			grip.copy = true
			grip.start = g.shown
			grip.shown = g.shown
			return grip
		if g is FittingGrip and (g.decoration == pick.decoration if pick.has("decoration") else g.wall == pick.wall and g.path == grip.path and g.key == pick.key and g.key != "clutter" and g.index == pick.index and g.on_roof == pick.on_roof):
			return g if g.sized() else null
	if pick.has("decoration"):
		grip.decoration = pick.decoration
		return grip
	var d: Dictionary = world.state.paths[grip.path] if grip.path >= 0 else world.state.walls[pick.wall.id]
	grip.on_roof = pick.on_roof
	grip.index = Array((d.roof if pick.on_roof else d)[pick.key]).find(pick.value)
	grip.start = pick.value if grip.key == "clutter" else Vector4()
	grip.shown = grip.start
	return grip if grip.index >= 0 else null


func standing_openings(w: Wall, own: Array) -> Array[Vector4]:
	var shown := w.layout.openings.duplicate()
	w.layout.openings.assign(own)
	for p in paths.layouts:
		_cut_meetings(w, p.meetings(w.layout))
	var standing := w.layout.openings.duplicate()
	w.layout.openings = shown
	return standing


## Laid through the reshape's own path, so what a tool shows of an edit is what the edit builds.
func show_reshaped(id: int, data := {}) -> void:
	var w := find(id)
	if w == null or _held(w):
		return
	if data.keys() == ["paint"]:
		w.repaint(World.reshaped(world.state.walls[id], data).paint)
	else:
		_relay(w, data)


func _relay(w: Wall, data := {}) -> void:
	w.due = Callable()
	var d := World.reshaped(world.state.walls[w.id], data)
	w.set_data(d)
	w.reshaped = data
	_settle(w)
	_open_paths(w, d.openings)
	w.rebuild()


func _open_paths(w: Wall, own: Variant = null) -> void:
	w.layout.openings.assign(Array(w.reshaped.get("openings", world.state.walls[w.id].openings) if own == null else own))
	for p in paths.layouts:
		_cut_meetings(w, p.meetings(w.layout))
	_path_openings[w.id] = w.layout.openings.duplicate()
	for p in paths.previews:
		_cut_meetings(w, p.meetings(w.layout))


## Searches only cells each path shares with a wall, so a long stroke costs its crossings, not length times walls.
func _preview_crossings() -> void:
	var walls_at := walls_by_cell()
	var check: Array = walls
	var met := {}
	# Between relays of one stroke only the walls in the cells its moving end left or reached can change.
	var moved: Variant = paths.drawing.moved if paths.drawing != null else {}
	if walls_at_rev == _previewed_rev and paths.previews == _previewed_paths and moved != null:
		var near := {}
		for c in moved:
			for w: Wall in walls_at.get(c, []):
				near[w] = true
		check = near.keys()
		for w: Wall in check:
			met[w] = {}
			for p in paths.previews:
				var shared := p.shared_cells(w.layout)
				if not shared.is_empty():
					met[w][p] = shared
	else:
		for p in paths.previews:
			for c in p.segment_cells():
				for w: Wall in walls_at.get(c, []):
					met.get_or_add(w, {}).get_or_add(p, []).append(c)
	_previewed_rev = walls_at_rev
	_previewed_paths = paths.previews.duplicate()
	for w: Wall in check:
		if _held(w) or not _path_openings.has(w.id):
			continue
		var cut_from := [_path_openings[w.id]]
		var meeting: Dictionary = met.get(w, {})
		for p in meeting:
			cut_from.append_array([p, p.meetings(w.layout, meeting[p])])
		var last: Array = _previewed.get(w, [])
		if not last.is_empty() and is_same(last[0], w.layout.segment_cells()) and last[1] == cut_from:
			continue
		_previewed[w] = [w.layout.segment_cells(), cut_from]
		var before := w.layout.openings.duplicate()
		w.layout.openings.assign(_path_openings[w.id])
		for k in range(2, cut_from.size(), 2):
			_cut_meetings(w, cut_from[k])
		if before != w.layout.openings:
			w.rebuild()


func walls_by_cell() -> Dictionary:
	for w in _walls_at_from.keys():
		if not is_instance_valid(w) or w.is_queued_for_deletion():
			_unindex(w)
	for w in walls:
		var grid := w.layout.segment_cells()
		if not is_same(grid, _walls_at_from.get(w)):
			_unindex(w)
			_walls_at_from[w] = grid
			walls_at_rev += 1
			for c in grid:
				_walls_at.get_or_add(c, []).append(w)
	return _walls_at


func _unindex(w: Variant) -> void:
	if not _walls_at_from.has(w):
		return
	for c in _walls_at_from[w]:
		_walls_at[c].erase(w)
		if _walls_at[c].is_empty():
			_walls_at.erase(c)
	_walls_at_from.erase(w)
	walls_at_rev += 1


## Only the arches change, so the wall is not resampled.
func relay_crossings(path: PathLayout) -> void:
	var walls_at := walls_by_cell()
	var met := {}
	for c in path.segment_cells():
		for w: Wall in walls_at.get(c, []):
			met.get_or_add(w, []).append(c)
	var eye := get_viewport().get_camera_3d()
	var heard := Vector3.INF
	# A stroke laid after every other path, its ghost the only preview: a wall whose preview is cut from the paths laid
	# as they stand already shows the arches this lays, cut last as it would be.
	var ghost: PathLayout = null
	if paths.previews.size() == 1 and not paths.layouts.is_empty() and paths.layouts[-1] == path and paths.previews[0].same_stroke(path):
		ghost = paths.previews[0]
	for w in walls:
		if not met.has(w) or _held(w):
			continue
		var last: Array = _previewed.get(w, [])
		if ghost != null and not last.is_empty() and is_same(last[0], w.layout.segment_cells()) and last[1].size() == 3 and last[1][1] == ghost and last[1][0] == _path_openings[w.id]:
			if last[1][2].is_empty():
				continue
			_path_openings[w.id] = w.layout.openings.duplicate()
		elif not path.meetings(w.layout, met[w]).is_empty():
			var before := w.layout.openings.duplicate()
			_open_paths(w)
			if before != w.layout.openings:
				w.rebuild()
		else:
			continue
		var top := _top(w)
		if eye == null or heard == Vector3.INF or top.distance_to(eye.global_position) < heard.distance_to(eye.global_position):
			heard = top
	# One cue for the walls a path crosses, from the nearest: a voice each would cost a frame and drown one another.
	if heard != Vector3.INF:
		_sound(Cues.Act.ARCH, heard)


## An arch that would overlap one already there stands a pitch from it as an arcade, so no opening closes.
func _cut_meetings(w: Wall, meetings: Array[Dictionary]) -> void:
	var layout := w.layout
	if layout.floored():
		for m in meetings:
			for door in layout.path_doors(layout.wrap(m.s), m.span, layout.openings):
				layout.openings.append(door)
		return
	if not layout.can_arch():
		return
	var placed := layout.openings.duplicate()
	for a in PathLayout.arches(meetings):
		a = layout.wrap(a)
		var past := INF
		var size := 1.0
		for e in placed:
			if absf(layout.offset(a, e.x)) < absf(past):
				past = layout.offset(a, e.x)
				size = e.w
		if absf(past) < WallLayout.ARCH_HALF * size:
			continue
		# Beside an opening of `size`, a doorway arch stands as far from it as the pair's halves and rings reach.
		var pair := (1.0 + size) * 0.5
		var tries := [a]
		if absf(past) < WallLayout.ARCH_SPACING * pair:
			var side := signf(past) * WallLayout.ARCADE_PITCH * pair
			tries = [layout.wrap(a - past + side), layout.wrap(a - past - side)]
		for t in tries:
			if placed.size() < Commands.MAX_FITTINGS and layout.opening_fits(WallLayout.archway(t), placed):
				placed.append(WallLayout.archway(t))
				layout.openings.append(WallLayout.archway(t))
				break


func _sound(act: Cues.Act, at: Vector3, hand: Hand = null) -> void:
	if not quiet:
		Cues.play(act, at, hand)


func _cue(act: Cues.Act, at: Vector3, hands: Array, tension := 0.0) -> void:
	built.emit()
	Cues.play_in(act, at, hands, tension)


## `handed` when it is the next of this player's walls in hand.
func put(id: int, handed: bool) -> void:
	var w := _new_wall()
	w.id = id
	w.finished = true
	walls.append(w)
	if handed and not _handing.is_empty():
		w.stand_in(_handing.pop_front())
	_relay(w)
	_sound(Cues.Act.WALL_SETTLE, _top(w), _handing_hand if handed else null)


func _let_go_handed() -> void:
	for w in _handing:
		w.queue_free()
	_handing.clear()


func clear() -> void:
	for w in walls.duplicate():
		take(w.id)


func take(id: int) -> void:
	_path_openings.erase(id)
	var w := find(id)
	_previewed.erase(w)
	if w == held:
		held = null
		_holders.clear()
		_riders.clear()
	_riders.erase(w)
	_settling.erase(id)
	_sound(Cues.Act.WALL_CRUMBLE, _top(w))
	walls.erase(w)
	_stir(w, w.massing)
	w.queue_free()


## A held wall catches up when let go. Laid in its turn (`Wall.due`), so a house with a storey lays over frames.
func restyle(id: int, changed: Array) -> void:
	var w := find(id)
	if changed == ["paint"]:
		w.repaint(world.state.walls[id].paint)
		return
	if _held(w):
		return
	w.set_data(World.reshaped(world.state.walls[id], {}))
	w.due = _lay_again.bind(w, [] if quiet else changed)


func _restyle_sound(w: Wall, changed: Array) -> void:
	if "ruins" in changed:
		_sound(Cues.Act.WALL_CRUMBLE, _top(w))
	elif "openings" in changed:
		_sound(Cues.Act.ARCH, _top(w))
	elif "roof" in changed or "gable_end" in changed:
		_sound(Cues.Act.WALL_LAY, _ridge(w))
	else:
		_sound(Cues.Act.WALL_RESTYLE, _top(w))


func find(id: int) -> Wall:
	for w in walls:
		if w.id == id:
			return w
	return null


func _held(w: Wall) -> bool:
	if w != null and (w == held or _riders.has(w)):
		return true
	for m in masons:
		if m.growing is FittingGrip and m.growing.wall == w:
			return true
	return false


## Ivy waits for `settled`. Sorted by id, a build comes after those it stands on: laid before them, a house on a build
## the ground fell away under hangs a plinth from the old top.
func reground(area: Rect2, settled: bool) -> void:
	var order := walls.duplicate()
	order.sort_custom(func(a: Wall, b: Wall) -> bool: return a.id < b.id)
	var moved := {}
	var tops := {}
	var height := world.terrain.held_height(true)
	var water := world.terrain.held_water(true)
	for w: Wall in order:
		if not w.footprint().intersects(area) and not Array(w.on).any(func(o: int) -> bool: return moved.has(o)):
			continue
		moved[w.id] = w
		if not _held(w):
			if settled and w.massing != null and walls.any(func(o: Wall) -> bool: return _meets(w, o, w.massing)):
				_settle(w)
			elif not settled and not w.on.is_empty():
				w.layout.supports = _shown_tops(w.on, moved, tops, height, water)
		w.rebuild(settled)


func _shown_tops(on: PackedInt32Array, moved: Dictionary, tops: Dictionary, height: Callable, water: Callable) -> Array[Massing]:
	var out: Array[Massing] = []
	for id in on:
		if moved.has(id) and not tops.has(id):
			var under: Wall = moved[id]
			var shown := under.layout.inputs()
			shown.resample(height, water)
			tops[id] = Massing.of(shown, under.roof)
		var o := find(id)
		var top: Massing = tops.get(id, o.massing if o != null else null)
		if top != null:
			out.append(top)
	return out


func _top(w: Wall) -> Vector3:
	return w.layout.point_at(w.layout.length() * 0.5) + Vector3.UP * w.layout.height


func _ridge(w: Wall) -> Vector3:
	var mid := Vector3.ZERO
	for p in w.layout.points:
		mid += p
	return mid / w.layout.points.size() + Vector3.UP * (w.layout.height + w.roof.pitch)


## Every building tool takes the first surface hit, then decides what it allows. `through_arches` is for the teleport
## and decorations placed beyond an arch.
func pick_building(origin: Vector3, dir: Vector3, with_held := false, through_arches := false) -> Dictionary:
	var best := {}
	for w in walls:
		if _held(w) and not with_held:
			continue
		if w.pick_bounds.grow(WALL_PICK).intersects_ray(origin, dir) != null:
			var hit := w.ray_hit(origin, dir, through_arches)
			if not hit.is_empty() and hit.along < best.get("along", INF):
				best = hit
				best.wall = w
				best.surface = "wall"
		if w.roof != null:
			for surface in ["roof", "gable"]:
				var t := w.roof.ray_hit(origin, dir) if surface == "roof" else w.roof.gable_hit(origin, dir)
				if t < best.get("along", INF):
					var point := origin + dir * t
					best = {"wall": w, "surface": surface, "along": t, "point": point, "s": w.layout.closest_s(point), "distance": 0.0, "side": surface == "gable"}
	return best


func pick_floor(origin: Vector3, dir: Vector3) -> Dictionary:
	var best := {}
	for w in walls:
		if w.roof == null or _held(w):
			continue
		var t := w.layout.floor_hit(origin, dir)
		if t < best.get("along", INF):
			best = {"wall": w, "along": t, "point": origin + dir * t}
	return best


func floor_under(p: Vector3) -> float:
	var y := world.terrain.shown_at(p.x, p.z)
	for w in walls:
		if _held(w):
			continue
		y = maxf(y, w.layout.walk_under(p))
		if w.roof != null:
			y = maxf(y, maxf(w.roof.deck_under(p), w.layout.floor_under(p)))
	return y


## A pitched roof counts as its house's top: what is built there stands on the walls under it.
func aim(origin: Vector3, dir: Vector3) -> Dictionary:
	var ground: Variant = world.terrain.raycast(origin, dir)
	var best := {} if ground == null else {"point": ground, "on": -1, "along": origin.distance_to(ground)}
	for w in walls:
		if _held(w) or w.massing == null or w.layout.fence:
			continue
		var t := _top_hit(w, origin, dir)
		if t < best.get("along", INF):
			best = {"point": origin + dir * t, "on": w.id, "along": t}
	return best


func _top_hit(w: Wall, origin: Vector3, dir: Vector3) -> float:
	if w.roof != null and not w.roof.flat():
		return minf(w.roof.ray_hit(origin, dir), w.roof.gable_hit(origin, dir))
	if dir.y > -1e-3:
		return INF
	var top := w.massing.feet[0] + w.massing.rise
	if not w.layout.closed:
		if w.pick_bounds.grow(WALL_PICK).intersects_ray(origin, dir) == null:
			return INF
		top = w.layout.point_at(w.ray_distance(origin, dir).s).y + w.layout.height + WallLayout.CAP
	var hit := _at_level(origin, dir, top)
	if hit.is_empty() or absf(w.massing.rest(hit.point.x, hit.point.z) - top) > TOP_BAND:
		return INF
	return origin.distance_to(hit.point)


static func _at_level(origin: Vector3, dir: Vector3, level: float) -> Dictionary:
	if dir.y > -1e-3 or origin.y < level:
		return {}
	return {"point": origin + dir * ((level - origin.y) / dir.y), "on": -1}


func _rest_on(st: Stroke, p: Vector3) -> void:
	for w in walls:
		if st.on.size() >= Commands.MAX_SUPPORTS:
			return
		if w.massing != null and not w.layout.fence and not st.on.has(w.id) and absf(w.massing.rest(p.x, p.z) - st.level) < TOP_BAND:
			st.on.append(w.id)
			st.plan.supports = _solids(st.on)
			st.planned = false


func _solids(ids: PackedInt32Array) -> Array[Massing]:
	var out: Array[Massing] = []
	for id in ids:
		var w := find(id)
		if w != null and w.massing != null:
			out.append(w.massing)
	return out


func _below(on: PackedInt32Array) -> Dictionary:
	var out := {}
	var todo := Array(on)
	while not todo.is_empty():
		var id: int = todo.pop_back()
		if out.has(id):
			continue
		out[id] = true
		var w := find(id)
		if w != null:
			todo.append_array(Array(w.on))
	return out


func _settle(w: Wall) -> void:
	_meet(w)
	w.layout.resample(world.terrain.height_at, world.terrain.water_at, world.terrain.revision())
	_reshaped(w)


func _meet(w: Wall) -> void:
	var supports: Array[Massing] = []
	var resting: Array[Massing] = []
	var joined: Array[Massing] = []
	var older: Array[Massing] = []
	var under := _below(w.on)
	var rect := _reach(w)
	for o in walls:
		if o == w or o.massing == null or not o.massing.rect.intersects(rect):
			continue
		if w.on.has(o.id):
			supports.append(o.massing)
		elif under.has(o.id):
			continue
		elif w.id >= 0 and _below(o.on).has(w.id):
			resting.append(o.massing)
		elif o.massing.closed:
			joined.append(o.massing)
			if w.id < 0 or o.id < w.id:
				older.append(o.massing)
	w.layout.supports = supports
	w.layout.resting = resting
	w.layout.joined = joined
	w.layout.older = older


static func _reach(w: Wall) -> Rect2:
	var r := Rect2(Vector2(w.layout.points[0].x, w.layout.points[0].z), Vector2.ZERO)
	for p in w.layout.points:
		r = r.expand(Vector2(p.x, p.z))
	return r.grow(WallLayout.THICKNESS + Massing.REACH + 0.5)


func _reshaped(w: Wall) -> void:
	var was := w.massing
	w.massing = Massing.of(w.layout, w.roof)
	if not w.massing.same(was):
		_stir(w, was)
		_stir(w, w.massing)


func _stir(w: Wall, s: Massing) -> void:
	if s == null:
		return
	for o in walls:
		if _meets(w, o, s) and not o.due.is_valid():
			o.due = _lay_again.bind(o, null)


func _related(a: Wall, b: Wall) -> bool:
	return a.massing.closed or b.massing.closed or _below(a.on).has(b.id) or _below(b.on).has(a.id)


func _meets(w: Wall, o: Wall, s: Massing) -> bool:
	return o != w and o.massing != null and o.massing.rect.intersects(s.rect) and _related(w, o)


## `changed` is null when laid again for what it meets, else the fields the garden changed.
func _lay_again(w: Wall, changed: Variant) -> void:
	if _held(w) or not world.state.walls.has(w.id):
		return
	_settle(w)
	if changed != null:
		_open_paths(w)
	w.rebuild()
	if changed != null and not changed.is_empty():
		_restyle_sound(w, changed)
