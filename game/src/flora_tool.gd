class_name FloraTool
extends Node3D

## Left hand: trigger paints grass or flowers where the hand points, X switches between them, grip
## plants a tree there. The brush widens with distance; painting a spot again thickens it.

const RATES := {&"flowers": 12.0, &"grass": 30.0}
const TINTS := {&"flowers": Color(1.0, 0.82, 0.9, 0.6), &"grass": Color(0.78, 1.0, 0.55, 0.6)}
const RADIUS_PER_METRE := 0.15
const MIN_RADIUS := 0.3
const MAX_RADIUS := 3.0

## A plant went in, for the soundscape.
signal planted(at: Vector3)

var rig: Rig
var flora: Flora
var mode := &"flowers"
var painting := false
var _rng := RandomNumberGenerator.new()
var _owed := 0.0
var _buttons: Buttons
var _beam: Beam
var _ring: MeshInstance3D


func _init(player: Rig, plants: Flora) -> void:
	rig = player
	flora = plants
	_rng.seed = 23
	_buttons = Buttons.new(rig.left).watch(["trigger_click", "grip_click", "ax_button"])
	_beam = Beam.new(Color.WHITE)
	add_child(_beam)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.96
	ring.outer_radius = 1.0
	ring.rings = 32
	ring.ring_segments = 4
	_ring = MeshInstance3D.new()
	_ring.mesh = ring
	_ring.material_override = _beam.material_override
	_ring.top_level = true
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	set_mode(mode)


func _process(delta: float) -> void:
	var hand := rig.left.global_transform
	var hit: Variant = null
	if not rig.aiming:
		hit = Terrain.raycast(hand.origin, -hand.basis.z)
	var radius := brush_radius(hand.origin, hit)
	_beam.visible = hit != null and rig.left.get_has_tracking_data()
	_ring.visible = _beam.visible
	if _beam.visible:
		_beam.span(hand.origin, hit)
		_ring.global_transform = Transform3D(Basis().scaled(Vector3(radius, 1.0, radius)), hit + Vector3.UP * 0.04)

	painting = hit != null and _buttons.held("trigger_click")
	if painting:
		paint(hit, radius, delta)
	if _buttons.pressed("ax_button"):
		set_mode(&"grass" if mode == &"flowers" else &"flowers")
	if _buttons.pressed("grip_click") and hit != null:
		plant_tree(hit)
	_buttons.latch()


static func brush_radius(hand: Vector3, hit: Variant) -> float:
	if hit == null:
		return MIN_RADIUS
	return clampf(hand.distance_to(hit) * RADIUS_PER_METRE, MIN_RADIUS, MAX_RADIUS)


## Paint `delta` seconds of the current mode over a disc on the ground.
func paint(center: Vector3, radius: float, delta: float) -> void:
	_owed += RATES[mode] * PI * radius * radius * delta
	var n := int(_owed)
	_owed -= n
	for p in FloraLayout.brush(center, radius, n, _rng, Terrain.height_at):
		if mode == &"grass":
			flora.add_grass(p, _rng)
		else:
			flora.add_flower(p, _rng)
	if n > 0:
		planted.emit(center)


func plant_tree(at: Vector3) -> void:
	flora.add_tree(at, _rng)
	planted.emit(at)


func set_mode(m: StringName) -> void:
	mode = m
	(_beam.material_override as StandardMaterial3D).albedo_color = TINTS[m]
