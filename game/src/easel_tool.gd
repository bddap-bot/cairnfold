class_name EaselTool
extends Node3D

## Painting at an easel, with nothing to pick from a menu. A hand holding the easel tool holds a brush, reaching past
## the controller. Its trigger, pointed at open ground away from any easel, sets an easel up there facing the player.
## At an easel everything is picked up or touched: a grip at the pot takes a small round, a big round or a flat brush,
## and at the tray one of three sticks of charcoal, thin to thick, held leaned back so its side meets the canvas. An
## easel holds one of each, and the one a hand holds is off it until that hand takes another. A grip at either palette, the watercolour box or the oil palette, takes it by its
## thumb hole, and it stays in that hand, as a brush does, until the next grip, wherever the hand is, sends it back to
## its rest on the tray, or another tool is picked. The palette a brush is dipped into is its medium: a watercolour pan
## loads that pigment, mixing with what is on the brush already; an oil colour loads it pure, and oils mix on the oil
## palette's open board, painted onto it and picked up from it by touching it (`Mixing`); the jar wets the brush for
## watercolour, thinner each dip, and the water clouds with what it rinses off. Touching the canvas paints: pushing in
## presses harder, and moving fast skims. A grip on the canvas's face takes its sheet, and pulling it well away tears it off for a fresh one.
## Strokes go to the garden as build commands (`paint`) when the brush leaves the canvas, laid on this machine's
## canvas as they are painted and played on everyone else's as they were.

## A grip takes what is within this of the hand.
const REACH := 0.12
## The tip touches within this of the canvas's face, and pushed this far past touching presses fully.
const CONTACT := 0.006
const PRESS_DEPTH := 0.035
## A sheet pulled this far off the canvas tears away when let go.
const PEEL := 0.3
## The trigger sets an easel up only with none this near the hand.
const PLACE_CLEAR := 2.5
## A brush held still on the canvas keeps laying paint this often, in ticks.
const STILL_TICKS := 6
## On the mixing field a brush touches a disc whose radius, pressed fully, is its reach on the canvas in texels
## (`Brushwork.radii`) times this, in metres.
const MIX_RADIUS := 0.0006
## The palette's thumb hole in the hand holding it, from the controller, the palette reaching forward and inward,
## turned this far off the hand's right.
const GRIP := Vector3(0, -0.035, 0.02)
const GRIP_YAW := 0.5
## A palette set down travels from where it was to its rest on the tray in this long, in seconds.
const RETURN := 0.3
const TINT := Color(0.95, 0.86, 0.72, 0.6)
## What a dip into each medium's palette is called, before the pigment's index.
const PAINTS := {Brushwork.Medium.WATER: "pan", Brushwork.Medium.OIL: "oil"}

## One hand's brush and what it is doing.
class Painter:
	var hand: Hand
	var buttons: Buttons
	var brush := Brushwork.Brush.BIG
	## The id of the easel the brush was taken from, which lacks it while this hand shows it, and whether it showed it
	## last frame.
	var brush_from := 0
	var showing := false
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
	## The easel whose mixing field the tip is working, whether it changed it, and the microseconds each frame of it
	## took.
	var board: Easels.Easel
	var mixed := false
	var mix_cost := PackedInt32Array()
	## The easel whose palette of medium `kit` this hand holds.
	var palette: Easels.Easel
	var kit := Brushwork.Medium.OIL
	## The hand's tool when it took the palette, back in hand when the palette is set down.
	var before := Hand.Tool.EASEL
	var peel: Easels.Easel
	var ghost: Node3D
	var shown := 0.0
	## What the hand held when last logged (`holding`).
	var held := ""
	var contact := CanvasContact.new()
	var contact_easel: Easels.Easel
	var contact_point := Vector3.INF
	var bend := Vector3.ZERO


## A trigger that set no easel up, and why; the log carries it too.
signal declined(why: String)
signal canvas_contact(hand: Hand, at: Vector3, stick: bool, touching: bool, pressure: float, speed: float, distance: float, hard: bool)

