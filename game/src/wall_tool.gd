class_name WallTool
extends Node3D

## Walls, for whichever hand holds them: trigger draws a wall along the ground, a loop as much as a line,
## and a grip pointed at a wall, whatever the hand holds, pulls its height, at a roof its pitch and curvature, and at a
## tree or boulder its size, its top following the hand. Each hand grabs on its own, so two hands pull two walls, roofs, trees or boulders at once; a grip on one the other hand
## holds takes nothing. A hand holding the house or the tower takes hold of one with its trigger, where it points, and carries it; the
## other hand's grip, pressed while it is carried, joins in, whatever it points at, to turn it with the pair and stretch it
## along their span, a tower every way at once; letting go builds it. A built
## house held by one hand's grip takes the other's too, and the pair stretch its width or depth where it stands, and
## raised or lowered together raise it onto a plinth or set it back down. A path across a wall opens an arch where they cross,
## or an arcade where the crossing is wide: those arches follow from the paths standing, so they come and go
## with the path. A hand holding the fence draws fences the same way: posts and rails, a wooden arch where a
## path crosses. Every finished edit goes to the garden as a build command; this tool shows it until then.
## A hand points at the ground or at a build's top, and what it builds there stands on that build; builds that
## meet join (docs/design.md, "Buildings on buildings").

const POINT_SPACING := 0.45
const REBUILD_EVERY := 0.06
const WALL_PICK := 0.7
const TINT := Color(1.0, 0.97, 0.9, 0.55)
const HOUSE_HEIGHT := 2.4
const TOWER_HEIGHT := 4.5
const HOUSE_SIDE := 2.4
enum RoofStyle { PITCHED, FLAT, THATCHED }
enum RoofShape { FLAT, PITCHED }
const ROOF_OPTIONS := {
	RoofShape.FLAT: [RoofStyle.FLAT],
	RoofShape.PITCHED: [RoofStyle.PITCHED, RoofStyle.THATCHED],
}

const HOUSE_SIZE := Vector2(4.5, 4.5)
const TOWER_SIZE := Vector2(3.4, 3.4)
const HOUSE_REACH := 6.0
const TOP_BAND := 0.4
const ROOF_STEP := 0.1
## How far a carried house goes, in metres, between two scrapes.
const CARRY_STEP := 0.12

## Something was built, moved or pulled here: the music makes room.
signal built


## A thing a grip grows and shrinks, its top following the hand: how to read and show its scale, the range it may
## take, and the command that sets it in the garden.
class Sizing:
	var scale: Callable
	var top: Callable
	var limits: Vector2
	var current: Callable
	var show: Callable
	var command: Callable
	var settle: Callable


class Mason:
	var hand: Hand
	var buttons: Buttons
	var stroke: Stroke
	var lifting: Wall
	var roofing: Wall
	## What the grip is sizing (a tree's trunk or a boulder), how, and its top's height over the ground at its scale
	## `lift_start`.
	var growing: Object
	var sizing: Sizing
	var grow_top := 0.0
	var lift_start := 0.0
	var curve_start := 0.0
	var lift_hand := Vector3.ZERO
	var lift_gain := 1.0
	var lift_at := Vector3.ZERO
	var lift_side := Vector3.RIGHT
	var pick := {}
	## The gable end the hand points at before any roof, as `pick_building` gives it.
	var gable := {}
	## Where the hand points to build, and the id of the build it points at, or -1 on the ground.
	var ground: Variant = null
	var on := -1


## A stroke being drawn and the walls it builds, shown as it grows and kept on release.
class Stroke:
	var points: Array[Vector3] = []
	var plan: WallPlan
	var walls: Array[Wall] = []
	var planned := false
	## The builds it stands on, and the height of the top it is drawn on, or NAN on the ground.
	var on := PackedInt32Array()
	var level := NAN


var rig: Rig
var world: World
var flora: Flora
var paths: Paths
var masonry := Masonry.new(Wall.kinds())
var walls: Array[Wall] = []
## The paint new builds are laid in: the swatch last picked on this machine for each material (PaletteTool).
var paint := Palette.plain()
## The gable ends new houses are laid with: the style last turned to on this machine.
var gable_end := WallLayout.GableEnd.WALL
## Whether new walls and houses are laid in plaster: the face last turned to on this machine.
var plaster := false
var timber_style := 0
## Whether new houses are thatched: the roof last turned to on this machine.
var thatch := false
## Whether new houses and towers are floored at every storey: the floor last turned to on this machine.
var storey_floors := false
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
## A built house held by two grips: the hands, their poses when they took it, its footprint and garden data then,
## and the footprint it has now.
var resizing: Wall
var _resize_hands: Array[Mason] = []
var _resize_from: Array[Transform3D] = []
var _resize_start := {}
var _resize_data := {}
var resized_to := {}
var _resize_step := 0
## How far the house rises for each metre both hands rise; 0 for one standing on a build, which stays on its top.
var _resize_gain := 0.0
## True while the garden is swapped wholesale: walls come and go without a sound.
var quiet := false
var _since_rebuild := 0.0
var _dirty := false
## Ids of builds to lay again at the end of the frame for what they meet.
var _due := {}
var _path_openings := {}
var _walls_at := {}
var _walls_at_from: Array = []
## Wall → the segment grid and inputs its preview arches were last cut from: a wall the stroke's moving end is not
## near keeps them.
var _previewed := {}
## The walls in hand of this player's command that last came back, for the garden's walls it puts up (`put`).
var _handing: Array[Wall] = []
var _handing_hand: Hand
## How far the house in hand has been carried since its last scrape.
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
		m.buttons = Buttons.new(h).watch(["tool", "grab"])
		masons.append(m)


static func draws(hand: Hand) -> bool:
	return hand.tool in [Hand.Tool.WALLS, Hand.Tool.FENCE]


func mason(hand: Hand) -> Mason:
	for m in masons:
		if m.hand == hand:
			return m
	return null


## Whether `hand`, or with none any hand, has an edit under way.
func busy(hand: Hand = null) -> bool:
	if house != null and hand == null:
		return true
	for m in masons:
		if (hand == null or m.hand == hand) and (m.stroke != null or m.lifting != null or m.roofing != null or m.growing != null or m in _holders or m in _resize_hands):
			return true
	return false


