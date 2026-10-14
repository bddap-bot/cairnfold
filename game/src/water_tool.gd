class_name WaterTool
extends Node3D

## Digs ponds, for whichever hand holds the pond tool: a held trigger scoops a hollow where the hand
## points, deeper the longer it is held, and on release the hollow fills with water. Digging is the terrain
## tool's stroke pulled down, so the hollow is ordinary ground, and the seed its water fills from rides on
## the same build command.

const RADIUS := 2.8
const DIG_RATE := 0.7
const MAX_DEPTH := 1.3
## Even a tap scoops this deep, enough to hold water.
const MIN_SCOOP := 0.45
const TINT := Color(0.7, 0.92, 1.0, 0.6)

var rig: Rig
var terrain: TerrainTool
var water: Water
## The hand digging now; the terrain tool pulls one stroke at a time.
var digger: Hand
var _buttons: Array[Buttons] = []
var _at := Vector3.ZERO
var _depth := 0.0


func _init(player: Rig, terrain_tool: TerrainTool, ponds: Water) -> void:
	rig = player
	terrain = terrain_tool
	water = ponds
	for h in rig.hands:
		_buttons.append(Buttons.new(h).watch(["trigger_click"]))


func _process(delta: float) -> void:
	for b in _buttons:
		_handle(b, delta)
		b.latch()


func _handle(b: Buttons, delta: float) -> void:
	var hand: Hand = b.hand
	var holding := hand.tool == Hand.Tool.POND and rig.aim_hand != hand
	if digger == hand and (not holding or b.released("trigger_click")):
		end()
	if not holding or not hand.get_has_tracking_data():
		return
	if digger == hand:
		hand.point(_at, TINT)
		if b.held("trigger_click"):
			deepen(delta)
		return
	var t := hand.global_transform
	var hit: Variant = Terrain.raycast(t.origin, -t.basis.z)
	hand.point(hit, TINT)
	if hit != null and b.pressed("trigger_click") and not terrain.busy():
		begin(hand, hit)


func begin(hand: Hand, ground: Vector3) -> void:
	digger = hand
	_at = ground
	_depth = 0.0
	terrain.begin(ground, RADIUS)


func deepen(delta: float) -> void:
	_depth = minf(_depth + DIG_RATE * delta, MAX_DEPTH)
	terrain.pull(-maxf(_depth, MIN_SCOOP) * smoothstep(0.0, MIN_SCOOP, _depth))
	terrain.follow(delta)


## Makes the hollow permanent and leaves a seed for its water.
func end() -> void:
	digger = null
	terrain.pull(-maxf(_depth, MIN_SCOOP))
	terrain.end_stroke({"seed": Terrain.grid_point(_at.x, _at.z)})