var rig: Rig
var easels: Easels
var world: World
var painters: Array[Painter] = []
var highlighted: Array[Node3D] = []
var highlight := Meshes.glow(Color(1.0, 0.8, 0.3, 0.45))
## Each palette on its way back to its tray, by its node: [easel, kit, where it set off from, how far along (0..1)].
var returning := {}
## What each easel lacks, by Vector3i(easel id, HeldItem.Kind, brush or kit): the Painter or HeldItem showing it.
var taken := {}


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
			m.transform = ToolModels.hold(kind)
			m.visible = false
			if not Brushwork.is_stick(kind):
				(m.get_node("tip") as MeshInstance3D).material_override = p.tip
			h.body.add_child(m)
			p.models[kind] = m
		p.ghost = _ghost()
		add_child(p.ghost)
		p.held = holding(p)
		painters.append(p)
	_show_paint.call_deferred(painters[0])
	_show_paint.call_deferred(painters[1])


func _ghost() -> Node3D:
	var g := Node3D.new()
	Easels.lay_frame(g, g)
	g.top_level = true
	g.visible = false
	Meshes.ghostly(g, Meshes.glow(TINT))
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
		p.board = null
		p.mix_cost.clear()
		_set_down(p)
		p.peel = null
		p.brush_from = 0


func _process(delta: float) -> void:
	_return(delta)
	_rack()
	_preview()
	for p in painters:
		_handle(p, delta)
		_note(p)
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
		_clear_contact(p)
		_lift(p)
		return
	var tip := held_brush(p) * ToolModels.BRUSH_TIP
	var e := easels.nearest(tip)
	if e != null:
		_dip(p, tip)
		if _mix(p, tip, delta):
			end_stroke(p)
			_clear_contact(p)
			hand.hold()
			return
		if _touch(p, e, delta):
			hand.hold()
			return
	if e == null or Easels._flat(e.global_position, hand.global_position) > PLACE_CLEAR:
		_aim_ground(p)
	elif p.buttons.pressed("tool"):
		_decline(hand, "the hand is within %.1f m of an easel" % PLACE_CLEAR)


## Sets an easel up where the hand points, facing the player, on the trigger.
func _aim_ground(p: Painter) -> void:
	var t := p.hand.global_transform
	var hit: Variant = world.terrain.raycast(t.origin, -t.basis.z)
	p.hand.point(hit, TINT)
	var why := "it points at no ground" if hit == null else Easels.crowded(hit, world.state.easels)
	if not why.is_empty():
		if p.buttons.pressed("tool"):
			_decline(p.hand, why)
		return
	var yaw := Easels.facing(hit, rig.head.global_position)
	p.ghost.visible = true
	p.ghost.global_transform = easels.on_ground(hit, yaw)
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


## What a grip at the hand takes: the previewed implement, palette or canvas sheet within reach; a hand
## holding a palette sends it back to its tray, wherever the hand is, and takes nothing.
func grab(p: Painter) -> void:
	var at := p.hand.global_position
	if p.palette != null:
		_set_down(p, true)
		_note(p, true)
		Cues.play(Cues.Act.BRUSH_TAKE, at, p.hand)
		return
	var choice := candidate(p)
	if not choice.is_empty():
		choice.take.call()
		_note(p, true)
		Cues.play(Cues.Act.BRUSH_TAKE, at, p.hand)


## Whether a grip of `hand`'s is painting's: it holds a palette, paints, tears a sheet or reaches an implement, palette
## or the canvas. Any other grip on an easel's stand carries the easel (`WallTool.grip_easel`).
func claims(hand: Hand) -> bool:
	var p := painter(hand)
	return p != null and (p.palette != null or busy(hand) or not candidate(p).is_empty())


## Touching a handle wins by proximity; approaching it distinguishes neighbours by the hand's pointing line.
static func pick_distance(hand: Transform3D, target: Vector3) -> float:
	var offset := target - hand.origin
	var distance := offset.length()
	if distance >= REACH:
		return INF
	if distance <= 0.05:
		return distance
	var forward := -hand.basis.z.normalized()
	var along := maxf(0.0, offset.dot(forward))
	return 0.05 + distance * 0.2 + (offset - forward * along).length()


