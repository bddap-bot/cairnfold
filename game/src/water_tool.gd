class_name WaterTool
extends Node3D

## Fills ponds, for whichever hand holds the pond tool: the hand points at the ground, and the hollow beside that
## point shows the water it would hold standing at that point's height; the trigger lets it in. Pointing at the
## rim of a dug hole fills it to the brim, lower down shallower, and pointing into a pond sets its level anew.
## Water never stands higher than the rim it would spill over (PondLayout); where no hollow holds any, the ray
## shows it refused and the trigger bumps.

const TINT := Color(0.7, 0.92, 1.0, 0.6)
const REFUSED := Color(0.72, 0.76, 0.86, 0.5)
## How far the pointed spot moves before the water it would hold is worked out again.
const FOLLOW := 0.05

var rig: Rig
var world: World
var _buttons: Array[Buttons] = []
## Per hand: the water shown, the ground point it is shown for and the pond it shows, and the point being worked
## out off the main thread, with its task and the box the task leaves its pond in.
var _ghosts: Array[MeshInstance3D] = []
var _at: Array[Vector3] = []
var _ponds: Array[PondLayout.Pond] = []
var _asked: Array[Vector3] = []
var _tasks: Array[int] = []
var _boxes: Array[Array] = []
var _ghost_material := StandardMaterial3D.new()


func _init(player: Rig, garden: World) -> void:
	rig = player
	world = garden
	_ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ghost_material.albedo_color = Color(TINT, 0.45)
	for h in rig.hands:
		_buttons.append(Buttons.new(h).watch(["tool"]))
		var ghost := MeshInstance3D.new()
		ghost.material_override = _ghost_material
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


func _process(_delta: float) -> void:
	for i in _buttons.size():
		_handle(i)
		_buttons[i].latch()


func _handle(i: int) -> void:
	var b := _buttons[i]
	var hand: Hand = b.hand
	if hand.tool != Hand.Tool.POND or rig.aim_hand == hand or not hand.get_has_tracking_data():
		_show(i, null)
		return
	var t := hand.global_transform
	var hit: Variant = Terrain.raycast(t.origin, -t.basis.z)
	_show(i, hit)
	hand.point(hit, TINT if _ponds[i] != null else REFUSED)
	if hit != null and b.pressed("tool"):
		fill(hand, hit)


## Shows the water filling to ground point `hit` would hold, or nothing; the flood is worked out on another thread,
## so a moving point shows what it held a frame or two before.
func _show(i: int, hit: Variant) -> void:
	if _tasks[i] >= 0 and WorkerThreadPool.is_task_completed(_tasks[i]):
		WorkerThreadPool.wait_for_task_completion(_tasks[i])
		_tasks[i] = -1
		_at[i] = _asked[i]
		_ponds[i] = _boxes[i][0]
		if _ponds[i] != null:
			_ghosts[i].mesh = PondWater.sheet(_ponds[i])
			_ghosts[i].position = Vector3(0, _ponds[i].level + 0.01, 0)
	if hit == null:
		_at[i] = Vector3.INF
		_ponds[i] = null
	elif _tasks[i] < 0 and _at[i].distance_to(hit) > FOLLOW:
		_asked[i] = hit
		var box := [null]
		_boxes[i] = box
		var from := Water.candidates(hit)
		var level: float = hit.y
		_tasks[i] = WorkerThreadPool.add_task(func() -> void: box[0] = Water.deepest(from, level))
	_ghosts[i].visible = _ponds[i] != null


## Lets in the water that filling to ground point `hit` would hold, as a build command: what the hand's preview
## shows when it is of that point. With none, the hand bumps.
func fill(hand: Hand, hit: Vector3) -> void:
	var i := rig.hands.find(hand)
	var shown := i >= 0 and _at[i].distance_to(hit) <= FOLLOW
	var at: Vector3 = _at[i] if shown else hit
	var p: PondLayout.Pond = _ponds[i] if shown else Water.pointed(hit)
	if p == null:
		Cues.play(Cues.Act.REFUSED, hand.global_position, hand)
		return
	Cues.play(Cues.Act.POND_POUR, at, hand)
	world.submit({"op": "ponds", "put": {p.at: at.y}}, Callable(), hand)
