class_name GroundGrab
extends Node3D

## Shapes the ground, whatever a hand holds: a grip on the ground grabs it where the hand points and the
## grabbed point follows the hand up into a hill or down into a hollow, shown as the ground's live hump.
## Letting go sends the ground's new heights as a build command, one step per grab; the hump shows until it
## is in. Farther ground grabs a wider hill and rises faster than the hand. Each hand grabs on its own, with
## its own hump, so two hands pull two hills at once; on the same ground their humps add. The ground is the
## last thing a grip takes: a wall, roof or carried house it points at takes it first; open sky, and the sun
## or the moon even under the ground, is the sky's.

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


## One hand's stroke on the ground, and its strokes sent whose hump still shows.
class Grab:
	var hand: Hand
	var slot := 0
	var grip: Buttons
	var ring: MeshInstance3D
	var at: Variant = null
	## The grip holds this stroke; a stroke begun by a script is moved by it.
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
	for h in rig.hands:
		var g := Grab.new()
		g.hand = h
		g.slot = _grabs.size()
		g.grip = Buttons.new(h).watch(["grab"])
		g.ring = FloraTool.ring(TINT, 48, 0.97)
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
		FloraTool.put_ring(g.ring, g.at, g.radius, 0.05)
		if not hand.tracked():
			return
		pull(hand, (hand.position.y - g.hand_y) * g.gain)
		follow(hand, delta)
		_tick(g)
		return
	if not g.grip.pressed("grab") or g.at != null or hand.taken() or hand.picking or rig.aim_hand == hand or not hand.tracked() or editing.call(hand):
		return
	var dir := -hand.global_basis.z
	var hit: Variant = Terrain.raycast(hand.grip_from(), dir, hand.grip_reach())
	if hit == null or Daylight.aims_at_body(dir, world.time):
		return
	begin(hand, hit, hand.at_controller().distance_to(hit) * RADIUS_PER_METRE)
	g.gripped = true
	g.hand_y = hand.position.y
	g.gain = Hand.reach_gain(hand.global_position.distance_to(hit))
	g.ticked = 0.0
	FloraTool.put_ring(g.ring, hit, g.radius, 0.05)


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
	g.lift = clampf(metres, -Terrain.RELIEF, Terrain.RELIEF)
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


## Sends `hand`'s stroke to the garden as one step; a tap that barely moved leaves the ground as it was.
func end_stroke(hand: Hand) -> void:
	var g := _grab(hand)
	var cmd := stroke(hand)
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
