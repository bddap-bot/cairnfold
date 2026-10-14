class_name Quality
extends Node

## The game's one graphics configuration: a ladder of steps from full quality down, walked by the GPU time each
## frame takes, so every headset settles on the prettiest step it holds at its refresh rate. A knob is on it only with
## a saving measured on the Quest 2 (see "Automatic quality" in docs/design.md), and each moves at no frame cost.

## One rung of the ladder. Reaches are in metres; `blob_detail` is `Meshes.blob`'s subdivisions.
class Step:
	var grass_m: float
	var flowers_m: float
	var blob_detail: int

	func _init(grass: float, flowers: float, blobs: int) -> void:
		grass_m = grass
		flowers_m = flowers
		blob_detail = blobs


## Full quality first, then cheapest loss per millisecond saved. Flowers beyond 60 m are under two pixels across on
## the Quest 2.
static var ladder: Array[Step] = [
	Step.new(24.0, 60.0, 2),
	Step.new(20.0, 60.0, 2),
	Step.new(16.0, 60.0, 2),
	Step.new(13.0, 60.0, 2),
	Step.new(10.0, 60.0, 2),
	Step.new(10.0, 20.0, 2),
	Step.new(10.0, 20.0, 1),
]
## Grass and flower reach move toward their step at this many metres a second, so the edge recedes rather than jumps.
const REACH_RATE := 8.0
## Seconds of rendered frames the governor sits out at the start: loading's first frames are not the scene's cost.
const WARMUP := 5.0

var governor := Governor.new(ladder.size() - 1)
## The step held instead of the governor's, for measuring; -1 while governed.
var pin := -1:
	set(n):
		pin = clampi(n, -1, ladder.size() - 1)
var budget_ms := 0.0
## The viewport's GPU time for the last frame measured, in milliseconds, and whether this frame measured one.
var frame_ms := 0.0
var fresh := false
var _xr: OpenXRInterface
var _flora: Flora
var _vp: RID
var _warm := 0.0
## Whether the knobs had reached their step last frame: a step still under way is not judged as one that failed.
var _settled := false


func _init(xr: OpenXRInterface, flora: Flora) -> void:
	_xr = xr
	_flora = flora


func _ready() -> void:
	_vp = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)


## The step the knobs are heading to.
func step() -> int:
	return pin if pin >= 0 else governor.level


func _process(delta: float) -> void:
	var ms := RenderingServer.viewport_get_measured_render_time_gpu(_vp)
	# The timer holds its last reading while the runtime skips rendering, as with the headset off the head.
	fresh = ms > 0.0 and ms != frame_ms
	frame_ms = ms
	if _xr != null and fresh:
		# The runtime may report the shell's rate for the first frames, so the budget follows it every frame. The
		# viewport's timer reads about 1 ms above the Quest runtime's own GPU time, and frames hold the refresh rate
		# until it reaches the whole period, so the period is its line.
		var hz := _xr.display_refresh_rate if _xr.display_refresh_rate > 0.0 else Budget.REFRESH_HZ
		budget_ms = 1000.0 / hz
		_warm += delta
		if pin < 0 and _warm > WARMUP and _settled:
			governor.step(frame_ms, budget_ms, delta)
	_settled = _flora.approach(ladder[step()], delta)


## Walks the ladder on one signal, the GPU time of each frame against the budget: down at once when frames
## run over it, up only after a calm spell, and slower each time a step up had to be undone.
class Governor:
	## Consecutive frames this far over budget take a step down.
	const HOT := 1.05
	const HOT_FRAMES := 2
	## Frames this far over the budget take two steps instead.
	const SEVERE := 1.25
	## Frames ignored after any step while the GPU timer and the grass catch up with the change.
	const SETTLE_FRAMES := 6
	## A calm spell is time spent with the frame time, averaged over AVERAGE_SECONDS, under this share of the budget:
	## single frames vary by more than a step saves, so they neither make nor break one.
	const CALM := 0.96
	const AVERAGE_SECONDS := 1.0
	const CALM_SECONDS := 2.0
	const CALM_SECONDS_MAX := 64.0
	## A step down this soon after the step up that reached it doubles the calm needed to step up again; the
	## doubling lasts the session.
	const REGRET_SECONDS := 10.0

	## 0 is full quality; each step down the ladder adds one.
	var level := 0
	var bottom: int
	var _hot := 0
	var _settle := 0
	var _calm := 0.0
	var _average := 0.0
	var _since_up := INF
	## Calm seconds needed to step up into each level.
	var _wait := PackedFloat32Array()

	func _init(steps: int) -> void:
		bottom = steps
		_wait.resize(steps + 1)
		_wait.fill(CALM_SECONDS)

	func step(frame_ms: float, budget_ms: float, dt: float) -> void:
		_since_up += dt
		_average = frame_ms if _average == 0.0 else _average + (frame_ms - _average) * minf(dt / AVERAGE_SECONDS, 1.0)
		if _settle > 0:
			_settle -= 1
			return
		_hot = _hot + 1 if frame_ms > budget_ms * HOT else 0
		_calm = _calm + dt if _average < budget_ms * CALM else 0.0
		if _hot >= HOT_FRAMES and level < bottom:
			if _since_up < REGRET_SECONDS:
				_wait[level] = minf(_wait[level] * 2.0, CALM_SECONDS_MAX)
			_since_up = INF
			_move(mini(level + (2 if frame_ms > budget_ms * SEVERE else 1), bottom))
		elif level > 0 and _calm >= _wait[level - 1]:
			_move(level - 1)
			_since_up = 0.0

	func _move(to: int) -> void:
		level = to
		_hot = 0
		_calm = 0.0
		_settle = SETTLE_FRAMES
