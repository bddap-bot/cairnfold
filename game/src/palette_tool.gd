class_name PaletteTool
extends Node3D

## The colour and style pickers, for whichever hand holds one: the trigger on a thing opens a wheel of its
## choices over the controller, and twisting the wrist turns the wheel like a dial, showing each choice live
## on this machine; letting go sends the choice at the top to the garden, so everyone building sees it, and it
## is one undo step. The colour tool's choices are swatches of the material pointed at: a build's stone, roof
## tiles, woodwork (fences, window frames, doors, wooden railings, ladders) or plaster, as a `reshape` of its paint
## (builds laid after take the swatch let go last), or on the meadow the garden's season. The style tool's are
## miniatures of the styles of what it points at: a gable end's, a roof's covering (stone when flat, tile or thatch when pitched, a house's or a
## tower's), a roofless wall's top, a wall's face (stone, plaster worn back to the stone by a chosen amount, timber
## framing, or planks across or upright) or a fence's (rails or planks; builds laid after take the finish let go last),
## a foundation (stone or plaster, or under a house or tower stone pillars or timber posts
## for it to stand on when raised; houses laid after take it), a house's or tower's floor (flags or planks, apart from its walls; houses laid after take
## it), a flight's or landing's railings (stairs laid after take them), a tree's species, or a stroke of painted
## stone ground's or a boulder's, one list of stone styles (StoneStyles; stone painted and boulders set down after take
## the style let go last), a path's surface (dirt, sand, cobbles, flagstones or a garden bed; paths laid after take it),
## or a window's family (cottage, arched, arrow slit or round; a door's cottage or arched, the
## lights fused with it alike; windows opened after take it), a decoration's (the strings' between a string of lanterns
## and one of flags; strings hung after take it). It only restyles: openings are the windows' and the arch's, and a
## corner window is the windows' at a corner. The colour tool on a room's window picks the colour its glass glows at
## night, and on a lantern, or a decoration with a flame, its colour and brightness: a wall's lanterns all burn alike.
## A tap of the colour tool's trigger on a wall, house, tower or fence takes its look into the hand (`look_of`), and each
## tap on another after lays that look on it (`look_onto`), one undo step each; a tap anywhere else lets the look go.

const BEAM := Color(1.0, 1.0, 1.0, 0.6)
const WHEEL_RADIUS := 0.07
## A wheel of many choices widens so neighbours stay this far apart around it.
const CHOICE_GAP := 0.045
## Where the wheel stands from the controller, in its frame when the trigger went down.
const WHEEL_AT := Vector3(0, 0.06, -0.05)
## The longest press of the colour tool's trigger, in seconds, that leaves its wheel where it opened and is a tap.
const TAP := 0.3

enum Restyle { GABLE, ROOF, TOP, FACE, TREE, RAIL, STONE, DECORATION, FLOOR, FOUNDATION, WINDOW, PATH }
## The face wheel's choices, each a WallLayout.Finish and how worn its plaster is.
const FACES: Array[Vector2] = [Vector2(WallLayout.Finish.BARE, 0.0), Vector2(WallLayout.Finish.PLASTER, 0.0), Vector2(WallLayout.Finish.PLASTER, 0.25), Vector2(WallLayout.Finish.PLASTER, 0.5), Vector2(WallLayout.Finish.PLASTER, 0.75), Vector2(WallLayout.Finish.TIMBER, 0.0), Vector2(WallLayout.Finish.BOARDS_ACROSS, 0.0), Vector2(WallLayout.Finish.BOARDS_UPRIGHT, 0.0)]
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
	## Seconds of game time it has been open.
	var held := 0.0
	var node: Node3D
	var choices: Array[Node3D] = []
	## Per choice, the `reshape` data that gives the build it, worked out from the build as the garden laid it.
	var data: Array[Dictionary] = []


var rig: Rig
var walls: WallTool
var world: World
var wheels := {}
## The look each hand's colour tool took with a tap, as `look_of` gives it.
var looks := {}
var _buttons: Array[Buttons] = []


func _init(player: Rig, builder: WallTool, garden: World) -> void:
	rig = player
	walls = builder
	world = garden
	for h in rig.hands:
		_buttons.append(Buttons.new(h).watch(["tool"]))
	world.restored.connect(func() -> void:
		looks.clear()
		for hand in wheels.keys():
			_drop(hand))


