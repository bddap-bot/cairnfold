class_name EaselTool
extends Node3D

## Painting at an easel, with nothing to pick from a menu. A hand holding the easel tool holds a brush, reaching past
## the controller. Its trigger, pointed at open ground away from any easel, sets an easel up there facing the player.
## At an easel everything is picked up or touched: a grip at the pot takes a small round, a big round or a flat brush,
## and at the tray the charcoal; a grip at either palette, the watercolour box or the oil palette, takes it by its
## thumb hole, and it stays in that hand, as a brush does, until a grip sets it back on its tray, takes a brush, or
## another tool is picked. The palette a brush is dipped into is its medium: a watercolour pan or an oil colour loads
## that pigment, mixing with what is on it already in the same medium; the jar wets the brush for watercolour, thinner
## each dip, and the water clouds with what it rinses off. Touching the canvas paints: pushing in presses harder, and
## moving fast skims. A grip on the canvas's face takes its sheet, and pulling it well away tears it off for a fresh one.
## Strokes go to the garden as build commands (`paint`) when the brush leaves the canvas, laid on this machine's
## canvas as they are painted and played on everyone else's as they were.

## A grip takes what is within this of the hand.
const REACH := 0.12
## The tip touches within this of the canvas's face, and pushed this far past touching presses fully.
const CONTACT := 0.006
const PRESS_DEPTH := 0.035
const LIFT_OFF := 0.015
## A sheet pulled this far off the canvas tears away when let go.
const PEEL := 0.3
## The trigger sets an easel up only with none this near the hand.
const PLACE_CLEAR := 2.5
## A brush held still on the canvas keeps laying paint this often, in ticks.
const STILL_TICKS := 6
## The palette's thumb hole in the hand holding it, from the controller, the palette reaching forward and inward,
## turned this far off the hand's right.
const GRIP := Vector3(0, -0.035, 0.02)
const GRIP_YAW := 0.5
const TINT := Color(0.95, 0.86, 0.72, 0.6)
## What a dip into each medium's palette is called, before the pigment's index.
const PAINTS := {Brushwork.Medium.WATER: "pan", Brushwork.Medium.OIL: "oil"}

## One hand's brush and what it is doing.
class Painter:
	var hand: Hand
	var buttons: Buttons
	var brush := Brushwork.Brush.BIG
	var medium := Brushwork.Medium.WATER
	## The paint on the brush: its colour as optical density, how strong (a wash is weak), and how much is left.
	var colour := Vector3.ZERO
	var strength := 0.0
	var load := 0.0
	var models := {}
	var tip: StandardMaterial3D
	## The stroke being painted: {easel, data, stroker, last: [uv, pressure], at (tick of the last sample)}.
	var stroke := {}
	## What the tip is in, so a dip happens once on going in.
	var dipped := ""
	## The easel whose palette of medium `kit` this hand holds.
	var palette: Easels.Easel
	var kit := Brushwork.Medium.OIL
	## The hand's tool when it took the palette, back in hand when the palette is set down.
	var before := Hand.Tool.EASEL
	var peel: Easels.Easel
	var ghost: Node3D
	var shown := 0.0


## A trigger that set no easel up, and why; the log carries it too.
signal declined(why: String)

var rig: Rig
var easels: Easels
var world: World
var painters: Array[Painter] = []


func _init(player: Rig, stands: Easels, garden: World) -> void:
	rig = player
	easels = stands
	world = garden
	world.restored.connect(_forget)
	for h in rig.hands:
		var p := Painter.new()
		p.hand = h
		p.buttons = Buttons.new(h).watch(["tool", "grab"])
		p.tip = StandardMaterial3D.new()
		p.tip.roughness = 0.5
		for kind in Brushwork.Brush.values():
			var m := ToolModels.brush(kind)
			m.visible = false
			if kind != Brushwork.Brush.STICK:
				(m.get_node("tip") as MeshInstance3D).material_override = p.tip
			h.add_child(m)
			p.models[kind] = m
		p.ghost = _ghost()
		add_child(p.ghost)
		painters.append(p)
	_show_paint.call_deferred(painters[0])
	_show_paint.call_deferred(painters[1])


func _ghost() -> Node3D:
	var g := ToolModels.build(Hand.Tool.EASEL)
	g.scale = Vector3.ONE * 32.0
	g.top_level = true
	g.visible = false
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = TINT
	for mi in g.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat
	return g