func _process(delta: float) -> void:
	_let_go_handed()
	for m in masons:
		_handle(m)
	_house_input()
	if house != null:
		_carry_laid()
	if resizing != null:
		_hands_resize()
	for m in _holders:
		m.hand.hold()
	_since_rebuild += delta
	if _dirty and _since_rebuild >= REBUILD_EVERY:
		_flush()
	_relay_due()
	for m in masons:
		if m.lifting != null or m.roofing != null or m.growing != null or m in _resize_hands:
			m.hand.hold()
		_preview(m)
		m.buttons.latch()


func _handle(m: Mason) -> void:
	m.pick = {}
	m.gable = {}
	m.ground = null
	if rig.aim_hand == m.hand:
		_let_go(m)
		return
	if m.stroke != null and (not draws(m.hand) or m.buttons.released("tool")):
		end_stroke(m)
	if m.buttons.released("grab"):
		if m.lifting != null:
			end_lift(m)
		if m.roofing != null:
			end_roof(m)
		if m.growing != null:
			end_grow(m)
		if m in _resize_hands:
			end_resize(m.hand)
	if not m.hand.get_has_tracking_data():
		return
	var hand := m.hand.global_transform
	var origin := hand.origin
	var dir := -hand.basis.z
	if draws(m.hand):
		var aimed := aim(origin, dir) if m.stroke == null or is_nan(m.stroke.level) else _at_level(origin, dir, m.stroke.level)
		m.ground = aimed.get("point")
		m.on = aimed.get("on", -1)
		m.pick = pick_building(origin, dir)
		m.gable = m.pick if m.pick.get("surface") == "gable" else {}
		m.hand.point(m.ground if m.pick.is_empty() else m.pick.point, TINT)
		if m.buttons.pressed("tool") and m.ground != null and not busy(m.hand):
			begin_stroke(m, m.ground, m.on)
		elif m.buttons.held("tool") and m.stroke != null and m.ground != null:
			extend_stroke(m, m.ground)

	if m.buttons.pressed("grab") and house == null and not busy(m.hand):
		var pick := pick_building(origin, dir, true)
		var roof := pick if pick.get("surface") == "roof" else {}
		var ground: Variant = Terrain.raycast(origin, dir)
		var nearest: float = origin.distance_to(ground) if ground != null else INF
		var tree := flora.solid_hit(origin, dir, nearest)
		var trunk: Flora.Plant = tree.plants[0] if not tree.is_empty() and tree.plants[0].pool == flora.trunks else null
		var rock := world.boulders.pick(origin, dir, minf(nearest, minf(pick.get("along", INF), tree.get("along", INF)))) if world.boulders != null else {}
		if not rock.is_empty():
			if not masons.any(func(o: Mason) -> bool: return o.growing == rock.boulder):
				begin_grow(m, rock.boulder, origin, rock.point)
		elif trunk != null and tree.along < pick.get("along", INF):
			if not masons.any(func(o: Mason) -> bool: return o.growing == trunk):
				begin_grow(m, trunk, origin, tree.point)
		elif not roof.is_empty() and roof.along < nearest:
			if _held(roof.wall):
				_join(m, roof.wall)
			else:
				begin_roof(m, roof.wall, origin)
		elif not pick.is_empty() and pick.along < nearest and not pick.wall.layout.fence:
			if _held(pick.wall):
				_join(m, pick.wall)
			else:
				begin_lift(m, pick.wall, origin, pick.point)
	elif m.buttons.held("grab") and m.lifting != null:
		drag_lift(m, origin.y)
	elif m.buttons.held("grab") and m.roofing != null:
		drag_roof(m, origin)
	elif m.buttons.held("grab") and m.growing != null:
		drag_grow(m, origin.y)


## Shows the bar what the edit in `m`'s hand would add.
func _preview(m: Mason) -> void:
	var change := {}
	if m.stroke != null:
		for w in m.stroke.walls:
			Budget.add(change, Budget.wall(w.data()))
	elif m.lifting != null:
		change = world.change_of({"op": "reshape", "of": "walls", "id": m.lifting.id, "data": {"height": m.lifting.layout.height}})
	elif m.roofing != null:
		change = world.change_of({"op": "reshape", "of": "walls", "id": m.roofing.id, "data": {"roof": {"pitch": m.roofing.roof.pitch}}})
	elif m.growing != null and m.sizing.current.call():
		change = world.change_of(m.sizing.command.call(m.sizing.scale.call()))
	elif m in _holders and house != null:
		change = Budget.wall(house.data())
	elif not _resize_hands.is_empty() and m == _resize_hands[0]:
		change = world.change_of({"op": "reshape", "of": "walls", "id": resizing.id, "data": reshape_house(_resize_data, resized_to)})
	if not change.is_empty():
		world.preview(m.hand, change)


func _let_go(m: Mason) -> void:
	if m.stroke != null:
		end_stroke(m)
	if m.lifting != null:
		end_lift(m)
	if m.roofing != null:
		end_roof(m)
	if m.growing != null:
		end_grow(m)
	if m in _resize_hands:
		end_resize(m.hand)


func _flush() -> void:
	for m in masons:
		if m.stroke != null:
			_plan(m.stroke)
			for w in m.stroke.walls:
				w.rebuild(false)
		if m.lifting != null:
			m.lifting.rebuild(false)
		if m.roofing != null:
			m.roofing.rebuild(false)
	if resizing != null:
		resizing.rebuild(false)
	if house != null and _house_dirty:
		house.rebuild(false)
		_house_dirty = false
	_dirty = false
	_since_rebuild = 0.0


func _new_wall() -> Wall:
	return _add_wall(Wall.new(randi(), masonry))


func _add_wall(w: Wall) -> Wall:
	w.paint = paint.duplicate()
	get_parent().add_child(w)
	return w


## A stroke from `p`, on the build `on` (-1 the ground): one begun on a build's top is drawn on that top's level,
## merging only with walls standing on that build as a stroke on the ground merges with walls on the ground.
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
	m.stroke.plan.plaster = plaster and not m.stroke.plan.fence
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


func _plan(st: Stroke) -> void:
	if st.planned:
		return
	st.planned = true
	var layouts := st.plan.pieces(st.points, Terrain.height_at)
	while st.walls.size() > layouts.size():
		st.walls.pop_back().queue_free()
	for i in layouts.size():
		if i == st.walls.size():
			st.walls.append(_add_wall(Wall.new(layouts[i].seed, masonry)))
		st.walls[i].layout = layouts[i]
		st.walls[i].on = st.on
		_meet(st.walls[i])