## Preview and grip use this same winner, including palettes and the sheet that could otherwise steal a brush grab.
func candidate(p: Painter) -> Dictionary:
	if p.palette != null or p.peel != null:
		return {}
	var at := p.hand.global_position
	var best := REACH
	var choice := {}
	for e: Easels.Easel in easels.easels.values():
		for kind: Brushwork.Brush in e.brushes:
			var node: Node3D = e.brushes[kind]
			if taken.get(Vector3i(e.id, HeldItem.Kind.BRUSH, kind), p) != p:
				continue
			var d := pick_distance(p.hand.global_transform, node.global_transform * Easels.grip(kind))
			if d < best:
				best = d
				choice = {"take": _take_brush.bind(p, kind, e), "node": node}
		for kit: Brushwork.Medium in e.palettes:
			if not taken.has(Vector3i(e.id, HeldItem.Kind.PALETTE, kit)) and not painters.any(func(o: Painter) -> bool: return o.palette == e and o.kit == kit):
				var d := at.distance_to(e.palettes[kit].global_position)
				if d < maxf(REACH, Easels.KIT_REACH[kit]) and (choice.is_empty() or d < best):
					best = d
					choice = {"take": _take_palette.bind(p, e, kit)}
		var c := e.on_canvas(at)
		if c.x >= 0.0 and c.x <= 1.0 and c.y >= 0.0 and c.y <= 1.0 and c.z > -0.02 and c.z < REACH and c.z < best:
			best = c.z
			choice = {"take": func() -> void: p.peel = e}
	return choice


func _preview() -> void:
	var next: Array[Node3D] = []
	for p in painters:
		var h := p.hand
		if h.tracked() and rig.aim_hand != h and not h.picking and not h.taken():
			var choice := candidate(p)
			if choice.has("node") and not next.has(choice.node):
				next.append(choice.node)
	for node in highlighted:
		if is_instance_valid(node) and not next.has(node):
			for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
				mesh.material_overlay = null
	for node in next:
		if not highlighted.has(node):
			for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
				mesh.material_overlay = highlight
	highlighted = next


## Puts a brush of `kind` in `p`'s hand, taken from easel `from`, and sends what the hand had back to its easel.
func _take_brush(p: Painter, kind: Brushwork.Brush, from: Easels.Easel) -> void:
	p.contact.reset()
	end_stroke(p)
	_set_down(p)
	p.hand.tool = Hand.Tool.EASEL
	p.brush = kind
	for o in painters:
		if o != p and o.brush_from == from.id and o.brush == kind:
			o.brush_from = 0
	p.brush_from = from.id
	taken[Vector3i(from.id, HeldItem.Kind.BRUSH, kind)] = p
	p.medium = Brushwork.medium_of(kind, p.medium)
	p.colour = Vector3.ZERO
	p.strength = 0.0
	p.load = 1.0 if Brushwork.is_stick(kind) else 0.0
	_show_paint(p)


## Takes off each easel what a hand shows, here or a player's across the garden as their `HeldItem` shows it, so
## everyone sees the same, and shows the rest: a brush is back on its easel while its hand shows anything else, and a
## hand coming back to it finds it gone if someone took it meanwhile. A palette in a hand here is carried off already.
func _rack() -> void:
	taken.clear()
	for item: HeldItem in get_tree().get_nodes_in_group(HeldItem.GROUP):
		var s := item.state
		if s.size() > HeldItem.DETAIL and s[HeldItem.DETAIL] > 0 and (s[0] == HeldItem.Kind.BRUSH or s[0] == HeldItem.Kind.PALETTE):
			taken[Vector3i(s[HeldItem.DETAIL], s[0], s[1])] = item
	for p in painters:
		if p.showing and _shows_brush(p):
			taken[Vector3i(p.brush_from, HeldItem.Kind.BRUSH, p.brush)] = p
	for p in painters:
		var key := Vector3i(p.brush_from, HeldItem.Kind.BRUSH, p.brush)
		if not p.showing and _shows_brush(p):
			if taken.has(key):
				p.brush_from = 0
			else:
				taken[key] = p
		p.showing = _shows_brush(p)
	for e: Easels.Easel in easels.easels.values():
		for kind: Brushwork.Brush in e.brushes:
			e.brushes[kind].visible = not taken.has(Vector3i(e.id, HeldItem.Kind.BRUSH, kind))
		for kit: Brushwork.Medium in e.palettes:
			if not painters.any(func(o: Painter) -> bool: return o.palette == e and o.kit == kit):
				e.palettes[kit].visible = not taken.has(Vector3i(e.id, HeldItem.Kind.PALETTE, kit))