## Whether `hand`, or with none any hand, holds a wheel open. One wheel at a time, so two hands never pick for one
## material from stale starts.
func busy(hand: Hand = null) -> bool:
	return wheels.has(hand) if hand != null else not wheels.is_empty()


func _process(delta: float) -> void:
	for w: Wheel in wheels.values():
		w.held += delta
	for b in _buttons:
		var hand: Hand = b.hand
		var wheel: Wheel = wheels.get(hand)
		if hand.tool != Hand.Tool.COLOUR:
			looks.erase(hand)
		if wheel != null and (hand.tool != wheel.target.tool or b.released("tool")):
			close(hand, hand.tool == wheel.target.tool)
		elif wheel != null and b.held("tool"):
			twist(hand, wheel.degrees + wrapf(_roll(wheel.basis, hand.global_basis) - wheel.degrees, -180.0, 180.0))
		elif wheel == null and hand.tool in [Hand.Tool.COLOUR, Hand.Tool.STYLE] and rig.aim_hand != hand and hand.tracked():
			var t := hand.global_transform
			var target := aim(t.origin, -t.basis.z) if hand.tool == Hand.Tool.COLOUR else aim_style(t.origin, -t.basis.z)
			hand.point(target.get("point", null), _beam(looks.get(hand, {})))
			if b.pressed("tool") and not target.is_empty() and not busy():
				open(hand, target)
		b.latch()
	for hand in wheels:
		hand.hold()
		_place(wheels[hand], hand)


## What the colour tool's trigger would recolour from `origin` along `dir`: `element`, `point` and the build's garden
## table `of` and `id` ("" and -1 on the meadow), or empty.
func aim(origin: Vector3, dir: Vector3) -> Dictionary:
	var hits := world.pick(origin, dir, {World.Kind.BUILDING: INF, World.Kind.TARGET: INF, World.Kind.GROUND: INF, World.Kind.BOULDER: INF, World.Kind.STAIRS: INF})
	var fitting: Dictionary = hits.get(World.Kind.TARGET, {})
	var pick: Dictionary = hits.get(World.Kind.BUILDING, {})
	var roof := pick if pick.get("surface") == "roof" else {}
	var gable := pick if pick.get("surface") == "gable" else {}
	var rock: Dictionary = hits.get(World.Kind.BOULDER, {})
	var stair: Dictionary = hits.get(World.Kind.STAIRS, {})
	if not stair.is_empty():
		return colour_target(Palette.KINDS.get(stair.kind, Palette.Element.WOOD), stair.point, "stairs", stair.stair)
	if not rock.is_empty():
		return colour_target(Palette.Element.STONE, rock.point, "boulders", rock.boulder.id)
	if fitting.get("what") == "lantern":
		return colour_target(Palette.Element.LANTERN, fitting.point, "walls", fitting.wall.id)
	if fitting.has("decoration") and world.decorations.lit(fitting.decoration):
		return colour_target(Palette.Element.LANTERN, fitting.point, "decorations", fitting.decoration)
	if not gable.is_empty():
		if _on_timber(gable.wall.layout, gable.point):
			return colour_target(Palette.Element.TIMBER, gable.point, "walls", gable.wall.id)
		var end: WallLayout = gable.wall.layout
		var wood := end.gable_kind() == WallLayout.GableEnd.BOARDS
		return colour_target(Palette.Element.WOOD if wood else Palette.Element.PLASTER if end.plastered() else Palette.Element.STONE, gable.point, "walls", gable.wall.id)
	if not roof.is_empty():
		var r: RoofLayout = roof.wall.roof
		var covering := (Palette.Element.WOOD if r.deck == RoofLayout.Deck.WOOD else Palette.Element.STONE) if r.flat() else Palette.Element.THATCH if r.thatched() else Palette.Element.ROOF
		return colour_target(covering, roof.point, "walls", roof.wall.id)
	if not pick.is_empty():
		var layout: WallLayout = pick.wall.layout
		if _on_timber(layout, pick.point):
			return colour_target(Palette.Element.TIMBER, pick.point, "walls", pick.wall.id)
		var y: float = pick.point.y - layout.point_at(pick.s).y
		var opening := layout.opening_at(pick.s, y)
		if not opening.is_empty() and not opening.door and layout.floored():
			return colour_target(Palette.Element.GLOW, pick.point, "walls", pick.wall.id)
		var wood := layout.fence or layout.boards_at(y) or not opening.is_empty()
		return colour_target(Palette.Element.WOOD if wood else Palette.Element.PLASTER if layout.plaster_at(y) else Palette.Element.STONE, pick.point, "walls", pick.wall.id)
	if hits.has(World.Kind.GROUND):
		return colour_target(Palette.Element.MEADOW, hits[World.Kind.GROUND].point)
	return {}