func end_stroke(m: Mason) -> void:
	_plan(m.stroke)
	var built_walls := m.stroke.walls
	m.stroke = null
	if not built_walls.is_empty():
		_finish(built_walls, m.hand)


## Sends a stroke's walls to the garden as one step; they stand as drawn until the garden's walls they become
## are laid.
func _finish(ws: Array[Wall], hand: Hand = null) -> void:
	world.submit({"op": "wall", "walls": ws.map(func(w: Wall) -> Dictionary: return w.data())}, func() -> void:
		_let_go_handed()
		_handing = ws
		_handing_hand = hand, hand)


## The garden is being swapped: walls in hand belong to the old one.
func _forget() -> void:
	_let_go_handed()
	_path_openings.clear()
	_previewed.clear()
	for m in masons:
		if m.stroke != null:
			for w in m.stroke.walls:
				w.queue_free()
		m.stroke = null
		m.lifting = null
		m.roofing = null
		m.growing = null
	if house != null:
		house.queue_free()
		house = null
		_holders.clear()
	_due.clear()


## Who holds the house: a hand holding the house tool by its trigger takes it up, and once it is up the other
## hand's grip holds it too. Each change of hands starts the carry afresh from where the house stands.
func _house_input() -> void:
	var holders: Array[Mason] = []
	var starting := false
	for m in masons:
		if not m.hand.tool in [Hand.Tool.HOUSE, Hand.Tool.TOWER] or rig.aim_hand == m.hand or not m.hand.get_has_tracking_data():
			continue
		if m.buttons.held("tool"):
			holders.append(m)
			starting = starting or m.buttons.pressed("tool")
		elif house == null:
			m.hand.point(aim(m.hand.global_position, -m.hand.global_basis.z).get("point"), TINT)
	if house == null and (not starting or holders.any(func(m: Mason) -> bool: return busy(m.hand))):
		return
	for m in masons:
		var gripping := m.buttons.pressed("grab") or (m in _holders and m.buttons.held("grab"))
		if not m in holders and gripping and m.hand.get_has_tracking_data() and m.stroke == null and m.lifting == null and m.roofing == null:
			holders.append(m)
	if house == null:
		var lead := holders[0].hand
		var aimed := aim(lead.global_position, -lead.global_basis.z)
		var at: Variant = aimed.get("point")
		if at == null:
			var ahead := -rig.head.global_basis.z
			ahead.y = 0.0
			at = Terrain.ground(rig.head.global_position.x + ahead.normalized().x * HOUSE_REACH, rig.head.global_position.z + ahead.normalized().z * HOUSE_REACH)
		var on := aimed.get("on", -1) as int
		begin_house(at, angle(rig.head.global_basis.x), PackedInt32Array([on]) if on >= 0 else PackedInt32Array(), lead.tool == Hand.Tool.TOWER)
		Cues.play(Cues.Act.HOUSE_TAKE, house_at.center, lead)
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
	if not to.center.is_equal_approx(house_at.center) or not is_equal_approx(to.yaw, house_at.yaw) or not to.size.is_equal_approx(house_at.size) or to.rise != house_at.rise:
		var stretched: bool = not to.size.is_equal_approx(house_at.size)
		_carried += to.center.distance_to(house_at.center) + absf(angle_difference(to.yaw, house_at.yaw)) * to.size.x * 0.5
		place_house(to.center, to.yaw, to.size, to.rise)
		if stretched:
			_cue(Cues.Act.HOUSE_STRETCH, to.center, _hands_of(holders), Cues.stretch(_hold_start.size.length(), to.size.length()))
		elif _carried > CARRY_STEP:
			_carried = 0.0
			_cue(Cues.Act.HOUSE_MOVE, to.center, _hands_of(holders))


## A square house, or a round tower under a cone, standing at `at`, its front square to `yaw`, until it is placed and let go.
func begin_house(at: Vector3, yaw: float, on := PackedInt32Array(), round := false) -> void:
	house = _new_wall()
	house.on = on
	house.layout.plaster = plaster and not round
	house.layout.timber_style = timber_style
	house.layout.storey_floors = storey_floors
	house.layout.gable_end = gable_end
	house.layout.closed = true
	house.layout.top = WallLayout.Top.CAP
	house.layout.height = TOWER_HEIGHT if round else HOUSE_HEIGHT
	var roof := RoofLayout.new()
	roof.kind = RoofLayout.Kind.CONE if round else RoofLayout.Kind.GABLE
	roof.seed = house.layout.seed
	roof.thatch = thatch
	house.add_roof(roof)
	_holders.clear()
	_laid_at.clear()
	house_at = {"round": round, "rise": 0.0, "grounded": on.is_empty()}
	place_house(at, yaw, TOWER_SIZE if round else HOUSE_SIZE)


## Moving, turning or raising the house carries the stones laid as they are, walls, roof and all; a new size or plinth lays them again.
func place_house(at: Vector3, yaw: float, size: Vector2, rise := 0.0) -> void:
	var resized: bool = not house_at.has("size") or not size.is_equal_approx(house_at.size) or rise != house_at.rise
	house_at.center = Terrain.ground(at.x, at.z)
	house_at.yaw = yaw
	house_at.size = size
	house_at.rise = rise
	if resized:
		_lay_house()


func _lay_house() -> void:
	var outline := WallTool.outline(house_at)
	house.layout.points = outline
	house.layout.rise = house_at.rise
	house.roof.pitch = pitch_for(house_at)
	house.roof.center = house_at.center
	house.roof.radius = house_at.size.x * 0.5
	_meet(house)
	_laid_at.append({"points": outline, "center": house_at.center, "yaw": house_at.yaw, "rise": house_at.rise})
	_house_dirty = true
	_dirty = true


func _carry_laid() -> void:
	var laid := house.layout.laid_points
	var i := _laid_at.find_custom(func(e: Dictionary) -> bool: return e.points == laid and e.rise == house.layout.laid_rise)
	if i < 0:
		return
	_laid_at = _laid_at.slice(i)
	var was: Dictionary = _laid_at[0]
	# A house on a build keeps that build's top as it is carried; on the ground it rides the ground.
	var lift: float = 0.0 if not house.on.is_empty() else _lowest(outline(house_at)) - _lowest(outline({"center": was.center, "yaw": was.yaw, "size": house_at.size, "round": house_at.round})) + house_at.rise - was.rise
	var from := Transform3D(Basis(Vector3.UP, was.yaw), Vector3(was.center.x, 0.0, was.center.z))
	var to := Transform3D(Basis(Vector3.UP, house_at.yaw), Vector3(house_at.center.x, lift, house_at.center.z))
	house.transform = to * from.affine_inverse()