func painter(hand: Hand) -> Painter:
	for p in painters:
		if p.hand == hand:
			return p
	return null


## Whether `hand`, or with none any hand, has a stroke or a tear under way.
func busy(hand: Hand = null) -> bool:
	return painters.any(func(p: Painter) -> bool: return (hand == null or p.hand == hand) and (not p.stroke.is_empty() or p.peel != null))


func _forget() -> void:
	for p in painters:
		p.stroke = {}
		_set_down(p)
		p.peel = null


func _process(delta: float) -> void:
	for p in painters:
		_handle(p, delta)
		p.buttons.latch()


func _handle(p: Painter, delta: float) -> void:
	var hand := p.hand
	var live := hand.tracked() and rig.aim_hand != hand and not hand.picking
	p.ghost.visible = false
	_hold_palette(p)
	_pull_sheet(p, live)
	if live and p.buttons.pressed("grab") and not hand.taken() and p.peel == null:
		grab(p)
	if p.palette != null or p.peel != null:
		hand.hold()
	var holding := hand.tool == Hand.Tool.EASEL and p.palette == null
	_show_brush(p, holding, delta)
	if holding and not live and p.buttons.pressed("tool"):
		_decline(hand, "the hand is %s" % ("untracked" if not hand.tracked() else "aiming a teleport" if rig.aim_hand == hand else "picking a tool"))
	if not holding or not live or p.peel != null:
		end_stroke(p)
		return
	var tip := hand.global_transform * ToolModels.BRUSH_TIP
	var e := easels.nearest(tip)
	if e != null:
		_dip(p, tip)
		if _touch(p, e, tip):
			hand.hold()
			return
	if e == null or Easels._flat(e.global_position, hand.global_position) > PLACE_CLEAR:
		_aim_ground(p)
	elif p.buttons.pressed("tool"):
		_decline(hand, "the hand is within %.1f m of an easel" % PLACE_CLEAR)


## Sets an easel up where the hand points, facing the player, on the trigger.
func _aim_ground(p: Painter) -> void:
	var t := p.hand.global_transform
	var hit: Variant = Terrain.raycast(t.origin, -t.basis.z)
	p.hand.point(hit, TINT)
	var why := "it points at no ground" if hit == null else Easels.crowded(hit, world.state.easels)
	if not why.is_empty():
		if p.buttons.pressed("tool"):
			_decline(p.hand, why)
		return
	var yaw := Easels.facing(hit, rig.head.global_position)
	p.ghost.visible = true
	p.ghost.global_transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * 32.0), hit)
	world.preview(p.hand, {"easel": 1})
	if p.buttons.pressed("tool"):
		place(hit, yaw, p.hand)


func place(at: Vector3, yaw: float, hand: Hand = null) -> void:
	var why := Easels.crowded(at, world.state.easels)
	if why.is_empty():
		if world.fits({"op": "easel", "at": at, "yaw": yaw}):
			Cues.play(Cues.Act.EASEL_PLACE, at, hand)
		world.submit({"op": "easel", "at": at, "yaw": yaw}, Callable(), hand)
	elif hand != null:
		_decline(hand, why)


func _decline(hand: Hand, why: String) -> void:
	print("easel: none set up: %s" % why)
	Cues.play(Cues.Act.REFUSED, hand.global_position, hand)
	declined.emit(why)


## What a grip at the hand takes: the nearest brush in a pot, charcoal, palette or canvas sheet within reach; a hand
## holding a palette sets it down at its place on the tray.
func grab(p: Painter) -> void:
	var at := p.hand.global_position
	var best := REACH
	var take := Callable()
	for e: Easels.Easel in easels.easels.values():
		for kind in e.brushes:
			var d := at.distance_to(e.brushes[kind].global_transform * (ToolModels.BRUSH_TIP * 0.5))
			if d < best:
				best = d
				take = _take_brush.bind(p, kind)
		var d := at.distance_to(e.stick.global_transform * (ToolModels.BRUSH_TIP * 0.5))
		if d < best:
			best = d
			take = _take_brush.bind(p, Brushwork.Brush.STICK)
		for kit: Brushwork.Medium in e.palettes:
			if p.palette == e and p.kit == kit:
				d = at.distance_to(e.tray(Easels.KITS[kit]))
				if d < maxf(best, Easels.KIT_REACH[kit]):
					best = d
					take = _set_down.bind(p, true)
			elif not painters.any(func(o: Painter) -> bool: return o.palette == e and o.kit == kit):
				d = at.distance_to(e.palettes[kit].global_position)
				if d < maxf(best, Easels.KIT_REACH[kit]):
					best = d
					take = _take_palette.bind(p, e, kit)
		var c := e.on_canvas(at)
		if p.palette == null and c.x >= 0.0 and c.x <= 1.0 and c.y >= 0.0 and c.y <= 1.0 and c.z > -0.02 and c.z < REACH and c.z < best:
			best = c.z
			take = func() -> void: p.peel = e
	if take.is_valid():
		take.call()
		Cues.play(Cues.Act.BRUSH_TAKE, at, p.hand)