func colour_target(element: Palette.Element, point: Vector3, of := "", id := -1) -> Dictionary:
	return {"tool": Hand.Tool.COLOUR, "element": element, "count": Palette.count(element), "point": point, "of": of, "id": id}


## What the style tool would restyle from `origin` along `dir`, as `aim` gives it, with `restyle` in place of an
## element, or empty: the tree, stairs, boulder, floor, gable end, roof, wall, fence, path or painted stone it meets first,
## a roofless wall's top near it; ladders, single-rope bridges, bushes and the bare meadow have no style.
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
	var stroke := world.marks.mark_at(ground.x, ground.z) if ground != null and world.marks.laid_bare(ground.x, ground.z) > 0.5 else -1
	if world.state.paths.has(stroke):
		return {"tool": Hand.Tool.STYLE, "restyle": Restyle.PATH, "count": styles(Restyle.PATH), "point": ground, "of": "paths", "id": stroke, "wall": null}
	if world.state.grounds.has(stroke):
		return {"tool": Hand.Tool.STYLE, "restyle": Restyle.STONE, "count": styles(Restyle.STONE), "point": ground, "of": "", "id": -1, "wall": null, "stroke": stroke}
	if not rock.is_empty():
		return {"tool": Hand.Tool.STYLE, "restyle": Restyle.STONE, "count": styles(Restyle.STONE), "point": rock.point, "of": "boulders", "id": rock.boulder.id, "wall": null}
	if not stair.is_empty():
		if not StairLayout.can_rail(world.state.stairs[stair.stair]):
			return {}
		return {"tool": Hand.Tool.STYLE, "restyle": Restyle.RAIL, "count": styles(Restyle.RAIL), "point": stair.point, "of": "stairs", "id": stair.stair, "wall": null}
	if not floor.is_empty():
		return style_target(Restyle.FLOOR, floor.wall, floor.point)
	if not solid.is_empty() and solid.plants[0].pool == walls.flora.trunks:
		return {"tool": Hand.Tool.STYLE, "restyle": Restyle.TREE, "count": FloraLayout.Species.size(), "point": solid.point, "of": "", "id": -1, "wall": null, "tree": solid.plants[0]}
	if pick.get("what") == "opening" and int(pick.value.z) in WallLayout.WINDOW_FAMILIES:
		return window_target(pick.wall, pick.value, pick.point)
	if pick.has("decoration"):
		var options := DecorationLayout.standing(world.state.decorations[pick.decoration].mount)
		return {"tool": Hand.Tool.STYLE, "restyle": Restyle.DECORATION, "options": options, "count": options.size(), "point": pick.point, "of": "decorations", "id": pick.decoration, "wall": pick.wall}
	if not gable.is_empty():
		return style_target(Restyle.GABLE, gable.wall, gable.point)
	if not roof.is_empty() and not WallTool.house_of(world.state.walls.get(roof.wall.id, {})).is_empty():
		return style_target(Restyle.ROOF, roof.wall, roof.point)
	if not pick.is_empty():
		var layout: WallLayout = pick.wall.layout
		var top: bool = not layout.fence and layout.cover != WallLayout.Cover.ROOF and pick.point.y - layout.point_at(pick.s).y > layout.height - WallTool.TOP_BAND
		return style_target(Restyle.TOP if top else Restyle.FACE, pick.wall, pick.point)
	return {}


