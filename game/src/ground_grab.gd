class_name GroundGrab
extends Node3D

## Shapes the ground, whatever a hand holds: a grip on the ground grabs it where the hand points and the
## grabbed point follows the hand up into a hill or down into a hollow, shown as the ground's live hump.
## Letting go sends the ground's new heights as a build command, one step per grab; the hump shows until it
## is in. Farther ground grabs a wider hill and rises faster than the hand. Each hand grabs on its own, with
## its own hump, so two hands pull two hills at once; on the same ground their humps add. The ground is the
## last thing a grip takes: a wall, roof or carried house it points at takes it first; open sky is the sky's.

const MIN_RADIUS := 2.0
const MAX_RADIUS := 9.0
const RADIUS_PER_METRE := 0.3
## Hills widen with height so their flanks stay walkable and walls on them stay standing.
const SPREAD := 3.0
const FOLLOW_EVERY := 0.06
const TICK := 0.25
const TINT := Color(0.92, 0.85, 0.66, 0.6)

## Ground under `area` moved; `settled` once a stroke ends or a step is undone or redone.
signal reshaped(area: Rect2, settled: bool)


## One hand's stroke on the ground, by its grip or by a tool it holds (WaterTool), and its strokes sent
## whose hump still shows.
class Grab:
	var hand: Hand
	var slot := 0
	var grip: Buttons
	var ring: MeshInstance3D
	var at: Variant = null
	## The grip holds this stroke; a tool's stroke is moved by the tool.
	var gripped := false
	var hand_y := 0.0
	var gain := 1.0
	var lift := 0.0
	var ticked := 0.0
	var base_radius := MIN_RADIUS
	var radius := MIN_RADIUS
	var moved := Rect2()
	var since_follow := 0.0
	var sent := 0
	var pending := Rect2()


var rig: Rig
var world: World
var editing: Callable
var _grabs: Array[Grab] = []
var _due := Rect2()


func _init(player: Rig, garden: World, busy: Callable = func(_hand: Hand) -> bool: return false) -> void:
	rig = player
	world = garden
	editing = busy
	process_priority = 10
	world.restored.connect(drop)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.97
	ring.outer_radius = 1.0
	ring.rings = 48
	ring.ring_segments = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = TINT
	for h in rig.hands:
		var g := Grab.new()
		g.hand = h
		g.slot = _grabs.size()
		g.grip = Buttons.new(h).watch(["grab"])
		g.ring = MeshInstance3D.new()
		g.ring.mesh = ring
		g.ring.material_override = mat
		g.ring.top_level = true
		g.ring.visible = false
		g.ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(g.ring)
		_grabs.append(g)


## Whether `hand`, or with none any hand, has a stroke under way.
func busy(hand: Hand = null) -> bool:
	return _grabs.any(func(g: Grab) -> bool: return g.at != null and (hand == null or g.hand == hand))


func _grab(hand: Hand) -> Grab:
	return _grabs[rig.hands.find(hand)]


func _process(delta: float) -> void:
	for g in _grabs:
		_handle(g, delta)
		g.grip.latch()
		if g.gripped:
			g.hand.hold()


func _handle(g: Grab, delta: float) -> void:
	var hand := g.hand
	g.ring.visible = false
	if g.gripped:
		if rig.aim_hand == hand or hand.taken() or not g.grip.held("grab"):
			end_stroke(hand)
			return
		_show_ring(g.ring, g.at, g.radius)
		if not hand.get_has_tracking_data():
			return
		pull(hand, (hand.position.y - g.hand_y) * g.gain)
		follow(hand, delta)
		_tick(g)
		return
	if not g.grip.pressed("grab") or g.at != null or hand.taken() or hand.picking or rig.aim_hand == hand or not hand.get_has_tracking_data() or editing.call(hand):
		return
	var t := hand.global_transform
	var hit: Variant = Terrain.raycast(t.origin, -t.basis.z)
	if hit == null:
		return
	var reach := t.origin.distance_to(hit)
	begin(hand, hit, reach * RADIUS_PER_METRE)
	g.gripped = true
	g.hand_y = hand.position.y
	g.gain = Hand.reach_gain(reach)
	g.ticked = 0.0
	_show_ring(g.ring, hit, g.radius)