func _take_brush(p: Painter, kind: Brushwork.Brush) -> void:
	end_stroke(p)
	_set_down(p)
	p.hand.tool = Hand.Tool.EASEL
	p.brush = kind
	p.medium = Brushwork.medium_of(kind, p.medium)
	p.colour = Vector3.ZERO
	p.strength = 0.0
	p.load = 1.0 if kind == Brushwork.Brush.STICK else 0.0
	_show_paint(p)
	_log(p, "takes the %s" % Brushwork.Brush.keys()[kind].to_lower())


func _take_palette(p: Painter, e: Easels.Easel, kit: Brushwork.Medium) -> void:
	if p.palette == null:
		p.before = p.hand.tool
	_set_down(p)
	end_stroke(p)
	p.hand.tool = Hand.Tool.EASEL
	p.palette = e
	p.kit = kit
	_hold_palette(p)
	_log(p, "takes the %s palette" % Brushwork.Medium.keys()[kit].to_lower())


func _hold_palette(p: Painter) -> void:
	var e := p.palette
	if e == null:
		return
	if not is_instance_valid(e) or not e.is_inside_tree() or p.hand.tool != Hand.Tool.EASEL:
		_set_down(p)
		return
	var node: Node3D = e.palettes[p.kit]
	node.top_level = true
	node.global_transform = p.hand.global_transform * held(p.hand)


## A hand's held things changing, for a log that shows what each hand held when a player found it stuck.
func _log(p: Painter, what: String) -> void:
	print("easel: %s hand %s (tool %s, brush %s, %s, palette %s)" % [p.hand.tracker, what, Hand.Tool.keys()[p.hand.tool], Brushwork.Brush.keys()[p.brush], Brushwork.Medium.keys()[p.medium], Brushwork.Medium.keys()[p.kit] if p.palette != null else "none"])


## The palette in `hand`, from the controller: held by its thumb hole, its paint up and reaching forward and toward the
## other hand.
static func held(hand: Hand) -> Transform3D:
	var b := Basis(Vector3.UP, GRIP_YAW if hand.tracker == &"left_hand" else PI - GRIP_YAW)
	return Transform3D(b, GRIP - b * Easels.THUMB)


## Puts the palette in `p`'s hand back on its tray, and with `restore` gives the hand back what it held before.
func _set_down(p: Painter, restore := false) -> void:
	var e := p.palette
	p.palette = null
	if e == null:
		return
	if restore:
		p.hand.tool = p.before
	if is_instance_valid(e):
		var node: Node3D = e.palettes[p.kit]
		node.top_level = false
		node.transform = Transform3D(Basis(), Easels.KITS[p.kit])
	_log(p, "sets the %s palette down" % Brushwork.Medium.keys()[p.kit].to_lower())


func _pull_sheet(p: Painter, live: bool) -> void:
	var e := p.peel
	if e == null:
		return
	if not is_instance_valid(e) or not e.is_inside_tree():
		p.peel = null
		return
	var pulled := maxf(e.on_canvas(p.hand.global_position).z, 0.0)
	if not live or not p.buttons.held("grab"):
		e.canvas_mesh.transform = Easels.canvas_local()
		p.peel = null
		if pulled >= PEEL:
			fresh_sheet(e.id, p.hand)
		return
	var half := Brushwork.METRES.y * 0.5
	var curl := atan2(minf(pulled, PEEL * 1.5), Brushwork.METRES.y)
	var hinge := Transform3D(Basis(), Vector3(0, half, 0)) * Transform3D(Basis(Vector3.RIGHT, curl), Vector3(0, -half, 0.002))
	e.canvas_mesh.transform = Easels.canvas_local() * hinge