static func _lowest(points: Array[Vector3]) -> float:
	var low := INF
	for c in points:
		low = minf(low, Terrain.height_at(c.x, c.z))
	return low


func end_house() -> void:
	if house_at.center != _laid_at[-1].center or house_at.yaw != _laid_at[-1].yaw:
		_lay_house()
	var w := house
	var hand: Hand = _holders[0].hand if not _holders.is_empty() else null
	house = null
	_holders.clear()
	_finish([w], hand)


static func footprint(center: Vector3, yaw: float, size: Vector2) -> Dictionary:
	var along := Vector3.RIGHT.rotated(Vector3.UP, yaw)
	return {"a": center - along * size.x * 0.5, "b": center + along * size.x * 0.5, "length": size.x, "depth": size.y}


## The wall line of a house standing at `at`: a circle `size.x` across if it is round, else its four corners.
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
	return ROOF_OPTIONS[RoofShape.FLAT if pitch <= 0.0 else RoofShape.PITCHED]


static func roof_style(d: Dictionary) -> RoofStyle:
	if d.roof.pitch <= 0.0:
		return RoofStyle.FLAT
	return RoofStyle.THATCHED if d.roof.thatch else RoofStyle.PITCHED


## Coverings never reshape the roof; a flat deck remembers the covering to use when pulled up.
static func restyle_roof(d: Dictionary, style: RoofStyle) -> Dictionary:
	if style not in roof_options(d.roof.pitch) or style == RoofStyle.FLAT:
		return {}
	return {"roof": {"thatch": style == RoofStyle.THATCHED}}


## Where a built house stands, as `outline` takes it, from its garden data; {} for a build that is no house or tower.
static func house_of(d: Dictionary) -> Dictionary:
	if not d.has("roof") or not d.closed:
		return {}
	if d.roof.kind == RoofLayout.Kind.CONE:
		return {"center": d.roof.center, "yaw": 0.0, "size": Vector2.ONE * d.roof.radius * 2.0, "round": true, "rise": d.rise}
	var p: PackedVector3Array = d.points
	if p.size() != 4:
		return {}
	return {"center": (p[0] + p[2]) * 0.5, "yaw": angle(p[1] - p[0]), "size": Vector2(_flat(p[1] - p[0]).length(), _flat(p[3] - p[0]).length()), "round": false, "rise": d.rise}


## The `reshape` that stands the house with garden data `d` as `to`: its wall line, every fitting and arch kept in
## proportion along its own wall, and its roof over the new walls with its slope and chimneys kept.
static func reshape_house(d: Dictionary, to: Dictionary) -> Dictionary:
	var from := house_of(d)
	var was: Array[Vector3] = []
	was.assign(Array(d.points))
	var now := outline(to)
	var moved := func(s: float) -> float: return _loop_s(now, _scaled(from, to, _loop_point(was, s)))
	var openings := PackedVector3Array()
	for w: Vector3 in d.openings:
		openings.append(Vector3(moved.call(w.x), w.y, w.z))
	var lanterns := PackedVector3Array()
	for l: Vector3 in d.lanterns:
		lanterns.append(Vector3(moved.call(l.x), l.y, l.z))
	var flags := PackedFloat32Array()
	for f: float in d.flags:
		flags.append(moved.call(f))
	var roof := {}
	if to.round:
		roof = {"center": to.center, "radius": to.size.x * 0.5, "pitch": d.roof.pitch * to.size.x / from.size.x}
	else:
		var chimneys := PackedVector2Array()
		var r0 := _ridge_of(from)
		var r1 := _ridge_of(to)
		for c: Vector2 in d.roof.chimneys:
			var o: Vector3 = _scaled(from, to, from.center + r0 * c.x + r0.cross(Vector3.UP) * c.y) - to.center
			chimneys.append(Vector2(o.dot(r1), o.dot(r1.cross(Vector3.UP))))
		roof = {"pitch": d.roof.pitch * to.size.y / from.size.y, "chimneys": chimneys}
	return {"points": PackedVector3Array(now), "rise": to.get("rise", from.rise), "openings": openings, "lanterns": lanterns, "flags": flags, "roof": roof}


static func _ridge_of(at: Dictionary) -> Vector3:
	var span := footprint(at.center, at.yaw, at.size)
	return _flat(span.b - span.a).normalized()


## Where point `p` on or by the house standing as `from` lies on it standing as `to`, side by side in proportion.
static func _scaled(from: Dictionary, to: Dictionary, p: Vector3) -> Vector3:
	var x := Vector3.RIGHT.rotated(Vector3.UP, from.yaw)
	var z := x.cross(Vector3.UP)
	var q := _flat(p - from.center)
	var k: Vector2 = to.size / from.size
	var tx := Vector3.RIGHT.rotated(Vector3.UP, to.yaw)
	return to.center + tx * q.dot(x) * k.x + tx.cross(Vector3.UP) * q.dot(z) * k.y


## The point `s` along a closed wall line, measured as `WallLayout` lays a loop.
static func _loop_point(points: Array[Vector3], s: float) -> Vector3:
	var n := points.size()
	var total := 0.0
	for i in n:
		total += _flat(points[(i + 1) % n] - points[i]).length()
	s = fposmod(s, total)
	for i in n:
		var a := points[i]
		var b := points[(i + 1) % n]
		var l := _flat(b - a).length()
		if s <= l:
			return a.lerp(b, s / maxf(l, 1e-6))
		s -= l
	return points[0]


## How far along a closed wall line its nearest point to `p` lies.
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


