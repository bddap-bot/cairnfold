class_name PaletteTool
extends Node3D

## The colour and style pickers, for whichever hand holds one: the trigger on a thing opens a wheel of its
## choices over the controller, and twisting the wrist turns the wheel like a dial, showing each choice live
## on this machine; letting go sends the choice at the top to the garden, so everyone building sees it, and it
## is one undo step. The colour tool's choices are swatches of the material pointed at: a build's stone, roof
## tiles, woodwork (fences, window frames, doors) or plaster, as a `reshape` of its paint (builds laid after
## take the swatch let go last), or on the meadow the garden's season. The style tool's are miniatures of the
## styles of what it points at: a gable end's, a roof's (pitched, a tower's cone, flat), a roofless wall's top,
## a wall's face (stone or plaster, plain or arched there; builds laid after take the material let go last), or a
## tree's species.

const BEAM := Color(1.0, 1.0, 1.0, 0.6)
const WHEEL_RADIUS := 0.07
## Where the wheel stands from the controller, in its frame when the trigger went down.
const WHEEL_AT := Vector3(0, 0.06, -0.05)

enum Restyle { GABLE, ROOF, TOP, FACE, TREE }
## A face's styles: stone or plaster, each plain or arched where it is pointed at.
enum Face { STONE, STONE_ARCHED, PLASTER, PLASTER_ARCHED, ALSACE, MAGPIE, RURAL, FACHWERK, COLOMBAGE }

## A hand's open wheel: what it changes (`aim`'s target) on which build (-1 for none) or tree (its trunk; null for
## none), the choice it started on and the one at its top, and the hand's frame when it opened. One on neither is
## on the meadow.
class Wheel:
	var wall := -1
	var tree: Flora.Plant
	var target: Dictionary
	var start := 0
	var pick := 0
	var degrees := 0.0
	var basis := Basis()
	var node: Node3D
	var choices: Array[Node3D] = []
	## Per choice, the `reshape` data that gives the build it, worked out from the build as the garden laid it: a
	## shown choice lays the build again, and an arch it shows would stand in the way of the one it sends.
	var data: Array[Dictionary] = []


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


## What the colour tool's trigger would recolour from `origin` along `dir`: `element`, `point` and the `wall` (null
## on the meadow), or empty.
func aim(origin: Vector3, dir: Vector3) -> Dictionary:
	var pick := walls.pick_wall(origin, dir)
	var roof := walls.pick_roof(origin, dir)
	var along: float = roof.get("along", INF)
	var gable := walls.pick_gable(origin, dir)
	if gable.get("along", INF) < along and WallTool._on_roof(pick, gable):
		if _on_timber(gable.wall.layout, gable.point):
			return colour_target(Palette.Element.TIMBER, gable.point, gable.wall)
		var end: WallLayout = gable.wall.layout
		var wood := end.gable_end == WallLayout.GableEnd.BOARDS
		return colour_target(Palette.Element.WOOD if wood else Palette.Element.PLASTER if end.plaster else Palette.Element.STONE, gable.point, gable.wall)
	if along < INF and (pick.is_empty() or pick.distance > 0.2 or along < pick.along):
		return colour_target(Palette.Element.ROOF, roof.point, roof.wall)
	if not pick.is_empty():
		var layout: WallLayout = pick.wall.layout
		if _on_timber(layout, pick.point):
			return colour_target(Palette.Element.TIMBER, pick.point, pick.wall)
		var wood := layout.fence or not layout.opening_at(pick.s, pick.point.y - layout.point_at(pick.s).y).is_empty()
		return colour_target(Palette.Element.WOOD if wood else Palette.Element.PLASTER if layout.plaster else Palette.Element.STONE, pick.point, pick.wall)
	var ground: Variant = Terrain.raycast(origin, dir)
	if ground != null:
		return colour_target(Palette.Element.MEADOW, ground, null)
	return {}


func colour_target(element: Palette.Element, point: Vector3, wall: Wall) -> Dictionary:
	return {"tool": Hand.Tool.COLOUR, "element": element, "count": Palette.count(element), "point": point, "wall": wall}


## What the style tool would restyle from `origin` along `dir`, as `aim` gives it, with `restyle` in place of an
## element (and `s` along a wall for its face), or empty: the tree, gable end, roof or wall it meets first, a
## roofless wall's top near it; fences and bushes have no style.
func aim_style(origin: Vector3, dir: Vector3) -> Dictionary:
	var pick := walls.pick_wall(origin, dir)
	var roof := walls.pick_roof(origin, dir)
	var gable := walls.pick_gable(origin, dir)
	var solid := walls.flora.solid_hit(origin, dir, DeleteTool.REACH)
	var nearest := minf(minf(gable.get("along", INF), roof.get("along", INF)), pick.get("along", INF))
	if solid.get("along", INF) < nearest and solid.plants[0].pool == walls.flora.trunks:
		return {"tool": Hand.Tool.STYLE, "restyle": Restyle.TREE, "count": FloraLayout.Species.size(), "point": solid.point, "wall": null, "tree": solid.plants[0]}
	if gable.get("along", INF) < roof.get("along", INF) and WallTool._on_roof(pick, gable):
		return style_target(Restyle.GABLE, gable.wall, gable.point)
	if WallTool._on_roof(pick, roof) and not WallTool.house_of(world.state.walls.get(roof.wall.id, {})).is_empty():
		return style_target(Restyle.ROOF, roof.wall, roof.point)
	if not pick.is_empty() and not pick.wall.layout.fence:
		var layout: WallLayout = pick.wall.layout
		var top: bool = layout.cover != WallLayout.Cover.ROOF and pick.point.y - layout.point_at(pick.s).y > layout.height - WallTool.TOP_BAND
		return style_target(Restyle.TOP if top else Restyle.FACE, pick.wall, pick.point, pick.s)
	return {}


