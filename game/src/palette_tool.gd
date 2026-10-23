class_name PaletteTool
extends Node3D

## The colour and style pickers, for whichever hand holds one: the trigger on a thing opens a wheel of its
## choices over the controller, and twisting the wrist turns the wheel like a dial, showing each choice live
## on this machine; letting go sends the choice at the top to the garden, so everyone building sees it, and it
## is one undo step. The colour tool's choices are swatches of the material pointed at: a build's stone, roof
## tiles, woodwork (fences, window frames, doors, wooden railings, ladders) or plaster, as a `reshape` of its paint
## (builds laid after take the swatch let go last), or on the meadow the garden's season. The style tool's are
## miniatures of the styles of what it points at: a gable end's, a roof's covering (stone when flat, tile or thatch when pitched, a house's or a
## tower's), a roofless wall's top, a wall's face (stone, plaster or a house's timber framing; builds laid after take
## the material let go last), a house's or tower's floor (flags or planks, apart from its walls; houses laid after take
## it), a flight's or landing's railings (stairs laid after take them), a tree's species, or a stroke of painted
## stone ground's or a boulder's, one list of stone styles (StoneStyles; stone painted and boulders set down after take
## the style let go last). It only restyles: openings are the windows' and the arch's.

const BEAM := Color(1.0, 1.0, 1.0, 0.6)
const WHEEL_RADIUS := 0.07
## A wheel of many choices widens so neighbours stay this far apart around it.
const CHOICE_GAP := 0.045
## Where the wheel stands from the controller, in its frame when the trigger went down.
const WHEEL_AT := Vector3(0, 0.06, -0.05)

enum Restyle { GABLE, ROOF, TOP, FACE, TREE, RAIL, STONE, DECORATION, FLOOR }
enum Face { STONE, PLASTER, TIMBER }
enum Floor { FLAGS, PLANKS }

## A hand's open wheel: what it changes (`aim`'s target) on which build (its garden table `of` and `id`; "" and -1 for
## none; a boulder's is "boulders"), tree (its trunk; null for none) or stone stroke (-1 for none), the choice it started on and the one at its top,
## and the hand's frame when it opened. One on none of them is on the meadow.
class Wheel:
	var of := ""
	var id := -1
	var tree: Flora.Plant
	var stroke := -1
	var target: Dictionary
	var start := 0
	var pick := 0
	var degrees := 0.0
	var basis := Basis()
	var node: Node3D
	var choices: Array[Node3D] = []
	## Per choice, the `reshape` data that gives the build it, worked out from the build as the garden laid it.
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
			twist(hand, wheel.degrees + wrapf(_roll(wheel.basis, hand.global_basis) - wheel.degrees, -180.0, 180.0))
		elif wheel == null and hand.tool in [Hand.Tool.COLOUR, Hand.Tool.STYLE] and rig.aim_hand != hand and hand.tracked():
			var t := hand.global_transform
			var target := aim(t.origin, -t.basis.z) if hand.tool == Hand.Tool.COLOUR else aim_style(t.origin, -t.basis.z)
			hand.point(target.get("point", null), BEAM)
			if b.pressed("tool") and not target.is_empty() and not busy():
				open(hand, target)
		b.latch()
	for hand in wheels:
		hand.hold()
		_place(wheels[hand], hand)


