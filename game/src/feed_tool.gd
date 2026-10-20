class_name FeedTool
extends Node3D

## For a hand holding the seed dish: the trigger tosses a handful of seeds a little way along the hand's aim, farther
## the way the hand is swinging, to lie where it lands until it is eaten or sinks away. Seeds landing on a pond plop and
## ripple it, then rise through it to float.

## Per second: how quickly the throw follows the hand, so tracking jitter does not fling the seeds.
const EASE := 20.0
## Metres a second a handful leaves along the hand's aim on top of the hand's swing: from a still hand it lands about a
## metre off, near enough to feed what stands by.
const LAUNCH := 2.0
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
		handfuls.append(Handful.new(ponds))
		handfuls[i].splashed.connect(_splashed)
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
		if _buttons[i].pressed("tool") and h.holds_seeds() and rig.aim_hand != h:
			Cues.play(Cues.Act.SEEDS_THROW, dish(h), h)
			throw(dish(h), launch(h, rig.global_basis * _velocity.get(h, Vector3.ZERO)))
		_buttons[i].latch()


func dish(h: Hand) -> Vector3:
	return h.body.global_transform * Hand.TOP


## How fast a handful leaves the dish in `h` swinging at `swing`.
func launch(h: Hand, swing: Vector3) -> Vector3:
	return -h.global_basis.z * LAUNCH + swing


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


func _splashed(pond: PondWater, at: Vector3) -> void:
	pond.ripple(at, 0.4)
	Cues.play(Cues.Act.PLOP, at)


func tick(delta: float) -> void:
	for handful in handfuls:
		handful.tick(delta)
