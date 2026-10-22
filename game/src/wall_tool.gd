class_name WallTool
extends Node3D

## Walls, for whichever hand holds them: trigger draws a wall along the ground, a loop as much as a line, and a grip
## on a tree, bush, boulder, stairs or placed fitting carries it, a boulder turning with the hand every way, a fitting
## kept to what it stands on (`_fitting_sizing`), and sets it down when let go. Each hand grabs on its own; a grip on a
## tree, boulder, stairs or opening the other hand holds joins it, and the pair size it.
## A hand holding the house or the tower puts one up with its trigger where it points, and nothing more. A grip
## anywhere on a build, a wall, fence, house or tower, roof included, carries it: it moves and turns with the hand, a
## house or tower rising onto its plinth as the hand rises. The other hand's grip on it too sizes it: spread across a
## house the pair stretch its width or depth, a tower's diameter, along a wall or fence its length, and drawn apart
## upright they make walls taller; both on a roof, drawn apart upright they raise the ridge, and across they bow the
## slopes; both on its eaves they pull them out. Letting go sets it as one reshape. One build is in hand at a time. A path across a wall opens an arch where they cross,
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
enum RoofStyle { PITCHED, FLAT, THATCHED, BOARDED }
## What two hands on a house shape: its walls, its roof, or its eaves.
enum Pair { WALLS, ROOF, EAVES }
enum RoofShape { FLAT, PITCHED }
const ROOF_OPTIONS := {
	RoofShape.FLAT: [RoofStyle.FLAT, RoofStyle.BOARDED],
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


## A thing a grip holds and two grips size by their span: how to read and show its scale, the range it may take, and
## the command that sets it in the garden as shown ({} while it is as the garden has it); and what one hand alone does with it,
## `take` holding it from the hand's pose and `follow` moving it with the hand's pose: a tree, bush, boulder, stairs or
## fitting is carried.
class Sizing:
	var scale: Callable
	var limits: Vector2
	var current: Callable
	var show: Callable
	var command: Callable
	var settle: Callable
	var take: Callable
	var follow: Callable


## A flight of stairs, a landing or a ladder a grip holds, by its id in the garden.
class StairGrip:
	var id: int


## An easel a grip carries, by its id in the garden.
class EaselGrip:
	var id: int


class Mason:
	var hand: Hand
	var buttons: Buttons
	var stroke: Stroke
	## Whether its grip on the house in hand took the roof, and on the eave, past the walls, the way out from them
	## there; zero on its walls or the roof over them.
	var took_roof := false
	var eave_out := Vector3.ZERO
	## What the grip holds (a tree's trunk, a bush, a boulder, stairs or a fitting), how, and where it took it; with the
	## other hand's grip on it too, that mason, its scale `lift_start` and the hands' span when it joined.
	var growing: Object
	var sizing: Sizing
	var partner: Mason
	var pair_span := 0.0
	var lift_start := 0.0
	var lift_at := Vector3.ZERO
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
## Whether new houses are thatched, and what their decks are laid in when pushed flat: the roof last turned to on this machine.
var thatch := false
var deck := RoofLayout.Deck.STONE
var masons: Array[Mason] = []
## Whether painting at an easel takes `hand`'s grip (`EaselTool.claims`): its brushes, palettes and canvas keep their
## grips before anything a ray from the hand would carry.
var painting := func(_hand: Hand) -> bool: return false
## The build in hand, a house, tower, wall or fence, and where and how it stands now (`house_of` for a house or tower,
## `line_of` for any other, with "grounded" true for a house on the ground, which rides the ground and its plinth).
var held: Wall
var held_at := {}
## Where it stood as the garden had it when taken, and the builds standing on it, all the way up, each with where its
## stones stood when laid (`_laid_at`), carried with it.
var _held_was := {}
var _riders := {}
## The hands holding it, and what the pair of them shape; where it stood and their poses when the last of them took
## hold, and how far it goes per metre of hand.
var _holders: Array[Mason] = []
var _pair := Pair.WALLS
var _hold_start := {}
var _hold_from: Array[Transform3D] = []
var _hold_gain := 1.0
## Where the house stood for each footprint sent to be laid, so whichever is laid is carried to where it stands now.
var _laid_at: Array[Dictionary] = []
var _held_dirty := false
## Houses let go, and the builds on them, not yet laid as the garden has them, by id: their `_laid_at`, where the house
## was let go, and whether the garden has answered for them, so their stones are carried there until they are laid again.
var _settling := {}
## How far a house may be carried, in metres, or turned, in radians, and still count as left where it stood: a hand held
## still trembles.
const NUDGE := 0.05
const TURN_NUDGE := 0.02
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
	if held != null and hand == null:
		return true
	for m in masons:
		if (hand == null or m.hand == hand) and (m.stroke != null or m.growing != null or m in _holders):
			return true
	return false


func _process(delta: float) -> void:
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
	_relay_due()
	for m in masons:
		if m.growing != null or m in _holders:
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
	if m.buttons.released("grab") and m.growing != null:
		end_grow(m)
	if not m.hand.tracked():
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

	if m.buttons.pressed("grab") and not busy(m.hand) and not painting.call(m.hand):
		var on_held := _held_hit(origin, dir) if held != null else {}
		var pick := FittingTool.pick_target(self, origin, dir, true)
		var ground: Variant = Terrain.raycast(origin, dir)
		var nearest: float = origin.distance_to(ground) if ground != null else INF
		var tree := flora.solid_hit(origin, dir, nearest)
		var plant: Flora.Plant = tree.plants[0] if not tree.is_empty() else null
		var rock := world.boulders.pick(origin, dir, minf(nearest, minf(pick.get("along", INF), tree.get("along", INF)))) if world.boulders != null else {}
		var step := world.stairs.pick(origin, dir, minf(minf(nearest, rock.get("along", INF)), minf(pick.get("along", INF), tree.get("along", INF)))) if world.stairs != null else {}
		var stand := world.easels.pick_stand(origin, dir, minf(minf(minf(nearest, step.get("along", INF)), minf(tree.get("along", INF), rock.get("along", INF))), pick.get("along", INF))) if world.easels != null else {}
		var before: float = minf(minf(minf(nearest, step.get("along", INF)), minf(tree.get("along", INF), rock.get("along", INF))), stand.get("along", INF))
		if not on_held.is_empty() and on_held.along < (before if pick.get("wall") == held else minf(before, pick.get("along", INF))):
			_join_build(m, on_held.roof, on_held.eave)
		elif not stand.is_empty():
			grip_easel(m, stand.easel.id, hand, stand.point)
		elif not step.is_empty():
			begin_grow(m, _stair_grip(step.stair), hand, step.point)
		elif not rock.is_empty():
			begin_grow(m, rock.boulder, hand, rock.point)
		elif plant != null and tree.along < pick.get("along", INF):
			begin_grow(m, plant, hand, tree.point)
		elif pick.has("fitting") and pick.what != "tower_flag" and pick.along < nearest:
			var grip := _fitting_grip(pick)
			if grip != null:
				begin_grow(m, grip, hand, pick.point)
		elif not pick.is_empty() and pick.along < nearest:
			if held != null or not world.state.walls.has(pick.wall.id):
				m.hand.hold()
			else:
				var roof: bool = pick.get("surface") == "roof"
				take_build(pick.wall)
				_join_build(m, roof, pick.wall.roof.eave_way(pick.point) if roof else Vector3.ZERO)
	elif m.buttons.held("grab") and m.growing != null:
		if m.partner == null:
			m.sizing.follow.call(m, hand)
		elif m.pair_span > 0.0:
			drag_pair(m, m.partner.hand.global_position, origin)


## Shows the bar what the edit in `m`'s hand would add.
func _preview(m: Mason) -> void:
	var change := {}
	if m.stroke != null:
		for w in m.stroke.walls:
			Budget.add(change, Budget.wall(w.data()))
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


func _plan(st: Stroke, commit := false) -> void:
	if st.planned and not commit:
		return
	st.planned = true
	var layouts := st.plan.pieces(st.points, Terrain.height_at, commit)
	while st.walls.size() > layouts.size():
		st.walls.pop_back().queue_free()
	for i in layouts.size():
		if i == st.walls.size():
			st.walls.append(_add_wall(Wall.new(layouts[i].seed, masonry)))
		st.walls[i].layout = layouts[i]
		st.walls[i].on = st.on
		_meet(st.walls[i])


func end_stroke(m: Mason) -> void:
	_plan(m.stroke, true)
	var built_walls := m.stroke.walls
	m.stroke = null
	if not built_walls.is_empty():
		build(built_walls, m.hand)


## Sends a stroke's walls to the garden as one step; they stand as drawn until the garden's walls they become
## are laid.
func build(ws: Array[Wall], hand: Hand = null) -> void:
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
		m.eave_out = Vector3.ZERO
		m.growing = null
		m.sizing = null
		m.partner = null
	held = null
	_holders.clear()
	_riders.clear()
	_settling.clear()
	_due.clear()


## A hand holding the house or the tower points where one would stand, and its trigger puts one up there, on the
## ground or on the build's top it points at, its front square to the head; moving it is the grip's.
func _place_input() -> void:
	for m in masons:
		if not m.hand.tool in [Hand.Tool.HOUSE, Hand.Tool.TOWER] or rig.aim_hand == m.hand or not m.hand.tracked() or m in _holders:
			continue
		var aimed := aim(m.hand.global_position, -m.hand.global_basis.z)
		m.hand.point(aimed.get("point"), TINT)
		if not m.buttons.pressed("tool") or busy(m.hand):
			continue
		var at: Variant = aimed.get("point")
		if at == null:
			var ahead := -rig.head.global_basis.z
			ahead.y = 0.0
			at = rig.head.global_position + ahead.normalized() * HOUSE_REACH
		var on := aimed.get("on", -1) as int
		build([new_house(stance(at, angle(rig.head.global_basis.x), m.hand.tool == Hand.Tool.TOWER), PackedInt32Array([on]) if on >= 0 else PackedInt32Array())], m.hand)


## A new house, or round tower under a cone, standing at `at` with its front square to `yaw`, as `house_of` reads one.
static func stance(at: Vector3, yaw: float, round := false) -> Dictionary:
	var out := {"center": Terrain.ground(at.x, at.z), "yaw": yaw, "size": TOWER_SIZE if round else HOUSE_SIZE, "round": round, "rise": 0.0,
		"height": TOWER_HEIGHT if round else HOUSE_HEIGHT, "curve": 0.0, "overhang": RoofLayout.OVERHANG}
	out.pitch = pitch_for(out)
	return out


## A new house or tower standing as `at` has it (`stance`), on the builds `on`, laid as this machine lays new ones and
## shown until the garden has it (`build`).
func new_house(at: Dictionary, on := PackedInt32Array()) -> Wall:
	var w := _new_wall()
	w.on = on
	w.layout.plaster = plaster and not at.round
	w.layout.timber_style = timber_style
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


## Takes the built house or tower `w` in hand as the garden has it, or where it was let go if the garden has not yet
## answered, for the grips that join it (`_join_build`), or a script (`stand_build`), to move and size; what stands on it
## goes with it.
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
	_holders.clear()
	_carried = 0.0


## Where the stones `w` has laid stood, its house standing as it was let go or as the garden has it, `w` standing at
## `points` raised `rise` in the garden; it is held now, so no longer settling.
func _resettled(w: Wall, points: PackedVector3Array, rise: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = _settling.get(w.id, {}).get("laid_at", [] as Array[Dictionary])
	_settling.erase(w.id)
	var laid: Array[Vector3] = []
	laid.assign(Array(points))
	out.append({"points": laid, "laid_rise": rise, "center": _held_was.center, "yaw": _held_was.yaw, "rise": _held_was.rise})
	return out


## `m`'s grip joins the hold on the house in hand: on its roof with `roof`, on its eave going `eave` out from its walls.
func _join_build(m: Mason, roof: bool, eave: Vector3) -> void:
	m.took_roof = roof
	m.eave_out = eave
	_holders.append(m)
	m.hand.hold()
	_restart_hold()
	if _holders.size() == 1:
		Cues.play(Cues.Act.HOUSE_TAKE, held_at.center, m.hand)


## Each change of hands starts the hold afresh from where the house stands: two hands on its roof shape the roof, on its
## eaves pull them, and otherwise size it.
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


## Moves the house in hand with the hands holding it, and lets it go once none does.
func _hold_build() -> void:
	if _holders.is_empty():
		return
	var holding := _holders.filter(func(m: Mason) -> bool: return m.buttons.held("grab") and m.hand.tracked() and rig.aim_hand != m.hand)
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


## Shows the house in hand standing as `to`: moved or turned, its stones are carried as they were laid, roof, fittings
## and furniture with them; sized, raised or its roof reshaped, it is laid again.
func stand_build(to: Dictionary) -> void:
	to.center = Terrain.ground(to.center.x, to.center.z)
	var hands := _hands_of(_holders)
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


## How far a build standing as `at` reaches, across and up, as its sizing sounds it.
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


## Carries the stones `w` has laid to where its house stands as `at`, from where that stood when they were laid
## (`laid_at`), its decorations with them: a house on the ground rides the ground, one on a build keeps that build's top.
func _carry(w: Wall, laid_at: Array[Dictionary], at: Dictionary) -> void:
	var laid := w.layout.laid_points
	var i := laid_at.find_custom(func(e: Dictionary) -> bool: return e.points == laid and e.laid_rise == w.layout.laid_rise)
	if i < 0:
		return
	for k in i:
		laid_at.pop_front()
	var was: Dictionary = laid_at[0]
	var lift: float = 0.0 if not at.grounded else _lowest(outline(at)) - _lowest(outline({"center": was.center, "yaw": was.yaw, "size": at.size, "round": at.round})) + at.rise - was.rise
	var from := Transform3D(Basis(Vector3.UP, was.yaw), Vector3(was.center.x, 0.0, was.center.z))
	var to := Transform3D(Basis(Vector3.UP, at.yaw), Vector3(at.center.x, lift, at.center.z))
	_place_laid(w, to * from.affine_inverse())


func _place_laid(w: Wall, x: Transform3D) -> void:
	if w.transform.is_equal_approx(x):
		return
	w.transform = x
	if world.decorations != null:
		world.decorations.carry(w)


## Lets the house in hand go: it is set where and as it stands, one reshape with the builds on it carried along, and
## shown there until the garden lays it so.
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


## Whether a build held from `was` stands far enough from it as `at` to set it there.
static func _moved(was: Dictionary, at: Dictionary) -> bool:
	if Vector2(at.center.x - was.center.x, at.center.z - was.center.z).length() > NUDGE or absf(angle_difference(at.yaw, was.yaw)) > TURN_NUDGE:
		return true
	if at.has("size") and not at.size.is_equal_approx(was.size):
		return true
	return ["rise", "height", "pitch", "curve", "overhang", "length"].any(func(k: String) -> bool: return at.has(k) and absf(at[k] - was[k]) > 0.01)


## Where a house standing as `at` stands on the ground and which way it faces, as a frame.
static func _footing(at: Dictionary) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, at.yaw), Vector3(at.center.x, 0.0, at.center.z))


