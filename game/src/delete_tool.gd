class_name DeleteTool
extends Node3D

## Takes things away, for whichever hand holds it. On a wall the trigger is an eraser: held, its beam
## sweeps along the wall, and the stretch it swept breaks away into a ruin, stepped down to a gap at its foot
## with fallen stones; a tap breaks a short gap. The ruin shows as it is swept and goes to the garden when the
## trigger lets go. A sweep that would leave nothing worth standing, or one on a fence, house or tower, takes
## the whole of it. Off the walls, one press takes the tree nearest where the beam meets the ground, else the
## painted plants under the brush ring. Undo puts any of it back.

const TREE_REACH := 1.5
const TINT := Color(1.0, 0.7, 0.62, 0.6)

var rig: Rig
var walls: WallTool
var flora: Flora
var world: World
var _buttons: Array[Buttons] = []
## Sweeps under way, by whoever is sweeping (a hand, or the driver): {wall, from, to, last}, `from` and `to`
## unwrapped round a loop.
var _cuts := {}


func _init(player: Rig, builder: WallTool, plants: FloraTool, garden: World) -> void:
	rig = player
	walls = builder
	flora = plants.flora
	world = garden
	world.restored.connect(func() -> void: _cuts.clear())
	for h in rig.hands:
		_buttons.append(Buttons.new(h).watch(["trigger_click"]))


func busy() -> bool:
	return not _cuts.is_empty()


func _process(_delta: float) -> void:
	for b in _buttons:
		var hand: Hand = b.hand
		var live := hand.tool == Hand.Tool.DELETE and rig.aim_hand != hand and hand.get_has_tracking_data()
		var t := hand.global_transform
		if _cuts.has(hand):
			if live and b.held("trigger_click"):
				hand.point(sweep(hand, t.origin, -t.basis.z), TINT)
			else:
				let_go(hand)
		elif live:
			var pick := walls.pick_wall(t.origin, -t.basis.z)
			hand.point(pick.point if not pick.is_empty() else Terrain.raycast(t.origin, -t.basis.z), TINT)
			if b.pressed("trigger_click"):
				var target := aim(t.origin, -t.basis.z)
				if target.has("wall"):
					begin(hand, target.wall, target.s)
				else:
					take(target)
		b.latch()


## What a ray from `origin` along `dir` takes: its wall and where along it, or plants, if any. Painted plants
## are searched only on a press.
func aim(origin: Vector3, dir: Vector3) -> Dictionary:
	var pick := walls.pick_wall(origin, dir)
	if not pick.is_empty():
		return {"wall": pick.wall, "s": pick.s}
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


## One press and release: a wall breaks a short gap where it was pointed at, plants go at once.
func take(target: Dictionary) -> void:
	if target.has("wall"):
		begin(self, target.wall, target.s)
		let_go(self)
	elif target.has("plants"):
		var by_group := {}
		for p: Flora.Plant in target.plants:
			by_group.get_or_add(p.group, []).append(p.index)
		for g in by_group:
			by_group[g] = PackedInt32Array(by_group[g])
		world.submit({"op": "show", "plants": by_group, "on": false})


func begin(who: Object, w: Wall, s: float) -> void:
	_cuts[who] = {"wall": w, "from": s, "to": s, "last": s}
	_preview(_cuts[who])


## Follows a ray along the wall being erased and returns the point on it the ray is nearest.
func sweep(who: Object, origin: Vector3, dir: Vector3) -> Vector3:
	var cut: Dictionary = _cuts[who]
	var w: Wall = cut.wall
	if not is_instance_valid(w) or walls.find(w.id) != w:
		_cuts.erase(who)
		return origin + dir
	var hit := w.ray_distance(origin, dir)
	var at: float = cut.to + w.layout.offset(hit.s, cut.last)
	cut.last = hit.s
	cut.from = minf(cut.from, at)
	cut.to = maxf(cut.to, at)
	_preview(cut)
	return hit.point


## Sends what was swept: a reshape breaking the stretch away, or the whole wall when nothing would stand.
func let_go(who: Object) -> void:
	var cut: Dictionary = _cuts.get(who, {})
	_cuts.erase(who)
	var w: Wall = cut.get("wall")
	if w == null or not is_instance_valid(w) or walls.find(w.id) != w:
		return
	var ruins := _ruins(cut)
	if ruins.is_empty():
		world.submit({"op": "unwall", "ids": PackedInt32Array([w.id])}, walls.settle.bind(w.id))
	else:
		world.submit({"op": "reshape", "id": w.id, "data": {"ruins": PackedVector2Array(ruins)}}, walls.settle.bind(w.id))


## The wall's ruins once the sweep breaks away, or none when the whole wall goes.
func _ruins(cut: Dictionary) -> Array[Vector2]:
	var w: Wall = cut.wall
	var out: Array[Vector2] = []
	if w.layout.fence or w.roof != null:
		return out
	var layout := WallLayout.new()
	layout.lengths = w.layout.lengths
	layout.closed = w.layout.closed
	layout.ruins.assign(Array(world.state.walls[w.id].ruins))
	var left := layout.erase(cut.from, cut.to)
	if left.size() == 1 and left[0] == Vector2(0.0, layout.length()):
		return out
	return left


## Shows the wall broken as the sweep would leave it, on this machine only, until its command comes back.
func _preview(cut: Dictionary) -> void:
	var w: Wall = cut.wall
	if w.layout.fence or w.roof != null:
		return
	var ruins := _ruins(cut)
	if ruins.is_empty():
		ruins.append(Vector2(0.0, w.layout.length()))
	if ruins != w.layout.ruins:
		w.layout.ruins = ruins
		w.rebuild(false)
