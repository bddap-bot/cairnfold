class_name PaletteTool
extends Node3D

## The colour and style pickers, for whichever hand holds one: the trigger on a thing opens a wheel of its
## choices over the controller, and twisting the wrist turns the wheel like a dial, showing each choice live
## on this machine; letting go sends the choice at the top to the garden, so everyone building sees it, and it
## is one undo step. The colour tool's choices are swatches of the material pointed at: a build's stone, roof
## tiles, woodwork (fences, window frames, doors) or plaster, as a `reshape` of its paint (builds laid after
## take the swatch let go last), or on the meadow the garden's season. The style tool's are miniatures of the
## styles of what it points at: a gable end's, a roof's (pitched, a tower's cone, flat), a roofless wall's top,
## or along a wall plain or arched.

const BEAM := Color(1.0, 1.0, 1.0, 0.6)
const WHEEL_RADIUS := 0.07
## Where the wheel stands from the controller, in its frame when the trigger went down.
const WHEEL_AT := Vector3(0, 0.06, -0.05)

enum Restyle { GABLE, ROOF, TOP, ARCH }
const STYLES := {Restyle.GABLE: 3, Restyle.ROOF: 3, Restyle.TOP: 3, Restyle.ARCH: 2}

## A hand's open wheel: what it changes (`aim`'s target) on which build (-1 for the meadow), the choice it
## started on and the one at its top, and the hand's frame when it opened.
class Wheel:
	var wall := -1
	var target: Dictionary
	var start := 0
	var pick := 0
	var degrees := 0.0
	var basis := Basis()
	var node: Node3D
	var choices: Array[Node3D] = []


var rig: Rig
var walls: WallTool
var world: World
var wheels := {}
var _buttons: Array[Buttons] = []


func _init(player: Rig, builder: WallTool, garden: World) -> void:
	rig = player
	walls = builder
	world = garden
	for h in rig.hands:
		_buttons.append(Buttons.new(h).watch(["tool"]))
	world.restored.connect(func() -> void:
		for hand in wheels.keys():
			_drop(hand))


## Whether `hand`, or with none any hand, holds a wheel open. One wheel at a time, so two hands never pick for one
## material from stale starts.
func busy(hand: Hand = null) -> bool:
	return wheels.has(hand) if hand != null else not wheels.is_empty()


func _process(_delta: float) -> void:
	for b in _buttons:
		var hand: Hand = b.hand
		var wheel: Wheel = wheels.get(hand)
		if wheel != null and (hand.tool != wheel.target.tool or b.released("tool")):
			close(hand)
		elif wheel != null and b.held("tool"):
			twist(hand, _roll(wheel.basis, hand.global_basis))
		elif wheel == null and hand.tool in [Hand.Tool.COLOUR, Hand.Tool.STYLE] and rig.aim_hand != hand and hand.get_has_tracking_data():
			var t := hand.global_transform
			var target := aim(t.origin, -t.basis.z) if hand.tool == Hand.Tool.COLOUR else aim_style(t.origin, -t.basis.z)
			hand.point(target.get("point", null), BEAM)
			if b.pressed("tool") and not target.is_empty() and not busy():
				open(hand, target)
		b.latch()
	for hand in wheels:
		hand.hold()
		_place(wheels[hand], hand)


## What the trigger would recolour from `origin` along `dir`: `element`, `point` and the `wall` (null on the meadow), or empty.
func aim(origin: Vector3, dir: Vector3) -> Dictionary:
	var pick := walls.pick_wall(origin, dir)
	var roof := walls.pick_roof(origin, dir)
	var along: float = roof.get("along", INF)
	var gable := walls.pick_gable(origin, dir)
	if gable.get("along", INF) < along and WallTool._on_roof(pick, gable):
		var end: WallLayout = gable.wall.layout
		var wood := end.gable_end == WallLayout.GableEnd.BOARDS
		return colour_target(Palette.Element.WOOD if wood else Palette.Element.PLASTER if end.plaster else Palette.Element.STONE, gable.point, gable.wall)
	if along < INF and (pick.is_empty() or pick.distance > 0.2 or along < pick.along):
		return colour_target(Palette.Element.ROOF, roof.point, roof.wall)
	if not pick.is_empty():
		var layout: WallLayout = pick.wall.layout
		var wood := layout.fence or not layout.opening_at(pick.s, pick.point.y - layout.point_at(pick.s).y).is_empty()
		return colour_target(Palette.Element.WOOD if wood else Palette.Element.PLASTER if layout.plaster else Palette.Element.STONE, pick.point, pick.wall)
	var ground: Variant = Terrain.raycast(origin, dir)
	if ground != null:
		return colour_target(Palette.Element.MEADOW, ground, null)
	return {}