## The reshape that carries build `d` by `x`, a turn about the vertical and a move along the ground: its wall line, and a
## tower's cone with it; what stands along its walls or on its roof keeps its place there.
static func carried_by(d: Dictionary, x: Transform3D) -> Dictionary:
	var points := PackedVector3Array()
	for p: Vector3 in d.points:
		var q := x * Vector3(p.x, 0.0, p.z)
		points.append(Vector3(q.x, p.y, q.z))
	var out := {"points": points}
	if d.has("roof"):
		var c := x * Vector3(d.roof.center.x, 0.0, d.roof.center.z)
		out["roof"] = {"center": Vector3(c.x, d.roof.center.y, c.z)}
	return out


## The garden has answered for a house let go and the builds on it, taking them as they stood or turning them down. It
## answers before it applies what it took, so any not laid as the garden has them are laid so once it has.
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


## Whether `w` is laid from the garden's own copy of it as far as a hold changes it.
func _shows_garden(w: Wall) -> bool:
	var d: Dictionary = world.state.walls[w.id]
	if PackedVector3Array(w.layout.points) != d.points or w.layout.rise != d.rise or w.layout.height != d.height:
		return false
	return w.roof == null or (w.roof.pitch == d.roof.pitch and w.roof.curve == d.roof.curve and w.roof.overhang == d.roof.overhang and w.roof.center == d.roof.center)