func style_target(restyle: Restyle, wall: Wall, point: Vector3, s := 0.0) -> Dictionary:
	return {"tool": Hand.Tool.STYLE, "restyle": restyle, "count": styles(restyle), "point": point, "wall": wall, "s": s}


static func styles(restyle: Restyle) -> int:
	match restyle:
		Restyle.GABLE:
			return WallLayout.GableEnd.size()
		Restyle.ROOF:
			return WallTool.RoofStyle.size()
		Restyle.TOP:
			return WallLayout.Top.size()
		Restyle.TREE:
			return FloraLayout.Species.size()
	return Face.size()


## Opens the wheel for `target` (as `aim` or `aim_style` gives it) over `hand`, turning from its choice in the
## garden. While the trigger is held the hand's twist turns it; the driver, holding no trigger, turns it with `twist`.
func open(hand: Hand, target: Dictionary) -> void:
	var w := Wheel.new()
	w.target = target
	if target.wall != null:
		w.wall = target.wall.id
	w.tree = target.get("tree")
	w.start = _now(w)
	w.pick = w.start
	if w.wall >= 0 and target.tool == Hand.Tool.STYLE:
		for i in target.count:
			w.data.append(_data(w, i))
	w.basis = hand.global_basis.orthonormalized()
	w.node = Node3D.new()
	w.node.top_level = true
	for i in target.count:
		var choice := _swatch(target.element, i) if target.tool == Hand.Tool.COLOUR else _style(target.restyle, i, target.wall != null and target.wall.layout.plaster)
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


## The choice `w` would send as the garden has it now, or -1 once its build or tree is gone.
func _now(w: Wheel) -> int:
	if w.tree != null:
		var group: Dictionary = world.state.groups.get(w.tree.group, {})
		if walls.flora.species_of(w.tree) < 0 or group.is_empty():
			return -1
		return group.species.get(w.tree.index, FloraLayout.Species.OAK)
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
	if TimberFrame.applies(w.target.wall.layout):
		return Face.ALSACE + d.get("timber_style", 0)
	return int(walls.arched(w.target.wall, w.target.s)) + (Face.PLASTER if d.plaster else Face.STONE)


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
	var data := {}
	var timber_style: int = pick - Face.ALSACE if pick >= Face.ALSACE else -1
	if timber_style != world.state.walls[w.wall].get("timber_style", 0):
		data["timber_style"] = timber_style
	var plaster := pick >= Face.PLASTER
	if plaster != world.state.walls[w.wall].plaster:
		data["plaster"] = plaster
	var arched := walls.arched(w.target.wall, w.target.s) if pick >= Face.ALSACE else pick % 2 == 1
	if arched != walls.arched(w.target.wall, w.target.s):
		var arches: Variant = walls.arches_at(w.target.wall, w.target.s, arched)
		if arches == null:
			return {}
		data["arches"] = arches
	return data


## Shows `w`'s build, tree or the meadow with choice `pick`, here alone.
func _show(w: Wheel, pick: int) -> void:
	if w.tree != null:
		walls.flora.set_species(w.tree, pick as FloraLayout.Species)
		return
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
		walls.show_reshaped(built, w.data[pick])


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
	elif w.wall >= 0 and w.target.restyle == Restyle.FACE:
		walls.plaster = w.pick >= Face.PLASTER
		walls.timber_style = w.pick - Face.ALSACE if w.pick >= Face.ALSACE else -1
	var data: Dictionary = (w.data[w.pick] if w.target.tool == Hand.Tool.STYLE else _data(w, w.pick)) if w.wall >= 0 else {}
	if w.pick == now or (w.wall >= 0 and data.is_empty()):
		_settled(w)
	elif w.tree != null:
		world.submit({"op": "species", "group": w.tree.group, "index": w.tree.index, "species": w.pick}, _settled.bind(w))
	elif w.wall < 0:
		world.submit({"op": "season", "index": w.pick}, world.palette.apply)
	else:
		world.submit({"op": "reshape", "id": w.wall, "data": data}, _settled.bind(w))


## A sent choice is settled before it applies, so the build is shown as the garden has it once it has.
func _settled(w: Wheel) -> void:
	(func() -> void:
		if w.tree != null:
			if _now(w) >= 0:
				_show(w, _now(w))
		elif w.wall < 0 or w.target.tool == Hand.Tool.COLOUR:
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


static func twisted(count: int, start: int, degrees: float) -> int:
	return posmod(start + roundi(degrees / Palette.TWIST_STEP), count)


## Degrees the hand has turned about its pointing axis since `start`, clockwise as the hand sees it.
static func _roll(start: Basis, now: Basis) -> float:
	var fwd := -start.z
	var x := now.x - fwd * now.x.dot(fwd)
	return rad_to_deg(atan2(fwd.dot(start.x.cross(x)), start.x.dot(x)))


static func _on_timber(layout: WallLayout, point: Vector3) -> bool:
	for part in layout.stones:
		if part.kind == "timber":
			var local: Vector3 = part.xform.affine_inverse() * point
			if absf(local.x) <= 0.5 and absf(local.y) <= 0.65 and absf(local.z) <= 3.5:
				return true
	return false