func style_target(restyle: Restyle, wall: Wall, point: Vector3) -> Dictionary:
	if restyle == Restyle.FACE and point.y < wall.layout.point_at(wall.layout.closest_s(point)).y:
		restyle = Restyle.FOUNDATION
	var count := styles(restyle)
	if restyle == Restyle.FOUNDATION and not (wall.layout.floored() and wall.layout.supports.is_empty()):
		count = WallLayout.Foundation.PILLARS
	var options: Array = WallTool.roof_options(wall.roof.pitch) if restyle == Restyle.ROOF else range(count)
	if restyle == Restyle.FACE:
		options = options.filter(func(i: int) -> bool: return _faces(wall, int(FACES[i].x) as WallLayout.Finish))
	return {"tool": Hand.Tool.STYLE, "restyle": restyle, "options": options, "count": options.size(), "point": point, "of": "walls", "id": wall.id, "wall": wall}


## The style tool on window `opening` of `wall`: a wheel of the families (indices into WallLayout.WINDOW_FAMILIES) its
## opening, every light fused into it alike, still opens in where it stands.
func window_target(wall: Wall, opening: Vector4, point: Vector3) -> Dictionary:
	var options := range(WallLayout.WINDOW_FAMILIES.size()).filter(func(k: int) -> bool: return not _refamilied(wall, opening, WallLayout.WINDOW_FAMILIES[k]).is_empty())
	return {"tool": Hand.Tool.STYLE, "restyle": Restyle.WINDOW, "options": options, "count": options.size(), "point": point, "of": "walls", "id": wall.id, "wall": wall, "opening": opening}


## The openings of `wall` as the garden has them with every placed window making the opening `opening` makes put in
## `family`, or empty where they no longer open as one opening of that family, a door as a door and a window as a
## window, or `opening` is gone.
func _refamilied(wall: Wall, opening: Vector4, family: int) -> PackedVector4Array:
	var placed: Array[Vector4] = []
	placed.assign(Array(world.state.walls.get(wall.id, {}).get("openings", [])))
	var at := placed.find(opening)
	if at < 0:
		var same := placed.filter(func(e: Vector4) -> bool: return e.x == opening.x and e.y == opening.y and e.w == opening.w)
		if same.is_empty():
			return PackedVector4Array()
		at = placed.find(same[0])
	var layout := wall.layout
	var made := layout.openings_for(walls.standing_openings(wall, placed))
	var o := layout._opening_of(made, placed[at])
	if o.is_empty():
		return PackedVector4Array()
	var after := placed.duplicate()
	var moved: Array[int] = []
	for i in placed.size():
		if i == at or layout._opening_of(made, placed[i]) == o:
			after[i] = Vector4(placed[i].x, placed[i].y, family, placed[i].w)
			moved.append(i)
	var now := layout.openings_for(walls.standing_openings(wall, after))
	for i in moved:
		var into := layout._opening_of(now, after[i])
		if into.is_empty() or into.style != family or into.door != o.door:
			return PackedVector4Array()
	return PackedVector4Array(after)


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
		Restyle.PATH:
			return PathLayout.Surface.size()
		Restyle.FLOOR:
			return Floor.size()
		Restyle.FOUNDATION:
			return WallLayout.Foundation.size()
		Restyle.WINDOW:
			return WallLayout.WINDOW_FAMILIES.size()
	return FACES.size()


## Whether `wall` can take `finish`: what suits a fence or a wall, but a round tower under a cone stone alone, and a
## loop framed in timber only with a house's four corners.
static func _faces(wall: Wall, finish: WallLayout.Finish) -> bool:
	if not WallLayout.suits(finish, wall.layout.fence):
		return false
	if wall.roof != null and wall.roof.kind == RoofLayout.Kind.CONE:
		return finish == WallLayout.Finish.BARE
	return finish != WallLayout.Finish.TIMBER or not wall.layout.closed or wall.layout.corners().size() == 4


## Of the face wheel's `options` (indices into FACES), the one nearest a face of `finish` worn by `wear`, or -1.
static func face_choice(options: Array, finish: int, wear: float) -> int:
	var best := -1
	for i in options.size():
		var face: Vector2 = FACES[options[i]]
		if int(face.x) == finish and (best < 0 or absf(face.y - wear) < absf(FACES[options[best]].y - wear)):
			best = i
	return best


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
		var choice := _swatch(target.element, i) if target.tool == Hand.Tool.COLOUR else _style(target.restyle, target.get("options", range(target.count))[i], target.wall, target.of == "boulders")
		w.node.add_child(choice)
		w.choices.append(choice)
	add_child(w.node)
	wheels[hand] = w
	_place(w, hand)
	Metrics.note("style wheel: opened on %s" % Restyle.find_key(target.get("restyle", -1)) if target.tool == Hand.Tool.STYLE else "colour wheel: opened", (Time.get_ticks_usec() - start) / 1000.0)