## A house let go keeps its stones carried to where it was let go until it is laid as the garden has it.
func _settle_builds() -> void:
	for id: int in _settling.keys():
		var w := find(id)
		var s: Dictionary = _settling[id]
		if w == null or not world.state.walls.has(id):
			_settling.erase(id)
		elif s.back and not w.laying() and PackedVector3Array(w.layout.laid_points) == world.state.walls[id].points and w.layout.laid_rise == world.state.walls[id].rise:
			_place_laid(w, Transform3D.IDENTITY)
			_settling.erase(id)
		else:
			_carry(w, s.laid_at, s.at)


static func _lowest(points: Array[Vector3]) -> float:
	var low := INF
	for c in points:
		low = minf(low, Terrain.height_at(c.x, c.z))
	return low


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
		return RoofStyle.BOARDED if d.roof.deck == RoofLayout.Deck.WOOD else RoofStyle.FLAT
	return RoofStyle.THATCHED if d.roof.thatch else RoofStyle.PITCHED


## Coverings never reshape the roof: a flat deck keeps the covering to use when pulled up, a pitched roof the deck to
## lay when pushed flat.
static func restyle_roof(d: Dictionary, style: RoofStyle) -> Dictionary:
	if style not in roof_options(d.roof.pitch):
		return {}
	if d.roof.pitch <= 0.0:
		return {"roof": {"deck": RoofLayout.Deck.WOOD if style == RoofStyle.BOARDED else RoofLayout.Deck.STONE}}
	return {"roof": {"thatch": style == RoofStyle.THATCHED}}


