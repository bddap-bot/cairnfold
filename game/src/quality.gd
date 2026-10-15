class_name Quality
extends Node

## The game's one graphics configuration: a ladder of steps from full quality down, walked by the GPU time each
## frame takes, so every headset settles on the prettiest step it holds at its refresh rate. A knob is on it only with
## a saving measured on a headset (see "Automatic quality" in docs/design.md), and each moves at no frame cost.

## One rung of the ladder. Reaches are in metres; `blob_detail` is `Meshes.blob`'s subdivisions; `scaling_3d` is the
## share of the render target's width and height the 3D scene renders at, upscaled to it.
class Step:
	var grass_m: float
	var flowers_m: float
	var blob_detail: int
	var scaling_3d: float

	func _init(grass: float, flowers: float, blobs: int, scale: float) -> void:
		grass_m = grass
		flowers_m = flowers
		blob_detail = blobs
		scaling_3d = scale


## Full quality first, then cheapest loss per millisecond saved. A tenth off the 3D resolution saves more among
## buildings on the Steam Frame than every reach step together. Flowers beyond 60 m are under two pixels across on
## the Quest 2.
static var ladder: Array[Step] = [
	Step.new(24.0, 60.0, 2, 1.0),
	Step.new(24.0, 60.0, 2, 0.9),
	Step.new(20.0, 60.0, 2, 0.9),
	Step.new(16.0, 60.0, 2, 0.9),
	Step.new(13.0, 60.0, 2, 0.9),
	Step.new(10.0, 60.0, 2, 0.9),
	Step.new(10.0, 20.0, 2, 0.9),
	Step.new(10.0, 20.0, 1, 0.9),
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
var view: Viewport
var _warm := 0.0
## Whether the knobs had reached their step last frame: a step still under way is not judged as one that failed.
var _settled := false


func _init(xr: OpenXRInterface, flora: Flora) -> void:
	_xr = xr
	_flora = flora


func _ready() -> void:
	view = get_viewport()
	RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(), true)


## The step the knobs are heading to.
func step() -> int:
	return pin if pin >= 0 else governor.level


func _process(delta: float) -> void:
	var ms := RenderingServer.viewport_get_measured_render_time_gpu(view.get_viewport_rid())
	# The timer holds its last reading while the runtime skips rendering, as with the headset off the head.
	fresh = ms > 0.0 and ms != frame_ms
	frame_ms = ms
	if _xr != null and fresh:
		# The runtime may report the shell's rate for the first frames, so the budget follows it every frame.
		var hz := _xr.display_refresh_rate if _xr.display_refresh_rate > 0.0 else Budget.REFRESH_HZ
		budget_ms = 1000.0 / hz
		_warm += delta
		if pin < 0 and _warm > WARMUP and _settled:
			governor.step(frame_ms, budget_ms, delta)
	var at := ladder[step()]
	# The first frame at a lower 3D resolution takes 30 to 70 ms on the Frame and later switches cost nothing, so the
	# warm-up, whose frames are not the scene's cost, renders at the lowest first.
	var scale := ladder[-1].scaling_3d if _xr != null and _warm < WARMUP * 0.5 else at.scaling_3d
	if not is_equal_approx(view.scaling_3d_scale, scale):
		view.scaling_3d_scale = scale
		print("quality: 3D resolution %.2f" % scale)
	_settled = _flora.approach(at, delta)


## Walks the ladder on one signal, the GPU time of each frame against a line under the budget: down at once when
## frames run over the budget or their average over the line, up only after a calm spell when the step up is
## expected to stay under it, and slower each time a step up had to be undone.
class Governor:
	## Consecutive frames this far over budget take a step down.
	const HOT := 1.05
	const HOT_FRAMES := 2
	## Frames this far over the budget take two steps instead.
	const SEVERE := 1.25
	## Frames ignored after any step while the GPU timer and the grass catch up with the change.
	const SETTLE_FRAMES := 6
	## The line, as a share of the budget: the Steam Frame's runtime drops the game to every other refresh once its
	## GPU time nears 0.88 of the period, and keeps it there for seconds. This timer reads about 0.3 ms under that
	## GPU time, so the houses of demo/headset.json sat under a line at 0.85 while the runtime halved the rate.
	## A calm spell is time spent with the frame time, averaged over
	## AVERAGE_SECONDS, under the line by what the step down into this level saved: single frames vary by more than a
	## step saves, so they neither make nor break one.
	const LINE := 0.8
	const AVERAGE_SECONDS := 1.0
	const CALM_SECONDS := 2.0
	## The longest calm a step up waits for; as long under the line forgets what the step down saved, which the scene
	## may have outgrown, and which reads high when the step left frames already at every other refresh.
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
	var _quiet := 0.0
	var _average := 0.0
	var _since_up := INF
	## Calm seconds needed to step up into each level.
	var _wait := PackedFloat32Array()
	## What the step down into each level saved, in milliseconds: the average before it less the average over the
	## AVERAGE_SECONDS after it settled.
	var _saved := PackedFloat32Array()
	## Seconds averaged since the last step settled; the average steps down only once a whole one is in.
	var _averaged := 0.0
	var _before_down := 0.0
	var _went_down := false

	func _init(steps: int) -> void:
		bottom = steps
		_wait.resize(steps + 1)
		_wait.fill(CALM_SECONDS)
		_saved.resize(steps + 1)

	func step(frame_ms: float, budget_ms: float, dt: float) -> void:
		_since_up += dt
		if _settle > 0:
			_settle -= 1
			return
		_average = frame_ms if _average == 0.0 else _average + (frame_ms - _average) * minf(dt / AVERAGE_SECONDS, 1.0)
		var averaged := _averaged >= AVERAGE_SECONDS
		if not averaged:
			_averaged += dt
			if _averaged >= AVERAGE_SECONDS and _went_down:
				_saved[level] = maxf(_before_down - _average, 0.0)
		var line := budget_ms * LINE
		_hot = _hot + 1 if frame_ms > budget_ms * HOT else 0
		_quiet = _quiet + dt if _average < line else 0.0
		if _quiet >= CALM_SECONDS_MAX:
			_saved[level] = 0.0
		_calm = _calm + dt if averaged and _average + _saved[level] < line else 0.0
		if (_hot >= HOT_FRAMES or (averaged and _average > line)) and level < bottom:
			if _since_up < REGRET_SECONDS:
				_wait[level] = minf(_wait[level] * 2.0, CALM_SECONDS_MAX)
			_since_up = INF
			# A step down before the last one's second was in leaves the average from before both.
			if averaged or not _went_down:
				_before_down = _average
			_went_down = true
			_move(mini(level + (2 if frame_ms > budget_ms * SEVERE else 1), bottom))
		elif level > 0 and _calm >= _wait[level - 1]:
			_went_down = false
			_move(level - 1)
			_since_up = 0.0

	func _move(to: int) -> void:
		level = to
		_hot = 0
		_calm = 0.0
		_quiet = 0.0
		_average = 0.0
		_averaged = 0.0
		_settle = SETTLE_FRAMES