## Where a house held from `start` stands once the hands holding it move from poses `from` to `to`: one hand carries
## it and turns it with its own turn; two carry it by their midpoint, turn it with the line between them, and
## stretch it along that line by how far they spread, or a round one every way at once. `gain` scales the carry, so a far house keeps up.
## One on the ground rises as `lifted` has it.
static func carry(start: Dictionary, from: Array[Transform3D], to: Array[Transform3D], gain: float) -> Dictionary:
	var out := start.duplicate()
	out.rise = lifted(start.rise, from, to, gain if start.grounded else 0.0)
	if from.size() == 1:
		out.center = start.center + _flat(to[0].origin - from[0].origin) * gain
		out.yaw = start.yaw + angle_difference(angle(from[0].basis.x), angle(to[0].basis.x))
		return out
	var span0 := _flat(from[1].origin - from[0].origin)
	var span1 := _flat(to[1].origin - to[0].origin)
	out.center = start.center + _flat((to[0].origin + to[1].origin - from[0].origin - from[1].origin) * 0.5) * gain
	out.yaw = start.yaw + angle_difference(angle(span0), angle(span1))
	out.size = stretched(start, span0, span1.length() / maxf(span0.length(), 0.05))
	return out


static func stretched(start: Dictionary, span: Vector3, ratio: float) -> Vector2:
	if start.round:
		return Vector2.ONE * maxf(start.size.x * ratio, HOUSE_SIDE)
	var across: float = angle(span) - start.yaw
	var i := 0 if absf(cos(across)) >= absf(sin(across)) else 1
	var size: Vector2 = start.size
	size[i] = maxf(size[i] * ratio, HOUSE_SIDE)
	return size


## Where a built house held from `start` stands once two hands move from poses `from` to `to`: it keeps its place
## and turn and stretches as `stretched` has it, toward the hand that moved, so a hand held still keeps its wall.
## It rises as `lifted` has it.
static func resize(start: Dictionary, from: Array[Transform3D], to: Array[Transform3D], gain := 0.0) -> Dictionary:
	var out := start.duplicate()
	out.rise = lifted(start.rise, from, to, gain)
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
	return out


## How high above its ground a house raised `rise` stands once the hands holding it move from poses `from` to `to`:
## `gain` times as far as one hand rises, or as two rise together, the lesser of the two; a course at a time, from
## never below its ground. A `gain` of 0, for a house standing on a build, leaves it on that top.
static func lifted(rise: float, from: Array[Transform3D], to: Array[Transform3D], gain: float) -> float:
	var up := to[0].origin.y - from[0].origin.y
	if from.size() > 1:
		var other := to[1].origin.y - from[1].origin.y
		up = signf(up) * minf(absf(up), absf(other)) if signf(up) == signf(other) else 0.0
	return maxf(snappedf(rise + up * gain, WallLayout.COURSE), 0.0)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## The turn about the vertical that takes the x axis to `v`'s direction on the ground.
static func angle(v: Vector3) -> float:
	return atan2(-v.z, v.x)


## A grip on a build the other hand holds: on a house or tower it joins that hold to stretch it, and puts back
## what the first grip had pulled, so two hands change only its footprint; on anything else it takes nothing.
func _join(m: Mason, w: Wall) -> void:
	m.hand.hold()
	var first: Mason = null
	for o in masons:
		if o != m and (o.lifting == w or o.roofing == w):
			first = o
	if first == null or resizing != null or not world.state.walls.has(w.id) or house_of(world.state.walls[w.id]).is_empty():
		return
	first.lifting = null
	first.roofing = null
	begin_resize(w)
	_resize_hands = [first, m]
	_resize_from = [first.hand.global_transform, m.hand.global_transform]
	if w.on.is_empty():
		var mid := (_resize_from[0].origin + _resize_from[1].origin) * 0.5
		_resize_gain = Hand.reach_gain(mid.distance_to(_resize_start.center + Vector3.UP * w.layout.height * 0.5))


func _hands_resize() -> void:
	if _resize_hands.size() < 2:
		return
	var to: Array[Transform3D] = [_resize_hands[0].hand.global_transform, _resize_hands[1].hand.global_transform]
	drag_resize(resize(_resize_start, _resize_from, to, _resize_gain))


## Starts resizing built house `w` from the garden's copy of it, dropping any pull on it not yet sent.
func begin_resize(w: Wall) -> void:
	resizing = w
	_resize_hands.clear()
	_resize_data = world.state.walls[w.id].duplicate(true)
	_resize_start = house_of(_resize_data)
	resized_to = _resize_start
	_resize_gain = 0.0
	_resize_step = _steps(resized_to)
	w.set_data(_resize_data)
	_dirty = true


static func _steps(at: Dictionary) -> int:
	return roundi((at.size.x + at.size.y + at.rise) / WallLayout.COURSE)


## Shows the house being resized standing as `to`, with a stone sound every course it grows, shrinks, rises or sinks.
func drag_resize(to: Dictionary) -> void:
	if to.size.is_equal_approx(resized_to.size) and to.center.is_equal_approx(resized_to.center) and is_equal_approx(to.rise, resized_to.rise):
		return
	resized_to = to
	var d := _resize_data.duplicate(true)
	var change := reshape_house(_resize_data, to)
	for k in change:
		if k == "roof":
			d.roof.merge(change.roof, true)
		else:
			d[k] = change[k]
	resizing.set_data(d)
	_meet(resizing)
	_dirty = true
	var step := _steps(to)
	var top := resizing.layout.points[0] + Vector3.UP * resizing.layout.height
	var hands := _hands_of(_resize_hands)
	_cue(Cues.Act.WALL_STRETCH, top, hands, Cues.stretch(_steps(_resize_start), step))
	if step != _resize_step:
		_resize_step = step
		_cue(Cues.Act.WALL_LIFT, top, hands)


func end_resize(hand: Hand = null) -> void:
	var w := resizing
	resizing = null
	_resize_hands.clear()
	if resized_to.size.is_equal_approx(_resize_start.size) and is_equal_approx(resized_to.rise, _resize_start.rise):
		_relay(w)
	else:
		world.submit({"op": "reshape", "of": "walls", "id": w.id, "data": reshape_house(_resize_data, resized_to)}, settle.bind(w.id), hand)


func begin_lift(m: Mason, w: Wall, hand: Vector3, at: Vector3) -> void:
	m.lifting = w
	m.lift_start = w.layout.height
	m.lift_hand = hand
	m.lift_gain = Hand.reach_gain(hand.distance_to(at))
	m.lift_at = at