## Where a built house stands, as `outline` takes it, with its plinth's rise, its walls' height and its roof's pitch, bow
## and eaves, from its garden data; {} for a build that is no house or tower.
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


## The `reshape` that stands the house with garden data `d` as `to`: its wall line, height and roof as `to` has them,
## and every fitting and arch kept in proportion along its own wall, every chimney and dormer on its roof.
static func reshape_house(d: Dictionary, to: Dictionary) -> Dictionary:
	var from := house_of(d)
	var was: Array[Vector3] = []
	was.assign(Array(d.points))
	var now := outline(to)
	var moved := func(s: float) -> float: return _loop_s(now, _scaled(from, to, _loop_point(was, s)))
	var openings := PackedVector4Array()
	for w: Vector4 in d.openings:
		openings.append(Vector4(moved.call(w.x), w.y, w.z, w.w))
	var lanterns := PackedVector3Array()
	for l: Vector3 in d.lanterns:
		lanterns.append(Vector3(moved.call(l.x), l.y, l.z))
	var flags := PackedFloat32Array()
	for f: float in d.flags:
		flags.append(moved.call(f))
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
		roof = {"chimneys": moved_on.call(d.roof.chimneys), "dormers": moved_on.call(d.roof.dormers)}
	roof.merge({"pitch": to.pitch, "curve": to.curve, "overhang": to.overhang})
	return {"points": PackedVector3Array(now), "rise": to.rise, "height": to.height, "openings": openings, "lanterns": lanterns, "flags": flags, "roof": roof}


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


## Where a wall, fence or loop that is no house stands, as a hold moves it (`reshape_line`): its middle, its turn from
## where it stands, how many times as long as it stands, how long that is, its height and its plinth's rise; it rides no
## plinth.
static func line_of(d: Dictionary) -> Dictionary:
	var mid := Vector3.ZERO
	for p: Vector3 in d.points:
		mid += p / d.points.size()
	return {"center": mid, "yaw": 0.0, "length": 1.0, "run": Commands.length(d.points), "height": d.height, "rise": d.rise, "fence": d.fence, "grounded": false}


## The `reshape` that stands the wall with garden data `d` as `to` (`line_of`): its line carried, turned about its middle
## and drawn out `to.length` times as long, every opening, lantern, flag and ruin kept in proportion along it, and its
## height.
static func reshape_line(d: Dictionary, to: Dictionary) -> Dictionary:
	var from := line_of(d)
	var turn := Basis(Vector3.UP, to.yaw)
	var k: float = to.length
	var points := PackedVector3Array()
	for p: Vector3 in d.points:
		var q: Vector3 = to.center + turn * (_flat(p - from.center) * k)
		points.append(Vector3(q.x, p.y, q.z))
	var openings := PackedVector4Array()
	for o: Vector4 in d.openings:
		openings.append(Vector4(o.x * k, o.y, o.z, o.w))
	var lanterns := PackedVector3Array()
	for l: Vector3 in d.lanterns:
		lanterns.append(Vector3(l.x * k, l.y, l.z))
	var flags := PackedFloat32Array()
	for f: float in d.flags:
		flags.append(f * k)
	var ruins := PackedVector2Array()
	for r: Vector2 in d.ruins:
		ruins.append(r * k)
	return {"points": points, "height": to.height, "openings": openings, "lanterns": lanterns, "flags": flags, "ruins": ruins}


## Where a wall held from `start` stands once two hands move from poses `from` to `to`: drawn out or in along its line,
## about its middle, by the ratio of their spread, from a metre long to as long as a wall may run; drawn apart upright
## the hands make it taller, `gain` times as far as they are, a course at a time, a fence keeping its height.
static func stretch_line(start: Dictionary, from: Array[Transform3D], to: Array[Transform3D], gain := 1.0) -> Dictionary:
	var out := start.duplicate()
	var span0 := _flat(from[1].origin - from[0].origin).length()
	var run: float = start.run * start.length * _flat(to[1].origin - to[0].origin).length() / maxf(span0, 0.05)
	out.length = clampf(run, 1.0, Commands.MAX_LENGTH) / start.run
	if not start.fence:
		out.height = maxf(start.height + snappedf(_upright(from, to) * gain, WallLayout.COURSE), WallLayout.MIN_HEIGHT)
	return out