## What the colour tool's trigger would recolour from `origin` along `dir`: `element`, `point` and the build's garden
## table `of` and `id` ("" and -1 on the meadow), or empty.
func aim(origin: Vector3, dir: Vector3) -> Dictionary:
	var hits := world.pick(origin, dir, {World.Kind.BUILDING: INF, World.Kind.GROUND: INF, World.Kind.BOULDER: INF, World.Kind.STAIRS: INF})
	var pick: Dictionary = hits.get(World.Kind.BUILDING, {})
	var roof := pick if pick.get("surface") == "roof" else {}
	var gable := pick if pick.get("surface") == "gable" else {}
	var rock: Dictionary = hits.get(World.Kind.BOULDER, {})
	var stair: Dictionary = hits.get(World.Kind.STAIRS, {})
	if not stair.is_empty():
		return colour_target(Palette.KINDS[stair.kind], stair.point, "stairs", stair.stair)
	if not rock.is_empty():
		return colour_target(Palette.Element.STONE, rock.point, "boulders", rock.boulder.id)
	if not gable.is_empty():
		if _on_timber(gable.wall.layout, gable.point):
			return colour_target(Palette.Element.TIMBER, gable.point, "walls", gable.wall.id)
		var end: WallLayout = gable.wall.layout
		var wood := end.gable_end == WallLayout.GableEnd.BOARDS
		return colour_target(Palette.Element.WOOD if wood else Palette.Element.PLASTER if end.plaster else Palette.Element.STONE, gable.point, "walls", gable.wall.id)
	if not roof.is_empty():
		var r: RoofLayout = roof.wall.roof
		var covering := (Palette.Element.WOOD if r.deck == RoofLayout.Deck.WOOD else Palette.Element.STONE) if r.flat() else Palette.Element.THATCH if r.thatched() else Palette.Element.ROOF
		return colour_target(covering, roof.point, "walls", roof.wall.id)
	if not pick.is_empty():
		var layout: WallLayout = pick.wall.layout
		if _on_timber(layout, pick.point):
			return colour_target(Palette.Element.TIMBER, pick.point, "walls", pick.wall.id)
		var wood := layout.fence or not layout.opening_at(pick.s, pick.point.y - layout.point_at(pick.s).y).is_empty()
		return colour_target(Palette.Element.WOOD if wood else Palette.Element.PLASTER if layout.plaster_at(pick.point.y - layout.point_at(pick.s).y) else Palette.Element.STONE, pick.point, "walls", pick.wall.id)
	if hits.has(World.Kind.GROUND):
		return colour_target(Palette.Element.MEADOW, hits[World.Kind.GROUND].point)
	return {}


func colour_target(element: Palette.Element, point: Vector3, of := "", id := -1) -> Dictionary:
	return {"tool": Hand.Tool.COLOUR, "element": element, "count": Palette.count(element), "point": point, "of": of, "id": id}


## What the style tool would restyle from `origin` along `dir`, as `aim` gives it, with `restyle` in place of an
## element, or empty: the tree, stairs, boulder, floor, gable end, roof, wall or painted stone it meets first, a
## roofless wall's top near it; fences, ladders, bushes and unpaved ground have no style.
func aim_style(origin: Vector3, dir: Vector3) -> Dictionary:
	var hits := world.pick(origin, dir, {World.Kind.TARGET: INF, World.Kind.PLANT: DeleteTool.REACH, World.Kind.FLOOR: INF, World.Kind.STAIRS: INF, World.Kind.BOULDER: INF, World.Kind.GROUND: INF})
	var pick: Dictionary = hits.get(World.Kind.TARGET, {})
	var roof := pick if pick.get("surface") == "roof" else {}
	var gable := pick if pick.get("surface") == "gable" else {}
	var solid: Dictionary = hits.get(World.Kind.PLANT, {})
	var floor: Dictionary = hits.get(World.Kind.FLOOR, {})
	var stair: Dictionary = hits.get(World.Kind.STAIRS, {})
	var rock: Dictionary = hits.get(World.Kind.BOULDER, {})
	var ground: Variant = hits[World.Kind.GROUND].point if hits.has(World.Kind.GROUND) else null
	var stroke := Ground.mark_at(ground.x, ground.z) if ground != null and Ground.stone(ground.x, ground.z) > 0.5 else -1
	if world.state.grounds.has(stroke):
		return {"tool": Hand.Tool.STYLE, "restyle": Restyle.STONE, "count": styles(Restyle.STONE), "point": ground, "of": "", "id": -1, "wall": null, "stroke": stroke}
	if not rock.is_empty():
		return {"tool": Hand.Tool.STYLE, "restyle": Restyle.STONE, "count": styles(Restyle.STONE), "point": rock.point, "of": "boulders", "id": rock.boulder.id, "wall": null}
	if not stair.is_empty():
		if world.stairs.layouts[stair.stair].kind == StairLayout.Kind.LADDER:
			return {}
		return {"tool": Hand.Tool.STYLE, "restyle": Restyle.RAIL, "count": styles(Restyle.RAIL), "point": stair.point, "of": "stairs", "id": stair.stair, "wall": null}
	if not floor.is_empty():
		return style_target(Restyle.FLOOR, floor.wall, floor.point)
	if not solid.is_empty() and solid.plants[0].pool == walls.flora.trunks:
		return {"tool": Hand.Tool.STYLE, "restyle": Restyle.TREE, "count": FloraLayout.Species.size(), "point": solid.point, "of": "", "id": -1, "wall": null, "tree": solid.plants[0]}
	if pick.has("decoration"):
		return {"tool": Hand.Tool.STYLE, "restyle": Restyle.DECORATION, "options": range(DecorationLayout.STYLES.size()), "count": DecorationLayout.STYLES.size(), "point": pick.point, "of": "decorations", "id": pick.decoration, "wall": pick.wall}
	if not gable.is_empty():
		return style_target(Restyle.GABLE, gable.wall, gable.point)
	if not roof.is_empty() and not WallTool.house_of(world.state.walls.get(roof.wall.id, {})).is_empty():
		return style_target(Restyle.ROOF, roof.wall, roof.point)
	if not pick.is_empty() and not pick.wall.layout.fence:
		var layout: WallLayout = pick.wall.layout
		var top: bool = layout.cover != WallLayout.Cover.ROOF and pick.point.y - layout.point_at(pick.s).y > layout.height - WallTool.TOP_BAND
		return style_target(Restyle.TOP if top else Restyle.FACE, pick.wall, pick.point)
	return {}