## Whether `p`'s hand shows a brush taken from an easel.
static func _shows_brush(p: Painter) -> bool:
	return p.brush_from > 0 and p.hand.tool == Hand.Tool.EASEL and p.palette == null and p.peel == null


## Where `p`'s brush is, in its own frame (`ToolModels.brush`): held as `ToolModels.hold` holds it.
static func held_brush(p: Painter) -> Transform3D:
	return p.hand.body.global_transform * ToolModels.hold(p.brush)


func _take_palette(p: Painter, e: Easels.Easel, kit: Brushwork.Medium) -> void:
	if p.palette == null:
		p.before = p.hand.tool
	_set_down(p)
	end_stroke(p)
	p.hand.tool = Hand.Tool.EASEL
	p.palette = e
	p.kit = kit
	returning.erase(e.palettes[kit])
	_hold_palette(p)


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


## What `p`'s hand holds: a palette ("oil palette", "water palette"), the canvas's sheet, the brush or charcoal
## ("thin_stick", "stick", "thick_stick") while it holds the easel tool, or else its tool.
static func holding(p: Painter) -> String:
	if p.palette != null:
		return "%s palette" % Brushwork.Medium.keys()[p.kit].to_lower()
	if p.peel != null:
		return "sheet"
	if p.hand.tool == Hand.Tool.EASEL:
		return Brushwork.Brush.keys()[p.brush].to_lower()
	return Hand.Tool.keys()[p.hand.tool].to_lower()


## One line each time a hand's held thing changes, and on every grip that takes something even if it is the same
## again, for a log that shows what each hand held when a player found it stuck.
func _note(p: Painter, grip := false) -> void:
	var now := holding(p)
	if now == p.held and not grip:
		return
	print("easel: %s %s %s, held %s (%s)" % [p.hand.tracker, "grips and holds" if grip else "holds", now, p.held, Brushwork.Medium.keys()[p.medium]])
	p.held = now


## The palette in `hand`, from the controller: held by its thumb hole, its paint up and reaching forward and toward the
## other hand.
static func held(hand: Hand) -> Transform3D:
	var b := Basis(Vector3.UP, GRIP_YAW if hand.tracker == &"left_hand" else PI - GRIP_YAW)
	return Transform3D(b, GRIP - b * Easels.THUMB)


## Sends the palette in `p`'s hand back to its tray, and with `restore` gives the hand back what it held before.
func _set_down(p: Painter, restore := false) -> void:
	var e := p.palette
	p.palette = null
	if e == null:
		return
	if restore:
		p.hand.tool = p.before
	if is_instance_valid(e):
		var node: Node3D = e.palettes[p.kit]
		returning[node] = [e, p.kit, node.global_transform, 0.0]


## Carries each palette set down on toward its rest on the tray, easing in and out, and leaves it there.
func _return(delta: float) -> void:
	for node: Variant in returning.keys():
		var r: Array = returning[node]
		if not is_instance_valid(node) or not is_instance_valid(r[0]) or not (node as Node3D).is_inside_tree():
			returning.erase(node)
			continue
		var palette: Node3D = node
		var rest := Transform3D(Basis(), Easels.KITS[r[1]])
		r[3] = minf(r[3] + delta / RETURN, 1.0)
		if r[3] < 1.0:
			palette.global_transform = (r[2] as Transform3D).interpolate_with((palette.get_parent() as Node3D).global_transform * rest, smoothstep(0.0, 1.0, r[3]))
			continue
		palette.top_level = false
		palette.transform = rest
		returning.erase(node)


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
			if taken.has(Vector3i(e.id, HeldItem.Kind.PALETTE, kit)):
				continue
			var well := Easels.well_at(kit, e.palettes[kit].global_transform.affine_inverse() * tip)
			if well >= 0:
				into = "%s%d" % [PAINTS[kit], well]
		if _inside(e.global_transform.affine_inverse() * tip, Easels.JAR, Easels.JAR_SIZE):
			into = "jar"
		if into != "":
			if into != p.dipped and not Brushwork.is_stick(p.brush):
				if into == "jar":
					_rinse(e, p)
				dip(p, into)
				if into.begins_with(PAINTS[Brushwork.Medium.WATER]):
					e.wash.albedo_color = _paint_colour(p)
			break
	p.dipped = into