## Where a house held from `start` stands once the hand holding it moves from pose `from` to `to`: carried along the
## ground by the hand's move, `gain` times as far so a far house keeps up, and turned with the hand's own turn. One on
## the ground rises onto its plinth as the hand rises, its floor with it, a course at a time and never below its ground,
## so it never floats; one on a build keeps to that build's top.
static func carry(start: Dictionary, from: Transform3D, to: Transform3D, gain: float) -> Dictionary:
	var out := start.duplicate()
	out.center = start.center + _flat(to.origin - from.origin) * gain
	out.yaw = start.yaw + angle_difference(angle(from.basis.x), angle(to.basis.x))
	if start.grounded:
		out.rise = maxf(snappedf(start.rise + (to.origin.y - from.origin.y) * gain, WallLayout.COURSE), 0.0)
	return out


static func stretched(start: Dictionary, span: Vector3, ratio: float) -> Vector2:
	if start.round:
		return Vector2.ONE * maxf(start.size.x * ratio, HOUSE_SIDE)
	var across: float = angle(span) - start.yaw
	var i := 0 if absf(cos(across)) >= absf(sin(across)) else 1
	var size: Vector2 = start.size
	size[i] = maxf(size[i] * ratio, HOUSE_SIDE)
	return size


## Where a house held from `start` stands once two hands on it move from poses `from` to `to`: it keeps its place and
## turn and stretches as `stretched` has it, toward the hand that moved, so a hand held still keeps its wall, its roof
## keeping its slope; drawn apart or together upright, its walls grow taller or shorter, `gain` times as far as the hands
## are, a course at a time.
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


## The roof of a house held from `start` once two hands on it move from poses `from` to `to`: drawn apart or together
## upright they raise or lower its ridge, `gain` times as far as the hands are, all the way down snapping it flat;
## spread or closed across, they bow its slopes out or in.
static func bend(start: Dictionary, from: Array[Transform3D], to: Array[Transform3D], gain: float) -> Dictionary:
	var out := start.duplicate()
	var pitch: float = start.pitch + snappedf(_upright(from, to) * gain, ROOF_STEP)
	out.pitch = 0.0 if pitch < RoofLayout.FLAT_SNAP else pitch
	var spread := _flat(to[1].origin - to[0].origin).length() - _flat(from[1].origin - from[0].origin).length()
	out.curve = clampf(start.curve + spread * 2.0, -RoofLayout.CURVE, RoofLayout.CURVE)
	return out


## How far the eaves of a house held from `start` reach past its walls once two hands on them move from poses `from` to
## `to`, each pulling its own eave out along `out`, the way out from the walls there, or pushing it back: by how far
## they pull on average, `gain` times, on the nearest ROOF_STEP, from none to `reach`.
static func pull_eaves(start: Dictionary, from: Array[Transform3D], to: Array[Transform3D], out: Array[Vector3], gain: float, reach: float) -> Dictionary:
	var pulled := 0.0
	for i in 2:
		pulled += (to[i].origin - from[i].origin).dot(out[i]) * 0.5
	var at := start.duplicate()
	at.overhang = clampf(snappedf(minf(start.overhang, reach) + pulled * gain, ROOF_STEP), 0.0, reach)
	return at


## How much farther apart upright two hands are at poses `to` than at `from`.
static func _upright(from: Array[Transform3D], to: Array[Transform3D]) -> float:
	return absf(to[1].origin.y - to[0].origin.y) - absf(from[1].origin.y - from[0].origin.y)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## The turn about the vertical that takes the x axis to `v`'s direction on the ground.
static func angle(v: Vector3) -> float:
	return atan2(-v.z, v.x)


## Where a ray meets the house in hand as it is shown, carried from where it was laid: {along, roof, eave}, `eave` the
## way out from its walls for a roof hit past them (`RoofLayout.eave_way`), else zero; {} if it misses.
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


## Grip from the hand's pose `hand` on a tree, a bush, a boulder, stairs or a fitting at `at`, which one hand alone moves as its
## `Sizing` has it. A grip on one the other hand holds joins it: the two hands pulled apart grow it, pushed together
## shrink it, in proportion to their span; letting either go leaves it to the other alone.
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
	m.sizing.take.call(m, hand)


## The two hands sizing what `m` joined, now at `a` and `b`.
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
		s.take.call(other, other.hand.global_transform)
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


## How a grip holds `target`, a tree's trunk, a bush, a boulder, stairs or a fitting; each shows as the garden has it once its edit
## has come back or been turned down, unless a hand holds it again.
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