## A style's miniature smaller than it stands on a controller, so the wheel's choices stay apart.
static func _style(restyle: Restyle, i: int, wall: Wall, boulder := false) -> Node3D:
	var holder := Node3D.new()
	var house := restyle == Restyle.FACE and wall != null and wall.layout.closed and wall.layout.corners().size() == 4
	var model := ToolModels.style(restyle, i, wall.layout.finish if wall != null else WallLayout.Finish.BARE, wall != null and wall.roof != null and wall.roof.kind == RoofLayout.Kind.CONE, boulder, house, wall != null and wall.layout.fence)
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
		return d.lantern if w.of == "decorations" else d.paint[w.target.element]
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
		Restyle.PATH:
			return d.surface
		Restyle.FLOOR:
			return Floor.PLANKS if d.planks else Floor.FLAGS
		Restyle.FOUNDATION:
			return d.foundation
		Restyle.WINDOW:
			var now := Array(d.openings).filter(func(e: Vector4) -> bool: return e.x == w.target.opening.x and e.y == w.target.opening.y and e.w == w.target.opening.w)
			return -1 if now.is_empty() else w.target.options.find(WallLayout.WINDOW_FAMILIES.find(int(now[0].z)))
	return face_choice(w.target.options, d.finish, d.wear)


## The `reshape` data that gives `w`'s build choice `pick`; empty for one that cannot stand.
func _data(w: Wheel, pick: int) -> Dictionary:
	if w.target.tool == Hand.Tool.COLOUR:
		return {"lantern": pick} if w.of == "decorations" else {"paint": {w.target.element: pick}}
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
		Restyle.PATH:
			return {"surface": pick}
		Restyle.FLOOR:
			return {"planks": pick == Floor.PLANKS}
		Restyle.FOUNDATION:
			return {"foundation": pick}
		Restyle.WINDOW:
			var after := _refamilied(w.target.wall, w.target.opening, WallLayout.WINDOW_FAMILIES[w.target.options[pick]])
			return {} if after.is_empty() else {"openings": after}
	var face: Vector2 = FACES[w.target.options[pick]]
	var data := {}
	if int(face.x) != world.state.walls[w.id].finish:
		data["finish"] = int(face.x)
	if face.y != world.state.walls[w.id].wear:
		data["wear"] = face.y
	return data


## Shows `w`'s build, tree or the meadow with choice `pick`, here alone.
func _show(w: Wheel, pick: int) -> void:
	if w.tree != null:
		walls.flora.set_look(w.tree, pick as FloraLayout.Species, walls.flora.scale_of(w.tree))
		return
	if w.stroke >= 0:
		world.marks.restyle(w.stroke, pick)
		return
	if w.id < 0:
		Palette.preview(pick)
		return
	if world.state[w.of].has(w.id):
		_builder(w.of).show_reshaped(w.id, _data(w, pick) if w.target.tool == Hand.Tool.COLOUR else w.data[pick])


## What lays the builds of the garden's table `of`: each shows a reshape before it is sent and `settle`s back.
func _builder(of: String) -> Object:
	return {"walls": walls, "stairs": world.stairs, "boulders": world.boulders, "decorations": world.decorations, "paths": world.paths}[of]


