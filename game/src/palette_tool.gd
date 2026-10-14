class_name PaletteTool
extends Node3D

## The colour picker, for whichever hand holds it: the trigger on a thing opens a wheel of its material's
## swatches over the controller (on the meadow, its seasons), and twisting the wrist turns the wheel like a
## dial, recolouring the glade live on this machine; letting go sends the swatch at the top to the garden
## as a `palette` command, so everyone building sees it, and it is one undo step.
## Stone walls, roof tiles, woodwork (fences, window frames, doors) and plaster (gable ends) each have one
## colour for the whole glade.

const BEAM := Color(1.0, 1.0, 1.0, 0.6)
const WHEEL_RADIUS := 0.07
## Where the wheel stands from the controller, in its frame when the trigger went down.
const WHEEL_AT := Vector3(0, 0.06, -0.05)

## A hand's open wheel: what it paints, the swatch it started on and the one at its top, and the hand's
## frame when it opened.
class Wheel:
	var element: Palette.Element
	var start := 0
	var pick := 0
	var degrees := 0.0
	var basis := Basis()
	var node: Node3D
	var swatches: Array[MeshInstance3D] = []


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
		_buttons.append(Buttons.new(h).watch(["trigger_click"]))
	world.restored.connect(func() -> void:
		for hand in wheels.keys():
			_drop(hand))


## One wheel at a time, so two hands never pick for one material from stale starts.
func busy() -> bool:
	return not wheels.is_empty()


func _process(_delta: float) -> void:
	for b in _buttons:
		var hand: Hand = b.hand
		var wheel: Wheel = wheels.get(hand)
		if wheel != null and (hand.tool != Hand.Tool.COLOUR or b.released("trigger_click")):
			close(hand)
		elif wheel != null and b.held("trigger_click"):
			twist(hand, _roll(wheel.basis, hand.global_basis))
		elif wheel == null and hand.tool == Hand.Tool.COLOUR and rig.aim_hand != hand and hand.get_has_tracking_data():
			var t := hand.global_transform
			var target := aim(t.origin, -t.basis.z)
			hand.point(target.get("point", null), BEAM)
			if b.pressed("trigger_click") and not target.is_empty() and not busy():
				open(hand, target.element)
		b.latch()
	for hand in wheels:
		_place(wheels[hand], hand)


## What the trigger would recolour from `origin` along `dir`: `element` and `point`, or empty.
func aim(origin: Vector3, dir: Vector3) -> Dictionary:
	var pick := walls.pick_wall(origin, dir)
	var roof := walls.pick_roof(origin, dir)
	var along: float = roof.get("along", INF)
	var gable := INF
	for w in walls.walls:
		if w.roof != null:
			gable = minf(gable, w.roof.gable_hit(origin, dir))
	if gable < along and (pick.is_empty() or pick.distance > 0.2 or gable < pick.along):
		return {"element": Palette.Element.PLASTER, "point": origin + dir * gable}
	if along < INF and (pick.is_empty() or pick.distance > 0.2 or along < pick.along):
		return {"element": Palette.Element.ROOF, "point": roof.point}
	if not pick.is_empty():
		var layout: WallLayout = pick.wall.layout
		var wood := layout.fence or not layout.opening_at(pick.s, pick.point.y - layout.point_at(pick.s).y).is_empty()
		return {"element": Palette.Element.WOOD if wood else Palette.Element.STONE, "point": pick.point}
	var ground: Variant = Terrain.raycast(origin, dir)
	if ground != null:
		return {"element": Palette.Element.MEADOW, "point": ground}
	return {}


## Opens `element`'s wheel over `hand`, turning from the garden's swatch. While the trigger is held the
## hand's twist turns it; the driver, holding no trigger, turns it with `twist`.
func open(hand: Hand, element: Palette.Element) -> void:
	var w := Wheel.new()
	w.element = element
	w.start = world.palette.picks[element]
	w.pick = w.start
	w.basis = hand.global_basis.orthonormalized()
	w.node = Node3D.new()
	w.node.top_level = true
	for i in Palette.count(element):
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
		w.node.add_child(mi)
		w.swatches.append(mi)
	add_child(w.node)
	wheels[hand] = w
	_place(w, hand)


## Turns `hand`'s wheel to `degrees` of twist from where it opened, clockwise positive, showing its swatch
## on this machine only.
func twist(hand: Hand, degrees: float) -> void:
	var w: Wheel = wheels[hand]
	w.degrees = degrees
	var pick := Palette.twisted(w.element, w.start, degrees)
	if pick != w.pick:
		w.pick = pick
		world.palette.preview(w.element, pick)
		hand.trigger_haptic_pulse(&"haptic", 0.0, 0.25, 0.02, 0.0)


## Sends the swatch at the top of `hand`'s wheel to the garden, unless the garden already has it (another
## player may have picked it meanwhile); until it comes back it shows here alone.
func close(hand: Hand) -> void:
	var w: Wheel = wheels[hand]
	_drop(hand)
	if w.pick != world.palette.picks[w.element]:
		world.submit({"op": "palette", "element": w.element, "index": w.pick}, world.palette.apply)
	else:
		world.palette.apply()


func _drop(hand: Hand) -> void:
	wheels[hand].node.queue_free()
	wheels.erase(hand)


## The wheel follows the hand but keeps the frame it opened in, turning with the twist; the picked swatch
## stands at the top, larger.
func _place(w: Wheel, hand: Hand) -> void:
	w.node.global_transform = Transform3D(w.basis, hand.global_position + w.basis * WHEEL_AT)
	var n := w.swatches.size()
	for k in n:
		var a := (w.degrees / Palette.TWIST_STEP - (k - w.start)) * TAU / n
		w.swatches[k].position = Vector3(sin(a), cos(a), 0.0) * WHEEL_RADIUS
		w.swatches[k].scale = Vector3.ONE * (1.6 if k == w.pick else 1.0)


## Degrees the hand has turned about its pointing axis since `start`, clockwise as the hand sees it.
static func _roll(start: Basis, now: Basis) -> float:
	var fwd := -start.z
	var x := now.x - fwd * now.x.dot(fwd)
	return rad_to_deg(atan2(fwd.dot(start.x.cross(x)), start.x.dot(x)))