## The jar's water takes on some of the paint a brush rinses off in it.
func _rinse(e: Easels.Easel, p: Painter) -> void:
	if p.load > 0.02:
		e.water.albedo_color = e.water.albedo_color.lerp(Color(Brushwork.colour(p.colour), Easels.WATER.a), 0.25 * p.strength)


static func _inside(local: Vector3, base: Vector3, size: Vector2) -> bool:
	return Vector2(local.x - base.x, local.z - base.z).length() < size.x and local.y > base.y and local.y < base.y + size.y + 0.01


## Loads the brush from `what`: "jar", or a pigment as "pan<i>" or "oil<i>". A pan's mixes with the watercolour on the
## brush; an oil colour replaces what is on it. Paint of the other medium on the brush is wiped off first.
func dip(p: Painter, what: String) -> void:
	if Brushwork.is_stick(p.brush):
		return
	if what == "jar":
		p.medium = Brushwork.Medium.WATER
		p.load = 1.0
		p.strength *= 0.4
	else:
		var kit: Brushwork.Medium = PAINTS.find_key(what.rstrip("0123456789"))
		var a := Brushwork.absorbance(Brushwork.PIGMENTS[int(what.trim_prefix(PAINTS[kit]))])
		var clean := p.strength < 0.05 or p.load < 0.05 or p.medium != kit or kit == Brushwork.Medium.OIL
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
	if Brushwork.is_stick(p.brush):
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


## Works an oil palette's mixing field while the tip touches its open board, on the tray or in a hand: the brush and
## the board trade paint, so painting onto it lays and blends paint and touching it picks the paint there up. A
## watercolour brush leaves its water behind and takes up oil. Whether the tip touches a field.
func _mix(p: Painter, tip: Vector3, delta: float) -> bool:
	var on: Easels.Easel = null
	var local := Vector3.ZERO
	if not Brushwork.is_stick(p.brush):
		for e: Easels.Easel in easels.easels.values():
			if taken.has(Vector3i(e.id, HeldItem.Kind.PALETTE, Brushwork.Medium.OIL)):
				continue
			local = e.palettes[Brushwork.Medium.OIL].global_transform.affine_inverse() * tip
			if local.y < Easels.BOARD_TOP + CONTACT and local.y > Easels.WELL_DEPTH.x and Mixing.open_at(Vector2(local.x, local.z)) and Easels.well_at(Brushwork.Medium.OIL, local) < 0:
				on = e
				break
	if p.board != on:
		_lift(p)
	if on == null:
		return false
	p.board = on
	var start := Time.get_ticks_usec()
	var pressure := clampf((Easels.BOARD_TOP + CONTACT - local.y) / PRESS_DEPTH, 0.05, 1.0)
	var radius: float = Brushwork.radii(p.brush).y * MIX_RADIUS * (0.5 + 0.5 * pressure)
	var oil := p.medium == Brushwork.Medium.OIL
	var got := on.mixing.touch({"ks": Mixing.ks_of(p.colour), "load": p.load if oil else 0.0}, Vector2(local.x, local.z), radius, delta)
	if got[1]:
		on.show_mixing()
		p.mixed = true
		p.medium = Brushwork.Medium.OIL
		p.colour = Mixing.density_of(got[0].ks)
		p.strength = 1.0
		p.load = got[0].load
		_show_paint(p)
	p.mix_cost.append(Time.get_ticks_usec() - start)
	return true


