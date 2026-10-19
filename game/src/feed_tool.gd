class_name FeedTool
extends Node3D

## For a hand holding the seed dish: the trigger throws a handful of seeds the way the hand is swinging, or lets it
## fall from a still hand, to lie where it lands until it is eaten or sinks away. Seeds landing on a pond plop and ripple it.

## Per second: how quickly the throw follows the hand, so tracking jitter does not fling the seeds.
const EASE := 20.0
## Handfuls lying about at once; another throw takes up the oldest.
const HANDFULS := 8

## This player threw a handful: `Session` sends it to the others.
signal threw(from: Vector3, velocity: Vector3, seed: int)

var rig: Rig
var ponds: Water
var handfuls: Array[Handful] = []
var rng := RandomNumberGenerator.new()
var _buttons: Array[Buttons] = []
## Per hand: where the dish was last frame and how fast it has been swinging, in the rig's space, so a teleport or a
## snap turn throws nothing.
var _was := {}
var _velocity := {}
var _next := 0


func _init(player: Rig, water: Water) -> void:
	rig = player
	ponds = water
	for h in rig.hands:
		_buttons.append(Buttons.new(h).watch(["tool"]))
	for i in HANDFULS:
		handfuls.append(Handful.new(ponds.floor_at))
		handfuls[i].settled.connect(_settled)
		add_child(handfuls[i])


func _process(delta: float) -> void:
	tick(delta)
	for i in rig.hands.size():
		var h: Hand = rig.hands[i]
		var at := rig.global_transform.affine_inverse() * dish(h)
		if delta > 0.0:
			var moved: Vector3 = (at - _was.get(h, at)) / delta
			_velocity[h] = _velocity.get(h, Vector3.ZERO).lerp(moved, 1.0 - exp(-delta * EASE))
		_was[h] = at
		if _buttons[i].pressed("tool") and h.tool == Hand.Tool.SEEDS and h.tracked() and rig.aim_hand != h and not h.picking:
			Hand.bump(h)
			throw(dish(h), rig.global_basis * _velocity.get(h, Vector3.ZERO))
		_buttons[i].latch()


func dish(h: Hand) -> Vector3:
	return h.body.global_transform * Hand.TOP


## This player's throw, shared with the others.
func throw(from: Vector3, velocity: Vector3) -> Handful:
	var seed := rng.randi()
	threw.emit(from, velocity, seed)
	return toss(from, velocity, seed)


func toss(from: Vector3, velocity: Vector3, seed: int) -> Handful:
	var handful := handfuls[_next]
	_next = (_next + 1) % HANDFULS
	handful.toss(from, velocity, seed)
	return handful


func _settled(handful: Handful) -> void:
	var pond := ponds.pond_at(handful.position.x, handful.position.z)
	if pond != null:
		pond.ripple(handful.position, 0.4)
		ponds.splashed.emit(&"plop", handful.position)


func tick(delta: float) -> void:
	for handful in handfuls:
		handful.tick(delta)