func style_target(restyle: Restyle, wall: Wall, point: Vector3) -> Dictionary:
	var foundation := restyle == Restyle.FACE and point.y < wall.layout.point_at(wall.layout.closest_s(point)).y
	var count := Face.TIMBER if foundation else styles(restyle)
	if not foundation and restyle == Restyle.FACE and not (wall.layout.closed and wall.layout.corners().size() == 4):
		count = 1 if wall.roof != null and wall.roof.kind == RoofLayout.Kind.CONE else Face.TIMBER
	var options: Array = WallTool.roof_options(wall.roof.pitch) if restyle == Restyle.ROOF else range(count)
	return {"tool": Hand.Tool.STYLE, "restyle": restyle, "options": options, "face_key": "plinth_plaster" if foundation else "plaster", "count": options.size(), "point": point, "of": "walls", "id": wall.id, "wall": wall}


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
		Restyle.RAIL:
			return StairLayout.RAILS.size()
		Restyle.STONE:
			return StoneStyles.STYLES.size()
		Restyle.FLOOR:
			return Floor.size()
	return Face.size()


## Opens the wheel for `target` (as `aim` or `aim_style` gives it) over `hand`, turning from its choice in the
## garden. While the trigger is held the hand's twist turns it; the driver, holding no trigger, turns it with `twist`.
func open(hand: Hand, target: Dictionary) -> void:
	var start := Time.get_ticks_usec()
	var w := Wheel.new()
	w.target = target
	w.of = target.of
	w.id = target.id
	w.tree = target.get("tree")
	w.stroke = target.get("stroke", -1)
	w.start = _now(w)
	w.pick = w.start
	if w.id >= 0 and target.tool == Hand.Tool.STYLE:
		for i in target.count:
			w.data.append(_data(w, i))
	w.basis = hand.global_basis.orthonormalized()
	w.node = Node3D.new()
	w.node.top_level = true
	for i in target.count:
		var choice := _swatch(target.element, i) if target.tool == Hand.Tool.COLOUR else _style(target.restyle, target.get("options", range(target.count))[i], target.wall, target.of == "boulders", target.get("face_key", "") == "plaster")
		w.node.add_child(choice)
		w.choices.append(choice)
	add_child(w.node)
	wheels[hand] = w
	_place(w, hand)
	Metrics.note("style wheel: opened on %s" % Restyle.find_key(target.get("restyle", -1)) if target.tool == Hand.Tool.STYLE else "colour wheel: opened", (Time.get_ticks_usec() - start) / 1000.0)


## A style's miniature smaller than it stands on a controller, so the wheel's choices stay apart.
static func _style(restyle: Restyle, i: int, wall: Wall, boulder := false, face := false) -> Node3D:
	var holder := Node3D.new()
	var house := face and wall != null and wall.layout.closed and wall.layout.corners().size() == 4
	var model := ToolModels.style(restyle, i, wall != null and wall.layout.plaster, wall != null and wall.roof != null and wall.roof.kind == RoofLayout.Kind.CONE, boulder, house)
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
		Cues.play(Cues.Act.DIAL_TURN, hand.global_position, hand)