func fresh_sheet(id: int, hand: Hand = null) -> void:
	if hand != null:
		Cues.play(Cues.Act.SHEET_TEAR, hand.global_position, hand)
	world.submit({"op": "sheet", "easel": id, "strokes": []}, Callable(), hand)


## Dips the brush into whatever the tip has just gone into: a pan, an oil colour or the jar, on any easel's tray or a
## palette in a hand.
func _dip(p: Painter, tip: Vector3) -> void:
	var into := ""
	for e: Easels.Easel in easels.easels.values():
		if tip.distance_to(e.global_position) > 3.0:
			continue
		for kit: Brushwork.Medium in e.palettes:
			var well := Easels.well_at(kit, e.palettes[kit].global_transform.affine_inverse() * tip)
			if well >= 0:
				into = "%s%d" % [PAINTS[kit], well]
		if _inside(e.global_transform.affine_inverse() * tip, Easels.JAR, Easels.JAR_SIZE):
			into = "jar"
		if into != "":
			if into != p.dipped and p.brush != Brushwork.Brush.STICK:
				if into == "jar":
					_rinse(e, p)
				dip(p, into)
				if into != "jar":
					e.mixes[p.medium].albedo_color = _paint_colour(p)
			break
	p.dipped = into


## The jar's water takes on some of the paint a brush rinses off in it.
func _rinse(e: Easels.Easel, p: Painter) -> void:
	if p.load > 0.02:
		e.water.albedo_color = e.water.albedo_color.lerp(Color(Brushwork.colour(p.colour), Easels.WATER.a), 0.25 * p.strength)


static func _inside(local: Vector3, base: Vector3, size: Vector2) -> bool:
	return Vector2(local.x - base.x, local.z - base.z).length() < size.x and local.y > base.y and local.y < base.y + size.y + 0.01


## Loads the brush from `what`: "jar", or a pigment as "pan<i>" or "oil<i>". Paint of the other medium on the brush is
## wiped off first.
func dip(p: Painter, what: String) -> void:
	if p.brush == Brushwork.Brush.STICK:
		return
	if what == "jar":
		p.medium = Brushwork.Medium.WATER
		p.load = 1.0
		p.strength *= 0.4
	else:
		var kit: Brushwork.Medium = PAINTS.find_key(what.rstrip("0123456789"))
		var a := Brushwork.absorbance(Brushwork.PIGMENTS[int(what.trim_prefix(PAINTS[kit]))])
		var clean := p.strength < 0.05 or p.load < 0.05 or p.medium != kit
		p.medium = kit
		p.colour = a if clean else p.colour.lerp(a, 0.5)
		if kit == Brushwork.Medium.OIL:
			p.strength = 1.0
			p.load = 1.0
		else:
			p.strength = minf(1.0, p.strength + 0.6) if not clean else 0.6
			p.load = maxf(p.load, 0.6)
	Cues.play(Cues.Act.BRUSH_DIP, p.hand.global_position, p.hand)
	_show_paint(p)


func _paint_colour(p: Painter) -> Color:
	if p.brush == Brushwork.Brush.STICK:
		return Brushwork.colour(Brushwork.CHARCOAL)
	var density := p.colour * (p.strength if p.medium == Brushwork.Medium.WATER else 1.0) * (0.4 + 0.6 * p.load)
	return Brushwork.colour(density) * Color(0.95, 0.92, 0.86)


func _show_paint(p: Painter) -> void:
	p.tip.albedo_color = _paint_colour(p) if p.load > 0.02 else Color(0.86, 0.78, 0.62)
	p.tip.roughness = 0.25 if p.load > 0.02 and p.medium != Brushwork.Medium.CHARCOAL else 0.7


func _show_brush(p: Painter, holding: bool, delta: float) -> void:
	p.shown = move_toward(p.shown, 1.0 if holding else 0.0, delta / Hand.POP)
	for kind in p.models:
		var m: Node3D = p.models[kind]
		m.visible = kind == p.brush and p.shown > 0.0
		m.scale = Vector3.ONE * maxf(p.shown, 0.001)


