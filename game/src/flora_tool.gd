class_name FloraTool
extends Node3D

## Flowers, grass, stone, trees and paths, for whichever hand holds them: the trigger paints flowers, grass
## or stone ground where the hand points, plants a tree there, or lays a path along the stroke. The brush
## widens with distance; painting a spot again thickens it, and a path is as wide as the brush. The grip
## of a hand holding stone paints the ground back to meadow, and the plants under it stand up again.

## Plants per square metre per second of painting.
const RATES := {Hand.Tool.FLOWERS: 12.0, Hand.Tool.GRASS: 30.0}
const TINTS := {Hand.Tool.FLOWERS: Color(1.0, 0.82, 0.9, 0.6), Hand.Tool.GRASS: Color(0.78, 1.0, 0.55, 0.6), Hand.Tool.TREES: Color(0.85, 1.0, 0.8, 0.6), Hand.Tool.PATH: Color(1.0, 0.9, 0.7, 0.6), Hand.Tool.STONE: Color(0.9, 0.88, 0.82, 0.6)}
const RADIUS_PER_METRE := 0.15
const MIN_RADIUS := 0.3
const MAX_RADIUS := 3.0
## A held ground brush stamps again after this long, or once it has moved this fraction of its radius.
const STAMP_EVERY := 0.1
const STAMP_MOVE := 0.3

signal planted


class Brush:
	var hand: Hand
	var buttons: Buttons
	var ring: MeshInstance3D
	## What the current trigger hold has painted, one undo step on release.
	var stroke: Array[Flora.Plant] = []
	## The ground the current hold has painted, stone or meadow.
	var ground: Ground.Stroke
	var since_stamp := 0.0
	var last_stamp := Vector3.INF
	var owed := 0.0
	var paving := false


var rig: Rig
var flora: Flora
var paths: Paths
var history: History
var brushes: Array[Brush] = []
## Where the grass feels the left hand while it is untracked; desktop scripts hold it in the grass.
var stand_in := Flora.NO_HAND
var _rng := RandomNumberGenerator.new()


func _init(player: Rig, plants: Flora, ways: Paths, steps: History) -> void:
	rig = player
	flora = plants
	paths = ways
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
		b.buttons = Buttons.new(h).watch(["trigger_click", "grip_click"])
		b.ring = MeshInstance3D.new()
		b.ring.mesh = ring
		b.ring.material_override = mat
		b.ring.top_level = true
		b.ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(b.ring)
		brushes.append(b)


func busy() -> bool:
	if paths.busy():
		return true
	return _ground_held() or brushes.any(func(b: Brush) -> bool: return not b.stroke.is_empty())


func _ground_held() -> bool:
	return brushes.any(func(b: Brush) -> bool: return b.ground != null)


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
	if b.buttons.released("trigger_click") or (held == Hand.Tool.STONE and b.buttons.released("grip_click")):
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
	if held == Hand.Tool.PATH:
		radius = clampf(radius, PathLayout.HALF_WIDTH.x, PathLayout.HALF_WIDTH.y)
	b.ring.visible = true
	b.ring.global_transform = Transform3D(Basis().scaled(Vector3(radius, 1.0, radius)), hit + Vector3.UP * 0.04)
	if held == Hand.Tool.PATH:
		if b.buttons.pressed("trigger_click") and not paths.busy() and not _ground_held():
			begin_path(b, hit, radius)
		elif b.buttons.held("trigger_click") and b.paving:
			extend_path(hit, radius)
	elif b.buttons.held("trigger_click"):
		paint(b, hit, radius, delta)
	elif held == Hand.Tool.STONE and b.buttons.held("grip_click"):
		paint(b, hit, radius, delta, true)


static func _reach(hand: XRController3D) -> Vector3:
	return hand.global_position if hand.get_has_tracking_data() else Flora.NO_HAND


static func brush_radius(hand: Vector3, hit: Variant) -> float:
	if hit == null:
		return MIN_RADIUS
	return clampf(hand.distance_to(hit) * RADIUS_PER_METRE, MIN_RADIUS, MAX_RADIUS)


## Paints with the hand's tool; `meadow` takes stone ground back to meadow instead of laying it.
func paint(b: Brush, center: Vector3, radius: float, delta: float, meadow := false) -> void:
	if b.hand.tool == Hand.Tool.STONE:
		_lay_ground(b, Ground.Kind.MEADOW if meadow else Ground.Kind.STONE, center, radius, delta)
		return
	var grass := b.hand.tool == Hand.Tool.GRASS
	b.owed += RATES[b.hand.tool] * PI * radius * radius * delta
	var n := int(b.owed)
	b.owed -= n
	for p in FloraLayout.brush(center, radius, n, _rng, Terrain.height_at):
		# A plant on a path or stone would be parted to nothing and still take a slot in the pool.
		if Ground.bare(p.x, p.z) > 0.9:
			continue
		var plant := flora.add_grass(p, _rng) if grass else flora.add_flower(p, _rng)
		if plant != null:
			b.stroke.append(plant)
	if n > 0:
		planted.emit()


## A live path keeps its own copy of the ground mask, so nothing stamps it while one is drawn. One ground
## stroke at a time: two interleaved would replay in a different order than they were painted.
func _lay_ground(b: Brush, kind: Ground.Kind, center: Vector3, radius: float, delta: float) -> void:
	if b.ground != null and b.ground.kind != kind:
		end_stroke(b)
	b.since_stamp += delta
	if paths.busy() or (b.ground == null and _ground_held()) or (b.ground != null and b.since_stamp < STAMP_EVERY and center.distance_to(b.last_stamp) < radius * STAMP_MOVE):
		return
	if b.ground == null:
		b.ground = Ground.Stroke.new(kind)
	b.since_stamp = 0.0
	b.last_stamp = center
	if b.ground.add(center.x, center.z, radius * 0.4, radius * 0.8):
		planted.emit()


func end_stroke(b: Brush) -> void:
	if b.paving:
		end_path(b)
	var ground := b.ground
	b.ground = null
	if ground != null and ground.stamps.is_empty():
		ground = null
	if ground != null:
		Ground.lay(ground, true)
	if b.stroke.is_empty() and ground == null:
		return
	_record(b.stroke, ground)
	b.stroke = []


func begin_path(b: Brush, at: Vector3, radius: float) -> void:
	b.paving = true
	paths.begin(at, radius)
	planted.emit()


func extend_path(at: Vector3, radius: float) -> void:
	paths.extend(at, radius)
	planted.emit()


func end_path(b: Brush) -> void:
	b.paving = false
	var path := paths.end()
	if path != null:
		history.add(paths.take.bind(path), paths.put.bind(path), paths.chunks(path))
	planted.emit()


func plant_tree(at: Vector3) -> void:
	var parts := flora.add_tree(at, _rng)
	if parts.is_empty():
		return
	_record(parts)
	planted.emit()


func _record(plants: Array[Flora.Plant], ground: Ground.Stroke = null) -> void:
	history.add(_show.bind(plants, ground, false), _show.bind(plants, ground, true))


func _show(plants: Array[Flora.Plant], ground: Ground.Stroke, shown: bool) -> void:
	flora.set_shown(plants, shown)
	if ground == null:
		return
	if shown:
		Ground.lay(ground)
	else:
		Ground.lift(ground)