## Carries a tree or bush (`first`, a tree's trunk or a bush's blob), the meadow's own too: one hand moves it along the
## ground with the hand, a far one farther per metre; two hands size a tree by their span. Let go, its place and size are
## one `tree` command; over water it goes back where it stood.
func _plant_grip(first: Flora.Plant, s: Sizing, in_hand: Callable) -> Sizing:
	var tree := first.pool == flora.trunks
	var placed := func() -> Vector3:
		return world.state.groups.get(first.group, {}).get("places", {}).get(first.index, flora.home_of(first))
	var hold := {"from": Vector3.ZERO, "hand": Vector3.ZERO, "gain": 1.0}
	s.scale = flora.scale_of.bind(first) if tree else func() -> float: return 1.0
	s.limits = FloraLayout.SCALES if tree else Vector2.ONE
	s.current = first.current
	s.show = func(scale: float) -> void:
		if tree:
			flora.set_look(first, flora.species_of(first) as FloraLayout.Species, scale)
	s.command = func() -> Dictionary:
		var g: Dictionary = world.state.groups.get(first.group, {})
		var at := first.foot()
		if g.is_empty() or Water.drowned(at):
			return {}
		var cmd := {"op": "tree", "group": first.group, "index": first.index}
		var was: Vector3 = placed.call()
		if Vector2(at.x - was.x, at.z - was.z).length() >= NUDGE:
			cmd.at = Terrain.ground(at.x, at.z)
		if tree and not is_equal_approx(flora.scale_of(first), g.scale.get(first.index, 1.0)):
			cmd.scale = flora.scale_of(first)
		return {} if cmd.size() == 3 else cmd
	s.take = func(m: Mason, hand: Transform3D) -> void:
		hold.from = first.foot()
		hold.hand = hand.origin
		hold.gain = Hand.reach_gain(hand.origin.distance_to(m.lift_at))
	s.follow = func(_m: Mason, hand: Transform3D) -> void:
		flora.move(first, hold.from + (hand.origin - hold.hand) * hold.gain)
	s.settle = func() -> void:
		var g: Dictionary = world.state.groups.get(first.group, {})
		if first.current() and not g.is_empty() and not in_hand.call():
			flora.move(first, placed.call())
			if tree:
				flora.set_look(first, g.species.get(first.index, FloraLayout.Species.OAK), g.scale.get(first.index, 1.0))
	return s


## Carries a boulder: one hand moves it and turns it about its centre every way as the hand turns (`Boulders.carried`),
## a far one moving farther per metre of hand; let go, it drops straight down onto the ground under it, keeping its
## turn, or stays as deep as it was pushed into the ground (`BoulderLayout.rest`), its place, turn, depth and size one reshape.
func _boulder_grip(b: Boulders.Boulder, s: Sizing, in_hand: Callable) -> Sizing:
	var rocks := world.boulders
	var standing := func() -> bool: return is_instance_valid(b) and rocks.find(b.id) == b
	var grip := {"pose": b.pose(), "scale": b.size, "from": b.pose(), "hand": Transform3D(), "gain": 1.0}
	var data := func() -> Dictionary:
		var p: Transform3D = grip.pose
		var turn := p.basis.get_rotation_quaternion().normalized()
		return {"at": Terrain.ground(p.origin.x, p.origin.z), "turn": turn, "sink": BoulderLayout.sink(b.shape, turn, grip.scale, p.origin, Terrain.height_at), "scale": grip.scale}
	s.scale = func() -> float: return grip.scale
	s.limits = Vector2(BoulderLayout.LEAST, INF)
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
		var was := b.data
		if is_equal_approx(d.scale, was.scale) and d.turn.is_equal_approx(was.turn) and is_equal_approx(d.sink, was.sink) and is_equal_approx(d.at.x, was.at.x) and is_equal_approx(d.at.z, was.at.z):
			return {}
		return {"op": "reshape", "of": "boulders", "id": b.id, "data": d}
	s.take = func(m: Mason, hand: Transform3D) -> void:
		grip.from = grip.pose
		grip.hand = hand
		grip.gain = Hand.reach_gain(hand.origin.distance_to(m.lift_at))
	s.follow = func(_m: Mason, hand: Transform3D) -> void:
		grip.pose = Boulders.carried(grip.from, grip.hand, hand, grip.gain)
		rocks.show_held(b.id, grip.pose, grip.scale)
	s.settle = func() -> void:
		if standing.call() and not in_hand.call():
			rocks.settle(b.id)
	return s


## Carries a flight of stairs, a landing or a ladder: one hand moves it with the hand, a far one farther per metre, and
## turns it about the vertical through its middle as the hand turns (`carry_stairs`); two hands widen or narrow it by
## their span. Let go, it is set as one reshape.
func _stair_sizing(grip: StairGrip, s: Sizing, in_hand: Callable) -> Sizing:
	var stairs := world.stairs
	var was: Dictionary = world.state.stairs[grip.id].duplicate()
	var shown := {"a": was.a, "b": was.b, "width": was.width}
	var from := shown.duplicate()
	var hold := {"hand": Transform3D(), "gain": 1.0}
	var current := func() -> bool:
		var now: Dictionary = world.state.stairs.get(grip.id, {})
		return not now.is_empty() and now.a == was.a and now.b == was.b and now.width == was.width
	s.scale = func() -> float: return shown.width
	s.limits = StairLayout.WIDTH
	s.current = current
	s.show = func(width: float) -> void:
		shown.width = width
		stairs.show_reshaped(grip.id, shown)
	s.command = func() -> Dictionary:
		var same: bool = shown.a.is_equal_approx(was.a) and shown.b.is_equal_approx(was.b) and is_equal_approx(shown.width, was.width)
		return {} if same else {"op": "reshape", "of": "stairs", "id": grip.id, "data": shown.merged({"on": stair_supports(shown)})}
	s.take = func(m: Mason, hand: Transform3D) -> void:
		from.merge(shown, true)
		hold.hand = hand
		hold.gain = Hand.reach_gain(hand.origin.distance_to(m.lift_at))
	s.follow = func(_m: Mason, hand: Transform3D) -> void:
		shown.merge(carry_stairs(from, hold.hand, hand, hold.gain), true)
		stairs.show_reshaped(grip.id, shown)
	s.settle = func() -> void:
		if world.state.stairs.has(grip.id) and not in_hand.call():
			stairs.settle(grip.id)
	return s


