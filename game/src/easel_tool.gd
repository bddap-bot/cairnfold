class_name EaselTool
extends Node3D

## Painting at an easel, with nothing to pick from a menu. A hand holding the easel tool holds a brush, reaching past
## the controller. Its trigger, pointed at open ground away from any easel, sets an easel up there facing the player.
## At an easel everything is picked up or touched: a grip at the pot takes a small round, a big round or a flat brush,
## and at the tray the charcoal; a grip at the palette carries it in that hand until let go; the brush dipped in a
## colour well loads that pigment, mixing with what is on it already, in the jar it takes water (watercolour, thinner
## each dip) and in the tin oil. Touching the canvas paints: pushing in presses harder, and moving fast skims. A grip
## on the canvas's face takes its sheet, and pulling it well away tears it off for a fresh one.
## Strokes go to the garden as build commands (`paint`) when the brush leaves the canvas, laid on this machine's
## canvas as they are painted and played on everyone else's as they were.

## A grip takes what is within this of the hand.
const REACH := 0.12
## The tip touches within this of the canvas's face, and pushed this far past touching presses fully.
const CONTACT := 0.006
const PRESS_DEPTH := 0.035
const LIFT_OFF := 0.015
## The tip dips into a well within this of it.
const DIP := 0.026
## A sheet pulled this far off the canvas tears away when let go.
const PEEL := 0.3
## The trigger sets an easel up only with none this near the hand.
const PLACE_CLEAR := 2.5
## A brush held still on the canvas keeps laying paint this often, in ticks.
const STILL_TICKS := 6
## The palette in the hand that holds it, from the controller.
const HOLD := Transform3D(Basis(Vector3.UP, -0.5), Vector3(0.12, -0.05, -0.05))
const TINT := Color(0.95, 0.86, 0.72, 0.6)

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
	var palette: Easels.Easel
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
			(m.get_node("tip") as MeshInstance3D).material_override = p.tip if kind != Brushwork.Brush.STICK else null
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
		p.palette = null
		p.peel = null


func _process(delta: float) -> void:
	for p in painters:
		_handle(p, delta)
		p.buttons.latch()


func _handle(p: Painter, delta: float) -> void:
	var hand := p.hand
	var live := hand.tracked() and rig.aim_hand != hand and not hand.picking
	p.ghost.visible = false
	_hold_palette(p, live)
	_pull_sheet(p, live)
	if live and p.buttons.pressed("grab") and not hand.taken() and p.palette == null and p.peel == null:
		grab(p)
	if p.palette != null or p.peel != null:
		hand.hold()
	var holding := hand.tool == Hand.Tool.EASEL
	_show_brush(p, holding, delta)
	if holding and not live and p.buttons.pressed("tool"):
		_decline(hand, "the hand is %s" % ("untracked" if not hand.tracked() else "aiming a teleport" if rig.aim_hand == hand else "picking a tool"))
	if not holding or not live or p.palette != null or p.peel != null:
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
		world.submit({"op": "easel", "at": at, "yaw": yaw}, Callable(), hand)
	elif hand != null:
		_decline(hand, why)


func _decline(hand: Hand, why: String) -> void:
	print("easel: none set up: %s" % why)
	Hand.bump(hand)
	declined.emit(why)


## What a grip at the hand takes: the nearest brush in a pot, charcoal, palette or canvas sheet within reach.
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
		if not painters.any(func(o: Painter) -> bool: return o.palette == e):
			d = at.distance_to(e.palette.global_position)
			if d < maxf(best, Easels.PALETTE_SIZE.x * 0.5):
				best = d
				take = func() -> void: p.palette = e
		var c := e.on_canvas(at)
		if c.x >= 0.0 and c.x <= 1.0 and c.y >= 0.0 and c.y <= 1.0 and c.z > -0.02 and c.z < REACH and c.z < best:
			best = c.z
			take = func() -> void: p.peel = e
	if take.is_valid():
		take.call()
		p.hand.trigger_haptic_pulse(&"haptic", 0.0, 0.3, 0.03, 0.0)


func _take_brush(p: Painter, kind: Brushwork.Brush) -> void:
	end_stroke(p)
	p.hand.tool = Hand.Tool.EASEL
	p.brush = kind
	p.medium = Brushwork.medium_of(kind, p.medium)
	p.colour = Vector3.ZERO
	p.strength = 0.0
	p.load = 1.0 if kind == Brushwork.Brush.STICK else 0.0
	_show_paint(p)


func _hold_palette(p: Painter, live: bool) -> void:
	var e := p.palette
	if e == null:
		return
	if not is_instance_valid(e) or not e.is_inside_tree() or not live or not p.buttons.held("grab"):
		if is_instance_valid(e):
			e.palette.top_level = false
			e.palette.position = Easels.PALETTE
			e.palette.rotation = Vector3.ZERO
		p.palette = null
		return
	e.palette.top_level = true
	e.palette.global_transform = p.hand.global_transform * HOLD


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
	world.submit({"op": "sheet", "easel": id, "strokes": []}, Callable(), hand)


## Dips the brush into whatever the tip has just gone into: a well, the jar or the tin, on any easel's tray or a
## palette in a hand.
func _dip(p: Painter, tip: Vector3) -> void:
	var into := ""
	for e: Easels.Easel in easels.easels.values():
		if tip.distance_to(e.global_position) > 3.0:
			continue
		var on_palette := e.palette.global_transform.affine_inverse() * tip
		for i in Brushwork.PIGMENTS.size():
			if on_palette.distance_to(Easels.well(i)) < DIP:
				into = "well%d" % i
		if _inside(e.global_transform.affine_inverse() * tip, Easels.JAR, Easels.JAR_SIZE):
			into = "jar"
		if _inside(e.global_transform.affine_inverse() * tip, Easels.TIN, Easels.TIN_SIZE):
			into = "tin"
		if into != "":
			if into != p.dipped:
				dip(p, into)
				e.mix.albedo_color = _paint_colour(p)
			break
	p.dipped = into


static func _inside(local: Vector3, base: Vector3, size: Vector2) -> bool:
	return Vector2(local.x - base.x, local.z - base.z).length() < size.x and local.y > base.y and local.y < base.y + size.y + 0.01


## Loads the brush from `what`: "jar", "tin", or "well<i>".
func dip(p: Painter, what: String) -> void:
	if p.brush == Brushwork.Brush.STICK:
		return
	match what:
		"jar":
			p.medium = Brushwork.Medium.WATER
			p.load = 1.0
			p.strength *= 0.4
		"tin":
			p.medium = Brushwork.Medium.OIL
			p.load = 1.0
			p.strength = 1.0
		_:
			var a := Brushwork.absorbance(Brushwork.PIGMENTS[int(what.trim_prefix("well"))])
			var clean := p.strength < 0.05 or p.load < 0.05
			p.colour = a if clean else p.colour.lerp(a, 0.5)
			p.strength = 1.0 if p.medium == Brushwork.Medium.OIL else minf(1.0, p.strength + 0.6)
			p.load = maxf(p.load, 0.6)
	p.hand.trigger_haptic_pulse(&"haptic", 0.0, 0.2, 0.02, 0.0)
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
		p.hand.trigger_haptic_pulse(&"haptic", 0.0, 0.15, 0.02, 0.0)
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
