class_name DeleteTool
extends Node3D

## Takes away one thing per trigger press, for whichever hand holds it: the wall it points at, else the
## tree nearest where it meets the ground, else the painted plants under the brush ring. Undo puts it back.

const TREE_REACH := 1.5
const TINT := Color(1.0, 0.7, 0.62, 0.6)

var rig: Rig
var walls: WallTool
var flora: Flora
var world: World
var _buttons: Array[Buttons] = []


func _init(player: Rig, builder: WallTool, plants: FloraTool, garden: World) -> void:
	rig = player
	walls = builder
	flora = plants.flora
	world = garden
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
	var patch := flora.painted_near(ground, FloraTool.brush_radius(origin, ground))
	if not patch.is_empty():
		return {"plants": patch}
	return {}


func take(target: Dictionary) -> void:
	if target.has("wall"):
		world.submit({"op": "unwall", "ids": PackedInt32Array([target.wall.id])})
	elif target.has("plants"):
		var by_group := {}
		for p: Flora.Plant in target.plants:
			by_group.get_or_add(p.group, []).append(p.index)
		for g in by_group:
			by_group[g] = PackedInt32Array(by_group[g])
		world.submit({"op": "show", "plants": by_group, "on": false})