## Paints while the tip touches easel `e`'s canvas; whether it does.
func _touch(p: Painter, e: Easels.Easel, tip: Vector3) -> bool:
	var c := e.on_canvas(tip)
	var on := c.x >= 0.0 and c.x <= 1.0 and c.y >= 0.0 and c.y <= 1.0 and c.z > -0.1
	if not p.stroke.is_empty() and (p.stroke.easel != e or not on or c.z > CONTACT + LIFT_OFF):
		end_stroke(p)
	if not on or c.z > CONTACT:
		return not p.stroke.is_empty()
	var pressure := clampf((CONTACT - c.z) / PRESS_DEPTH, 0.05, 1.0)
	var t := p.hand.global_transform
	var across := e.canvas_frame().basis.inverse() * t.basis.x
	var angle := atan2(-across.y, across.x)
	touch(p, e, Vector2(c.x, c.y), pressure, angle)
	return true


## The tip at `uv` on easel `e`'s canvas, pressed `pressure` (0..1), a flat brush turned `angle`: starts a stroke or
## carries one on, laying its paint at once.
func touch(p: Painter, e: Easels.Easel, uv: Vector2, pressure: float, angle: float) -> void:
	var canvas := e.canvas
	if p.stroke.is_empty():
		if p.load <= 0.01 or not _room(e):
			return
		var data := {"medium": p.medium, "brush": p.brush, "colour": p.colour, "strength": p.strength, "load": p.load, "gap": clampi(canvas.ticks - canvas.last_end, 0, Brushwork.DRY_TICKS), "samples": PackedInt32Array()}
		p.stroke = {"easel": e, "data": data, "stroker": Brushwork.Stroker.new(data), "last": [], "at": canvas.ticks}
	var s := p.stroke
	if not s.last.is_empty():
		var r: float = Brushwork.RADII[p.brush].y * pressure
		var moved: float = (Vector2(uv - s.last[0]) * Vector2(Brushwork.SIZE)).length()
		if moved < maxf(r * 0.15, 1.0) and absf(pressure - s.last[1]) < 0.05 and canvas.ticks - s.at < STILL_TICKS:
			return
	var packed := Brushwork.pack(uv, pressure, angle, canvas.ticks - s.at if not s.last.is_empty() else 0)
	s.data.samples.append_array(packed)
	s.at = canvas.ticks
	s.last = [uv, pressure]
	canvas.lay(s.data, s.stroker.add(Brushwork.unpack(packed, 0)))
	Cues.play(Cues.Act.CHARCOAL_STROKE if p.brush == Brushwork.Brush.STICK else Cues.Act.CANVAS_STROKE, p.hand.global_position, p.hand, pressure)
	if Brushwork.count(s.data) >= Brushwork.MAX_SAMPLES:
		end_stroke(p)


## Whether easel `e` takes another stroke; past its limit the hand feels why.
func _room(e: Easels.Easel) -> bool:
	var standing: Dictionary = world.state.easels.get(e.id, {})
	var total := 0
	for s: Dictionary in standing.get("strokes", []):
		total += Brushwork.count(s)
	if not standing.is_empty() and standing.strokes.size() < Brushwork.MAX_STROKES and total + Brushwork.MAX_SAMPLES <= Brushwork.MAX_TOTAL:
		return true
	return false


## Sends the stroke under way, if any; the brush keeps what paint it has left.
func end_stroke(p: Painter) -> void:
	var s := p.stroke
	if s.is_empty():
		return
	p.stroke = {}
	var e: Easels.Easel = s.easel
	if not is_instance_valid(e):
		return
	e.canvas.last_end = e.canvas.ticks
	if p.brush != Brushwork.Brush.STICK:
		p.load *= s.stroker.left()
		_show_paint(p)
	var id := e.id
	var data: Dictionary = s.data
	world.submit({"op": "paint", "easel": id, "stroke": data}, func() -> void: _settled.call_deferred(id, data), p.hand)


## A stroke the garden turned down leaves the canvas as the garden has it.
func _settled(id: int, data: Dictionary) -> void:
	var standing: Dictionary = world.state.easels.get(id, {})
	if standing.is_empty():
		return
	var strokes: Array = standing.strokes
	for i in range(strokes.size() - 1, maxi(strokes.size() - 16, 0) - 1, -1):
		if strokes[i].samples == data.samples:
			return
	easels.repaint(id, strokes)