func drag_lift(m: Mason, hand_y: float) -> void:
	var h := maxf(m.lift_start + (hand_y - m.lift_hand.y) * m.lift_gain, WallLayout.MIN_HEIGHT)
	if not is_equal_approx(h, m.lifting.layout.height):
		var course := roundi(h / WallLayout.COURSE) != roundi(m.lifting.layout.height / WallLayout.COURSE)
		m.lifting.layout.height = h
		_dirty = true
		var at := Vector3(m.lift_at.x, Terrain.height_at(m.lift_at.x, m.lift_at.z) + h, m.lift_at.z)
		_cue(Cues.Act.WALL_STRETCH, at, [m.hand], Cues.stretch(m.lift_start, h))
		if course:
			_cue(Cues.Act.WALL_LIFT, at, [m.hand])


func end_lift(m: Mason) -> void:
	var w := m.lifting
	m.lifting = null
	if is_equal_approx(w.layout.height, m.lift_start):
		_relay(w)
	else:
		world.submit({"op": "reshape", "of": "walls", "id": w.id, "data": {"height": w.layout.height}}, settle.bind(w.id), m.hand)


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
	shape_roof(m.roofing, m.lift_start + move.y, m.curve_start + move.dot(m.lift_side) * 0.8, m.hand)


func shape_roof(w: Wall, pitch: float, curve: float, hand: Hand = null) -> void:
	var r := w.roof
	pitch = RoofLayout.snap_pitch(pitch, ROOF_STEP)
	curve = snappedf(clampf(curve, -RoofLayout.CURVE, RoofLayout.CURVE), ROOF_STEP)
	if is_equal_approx(pitch, r.pitch) and is_equal_approx(curve, r.curve):
		return
	r.pitch = pitch
	r.curve = curve
	_dirty = true
	_cue(Cues.Act.ROOF_FLAT if r.flat() else Cues.Act.ROOF_SHAPE, _ridge(w), [hand] if hand != null else [])


func end_roof(m: Mason) -> void:
	var w := m.roofing
	m.roofing = null
	if is_equal_approx(w.roof.pitch, m.lift_start) and is_equal_approx(w.roof.curve, m.curve_start):
		_relay(w)
	else:
		world.submit({"op": "reshape", "of": "walls", "id": w.id, "data": {"roof": {"pitch": w.roof.pitch, "curve": w.roof.curve}}}, settle.bind(w.id), m.hand)


## Grip on a tree or a boulder at `at`: the hand raised grows it and lowered shrinks it, its top rising and falling with
## the hand.
func begin_grow(m: Mason, target: Object, hand: Vector3, at: Vector3) -> void:
	m.growing = target
	m.sizing = _sizing(target)
	m.lift_start = m.sizing.scale.call()
	m.lift_hand = hand
	m.lift_at = at
	m.lift_gain = Hand.reach_gain(hand.distance_to(at))
	m.grow_top = m.sizing.top.call()


func drag_grow(m: Mason, hand_y: float) -> void:
	var s := m.sizing
	if not s.current.call():
		return
	var scale := clampf(snappedf(m.lift_start * (m.grow_top + (hand_y - m.lift_hand.y) * m.lift_gain) / m.grow_top, 0.01), s.limits.x, s.limits.y)
	if not is_equal_approx(scale, s.scale.call()):
		s.show.call(scale)
		_cue(Cues.Act.WALL_STRETCH, m.lift_at, [m.hand], Cues.stretch(m.lift_start, scale))


func end_grow(m: Mason) -> void:
	var s := m.sizing
	m.growing = null
	m.sizing = null
	if not s.current.call() or is_equal_approx(s.scale.call(), m.lift_start):
		s.settle.call()
	else:
		world.submit(s.command.call(s.scale.call()), s.settle, m.hand)


## How a grip sizes `target`, a tree's trunk or a boulder; either shows as the garden has it once its sizing has come
## back or been turned down, unless a hand holds it again.
func _sizing(target: Object) -> Sizing:
	var s := Sizing.new()
	var held := func() -> bool: return masons.any(func(o: Mason) -> bool: return o.growing == target)
	if target is Boulders.Boulder:
		var b: Boulders.Boulder = target
		var rocks := world.boulders
		var standing := func() -> bool: return is_instance_valid(b) and rocks.find(b.id) == b
		s.scale = func() -> float: return b.size
		s.top = b.top
		s.limits = BoulderLayout.SCALES
		s.current = standing
		s.show = func(scale: float) -> void: rocks.show_reshaped(b.id, {"scale": scale})
		s.command = func(scale: float) -> Dictionary: return {"op": "reshape", "of": "boulders", "id": b.id, "data": {"scale": scale}}
		s.settle = func() -> void:
			if standing.call() and not held.call():
				rocks.settle(b.id)
		return s
	var trunk: Flora.Plant = target
	s.scale = flora.scale_of.bind(trunk)
	s.top = flora.top_of.bind(trunk)
	s.limits = FloraLayout.SCALES
	s.current = trunk.current
	s.show = func(scale: float) -> void: flora.set_look(trunk, flora.species_of(trunk) as FloraLayout.Species, scale)
	s.command = func(scale: float) -> Dictionary: return {"op": "tree", "group": trunk.group, "index": trunk.index, "scale": scale}
	s.settle = func() -> void:
		var g: Dictionary = world.state.groups.get(trunk.group, {})
		if trunk.current() and not g.is_empty() and not held.call():
			flora.set_look(trunk, g.species.get(trunk.index, FloraLayout.Species.OAK), g.scale.get(trunk.index, 1.0))
	return s


## The openings in `w` with its stored placements and the paths standing, independent of its preview.
func standing_openings(w: Wall, own: Array) -> Array[Vector3]:
	var shown := w.layout.openings.duplicate()
	w.layout.openings.assign(own)
	for p in paths.layouts:
		_cut_crossings(w, p)
	var standing := w.layout.openings.duplicate()
	w.layout.openings = shown
	return standing


## A pulled height, roof or erased stretch shows as pulled until its command comes back, or goes back if it is
## turned down.
func settle(id: int) -> void:
	var w := find(id)
	if w != null and not _held(w):
		_relay(w)


## Lays a wall as a reshape with `data` would leave it, through the path that lays the reshape itself, so what a
## tool shows of an edit is what the edit builds; `settle` lays it as the garden has it again.
func show_reshaped(id: int, data: Dictionary) -> void:
	var w := find(id)
	if w == null or _held(w):
		return
	if data.keys() == ["paint"]:
		w.repaint(World.reshaped(world.state.walls[id], data).paint)
	else:
		_relay(w, data)