## The choice `w` would send as the garden has it now, or -1 once its build or tree is gone.
func _now(w: Wheel) -> int:
	if w.tree != null:
		var group: Dictionary = world.state.groups.get(w.tree.group, {})
		if walls.flora.species_of(w.tree) < 0 or group.is_empty():
			return -1
		return group.species.get(w.tree.index, FloraLayout.Species.OAK)
	if w.stroke >= 0:
		return world.state.grounds.get(w.stroke, {}).get("style", -1)
	if w.id < 0:
		return world.palette.season
	if not world.state[w.of].has(w.id):
		return -1
	var d: Dictionary = world.state[w.of][w.id]
	if w.target.tool == Hand.Tool.COLOUR:
		return d.paint[w.target.element]
	match w.target.restyle:
		Restyle.RAIL:
			return StairLayout.RAILS.find(d.rail)
		Restyle.GABLE:
			return d.gable_end
		Restyle.ROOF:
			return w.target.options.find(WallTool.roof_style(d))
		Restyle.TOP:
			return d.top
		Restyle.DECORATION:
			return w.target.options.find(d.style)
		Restyle.STONE:
			return d.style
		Restyle.FLOOR:
			return Floor.PLANKS if d.planks else Floor.FLAGS
	if w.target.face_key == "plaster" and d.plaster and d.timber_style >= 0 and d.closed and d.points.size() == 4:
		return Face.TIMBER
	return Face.PLASTER if d[w.target.face_key] else Face.STONE


## The `reshape` data that gives `w`'s build choice `pick`; empty for one that cannot stand.
func _data(w: Wheel, pick: int) -> Dictionary:
	if w.target.tool == Hand.Tool.COLOUR:
		return {"paint": {w.target.element: pick}}
	match w.target.restyle:
		Restyle.GABLE:
			return {"gable_end": pick}
		Restyle.ROOF:
			return WallTool.restyle_roof(world.state.walls[w.id], w.target.options[pick] as WallTool.RoofStyle)
		Restyle.TOP:
			return {"top": pick}
		Restyle.RAIL:
			return {"rail": StairLayout.RAILS[pick]}
		Restyle.DECORATION:
			return {"style": w.target.options[pick]}
		Restyle.STONE:
			return {"style": pick}
		Restyle.FLOOR:
			return {"planks": pick == Floor.PLANKS}
	var data := {}
	var timber_style: int = 0 if pick == Face.TIMBER else -1
	if w.target.face_key == "plaster" and timber_style != world.state.walls[w.id].timber_style:
		data["timber_style"] = timber_style
	var plaster := pick >= Face.PLASTER
	if plaster != world.state.walls[w.id][w.target.face_key]:
		data[w.target.face_key] = plaster
	return data


## Shows `w`'s build, tree or the meadow with choice `pick`, here alone.
func _show(w: Wheel, pick: int) -> void:
	if w.tree != null:
		walls.flora.set_look(w.tree, pick as FloraLayout.Species, walls.flora.scale_of(w.tree))
		return
	if w.stroke >= 0:
		Ground.restyle(w.stroke, pick)
		return
	if w.id < 0:
		Palette.preview(pick)
		return
	if world.state[w.of].has(w.id):
		_builder(w.of).show_reshaped(w.id, _data(w, pick) if w.target.tool == Hand.Tool.COLOUR else w.data[pick])


## What lays the builds of the garden's table `of`: each shows a reshape before it is sent and `settle`s back.
func _builder(of: String) -> Object:
	return {"walls": walls, "stairs": world.stairs, "boulders": world.boulders, "decorations": world.decorations}[of]


