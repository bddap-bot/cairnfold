class_name FeedTool
extends Node3D

## For a hand holding the seed dish: the trigger throws a handful of seeds the way the hand is swinging, or lets it
## fall from a still hand, to lie where it lands until it is eaten or sinks away.

## Per second: how quickly the throw follows the hand, so tracking jitter does not fling the seeds.
const EASE := 20.0
## Handfuls lying about at once; another throw takes up the oldest.
const HANDFULS := 8

var rig: Rig
var handfuls: Array[Handful] = []
var rng := RandomNumberGenerator.new()
var _floor: Callable
var _buttons: Array[Buttons] = []
## Per hand: where the dish was last frame and how fast it has been swinging, in the rig's space, so a teleport or a
## snap turn throws nothing.
var _was := {}
var _velocity := {}
var _next := 0


func _init(player: Rig, ponds: Water, builds: WallTool) -> void:
	rig = player
	_floor = func(p: Vector3) -> float: return maxf(ponds.floor_at(p), builds.floor_under(p)) if builds != null else ponds.floor_at(p)
	for h in rig.hands:
		_buttons.append(Buttons.new(h).watch(["trigger_click"]))
	for i in HANDFULS:
		handfuls.append(Handful.new(_floor))
		add_child(handfuls[i])


func _process(delta: float) -> void:
	for i in rig.hands.size():
		var h: Hand = rig.hands[i]
		var at := rig.global_transform.affine_inverse() * dish(h)
		if delta > 0.0:
			var moved: Vector3 = (at - _was.get(h, at)) / delta
			_velocity[h] = _velocity.get(h, Vector3.ZERO).lerp(moved, 1.0 - exp(-delta * EASE))
		_was[h] = at
		if _buttons[i].pressed("trigger_click") and h.tool == Hand.Tool.SEEDS and h.tracked() and rig.aim_hand != h and not h.picking:
			Hand.bump(h)
			toss(dish(h), rig.global_basis * _velocity.get(h, Vector3.ZERO))
		_buttons[i].latch()
	tick(delta)


func dish(h: Hand) -> Vector3:
	return h.body.global_transform * Hand.TOP


func toss(from: Vector3, velocity: Vector3) -> Handful:
	var handful := handfuls[_next]
	_next = (_next + 1) % HANDFULS
	handful.toss(from, velocity, rng)
	return handful


func tick(delta: float) -> void:
	for handful in handfuls:
		handful.tick(delta)
