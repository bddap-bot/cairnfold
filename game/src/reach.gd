class_name Reach
extends RefCounted

## Go-Go reach for one hand: where the hand is shown and grabs from, given where the controller is, calibrated to the
## player's own arm as they stretch it (see "Reaching far").

enum Mode { GOGO, AIM }
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

## The arm's length across the ground from the shoulder, as measured.
var arm := 0.0
## How far past the controller the hand stands now, steadied.
var out := 0.0
## +1 for a right hand, -1 for a left.
var side := 1.0


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


## The hand stays at the controller, its projection dropped.
func rest() -> void:
	out = 0.0
