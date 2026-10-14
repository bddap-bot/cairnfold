class_name FloraTool
extends Node3D

## Flowers, grass and trees, for whichever hand holds them: the trigger paints flowers or grass where the
## hand points, or plants a tree there. The brush widens with distance; painting a spot again thickens it.

## Plants per square metre per second of painting.
const RATES := {Hand.Tool.FLOWERS: 12.0, Hand.Tool.GRASS: 30.0}
const TINTS := {Hand.Tool.FLOWERS: Color(1.0, 0.82, 0.9, 0.6), Hand.Tool.GRASS: Color(0.78, 1.0, 0.55, 0.6), Hand.Tool.TREES: Color(0.85, 1.0, 0.8, 0.6)}
const RADIUS_PER_METRE := 0.15
const MIN_RADIUS := 0.3
const MAX_RADIUS := 3.0

signal planted


class Brush:
	var hand: Hand
	var buttons: Buttons
	var ring: MeshInstance3D
	## What the current trigger hold has painted, one undo step on release.
	var stroke: Array[Flora.Plant] = []
	var owed := 0.0


var rig: Rig
var flora: Flora
var history: History
var brushes: Array[Brush] = []
## Where the grass feels the left hand while it is untracked; desktop scripts hold it in the grass.
var stand_in := Flora.NO_HAND
var _rng := RandomNumberGenerator.new()


func _init(player: Rig, plants: Flora, steps: History) -> void:
	rig = player
	flora = plants
	history = steps
	_rng.seed = 23
	var ring := TorusMesh.new()
	ring.inner_radius = 0.96
	ring.outer_radius = 1.0
	ring.rings = 32
	ring.ring_segments = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 1, 1, 0.6)
	for h in rig.hands:
		var b := Brush.new()
		b.hand = h
		b.buttons = Buttons.new(h).watch(["trigger_click"])
		b.ring = MeshInstance3D.new()
		b.ring.mesh = ring
		b.ring.material_override = mat
		b.ring.top_level = true
		b.ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(b.ring)
		brushes.append(b)


func busy() -> bool:
	for b in brushes:
		if not b.stroke.is_empty():
			return true
	return false


## False for a plant still in a stroke being painted; it becomes undoable when the stroke ends.
func settled(plant: Flora.Plant) -> bool:
	for b in brushes:
		if b.stroke.has(plant):
			return false
	return true


func brush(hand: Hand) -> Brush:
	for b in brushes:
		if b.hand == hand:
			return b
	return null


func _process(delta: float) -> void:
	flora.part(rig.left.global_position if rig.left.get_has_tracking_data() else stand_in, _reach(rig.right))
	for b in brushes:
		_handle(b, delta)
		b.buttons.latch()


func _handle(b: Brush, delta: float) -> void:
	var held := b.hand.tool
	b.ring.visible = false
	if not TINTS.has(held) or rig.aim_hand == b.hand:
		end_stroke(b)
		return
	if b.buttons.released("trigger_click"):
		end_stroke(b)
	if not b.hand.get_has_tracking_data():
		return
	var hand := b.hand.global_transform
	var hit: Variant = Terrain.raycast(hand.origin, -hand.basis.z)
	b.hand.point(hit, TINTS[held])
	if hit == null:
		end_stroke(b)
		return
	if held == Hand.Tool.TREES:
		if b.buttons.pressed("trigger_click"):
			plant_tree(hit)
		return
	var radius := brush_radius(hand.origin, hit)
	b.ring.visible = true
	b.ring.global_transform = Transform3D(Basis().scaled(Vector3(radius, 1.0, radius)), hit + Vector3.UP * 0.04)
	if b.buttons.held("trigger_click"):
		paint(b, hit, radius, delta)


static func _reach(hand: XRController3D) -> Vector3:
	return hand.global_position if hand.get_has_tracking_data() else Flora.NO_HAND


static func brush_radius(hand: Vector3, hit: Variant) -> float:
	if hit == null:
		return MIN_RADIUS
	return clampf(hand.distance_to(hit) * RADIUS_PER_METRE, MIN_RADIUS, MAX_RADIUS)


func paint(b: Brush, center: Vector3, radius: float, delta: float) -> void:
	var grass := b.hand.tool == Hand.Tool.GRASS
	b.owed += RATES[b.hand.tool] * PI * radius * radius * delta
	var n := int(b.owed)
	b.owed -= n
	for p in FloraLayout.brush(center, radius, n, _rng, Terrain.height_at):
		var plant := flora.add_grass(p, _rng) if grass else flora.add_flower(p, _rng)
		if plant != null:
			b.stroke.append(plant)
	if n > 0:
		planted.emit()


func end_stroke(b: Brush) -> void:
	if b.stroke.is_empty():
		return
	_record(b.stroke)
	b.stroke = []


func plant_tree(at: Vector3) -> void:
	var parts := flora.add_tree(at, _rng)
	if parts.is_empty():
		return
	_record(parts)
	planted.emit()


func _record(plants: Array[Flora.Plant]) -> void:
	history.add(flora.set_shown.bind(plants, false), flora.set_shown.bind(plants, true))
