class_name StairTool
extends Node3D

## How wide stairs are drawn; a grip widens or narrows them after.
const WIDTH := 1.2

var rig: Rig
var walls: WallTool
var world: World
var _buttons: Array[Buttons] = []
var _strokes := {}

func _init(player: Rig, builder: WallTool, garden: World) -> void:
	rig = player
	walls = builder
	world = garden
	for h in rig.hands:
		_buttons.append(Buttons.new(h).watch(["tool"]))
	world.restored.connect(func():
		for hand in _strokes.keys():
			_cancel(hand))

func busy(hand: Hand = null) -> bool:
	return not _strokes.is_empty() if hand == null else _strokes.has(hand)

func begin(hand: Hand, at: Vector3, width := WIDTH) -> void:
	_cancel(hand)
	var ghost := Stones.new()
	add_child(ghost)
	_strokes[hand] = {"data": {"a": at, "b": at, "width": clampf(width, StairLayout.WIDTH.x, StairLayout.WIDTH.y), "sag": 0.0, "rail": world.stairs.rail, "seed": randi(), "paint": walls.paint.duplicate()}, "ghost": ghost}

func extend(hand: Hand, at: Vector3) -> void:
	if not _strokes.has(hand):
		return
	var s: Dictionary = _strokes[hand]
	var d: Vector3 = at - s.data.a
	s.data.b = s.data.a + d.limit_length(Commands.STROKE_LENGTH)
	s.data.sag = walls.stair_sag(s.data)
	s.data.rail = world.stairs.rail
	var layout := StairLayout.new()
	layout.build(s.data)
	if layout.treads.size() != s.get("steps", 1):
		s.steps = layout.treads.size()
		Cues.play(Cues.Act.STAIRS_LAY, s.data.b, hand)
	s.ghost.lay(layout.stones)
	world.preview(hand, world.change_of({"op": "stairs", "stairs": s.data}))

func end(hand: Hand) -> void:
	if not _strokes.has(hand):
		return
	var s: Dictionary = _strokes[hand]
	_strokes.erase(hand)
	if s.data.a.distance_to(s.data.b) < 0.3:
		s.ghost.queue_free()
		return
	s.data.on = walls.stair_supports(s.data)
	if world.fits({"op": "stairs", "stairs": s.data}):
		Cues.play(Cues.Act.STAIRS_SET, s.data.b, hand)
	world.submit({"op": "stairs", "stairs": s.data}, func(): s.ghost.queue_free(), hand)

func _cancel(hand: Hand) -> void:
	if _strokes.has(hand):
		_strokes[hand].ghost.queue_free()
		_strokes.erase(hand)

func _process(_delta: float) -> void:
	for buttons in _buttons:
		var hand := buttons.hand as Hand
		if hand.tool != Hand.Tool.STAIRS or rig.aim_hand == hand:
			_cancel(hand)
		elif hand.tracked():
			var t := hand.global_transform
			var hit := aim(t.origin, -t.basis.z)
			hand.point(hit.get("point"), WallTool.TINT)
			if buttons.pressed("tool") and not hit.is_empty():
				begin(hand, hit.point)
			if buttons.held("tool") and not hit.is_empty():
				extend(hand, hit.point)
			if buttons.released("tool"):
				end(hand)
		buttons.latch()


func aim(origin: Vector3, direction: Vector3) -> Dictionary:
	var hit := walls.aim(origin, direction)
	var stairs := world.stairs.pick(origin, direction, hit.get("along", INF))
	return stairs if not stairs.is_empty() else hit