## Lays a wall as the garden has it, with `data` in place of its own fields, with the arches the paths standing open
## in it, on and among the builds it meets.
func _relay(w: Wall, data := {}) -> void:
	var d := World.reshaped(world.state.walls[w.id], data)
	w.set_data(d)
	w.reshaped = data
	_meet(w)
	w.layout.resample(Terrain.height_at, Terrain.water_at)
	_reshaped(w)
	_open_paths(w, d.openings)
	w.rebuild()


func _open_paths(w: Wall, own: Variant = null) -> void:
	w.layout.openings.assign(Array(w.reshaped.get("openings", world.state.walls[w.id].openings) if own == null else own))
	for p in paths.layouts:
		_cut_crossings(w, p)
	_path_openings[w.id] = w.layout.openings.duplicate()
	for p in paths.previews:
		_cut_crossings(w, p)


## Cuts the paths in hand into the walls, looking only in the grid cells each shares with a wall, so a long stroke
## over many walls costs what its crossings do rather than its length times the walls.
func _preview_crossings() -> void:
	var walls_at := _walls_by_cell()
	var met := {}
	for p in paths.previews:
		var cells := p.segment_cells()
		for c in cells:
			for w: Wall in walls_at.get(c, []):
				if not met.has(w):
					met[w] = {}
				if not met[w].has(p):
					met[w][p] = []
				met[w][p].append(c)
	for w in walls:
		if _held(w) or not _path_openings.has(w.id):
			continue
		var meeting: Dictionary = met.get(w, {})
		var cut_from := [_path_openings[w.id]]
		for p in meeting:
			cut_from.append_array([p, p.segments_in(meeting[p])])
		var last: Array = _previewed.get(w, [])
		if not last.is_empty() and is_same(last[0], w.layout.segment_cells()) and last[1] == cut_from:
			continue
		_previewed[w] = [w.layout.segment_cells(), cut_from]
		var before := w.layout.openings.duplicate()
		w.layout.openings.assign(_path_openings[w.id])
		for p in meeting:
			_cut_crossings(w, p, meeting[p])
		if before != w.layout.openings:
			w.rebuild()


## Grid cell → the walls whose samples reach it (WallLayout.segment_cells), made again once any wall's samples change.
func _walls_by_cell() -> Dictionary:
	var grids := walls.map(func(w: Wall) -> Dictionary: return w.layout.segment_cells())
	if grids.size() != _walls_at_from.size() or range(grids.size()).any(func(k: int) -> bool: return not is_same(grids[k], _walls_at_from[k])):
		_walls_at = {}
		for k in walls.size():
			for c in grids[k]:
				if not _walls_at.has(c):
					_walls_at[c] = []
				_walls_at[c].append(walls[k])
		_walls_at_from = grids
	return _walls_at


## Wall chemistry: a path laid or lifted opens or closes arches in every wall it crosses. Only the arches change, so the
## wall is not resampled.
func relay_crossings(path: PathLayout) -> void:
	for w in walls:
		if not path.crossings(w.layout).is_empty() and not _held(w):
			var before := w.layout.openings.duplicate()
			_open_paths(w)
			if before != w.layout.openings:
				w.rebuild()
			_sound(Cues.Act.ARCH, _top(w, w.layout.length() * 0.5))


## Adds the arches `path` makes in `w` and returns them. A crossing already inside an opening needs none; one whose ring
## would overlap an arch there stands a pitch from it as an arcade instead, on the crossing's side if that
## fits, else the other, so no opening closes.
func _cut_crossings(w: Wall, path: PathLayout, cells: Array = []) -> Array[float]:
	var opened: Array[float] = []
	var layout := w.layout
	if not layout.can_arch():
		return opened
	var placed := layout.openings.duplicate()
	for a in path.crossings(layout, cells):
		a = layout.wrap(a)
		var past := INF
		for e in placed:
			if absf(layout.offset(a, e.x)) < absf(past):
				past = layout.offset(a, e.x)
		if absf(past) < WallLayout.ARCH_HALF:
			continue
		var tries := [a]
		if absf(past) < WallLayout.ARCH_SPACING:
			var side := signf(past) * WallLayout.ARCADE_PITCH
			tries = [layout.wrap(a - past + side), layout.wrap(a - past - side)]
		for t in tries:
			if placed.size() < Commands.MAX_FITTINGS and layout.opening_fits(WallLayout.archway(t), placed):
				placed.append(WallLayout.archway(t))
				layout.openings.append(WallLayout.archway(t))
				opened.append(t)
				break
	return opened


func _sound(act: Cues.Act, at: Vector3, hand: Hand = null) -> void:
	if not quiet:
		Cues.play(act, at, hand)


func _cue(act: Cues.Act, at: Vector3, hands: Array, tension := 0.0) -> void:
	built.emit()
	Cues.play_in(act, at, hands, tension)


static func _hands_of(ms: Array[Mason]) -> Array:
	return ms.map(func(m: Mason) -> Hand: return m.hand)


## The garden's side of a wall going up, from any player; `handed` when it is the next of this player's walls in hand.
func put(id: int, handed: bool) -> void:
	var w := _new_wall()
	w.id = id
	w.finished = true
	walls.append(w)
	if handed and not _handing.is_empty():
		w.stand_in(_handing.pop_front())
	_relay(w)
	_sound(Cues.Act.WALL_SETTLE, _top(w, w.layout.length() * 0.5), _handing_hand if handed else null)


## Walls in hand whose command was turned down, or whose garden is gone.
func _let_go_handed() -> void:
	for w in _handing:
		w.queue_free()
	_handing.clear()


func take(id: int) -> void:
	_path_openings.erase(id)
	var w := find(id)
	_previewed.erase(w)
	if w == resizing:
		resizing = null
		_resize_hands.clear()
	for m in masons:
		if m.lifting == w:
			m.lifting = null
		if m.roofing == w:
			m.roofing = null
	_sound(Cues.Act.WALL_CRUMBLE, _top(w, w.layout.length() * 0.5))
	walls.erase(w)
	_stir(w, w.massing)
	w.queue_free()