func colour_target(element: Palette.Element, point: Vector3, wall: Wall) -> Dictionary:
	return {"tool": Hand.Tool.COLOUR, "element": element, "count": Palette.count(element), "point": point, "wall": wall}


## What the style tool would restyle from `origin` along `dir`, as `aim` gives it, with `restyle` in place of an
## element (and `s` along a wall for an arch), or empty: the gable end, roof or wall it meets first, a roofless
## wall's top near it; fences have no style.
func aim_style(origin: Vector3, dir: Vector3) -> Dictionary:
	var pick := walls.pick_wall(origin, dir)
	var roof := walls.pick_roof(origin, dir)
	var gable := walls.pick_gable(origin, dir)
	if gable.get("along", INF) < roof.get("along", INF) and WallTool._on_roof(pick, gable):
		return style_target(Restyle.GABLE, gable.wall, gable.point)
	if WallTool._on_roof(pick, roof) and not WallTool.house_of(roof.wall.data()).is_empty():
		return style_target(Restyle.ROOF, roof.wall, roof.point)
	if not pick.is_empty() and not pick.wall.layout.fence:
		var layout: WallLayout = pick.wall.layout
		var top: bool = layout.cover != WallLayout.Cover.ROOF and pick.point.y - layout.point_at(pick.s).y > layout.height - WallTool.TOP_BAND
		return style_target(Restyle.TOP if top else Restyle.ARCH, pick.wall, pick.point, pick.s)
	return {}


func style_target(restyle: Restyle, wall: Wall, point: Vector3, s := 0.0) -> Dictionary:
	return {"tool": Hand.Tool.STYLE, "restyle": restyle, "count": STYLES[restyle], "point": point, "wall": wall, "s": s}


## Opens the wheel for `target` (as `aim` gives it) over `hand`, turning from its swatch in the garden. While the
## trigger is held the hand's twist turns it; the driver, holding no trigger, turns it with `twist`.
func open(hand: Hand, target: Dictionary) -> void:
	var w := Wheel.new()
	w.target = target
	if target.wall != null:
		w.wall = target.wall.id
	w.start = _now(w)
	w.pick = w.start
	w.basis = hand.global_basis.orthonormalized()
	w.node = Node3D.new()
	w.node.top_level = true
	for i in target.count:
		var choice := _swatch(target.element, i) if target.tool == Hand.Tool.COLOUR else _style(target.restyle, i, target.wall.layout.plaster)
		w.node.add_child(choice)
		w.choices.append(choice)
	add_child(w.node)
	wheels[hand] = w
	_place(w, hand)


## A style's miniature smaller than it stands on a controller, so the wheel's choices stay apart.
static func _style(restyle: Restyle, i: int, plastered: bool) -> Node3D:
	var holder := Node3D.new()
	var model := ToolModels.style(restyle, i, plastered)
	model.scale = Vector3.ONE * 0.7
	holder.add_child(model)
	return holder