## Sends the choice at the top of `hand`'s wheel to the garden, unless the garden already has it (another
## player may have picked it meanwhile); until it comes back it shows here alone. A build's swatch or gable end
## becomes the one new builds take. The colour tool's trigger `released` within TAP, its wheel still where it opened, is
## a tap.
func close(hand: Hand, released := true) -> void:
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
	elif w.id >= 0 and w.target.restyle == Restyle.FACE and w.target.wall.layout.fence:
		walls.fence_finish = int(FACES[w.target.options[w.pick]].x) as WallLayout.Finish
	elif w.id >= 0 and w.target.restyle == Restyle.FACE:
		walls.finish = int(FACES[w.target.options[w.pick]].x) as WallLayout.Finish
		walls.wear = FACES[w.target.options[w.pick]].y
	elif w.id >= 0 and w.target.restyle == Restyle.FOUNDATION:
		walls.foundation = w.pick as WallLayout.Foundation
	elif w.id >= 0 and w.target.restyle == Restyle.FLOOR:
		walls.planks = w.pick == Floor.PLANKS
	elif w.id >= 0 and w.target.restyle == Restyle.WINDOW:
		walls.window_family = WallLayout.WINDOW_FAMILIES[w.target.options[w.pick]]
	elif w.id >= 0 and w.target.restyle == Restyle.RAIL:
		world.stairs.rail = StairLayout.RAILS[w.pick]
	elif w.id >= 0 and w.target.restyle == Restyle.PATH:
		world.paths.surface = w.pick as PathLayout.Surface
	elif w.id >= 0 and w.target.restyle == Restyle.DECORATION and world.state.decorations[w.id].mount == "span":
		world.decorations.string_style = w.target.options[w.pick]
	elif w.target.get("restyle") == Restyle.STONE:
		Ground.style = w.pick
	if released and w.target.tool == Hand.Tool.COLOUR and w.pick == w.start and w.held < TAP:
		tap(hand, w.of, w.id)
		return
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


## A tap of `hand`'s colour tool on the build `id` of the garden's table `of`: on a wall, house, tower or fence it takes
## that build's look, or lays the look it took on it as one reshape; anywhere else it lets the look go.
func tap(hand: Hand, of: String, id: int) -> void:
	if of != "walls" or not world.state.walls.has(id):
		looks.erase(hand)
		return
	var d: Dictionary = world.state.walls[id]
	if not looks.has(hand):
		looks[hand] = look_of(d)
		Cues.play(Cues.Act.DIAL_TURN, hand.global_position, hand)
		return
	var data := look_onto(looks[hand], d)
	if data.is_empty():
		return
	Cues.play(Cues.Act.DIAL_SET, hand.global_position, hand)
	walls.show_reshaped(id, data)
	world.submit({"op": "reshape", "of": "walls", "id": id, "data": data}, func() -> void: walls.settle.call_deferred(id), hand)


## The look of a wall, house, tower or fence with garden data `d`: its paint, face, top, foundation, floor, gable ends
## and roof covering.
static func look_of(d: Dictionary) -> Dictionary:
	var look := {"fence": d.fence, "paint": PackedInt32Array(d.paint), "face": {"finish": d.finish, "wear": d.wear}, "top": d.top, "foundation": d.foundation, "planks": d.planks, "gable_end": d.gable_end}
	if d.has("roof"):
		look["roof"] = {"deck": d.roof.deck, "thatch": d.roof.thatch}
	return look


## The `reshape` data that lays `look` on the build with garden data `d`, as far as that build can take it: between a
## fence and a wall or house only the paint passes, a wall without a roof takes no covering, a tower's walls stay bare
## stone.
static func look_onto(look: Dictionary, d: Dictionary) -> Dictionary:
	var data := {}
	var paint := {}
	for e in mini(look.paint.size(), d.paint.size()):
		if Palette.SWATCHES.has(e) and look.paint[e] != d.paint[e]:
			paint[e] = look.paint[e]
	if not paint.is_empty():
		data["paint"] = paint
	for k in ["face", "top", "foundation", "planks", "gable_end", "roof"]:
		if look.fence != d.fence or not look.has(k) or (k == "roof" and not d.has("roof")):
			continue
		var part: Dictionary = look[k] if look[k] is Dictionary and k != "roof" else {k: look[k]}
		var cleaned: Variant = Commands._reshape("walls", data.merged(part), d)
		if cleaned != null:
			data = cleaned
	var out := {}
	for k: String in data:
		if k == "roof":
			var roof := {}
			for r: String in data.roof:
				if data.roof[r] != d.roof[r]:
					roof[r] = data.roof[r]
			if not roof.is_empty():
				out["roof"] = roof
		elif k == "paint" or data[k] != d[k]:
			out[k] = data[k]
	return out


func _beam(look: Dictionary) -> Color:
	if look.is_empty():
		return BEAM
	var element := Palette.Element.PLASTER if look.face.finish == WallLayout.Finish.PLASTER else Palette.Element.STONE
	var c := Palette.swatch(element, look.paint[element])
	c.a = BEAM.a
	return c


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
