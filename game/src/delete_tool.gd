class_name DeleteTool
extends Node3D

## Takes away one thing per trigger press, for whichever hand holds it: the wall it points at, else the
## tree nearest where it meets the ground, else the painted plants under the brush ring. Undo puts it back.

const TREE_REACH := 1.5
const TINT := Color(1.0, 0.7, 0.62, 0.6)

var rig: Rig
var walls: WallTool
var painter: FloraTool
var flora: Flora
var history: History
var _buttons: Array[Buttons] = []


func _init(player: Rig, builder: WallTool, plants: FloraTool, steps: History) -> void:
	rig = player
	walls = builder
	painter = plants
	flora = plants.flora
	history = steps
	for h in rig.hands:
		_buttons.append(Buttons.new(h).watch(["trigger_click"]))


func _process(_delta: float) -> void:
	for b in _buttons:
		var hand: Hand = b.hand
		if hand.tool == Hand.Tool.DELETE and rig.aim_hand != hand and hand.get_has_tracking_data():
			var t := hand.global_transform
			var pick := walls.pick_wall(t.origin, -t.basis.z)
			hand.point(pick.point if not pick.is_empty() else Terrain.raycast(t.origin, -t.basis.z), TINT)
			if b.pressed("trigger_click"):
				take(aim(t.origin, -t.basis.z))
		b.latch()


## What a ray from `origin` along `dir` takes: its wall or plants, if any. Painted plants are searched only on a press.
func aim(origin: Vector3, dir: Vector3) -> Dictionary:
	var pick := walls.pick_wall(origin, dir)
	if not pick.is_empty():
		return {"wall": pick.wall}
	var ground: Variant = Terrain.raycast(origin, dir)
	if ground == null:
		return {}
	var tree := flora.tree_near(ground, TREE_REACH)
	if not tree.is_empty():
		return {"plants": tree}
	var patch := flora.painted_near(ground, FloraTool.brush_radius(origin, ground)).filter(painter.settled)
	if not patch.is_empty():
		return {"plants": patch}
	return {}


func take(target: Dictionary) -> void:
	if target.has("wall"):
		walls.remove(target.wall)
	elif target.has("plants"):
		var plants: Array[Flora.Plant] = []
		plants.assign(target.plants)
		flora.set_shown(plants, false)
		history.add(flora.set_shown.bind(plants, true), flora.set_shown.bind(plants, false))
