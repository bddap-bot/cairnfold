class_name FeedTool
extends Node3D

## For a hand holding the seed dish: the trigger throws a handful of seeds the way the hand is moving, or lets it
## fall from a still hand, to lie where it lands until it is eaten or sinks away.

## Per second: how quickly the throw follows the hand, so tracking jitter does not fling the seeds.
const EASE := 20.0
## Handfuls lying about at once; another throw takes the oldest away.
const SCATTERS := 8

var rig: Rig
var water: Water
var scatters: Array[Scatter] = []
var rng := RandomNumberGenerator.new()
var _buttons: Array[Buttons] = []
var _was := {}
var _velocity := {}
## Seeds gone, kept a moment so whatever was eating them lets go before they are freed.
var _spent := {}


func _init(player: Rig, ponds: Water) -> void:
	rig = player
	water = ponds
	for h in rig.hands:
		_buttons.append(Buttons.new(h).watch(["trigger_click"]))


func _process(delta: float) -> void:
	for i in rig.hands.size():
		var h: Hand = rig.hands[i]
		var at := dish(h)
		if delta > 0.0:
			var moved: Vector3 = (at - _was.get(h, at)) / delta
			_velocity[h] = _velocity.get(h, Vector3.ZERO).lerp(moved, 1.0 - exp(-delta * EASE))
		_was[h] = at
		if _buttons[i].pressed("trigger_click") and h.tool == Hand.Tool.SEEDS and rig.aim_hand != h and not h.picking:
			Hand.bump(h)
			toss(dish(h), _velocity.get(h, Vector3.ZERO))
		_buttons[i].latch()
	tick(delta)


func dish(h: Hand) -> Vector3:
	return h.body.global_transform * Hand.TOP


func toss(from: Vector3, velocity: Vector3) -> Scatter:
	if scatters.size() >= SCATTERS:
		_spend(scatters[0])
	var s := Scatter.new(from, velocity, water.floor_at, rng.randi())
	add_child(s)
	scatters.append(s)
	return s


func tick(delta: float) -> void:
	for i in range(scatters.size() - 1, -1, -1):
		scatters[i].tick(delta)
		if scatters[i].gone():
			_spend(scatters[i])
	for s: Scatter in _spent.keys():
		_spent[s] -= delta
		if _spent[s] <= 0.0:
			_spent.erase(s)
			s.queue_free()


func _spend(s: Scatter) -> void:
	scatters.erase(s)
	s.visible = false
	_spent[s] = 1.0