static func _swatch(element: Palette.Element, i: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.011
	ball.height = 0.022
	ball.radial_segments = 12
	ball.rings = 6
	mi.mesh = ball
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Palette.swatch(element, i)
	mat.roughness = 0.7
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Turns `hand`'s wheel to `degrees` of twist from where it opened, clockwise positive, showing its swatch
## on this machine only.
func twist(hand: Hand, degrees: float) -> void:
	var w: Wheel = wheels[hand]
	w.degrees = degrees
	var pick := twisted(w.target.count, w.start, degrees)
	if pick != w.pick:
		w.pick = pick
		_show(w, pick)
		hand.trigger_haptic_pulse(&"haptic", 0.0, 0.25, 0.02, 0.0)


## The choice `w` would send as the garden has it now, or -1 once its build is gone.
func _now(w: Wheel) -> int:
	if w.wall < 0:
		return world.palette.season
	if not world.state.walls.has(w.wall):
		return -1
	var d: Dictionary = world.state.walls[w.wall]
	if w.target.tool == Hand.Tool.COLOUR:
		return d.paint[w.target.element]
	match w.target.restyle:
		Restyle.GABLE:
			return d.gable_end
		Restyle.ROOF:
			return WallTool.roof_style(d)
		Restyle.TOP:
			return d.top
	return int(walls.arched(w.target.wall, w.target.s))


## The `reshape` data that gives `w`'s build choice `pick`; empty for one that cannot stand.
func _data(w: Wheel, pick: int) -> Dictionary:
	if w.target.tool == Hand.Tool.COLOUR:
		return {"paint": {w.target.element: pick}}
	match w.target.restyle:
		Restyle.GABLE:
			return {"gable_end": pick}
		Restyle.ROOF:
			return WallTool.restyle_roof(world.state.walls[w.wall], pick as WallTool.RoofStyle)
		Restyle.TOP:
			return {"top": pick}
	var arches: Variant = walls.arches_at(w.target.wall, w.target.s, pick == 1)
	return {"arches": arches} if arches != null else {}


## Shows `w`'s build or the meadow with choice `pick`, here alone.
func _show(w: Wheel, pick: int) -> void:
	if w.wall < 0:
		Palette.preview(pick)
		return
	var built := walls.find(w.wall)
	if built == null or not world.state.walls.has(w.wall):
		return
	if w.target.tool == Hand.Tool.COLOUR:
		var paint: PackedInt32Array = world.state.walls[w.wall].paint.duplicate()
		paint[w.target.element] = pick
		built.repaint(paint)
	else:
		walls.show_reshaped(built, _data(w, pick))


## Sends the choice at the top of `hand`'s wheel to the garden, unless the garden already has it (another
## player may have picked it meanwhile); until it comes back it shows here alone. A build's swatch or gable end
## becomes the one new builds take.
func close(hand: Hand) -> void:
	var w: Wheel = wheels[hand]
	_drop(hand)
	var now := _now(w)
	if now < 0:
		return
	if w.wall >= 0 and w.target.tool == Hand.Tool.COLOUR:
		walls.paint[w.target.element] = w.pick
	elif w.wall >= 0 and w.target.restyle == Restyle.GABLE:
		walls.gable_end = w.pick as WallLayout.GableEnd
	var data := _data(w, w.pick) if w.wall >= 0 else {}
	if w.pick == now or (w.wall >= 0 and data.is_empty()):
		_settled(w)
	elif w.wall < 0:
		world.submit({"op": "season", "index": w.pick}, world.palette.apply)
	else:
		world.submit({"op": "reshape", "id": w.wall, "data": data}, _settled.bind(w))


## A sent choice is settled before it applies, so the build is shown as the garden has it once it has.
func _settled(w: Wheel) -> void:
	(func() -> void:
		if w.wall < 0 or w.target.tool == Hand.Tool.COLOUR:
			_show(w, _now(w))
		else:
			walls.settle(w.wall)).call_deferred()


func _drop(hand: Hand) -> void:
	wheels[hand].node.queue_free()
	wheels.erase(hand)


## The wheel follows the hand but keeps the frame it opened in, turning with the twist; the picked choice
## stands at the top, larger.
func _place(w: Wheel, hand: Hand) -> void:
	w.node.global_transform = Transform3D(w.basis, hand.global_position + w.basis * WHEEL_AT)
	var n := w.choices.size()
	for k in n:
		var a := (w.degrees / Palette.TWIST_STEP - (k - w.start)) * TAU / n
		w.choices[k].position = Vector3(sin(a), cos(a), 0.0) * WHEEL_RADIUS
		w.choices[k].scale = Vector3.ONE * (1.6 if k == w.pick else 1.0)


## The choice of `count` a twist of `degrees` from choice `start` stands at the top.
static func twisted(count: int, start: int, degrees: float) -> int:
	return posmod(start + roundi(degrees / Palette.TWIST_STEP), count)


## Degrees the hand has turned about its pointing axis since `start`, clockwise as the hand sees it.
static func _roll(start: Basis, now: Basis) -> float:
	var fwd := -start.z
	var x := now.x - fwd * now.x.dot(fwd)
	return rad_to_deg(atan2(fwd.dot(start.x.cross(x)), start.x.dot(x)))