## The tip has left the mixing field it was working: what it changed goes to the garden, and what it cost to the log.
func _lift(p: Painter) -> void:
	var e := p.board
	p.board = null
	if p.mix_cost.is_empty():
		return
	var cost := Array(p.mix_cost)
	print("easel: mixed %d frames, %.0f us a frame, %d us at most" % [cost.size(), cost.reduce(func(a: int, b: int) -> int: return a + b) / float(cost.size()), cost.max()])
	p.mix_cost.clear()
	if p.mixed and is_instance_valid(e) and e.is_inside_tree():
		world.submit({"op": "mix", "easel": e.id, "mix": e.mixing.bytes.duplicate()}, Callable(), p.hand)
	p.mixed = false


func _clear_contact(p: Painter) -> void:
	p.contact.reset()
	p.contact_easel = null
	p.contact_point = Vector3.INF
	p.bend = Vector3.ZERO
	if not Brushwork.is_stick(p.brush):
		ToolModels.bend(p.models[p.brush], p.brush, p.bend)
	canvas_contact.emit(p.hand, p.hand.global_position, Brushwork.is_stick(p.brush), false, 0.0, 0.0, 0.0, false)


## Paints while the tip touches easel `e`'s canvas; whether it does.
func _touch(p: Painter, e: Easels.Easel, delta: float) -> bool:
	if p.contact_easel != e:
		end_stroke(p)
		p.contact_point = Vector3.INF
		p.contact.reset()
		p.contact_easel = e
	var frame := e.canvas_frame()
	var stick := Brushwork.is_stick(p.brush)
	var contact := p.contact.move(frame, held_brush(p), p.brush)
	p.hand.body.global_transform = contact.pose * ToolModels.hold(p.brush).affine_inverse()
	if not stick:
		p.bend = contact.pose.basis.inverse() * frame.basis.z * contact.bend
		ToolModels.bend(p.models[p.brush], p.brush, p.bend)
	var distance: float = contact.point.distance_to(p.contact_point) if contact.on and p.contact_point != Vector3.INF else 0.0
	canvas_contact.emit(p.hand, contact.point, stick, contact.on, contact.pressure, distance / maxf(delta, 1e-6), distance, contact.hard)
	if not contact.on:
		end_stroke(p)
		p.contact_point = Vector3.INF
		return false
	p.contact_point = contact.point
	touch(p, e, contact.uv, contact.pressure, contact.angle, contact.side)
	return true


## The tip at `uv` on easel `e`'s canvas, pressed `pressure` (0..1), a flat brush or a stick turned `angle`, a stick
## lying `side` (0..1) on the canvas: starts a stroke or carries one on, laying its paint at once.
func touch(p: Painter, e: Easels.Easel, uv: Vector2, pressure: float, angle: float, side := 0.0) -> void:
	var canvas := e.canvas
	if p.stroke.is_empty():
		if p.load <= 0.01 or not _room(e):
			return
		var data := {"medium": p.medium, "brush": p.brush, "colour": p.colour, "strength": p.strength, "load": p.load, "gap": clampi(canvas.ticks - canvas.last_end, 0, Brushwork.DRY_TICKS), "samples": PackedInt32Array()}
		p.stroke = {"easel": e, "data": data, "stroker": Brushwork.Stroker.new(data), "last": [], "at": canvas.ticks}
	var s := p.stroke
	if not s.last.is_empty():
		var r: float = Brushwork.radii(p.brush).y * pressure
		var size := Vector2(Brushwork.SIZE)
		var moved := Brushwork.sweep(s.last[0] * size, s.last[2], uv * size, angle, maxf(side, s.last[3])).x
		if Brushwork.is_stick(p.brush) and moved < 0.01:
			return
		if moved < maxf(r * 0.15, 1.0) and absf(pressure - s.last[1]) < 0.05 and canvas.ticks - s.at < STILL_TICKS:
			return
	var packed := Brushwork.pack(uv, pressure, angle, canvas.ticks - s.at if not s.last.is_empty() else 0, side)
	s.data.samples.append_array(packed)
	s.at = canvas.ticks
	s.last = [uv, pressure, angle, side]
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
	e.canvas.end(s.data)
	if p.medium != Brushwork.Medium.SMEAR and not Brushwork.is_stick(p.brush):
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
