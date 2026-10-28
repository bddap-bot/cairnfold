class_name Reach
extends RefCounted

## Far reach for one hand: where the hand is shown and grabs from, given where the controller is, calibrated to the
## player's own arm as they stretch it (see "Reaching far").

## GOGO throws the hand by how far the arm is stretched, THRUST by how far it has been thrust out and back, AIM not at
## all: the hand points instead.
enum Mode { GOGO, THRUST, AIM }
## Every hand's reach, cycled by the left stick clicked in while centred until a headset playtest keeps one.
static var mode := Mode.GOGO

## The share of the arm the hand follows one to one.
const FROM := 2.0 / 3.0
## How far past the controller the hand is thrown at full stretch, in metres.
const FAR := 24.0
## How far along its aim, before or after it, a reaching hand's grip takes what it touches.
const TOUCH := 0.3
## The arm, from the shoulder across the ground, as a share of the eyes' height, until a stretch measures it.
const ARM_PER_EYE := 0.36
## The shoulder below the eyes and out to the hand's side, as shares of the arm.
const SHOULDER_DOWN := 0.35
const SHOULDER_OUT := 0.3
## The share of itself the learned arm loses a second while unstretched, never below the first guess, so the next
## player is learned anew and a hand held out never creeps.
const FORGET := 0.005
const STEADY_HZ := 4.0
const STEADY_HZ_PER_M := 2.0
## Faster than this away from or toward the shoulder, in metres a second, the controller thrusts; slower, it moves the
## hand one to one, so an arm drawn back slowly after a thrust leaves the hand out.
const THRUST_SPEED := 0.8
## Metres a thrust throws the hand out, or brings it back, per metre the controller travels in it.
const THRUST_GAIN := 16.0

## The arm's length across the ground from the shoulder, as measured.
var arm := 0.0
## How far past the controller the hand stands now, steadied.
var out := 0.0
## +1 for a right hand, -1 for a left.
var side := 1.0
## How far past the controller thrusts have thrown the hand, unsteadied, and how far the controller last stood from the
## shoulder, negative before it has stood anywhere.
var thrust := 0.0
var _was := -1.0


func _init(right: bool) -> void:
	side = 1.0 if right else -1.0


## The hand's pose for the controller at `at`, the eyes at `eyes` (both over the floor at y = 0), `delta` seconds on.
func project(at: Transform3D, eyes: Transform3D, delta: float) -> Transform3D:
	var shoulder := self.shoulder(eyes)
	var across := Vector2(at.origin.x - shoulder.x, at.origin.z - shoulder.z).length()
	if stretch(across, arm) == 0.0:
		arm *= exp(-FORGET * delta)
	arm = maxf(maxf(arm, across), ARM_PER_EYE * eyes.origin.y)
	var want := FAR * pow(stretch(across, arm), 2.0)
	if mode == Mode.THRUST:
		var from := at.origin.distance_to(shoulder)
		if _was >= 0.0 and absf(from - _was) > THRUST_SPEED * delta:
			thrust = clampf(thrust + (from - _was) * THRUST_GAIN, 0.0, FAR)
		_was = from
		want = thrust
	out = lerpf(out, want, 1.0 - exp(-(STEADY_HZ + STEADY_HZ_PER_M * absf(want - out)) * delta))
	return Transform3D(at.basis, at.origin + (at.origin - shoulder).normalized() * out)


## How far into the last third of `arm` a controller `across` from the shoulder is, 0 to 1.
static func stretch(across: float, arm: float) -> float:
	return clampf((across - arm * FROM) / (arm * (1.0 - FROM)), 0.0, 1.0)


## The shoulder on this hand's side for the eyes at `eyes`, scaled by the arm measured so far.
func shoulder(eyes: Transform3D) -> Vector3:
	var right := eyes.basis.x
	right.y = 0.0
	right = right.normalized() if right.length() > 0.01 else Vector3.RIGHT
	var a := maxf(arm, ARM_PER_EYE * eyes.origin.y)
	return eyes.origin + Vector3.DOWN * a * SHOULDER_DOWN + right * side * a * SHOULDER_OUT


## The hand stopped `at` metres past the controller by something solid: neither a stretch nor a thrust carries it
## deeper unseen.
func stop(at: float) -> void:
	out = minf(out, at)
	thrust = minf(thrust, at)


## The hand stays at the controller, its projection dropped.
func rest() -> void:
	out = 0.0
	thrust = 0.0
	_was = -1.0
