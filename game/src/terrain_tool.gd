class_name TerrainTool
extends Node3D

## Shapes the ground, for whichever hand holds it: the trigger grabs the ground where the hand points and
## the grabbed point follows the hand up into a hill or down into a hollow, made permanent when the
## trigger lets go. Farther ground grabs a wider hill and rises faster than the hand. One stroke at a
## time, since the ground carries one live hump.

const MIN_RADIUS := 2.0
const MAX_RADIUS := 9.0
const RADIUS_PER_METRE := 0.3
## Hills widen with height so their flanks stay walkable and walls on them stay standing.
const SPREAD := 3.0
const MAX_LIFT := 6.0
const FOLLOW_EVERY := 0.06
const TICK := 0.25
const TINT := Color(0.92, 0.85, 0.66, 0.6)

## Ground under `area` moved; `settled` once a stroke ends or a step is undone or redone.
signal reshaped(area: Rect2, settled: bool)

var rig: Rig
var history: History
var _triggers: Array[Buttons] = []
var _rings: Array[MeshInstance3D] = []
var _hand: Hand
var _hand_y := 0.0
var _gain := 1.0
var _lift := 0.0
var _ticked := 0.0
var _grabbed: Variant = null
var _base_radius := MIN_RADIUS
var _radius := MIN_RADIUS
var _moved := Rect2()
var _since_follow := 0.0


func _init(player: Rig, steps: History) -> void:
	rig = player
	history = steps
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
		_triggers.append(Buttons.new(h).watch(["trigger_click"]))
		var mi := MeshInstance3D.new()
		mi.mesh = ring
		mi.material_override = mat
		mi.top_level = true
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_rings.append(mi)


func busy() -> bool:
	return _grabbed != null


func _process(delta: float) -> void:
	for i in rig.hands.size():
		_handle(rig.hands[i], _triggers[i], _rings[i], delta)
		_triggers[i].latch()


func _handle(hand: Hand, trigger: Buttons, ring: MeshInstance3D, delta: float) -> void:
	ring.visible = false
	var holding := hand.tool == Hand.Tool.TERRAIN and rig.aim_hand != hand
	if _hand == hand:
		if not holding or not trigger.held("trigger_click"):
			end_stroke()
			return
		var g: Vector3 = _grabbed
		_show_ring(ring, g, _radius)
		if not hand.get_has_tracking_data():
			return
		pull((hand.position.y - _hand_y) * _gain)
		follow(delta)
		_tick(hand)
		hand.point(g + Vector3.UP * _lift, TINT)
		return
	if not holding or not hand.get_has_tracking_data():
		return
	var t := hand.global_transform
	var hit: Variant = Terrain.raycast(t.origin, -t.basis.z)
	hand.point(hit, TINT)
	if hit == null or busy():
		return
	var reach := t.origin.distance_to(hit)
	_show_ring(ring, hit, clampf(reach * RADIUS_PER_METRE, MIN_RADIUS, MAX_RADIUS))
	if trigger.pressed("trigger_click"):
		_hand = hand
		_hand_y = hand.position.y
		_gain = Hand.reach_gain(reach)
		_ticked = 0.0
		begin(hit, reach * RADIUS_PER_METRE)


func _show_ring(ring: MeshInstance3D, at: Vector3, radius: float) -> void:
	ring.visible = true
	ring.global_transform = Transform3D(Basis().scaled(Vector3(radius, 1.0, radius)), at + Vector3.UP * 0.05)


## A soft click in the hand for every TICK of height, so the ground feels like it gives way in steps.
func _tick(hand: Hand) -> void:
	if absf(_lift - _ticked) >= TICK:
		_ticked = snappedf(_lift, TICK)
		hand.trigger_haptic_pulse(&"haptic", 0.0, 0.25, 0.02, 0.0)


func begin(ground: Vector3, radius: float) -> void:
	assert(_grabbed == null)
	_grabbed = ground
	_lift = 0.0
	_base_radius = clampf(radius, MIN_RADIUS, MAX_RADIUS)
	_radius = _base_radius
	_since_follow = 0.0
	_moved = _span(_radius)


## Raises the grabbed ground `metres` above where the stroke began (negative digs).
func pull(metres: float) -> void:
	var g: Vector3 = _grabbed
	_lift = clampf(metres, clampf(Terrain.LOWEST - g.y, -MAX_LIFT, 0.0), clampf(Terrain.HIGHEST - g.y, 0.0, MAX_LIFT))
	_radius = maxf(_base_radius, absf(_lift) * SPREAD)
	Terrain.set_hump(g.x, g.z, _radius, _lift)
	_moved = _moved.merge(_span(_radius))


## Lets walls and the player catch up with a stroke, at most every FOLLOW_EVERY.
func follow(delta: float) -> void:
	_since_follow += delta
	if _since_follow >= FOLLOW_EVERY:
		_since_follow = 0.0
		reshaped.emit(_moved, false)


## Makes the stroke permanent and records it as one undo step; a tap that barely moved leaves the ground as it was.
## A stroke that changed the ground runs `apply` now and on redo and `revert` on undo, so whatever rides on
## the ground edit (a pond's seed) is undone with it.
func end_stroke(apply := Callable(), revert := Callable()) -> void:
	var g: Vector3 = _grabbed
	_grabbed = null
	_hand = null
	if absf(_lift) < 0.01:
		Terrain.set_hump(g.x, g.z, _radius, 0.0)
		reshaped.emit(_moved, true)
		return
	var cells := Terrain.cells_around(g.x, g.z, _radius)
	var before := Terrain.read(cells)
	Terrain.bake()
	if apply.is_valid():
		apply.call()
	reshaped.emit(_moved, true)
	history.add(_step.bind(cells, before, revert), _step.bind(cells, Terrain.read(cells), apply))


func _step(cells: Rect2i, values: PackedFloat32Array, also: Callable) -> void:
	if also.is_valid():
		also.call()
	restore(cells, values)


func restore(cells: Rect2i, values: PackedFloat32Array) -> void:
	Terrain.write(cells, values)
	reshaped.emit(Terrain.world_rect(cells), true)


func _span(r: float) -> Rect2:
	var g: Vector3 = _grabbed
	return Rect2(g.x - r, g.z - r, r * 2.0, r * 2.0).grow(Terrain.STEP)