## Sends the choice at the top of `hand`'s wheel to the garden, unless the garden already has it (another
## player may have picked it meanwhile); until it comes back it shows here alone. A build's swatch or gable end
## becomes the one new builds take.
func close(hand: Hand) -> void:
	var w: Wheel = wheels[hand]
	_drop(hand)
	var now := _now(w)
	if now < 0:
		return
	if w.id >= 0 and w.target.tool == Hand.Tool.COLOUR:
		walls.paint[w.target.element] = w.pick
	elif w.id >= 0 and w.target.restyle == Restyle.GABLE:
		walls.gable_end = w.pick as WallLayout.GableEnd
	elif w.id >= 0 and w.target.restyle == Restyle.ROOF and w.target.options[w.pick] in [WallTool.RoofStyle.FLAT, WallTool.RoofStyle.BOARDED]:
		walls.deck = RoofLayout.Deck.WOOD if w.target.options[w.pick] == WallTool.RoofStyle.BOARDED else RoofLayout.Deck.STONE
	elif w.id >= 0 and w.target.restyle == Restyle.ROOF:
		walls.thatch = w.target.options[w.pick] == WallTool.RoofStyle.THATCHED
	elif w.id >= 0 and w.target.restyle == Restyle.FACE and w.target.face_key == "plaster":
		walls.plaster = w.pick >= Face.PLASTER
		walls.timber_style = 0 if w.pick == Face.TIMBER else -1
	elif w.id >= 0 and w.target.restyle == Restyle.FLOOR:
		walls.planks = w.pick == Floor.PLANKS
	elif w.id >= 0 and w.target.restyle == Restyle.RAIL:
		world.stairs.rail = StairLayout.RAILS[w.pick]
	elif w.target.get("restyle") == Restyle.STONE:
		Ground.style = w.pick
	var data: Dictionary = (w.data[w.pick] if w.target.tool == Hand.Tool.STYLE else _data(w, w.pick)) if w.id >= 0 else {}
	if w.pick == now or (w.id >= 0 and data.is_empty()):
		_settled(w)
		return
	Cues.play(Cues.Act.DIAL_SET, hand.global_position, hand)
	if w.stroke >= 0:
		world.submit({"op": "restone", "id": w.stroke, "style": w.pick}, _settled.bind(w), hand)
	elif w.tree != null:
		world.submit({"op": "tree", "group": w.tree.group, "index": w.tree.index, "species": w.pick}, _settled.bind(w), hand)
	elif w.id < 0:
		world.submit({"op": "season", "index": w.pick}, world.palette.apply, hand)
	else:
		world.submit({"op": "reshape", "of": w.of, "id": w.id, "data": data}, _settled.bind(w), hand)


## A sent choice is settled before it applies, so the build is shown as the garden has it once it has.
func _settled(w: Wheel) -> void:
	(func() -> void:
		if w.tree != null or w.stroke >= 0:
			if _now(w) >= 0:
				_show(w, _now(w))
		elif w.id < 0 or w.target.tool == Hand.Tool.COLOUR:
			_show(w, _now(w))
		else:
			_builder(w.of).settle(w.id)).call_deferred()


func _drop(hand: Hand) -> void:
	wheels[hand].node.queue_free()
	wheels.erase(hand)


## The wheel follows the hand but keeps the frame it opened in, turning with the twist; the picked choice
## stands at the top, larger.
func _place(w: Wheel, hand: Hand) -> void:
	w.node.global_transform = Transform3D(w.basis, hand.global_position + w.basis * WHEEL_AT)
	var n := w.choices.size()
	for k in n:
		var a := (w.degrees / Palette.twist_step(n) - (k - w.start)) * TAU / n
		w.choices[k].position = Vector3(sin(a), cos(a), 0.0) * maxf(WHEEL_RADIUS, n * CHOICE_GAP / TAU)
		w.choices[k].scale = Vector3.ONE * (1.6 if k == w.pick else 1.0)


static func twisted(count: int, start: int, degrees: float) -> int:
	return posmod(start + roundi(degrees / Palette.twist_step(count)), count)


## Degrees the hand has turned about its pointing axis since `start`, clockwise as the hand sees it.
static func _roll(start: Basis, now: Basis) -> float:
	var fwd := -start.z
	var x := now.x - fwd * now.x.dot(fwd)
	return rad_to_deg(atan2(fwd.dot(start.x.cross(x)), start.x.dot(x)))


static func _on_timber(layout: WallLayout, point: Vector3) -> bool:
	for part in layout.stones:
		if part.kind == "timber":
			var local: Vector3 = part.xform.affine_inverse() * point
			# An arch's wedge runs through the wall along its local y (WallLayout._wedge).
			if part.has("ends"):
				local = Vector3(local.x, local.z, local.y)
			if absf(local.x) <= 0.5 and absf(local.y) <= 0.65 and absf(local.z) <= 3.5:
				return true
	return false
