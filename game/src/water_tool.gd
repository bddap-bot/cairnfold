class_name WaterTool
extends Node3D

## Water stands at the pointed spot's height, never above the rim it would spill over (PondLayout).

const TINT := Color(0.7, 0.92, 1.0, 0.6)
const REFUSED := Color(0.72, 0.76, 0.86, 0.5)
## Metres the pointed spot moves before its water is worked out again.
const FOLLOW := 0.05

var rig: Rig
var world: World
## Per hand: the water shown, its ground point and pond; the point being worked out off the main thread, its task
## (-1: none) and the box the task leaves its pond in.
var _ghosts: Array[MeshInstance3D] = []
var _at: Array[Vector3] = []
var _ponds: Array[PondLayout.Pond] = []
var _asked: Array[Vector3] = []
var _tasks: Array[int] = []
var _boxes: Array[Array] = []
## Fills let in before their preview caught up: [hand, pointed spot, task, box].
var _fires: Array[Array] = []


func _init(player: Rig, garden: World) -> void:
	rig = player
	world = garden
	var material := Meshes.glow(Color(TINT, 0.45))
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for h in rig.hands:
		var ghost := MeshInstance3D.new()
		ghost.material_override = material
		ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ghost.top_level = true
		ghost.visible = false
		add_child(ghost)
		_ghosts.append(ghost)
		_at.append(Vector3.INF)
		_ponds.append(null)
		_asked.append(Vector3.INF)
		_tasks.append(-1)
		_boxes.append([null])
	world.applied.connect(func(_cmd: Dictionary) -> void: _at.fill(Vector3.INF))


func _exit_tree() -> void:
	for t in _tasks:
		if t >= 0:
			WorkerThreadPool.wait_for_task_completion(t)
	_tasks.fill(-1)
	settle()


func _process(_delta: float) -> void:
	for i in rig.hands.size():
		_handle(i)
	while not _fires.is_empty() and WorkerThreadPool.is_task_completed(_fires[0][2]):
		_let_in(_fires.pop_front())


## True while a fill let in has not yet been sent to the garden.
func pouring() -> bool:
	return not _fires.is_empty()


func settle() -> void:
	while not _fires.is_empty():
		_let_in(_fires.pop_front())
	world.settle()


func _handle(i: int) -> void:
	var hand := rig.hands[i]
	var b := hand.buttons
	if hand.tool != Hand.Tool.POND or rig.aim_hand == hand or not hand.tracked():
		_show(i, null)
		return
	var t := hand.global_transform
	var hit: Variant = world.terrain.raycast(t.origin, -t.basis.z)
	_show(i, hit)
	hand.point(hit, TINT if _ponds[i] != null else REFUSED)
	if hit != null and b.pressed("tool"):
		fill(hand, hit)


## Flooded off the main thread, so a moving point shows what it held a frame or two before.
func _show(i: int, hit: Variant) -> void:
	if _tasks[i] >= 0 and WorkerThreadPool.is_task_completed(_tasks[i]):
		WorkerThreadPool.wait_for_task_completion(_tasks[i])
		_tasks[i] = -1
		_at[i] = _asked[i]
		_ponds[i] = _boxes[i][0]
		if _ponds[i] != null:
			_ghosts[i].mesh = PondWater.sheet(PondWater.quads(_ponds[i]))
			_ghosts[i].position = Vector3(0, _ponds[i].level + 0.01, 0)
	if hit == null:
		_at[i] = Vector3.INF
		_ponds[i] = null
	elif _tasks[i] < 0 and _at[i].distance_to(hit) > FOLLOW:
		_asked[i] = hit
		var box := [null]
		_boxes[i] = box
		var from := Water.candidates(world.terrain, hit)
		var level: float = hit.y
		_tasks[i] = WorkerThreadPool.add_task(func() -> void:
			box[0] = Water.deepest(from, level)
			if box[0] != null:
				PondWater.quads(box[0]))
	_ghosts[i].visible = _ponds[i] != null


## Submits now if the preview has caught up, else a frame or two later; `settle` waits for it.
func fill(hand: Hand, hit: Vector3) -> void:
	var i := rig.hands.find(hand)
	if i >= 0 and _at[i].distance_to(hit) <= FOLLOW and _fires.is_empty():
		_pour(hand, _at[i], _ponds[i])
		return
	var box := [null]
	var from := Water.candidates(world.terrain, hit)
	var level := hit.y
	_fires.append([hand, hit, WorkerThreadPool.add_task(func() -> void: box[0] = Water.deepest(from, level)), box])


func _let_in(fire: Array) -> void:
	WorkerThreadPool.wait_for_task_completion(fire[2])
	_pour(fire[0], fire[1], fire[3][0])


func _pour(hand: Hand, at: Vector3, p: PondLayout.Pond) -> void:
	if p == null:
		Cues.play(Cues.Act.REFUSED, hand.global_position, hand)
		return
	Cues.play(Cues.Act.POND_POUR, at, hand)
	world.submit({"op": "ponds", "put": {p.at: at.y}, "wet": p.cells.size()}, Callable(), hand)