func _show_ring(ring: MeshInstance3D, at: Vector3, radius: float) -> void:
	ring.visible = true
	ring.global_transform = Transform3D(Basis().scaled(Vector3(radius, 1.0, radius)), at + Vector3.UP * 0.05)


## A soft click in the hand for every TICK of height, so the ground feels like it gives way in steps.
func _tick(g: Grab) -> void:
	if absf(g.lift - g.ticked) >= TICK:
		g.ticked = snappedf(g.lift, TICK)
		Cues.play(Cues.Act.GROUND_SHAPE, (g.at as Vector3) + Vector3.UP * g.lift, g.hand)


func begin(hand: Hand, ground: Vector3, radius: float) -> void:
	var g := _grab(hand)
	assert(g.at == null)
	g.at = ground
	g.lift = 0.0
	g.base_radius = clampf(radius, MIN_RADIUS, MAX_RADIUS)
	g.radius = g.base_radius
	g.since_follow = 0.0
	g.moved = _span(g, g.radius)


## Raises the ground `hand` grabbed `metres` above where its stroke began (negative digs).
func pull(hand: Hand, metres: float) -> void:
	var g := _grab(hand)
	var at: Vector3 = g.at
	g.lift = metres
	g.radius = maxf(g.base_radius, absf(g.lift) * SPREAD)
	Terrain.set_hump(g.slot, at.x, at.z, g.radius, g.lift)
	g.moved = g.moved.merge(_span(g, g.radius))


## Lets walls catch up with a stroke, at most every FOLLOW_EVERY.
func follow(hand: Hand, delta: float) -> void:
	var g := _grab(hand)
	g.since_follow += delta
	if g.since_follow >= FOLLOW_EVERY:
		g.since_follow = 0.0
		reshaped.emit(g.moved, false)


## The heights `hand`'s stroke leaves, as a build command.
func stroke(hand: Hand) -> Dictionary:
	var g := _grab(hand)
	var at: Vector3 = g.at
	var cells := Terrain.cells_around(at.x, at.z, g.radius)
	return {"op": "heights", "cells": cells, "values": Terrain.raised(cells, g.slot)}


## Sends `hand`'s stroke to the garden as one step, with `extra` fields riding on it (a pond's seed); a tap
## that barely moved leaves the ground as it was.
func end_stroke(hand: Hand, extra := {}) -> void:
	var g := _grab(hand)
	var cmd := stroke(hand)
	cmd.merge(extra)
	g.at = null
	g.gripped = false
	if absf(g.lift) < 0.01:
		Terrain.clear_hump(g.slot)
		reshaped.emit(g.moved, true)
		return
	g.sent += 1
	g.pending = g.pending.merge(g.moved) if g.pending.has_area() else g.moved
	world.submit(cmd, _settled.bind(g), hand)


## A sent stroke is in the garden or was turned down: its hump goes and what stood on it settles back.
## The garden applies a stroke it takes right after this, so what stood on the hump settles with that write,
## never on the ground between the hump going and the heights arriving.
func _settled(g: Grab) -> void:
	g.sent -= 1
	if g.sent == 0 and g.at == null:
		Terrain.clear_hump(g.slot)
		_due = _due.merge(g.pending) if _due.has_area() else g.pending
		g.pending = Rect2()
		_settle_due.call_deferred()


func _settle_due() -> void:
	if _due.has_area():
		reshaped.emit(_due, true)
		_due = Rect2()


## The garden's side of a ground edit, from any player.
func restore(cells: Rect2i, values: PackedFloat32Array) -> void:
	Terrain.write(cells, values)
	var area := Terrain.world_rect(cells)
	if _due.has_area():
		area = area.merge(_due)
		_due = Rect2()
	reshaped.emit(area, true)


## Forgets every stroke under way, as when the garden is swapped for another.
func drop() -> void:
	for g in _grabs:
		g.at = null
		g.gripped = false
		Terrain.clear_hump(g.slot)


func _span(g: Grab, r: float) -> Rect2:
	var at: Vector3 = g.at
	return Rect2(at.x - r, at.z - r, r * 2.0, r * 2.0).grow(Terrain.STEP)