## A wall someone here is pulling keeps following their hand; it catches up when they let go.
func restyle(id: int, changed: Array) -> void:
	var w := find(id)
	if changed == ["paint"]:
		w.repaint(world.state.walls[id].paint)
		return
	if _held(w):
		return
	_relay(w)
	if "ruins" in changed:
		_sound(Cues.Act.WALL_CRUMBLE, _top(w, w.layout.length() * 0.5))
	elif "openings" in changed:
		_sound(Cues.Act.ARCH, _top(w, w.layout.length() * 0.5))
	elif "roof" in changed or "gable_end" in changed:
		_sound(Cues.Act.WALL_LAY, _ridge(w))
	else:
		_sound(Cues.Act.WALL_RESTYLE, _top(w, w.layout.length() * 0.5))


func find(id: int) -> Wall:
	for w in walls:
		if w.id == id:
			return w
	return null


func _held(w: Wall) -> bool:
	if w != null and w == resizing:
		return true
	for m in masons:
		if m.lifting == w or m.roofing == w:
			return true
	return false


## Lays again every wall standing on ground that moved; ivy waits for `settled`.
func reground(area: Rect2, settled: bool) -> void:
	for w in walls:
		if w.footprint().intersects(area):
			w.rebuild(settled)
			if settled and not _held(w) and _meets_any(w):
				w.layout.resample(Terrain.height_at, Terrain.water_at)
				_reshaped(w)


func _top(w: Wall, s: float) -> Vector3:
	return w.layout.point_at(s) + Vector3.UP * w.layout.height


## Over the middle of a roofed wall's ring at its ridge, from what the garden holds of it, laid yet or not.
func _ridge(w: Wall) -> Vector3:
	var mid := Vector3.ZERO
	for p in w.layout.points:
		mid += p
	return mid / w.layout.points.size() + Vector3.UP * (w.layout.height + w.roof.pitch)


## All building tools select the first surface, before deciding what that surface allows.
## A held pick also sees builds another hand is pulling.
func pick_building(origin: Vector3, dir: Vector3, held := false) -> Dictionary:
	var best := {}
	for w in walls:
		if _held(w) and not held:
			continue
		if w.pick_bounds.grow(WALL_PICK).intersects_ray(origin, dir) != null:
			var hit := w.ray_hit(origin, dir)
			if not hit.is_empty() and hit.along < best.get("along", INF):
				best = hit
				best.wall = w
				best.surface = "wall"
		if w.roof != null:
			for surface in ["roof", "gable"]:
				var t := w.roof.ray_hit(origin, dir) if surface == "roof" else w.roof.gable_hit(origin, dir)
				if t < best.get("along", INF):
					var point := origin + dir * t
					best = {"wall": w, "surface": surface, "along": t, "point": point, "s": w.layout.closest_s(point), "distance": 0.0}
	return best


## The first building or plant surface along a teleport ray, short of reach.
func solid_hit(origin: Vector3, dir: Vector3, reach: float) -> Variant:
	var hit := pick_building(origin, dir)
	var best: float = minf(minf(reach, hit.get("along", INF)), pick_floor(origin, dir).get("along", INF))
	var plant := flora.solid_hit(origin, dir, best)
	if not plant.is_empty():
		best = plant.along
	return origin + dir * best if best < reach else null


## The nearest floor inside a house or tower along a ray, as {wall, along, point}, or empty.
func pick_floor(origin: Vector3, dir: Vector3) -> Dictionary:
	var best := {}
	for w in walls:
		if w.roof == null or _held(w):
			continue
		var t := w.layout.floor_hit(origin, dir)
		if t < best.get("along", INF):
			best = {"wall": w, "along": t, "point": origin + dir * t}
	return best


## What a point stands on: the ground under it, a house's or tower's floor, or a flat roof's deck at or below it.
func floor_under(p: Vector3) -> float:
	var y := Terrain.height_at(p.x, p.z)
	for w in walls:
		if w.roof != null and not _held(w):
			y = maxf(y, maxf(w.roof.deck_under(p), w.layout.floor_under(p)))
	return y


## What a ray from a walls hand builds on: the nearer of the ground and the top of a build, as {point, on}, `on`
## the build's id or -1 for the ground; {} for neither. A pitched roof counts as its house's top: what is built
## there stands on the walls under it, in the roof's place.
func aim(origin: Vector3, dir: Vector3) -> Dictionary:
	var ground: Variant = Terrain.raycast(origin, dir)
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
	var top := w.massing.feet[0] + w.massing.rise
	if not w.layout.closed:
		if w.pick_bounds.grow(WALL_PICK).intersects_ray(origin, dir) == null:
			return INF
		top = w.layout.point_at(w.ray_distance(origin, dir).s).y + w.layout.height + WallLayout.CAP
	var hit := _at_level(origin, dir, top)
	if hit.is_empty() or absf(w.massing.rest(hit.point.x, hit.point.z) - top) > TOP_BAND:
		return INF
	return origin.distance_to(hit.point)


## Where a ray meets the level a stroke on a build's top is drawn on.
static func _at_level(origin: Vector3, dir: Vector3, level: float) -> Dictionary:
	if dir.y > -1e-3 or origin.y < level:
		return {}
	return {"point": origin + dir * ((level - origin.y) / dir.y), "on": -1}


## A stroke drawn on a top also stands on every other build whose top it crosses at that level.
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


## The ids of every build under the builds `on`, all the way down.
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


## The builds `w` meets: those it stands on, those standing on it, and the houses and towers it joins.
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


## Takes the room `w` takes up as it now stands; if that changed, every build meeting it, before or after, is laid
## again at the end of the frame.
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
		if o != w and o.massing != null and o.massing.rect.intersects(s.rect) and _related(w, o):
			_due[o.id] = true


## Whether two builds meet: one stands on the other, or one of them is a house or tower they join.
func _related(a: Wall, b: Wall) -> bool:
	return a.massing.closed or b.massing.closed or _below(a.on).has(b.id) or _below(b.on).has(a.id)


func _meets_any(w: Wall) -> bool:
	for o in walls:
		if o != w and o.massing != null and w.massing != null and o.massing.rect.intersects(w.massing.rect) and _related(w, o):
			return true
	return false


## Lays again the builds due, oldest first, so each stands on its supports as they now stand.
func _relay_due() -> void:
	while not _due.is_empty():
		var id: int = _due.keys().min()
		_due.erase(id)
		var w := find(id)
		if w == null or _held(w):
			continue
		_meet(w)
		w.layout.resample(Terrain.height_at, Terrain.water_at)
		_reshaped(w)
		w.rebuild()