## Where stairs held standing as `at` ({a, b, width}) stand once the hand holding them moves from pose `from` to `to`:
## moved with the hand, `gain` times as far, and turned about the vertical through their middle with the hand's own turn,
## their lower end never under the ground.
static func carry_stairs(at: Dictionary, from: Transform3D, to: Transform3D, gain: float) -> Dictionary:
	var mid: Vector3 = (at.a + at.b) * 0.5
	var turn := Basis(Vector3.UP, angle_difference(angle(from.basis.x), angle(to.basis.x)))
	var move := (to.origin - from.origin) * gain
	var a: Vector3 = mid + move + turn * (at.a - mid)
	var b: Vector3 = mid + move + turn * (at.b - mid)
	var low := a if a.y < b.y else b
	var under := maxf(Terrain.height_at(low.x, low.z) - low.y, 0.0)
	return {"a": a + Vector3.UP * under, "b": b + Vector3.UP * under, "width": at.width}


## The builds stairs standing as `d` rest their ends on, on a top or a floor inside, which take the stairs with them
## when they go.
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


## A grip from the hand's pose `hand` on easel `id`'s stand at `at` carries it; a grip on one another hand carries
## takes nothing, as two hands size no easel.
func grip_easel(m: Mason, id: int, hand: Transform3D, at: Vector3) -> void:
	if masons.any(func(o: Mason) -> bool: return o.growing is EaselGrip and o.growing.id == id):
		m.hand.hold()
		return
	var grip := EaselGrip.new()
	grip.id = id
	begin_grow(m, grip, hand, at)


## Carries an easel, its painting and kit with it: one hand moves it along the ground with the hand, a far one farther
## per metre, and turns it about the vertical as the hand turns (`carry_easel`); let go, it is set as one reshape of
## where it stands and which way it faces, or put back if it would crowd another.
func _easel_sizing(grip: EaselGrip, s: Sizing, in_hand: Callable) -> Sizing:
	var stands := world.easels
	var was: Dictionary = world.state.easels[grip.id]
	var start := {"at": was.at, "yaw": was.yaw}
	var shown := start.duplicate()
	var from := start.duplicate()
	var hold := {"hand": Transform3D(), "gain": 1.0}
	s.scale = func() -> float: return 1.0
	s.limits = Vector2.ONE
	s.current = func() -> bool:
		var now: Dictionary = world.state.easels.get(grip.id, {})
		return not now.is_empty() and now.at == start.at and now.yaw == start.yaw
	s.show = func(_scale: float) -> void: stands.stand(grip.id, shown.at, shown.yaw)
	s.command = func() -> Dictionary:
		if shown.at.distance_to(start.at) < NUDGE and absf(angle_difference(shown.yaw, start.yaw)) < TURN_NUDGE:
			return {}
		return {"op": "reshape", "of": "easels", "id": grip.id, "data": shown.duplicate()}
	s.take = func(m: Mason, hand: Transform3D) -> void:
		from.merge(shown, true)
		hold.hand = hand
		hold.gain = Hand.reach_gain(hand.origin.distance_to(m.lift_at))
	s.follow = func(_m: Mason, hand: Transform3D) -> void:
		shown.merge(carry_easel(from, hold.hand, hand, hold.gain), true)
		stands.stand(grip.id, shown.at, shown.yaw)
	s.settle = func() -> void:
		var now: Dictionary = world.state.easels.get(grip.id, {})
		if not now.is_empty() and not in_hand.call():
			stands.stand(grip.id, now.at, now.yaw)
	return s


## Where an easel standing as `at` ({at, yaw}) stands once the hand holding it moves from pose `from` to `to`: moved
## across the ground with the hand, `gain` times as far, on the ground there, and turned with the hand's own turn about
## the vertical.
static func carry_easel(at: Dictionary, from: Transform3D, to: Transform3D, gain: float) -> Dictionary:
	var move: Vector3 = at.at + (to.origin - from.origin) * gain
	return {"at": Terrain.ground(move.x, move.z), "yaw": wrapf(at.yaw + angle_difference(angle(from.basis.x), angle(to.basis.x)), -PI, PI)}


## The grip a hand already holding stairs `id` holds, so a second hand's grip on them joins that one.
func _stair_grip(id: int) -> StairGrip:
	for m in masons:
		if m.growing is StairGrip and m.growing.id == id:
			return m.growing
	var grip := StairGrip.new()
	grip.id = id
	return grip


## Carries a placed fitting with the hand, a far one farther per metre, by whole steps (`FittingGrip.moved`), stopping it
## at the last place it fits; two hands size an opening, which grows every way from where it stands, as far as it still
## opens without closing another, an arch up to the wall's top (WallLayout.opening_for). Its wall is laid again only as
## it moves on by a step. Let go, it is set as one reshape of its wall.
func _fitting_sizing(grip: FittingGrip, s: Sizing, in_hand: Callable) -> Sizing:
	if grip.decoration >= 0:
		return _decoration_grip(grip.decoration, s, in_hand)
	var w := grip.wall
	var key := grip.key
	var stored := func() -> Array:
		if not is_instance_valid(w) or find(w.id) != w or not world.state.walls.has(w.id):
			return []
		var d: Dictionary = world.state.walls[w.id]
		return Array((d.roof if grip.on_roof else d)[key])
	var start: Variant = stored.call()[grip.index]
	var shown := {"value": start, "laid": start}
	var hold := {"from": start, "hand": Transform3D(), "gain": 1.0}
	var others := func() -> Array:
		var rest: Array = stored.call()
		rest.remove_at(grip.index)
		return rest
	var data := func(v: Variant) -> Dictionary:
		var placed: Array = stored.call()
		placed[grip.index] = v
		var packed: Variant = {"openings": PackedVector4Array(placed), "lanterns": PackedVector3Array(placed), "flags": PackedFloat32Array(placed)}.get(key, PackedVector2Array(placed))
		return {"roof": {key: packed}} if grip.on_roof else {key: packed}
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
	s.scale = func() -> float: return shown.value.w if key == "openings" else 1.0
	s.limits = Vector2(WallLayout.MIN_SIZE, INF) if key == "openings" else Vector2.ONE
	s.show = func(size: float) -> void:
		if key == "openings":
			var at: Vector4 = shown.value
			var sized := func(k: float) -> Vector4: return Vector4(at.x, at.y, at.z, k)
			if size > at.w and not fits.call(sized.call(size)):
				var lo: float = at.w
				for i in 12:
					var mid := (lo + size) * 0.5
					if fits.call(sized.call(mid)):
						lo = mid
					else:
						size = mid
				size = floorf(lo * 100.0) / 100.0
			if not is_equal_approx(size, at.w) and fits.call(sized.call(size)):
				shown.value = sized.call(size)
		lay.call()
	s.take = func(m: Mason, hand: Transform3D) -> void:
		hold.from = shown.value
		hold.hand = hand
		hold.gain = Hand.reach_gain(hand.origin.distance_to(m.lift_at))
	s.follow = func(_m: Mason, hand: Transform3D) -> void:
		var by: Vector3 = FittingGrip.step((hand.origin - hold.hand.origin) * hold.gain, 0.0)[0]
		var v: Variant = FittingGrip.moved(w, key, hold.from, by)
		if v != shown.value and fits.call(v):
			shown.value = v
		lay.call()
	s.command = func() -> Dictionary: return {} if shown.value == start else {"op": "reshape", "of": "walls", "id": w.id, "data": data.call(shown.value)}
	s.settle = func() -> void:
		if current.call() and not in_hand.call():
			settle(w.id)
	return s


## Carries a decoration: one hand moves it across the ground, its floor or deck and turns it with the hand, or along the
## wall it stands at the foot of (`FittingGrip.carried`), stopping it at the last place it stands. Only its node moves
## while it is held; let go, it is set as one reshape.
func _decoration_grip(id: int, s: Sizing, in_hand: Callable) -> Sizing:
	var decorations := world.decorations
	var start: Dictionary = world.state.decorations[id].duplicate()
	var shown := {"d": start}
	var hold := {"from": start, "hand": Transform3D(), "gain": 1.0}
	var current := func() -> bool: return world.state.decorations.get(id) == start
	s.current = current
	s.scale = func() -> float: return 1.0
	s.limits = Vector2.ONE
	s.show = func(_size: float) -> void: pass
	s.take = func(m: Mason, hand: Transform3D) -> void:
		hold.from = shown.d
		hold.hand = hand
		hold.gain = Hand.reach_gain(hand.origin.distance_to(m.lift_at))
	s.follow = func(_m: Mason, hand: Transform3D) -> void:
		var step: Array = FittingGrip.step((hand.origin - hold.hand.origin) * hold.gain, angle_difference(angle(hold.hand.basis.x), angle(hand.basis.x)))
		var d := FittingGrip.carried(hold.from, find(start.wall), step[0], step[1])
		if d != shown.d and decorations.frame(d) != null:
			shown.d = d
			decorations.show_held(id, d)
	s.command = func() -> Dictionary:
		var d: Dictionary = shown.d
		return {} if d == start else {"op": "reshape", "of": "decorations", "id": id, "data": {"at": d.at, "turn": d.turn, "s": d.s}}
	s.settle = func() -> void:
		if not in_hand.call():
			decorations.settle(id)
	return s


## The grip on the fitting `pick` names (`FittingTool.pick_target`): the one a hand already holds, so a second hand's
## grip on an opening joins it, or a new one; null for one another hand holds that takes no size.
func _fitting_grip(pick: Dictionary) -> FittingGrip:
	for m in masons:
		var g: Variant = m.growing
		if g is FittingGrip and (g.decoration == pick.decoration if pick.has("decoration") else g.wall == pick.wall and g.key == pick.key and g.index == pick.index and g.on_roof == pick.on_roof):
			return g if g.sized() else null
	var grip := FittingGrip.new()
	if pick.has("decoration"):
		grip.decoration = pick.decoration
		return grip
	var d: Dictionary = world.state.walls[pick.wall.id]
	grip.wall = pick.wall
	grip.key = pick.key
	grip.on_roof = pick.on_roof
	grip.index = Array((d.roof if pick.on_roof else d)[pick.key]).find(pick.value)
	return grip if grip.index >= 0 else null


## The openings in `w` with its stored placements and the paths standing, independent of its preview.
func standing_openings(w: Wall, own: Array) -> Array[Vector4]:
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
	if w == held:
		held = null
		_holders.clear()
		_riders.clear()
	_riders.erase(w)
	_settling.erase(id)
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
	if w != null and (w == held or _riders.has(w)):
		return true
	for m in masons:
		if m.growing is FittingGrip and m.growing.wall == w:
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
## A held pick also sees builds another hand is pulling. `through_arches` sees through an arch's opening, as the
## teleport and a decoration placed beyond it do; a tool working the wall itself, or the arch's own ghost, does not.
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
					best = {"wall": w, "surface": surface, "along": t, "point": point, "s": w.layout.closest_s(point), "distance": 0.0}
	return best


## The first building or plant surface along a teleport ray, short of reach.
func solid_hit(origin: Vector3, dir: Vector3, reach: float) -> Variant:
	var hit := pick_building(origin, dir, false, true)
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
