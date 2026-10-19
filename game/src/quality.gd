class_name Quality
extends Node

## The game's one graphics configuration: a ladder of steps from full quality down, walked by the GPU time each
## frame takes, so every headset settles on the prettiest step it holds at its refresh rate. A knob is on it only with
## a saving measured on a headset (see "Automatic quality" in docs/design.md), and each moves at no frame cost.

## One rung of the ladder. Reaches are in metres; `blob_detail` is `Meshes.blob`'s subdivisions; settled stones beyond
## `stone_near_m` are drawn with a twelfth of their triangles (Stones.far_mesh), and ivy shrinks away by `ivy_m`.
## `shadows` is whether the sun casts them; `scale_3d` is the share of the headset's own 3D resolution drawn.
class Step:
	var grass_m: float
	var flowers_m: float
	var blob_detail: int
	var stone_near_m: float
	var ivy_m: float
	var shadows: bool
	var scale_3d: float

	func _init(grass: float, flowers: float, blobs: int, stones: float, ivy: float, sun := true, scale := 1.0) -> void:
		grass_m = grass
		flowers_m = flowers
		blob_detail = blobs
		stone_near_m = stones
		ivy_m = ivy
		shadows = sun
		scale_3d = scale


## Full quality first, then cheapest loss per millisecond saved. Flowers beyond 60 m are under two pixels across on
## the Quest 2.
static var ladder: Array[Step] = [
	Step.new(60.0, 60.0, 2, 16.0, 35.0),
	Step.new(48.0, 60.0, 2, 16.0, 35.0),
	Step.new(36.0, 60.0, 2, 16.0, 35.0),
	Step.new(30.0, 60.0, 2, 16.0, 35.0),
	Step.new(24.0, 60.0, 2, 16.0, 35.0),
	Step.new(24.0, 60.0, 2, 8.0, 25.0),
	Step.new(24.0, 20.0, 2, 8.0, 25.0),
	Step.new(24.0, 20.0, 1, 8.0, 25.0),
	Step.new(24.0, 20.0, 1, 4.0, 12.0),
	Step.new(24.0, 20.0, 1, 4.0, 12.0, false),
	Step.new(24.0, 20.0, 1, 4.0, 12.0, false, 0.78),
]
## The share of each eye's width and height the Steam Frame renders the 3D scene at, upscaled to it, above the ladder's
## last step. Changing it reallocates the scene's buffers, a 25 to 72 ms frame on the Frame, so only the last step,
## reached when every cheaper one has failed, changes it.
const FRAME_SCALE_3D := 0.9
## What a headset draws for the whole session: the share of each eye's width and height its runtime is asked for
## (render_target_size_multiplier), its MSAA, and where surfaces take reflected light from. The Quest 2's scene is bound
## by fragments: a smaller swapchain draws the same single pass, which the 3D scale does not on its driver, and the
## compositor stretches it to the display; 4x MSAA over 2x, and the sky's reflections on surfaces nearly all rough,
## cost its bare meadow 2.5 and 0.7 to 1.9 ms a frame at the ladder's bottom (see "Quest 2 measurements" in
## docs/design.md).
const QUEST_2 := {"render_scale": 0.7, "msaa": Viewport.MSAA_2X, "reflections": Environment.REFLECTION_SOURCE_DISABLED}
const HEADSET := {"render_scale": 1.0, "msaa": Viewport.MSAA_4X, "reflections": Environment.REFLECTION_SOURCE_SKY}
## What the ladder cuts is drawn on LADDER_LAYER, which the headset's views see, and again whole on FULL_LAYER, which
## only a photo sees (PhotoTool): grass and flowers to the garden's edge, every stone whole, ivy at every distance.
## Shaders that shrink things with distance take the photo's camera by `full_layer` (full_detail).
const LADDER_LAYER := 1 << 16
const FULL_LAYER := 1 << 17
const VIEW_MASK := 0xFFFFF & ~FULL_LAYER
const PHOTO_MASK := 0xFFFFF & ~LADDER_LAYER
## Grass and flower reach move toward their step at this many metres a second, so the edge recedes rather than jumps.
const REACH_RATE := 8.0
## Seconds of rendered frames the governor sits out at the start: loading's first frames are not the scene's cost.
const WARMUP := 5.0

var governor := Governor.new(ladder.size() - 1, popping())
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
var _masonry: Masonry
var _sun: DirectionalLight3D
var view: Viewport
## The headset's own 3D resolution, which each step's `scale_3d` is a share of.
var _scale := 1.0
var _warm := 0.0
## Whether the knobs had reached their step last frame: a step still under way is not judged as one that failed.
var _settled := false


func _init(xr: OpenXRInterface, flora: Flora, masonry: Masonry = null, sun: DirectionalLight3D = null) -> void:
	_xr = xr
	_flora = flora
	_masonry = masonry
	_sun = sun


func _ready() -> void:
	view = get_viewport()
	if _xr != null and OS.get_name() != "Android":
		_scale = FRAME_SCALE_3D
		view.scaling_3d_scale = _scale
		print("quality: 3D resolution %.2f" % _scale)
	RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(), true)


## What a headset of `model` (OS.get_model_name) draws for the session.
static func session(model: String) -> Dictionary:
	return QUEST_2 if model == "Quest 2" else HEADSET


## The levels a step up into would switch the sun's shadows or the 3D resolution back, which shows at once across the
## whole view: a governor crossing that line back and forth would flicker every shadow.
static func popping() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in ladder.size() - 1:
		if ladder[i].shadows != ladder[i + 1].shadows or ladder[i].scale_3d != ladder[i + 1].scale_3d:
			out.append(i)
	return out


static func full_detail(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter(&"full_layer", FULL_LAYER)


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
		if pin < 0 and _warm > WARMUP:
			governor.step(frame_ms, budget_ms, delta, _settled)
	var at := ladder[step()]
	_settled = _flora.approach(at, delta)
	if _sun != null and _sun.shadow_enabled != at.shadows:
		_sun.shadow_enabled = at.shadows
	var scale := _scale * at.scale_3d
	if not is_equal_approx(view.scaling_3d_scale, scale):
		view.scaling_3d_scale = scale
	if _masonry != null:
		_settled = Wall.approach(at, delta, _masonry) and _settled


## Walks the ladder on one signal, the GPU time of each frame against a line under the budget: down at once when
## frames run over the budget or their average over the line, up only after a calm spell when the step up is
## expected to stay under it, and slower each time a step up had to be undone. The runtime holding the game at every
## other refresh counts as over budget whatever the timer reads: there it reads high by the runtime's own work in
## between, and on the Steam Frame the runtime let a scene back to 72 Hz only once it read under about 11 ms, which
## the line alone never asked of it.
class Governor:
	## Consecutive frames this far over budget take a step down.
	const HOT := 1.05
	const HOT_FRAMES := 2
	## Frames this far over the budget take two steps instead.
	const SEVERE := 1.25
	## Frames ignored after any step while the GPU timer and the grass catch up with the change.
	const SETTLE_FRAMES := 6
	## Frames this far apart on average, as a share of the refresh period, are the runtime's every other refresh.
	const HALVED := 1.5
	## Every other refresh counts only with the timer above this share of the budget: lower, the CPU held the frame.
	const HALVED_GPU := 0.6
	const PAUSE := 4.0
	## The line, as a share of the budget: the Steam Frame's runtime drops the game to every other refresh once its
	## GPU time nears 0.88 of the period, and keeps it there for seconds. This timer reads about 0.3 ms under that
	## GPU time, so the houses of demo/headset.json sat under a line at 0.85 while the runtime halved the rate.
	## A calm spell is time spent with the frame time, averaged over
	## AVERAGE_SECONDS, under the line by what the step up out of this level costs: single frames vary by more than a
	## step saves, so they neither make nor break one.
	const LINE := 0.8
	const AVERAGE_SECONDS := 1.0
	const CALM_SECONDS := 2.0
	## The longest calm a step up waits for; as long under the line forgets what the step cost, which the scene may
	## have outgrown, and which reads high when the step left frames already at every other refresh.
	const CALM_SECONDS_MAX := 64.0
	## What a step up not yet measured in this scene is taken to cost, as a share of the budget: half the gap between
	## the line and the Steam Frame's cliff at 0.88. Taken as nothing, its full garden stepped up from 10.8 ms into a
	## step that crossed the cliff and held every other refresh for six seconds.
	const UNMEASURED := 0.04
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
	var _interval := 0.0
	var _since_up := INF
	## Calm seconds needed to step up into each level.
	var _wait := PackedFloat32Array()
	## What the step up out of each level costs, in milliseconds, or -1 while unmeasured: the difference between the
	## average before a step between it and the level above and the average over the AVERAGE_SECONDS after it settled.
	var _cost := PackedFloat32Array()
	## Seconds averaged since the last step settled; the average steps down only once a whole one is in.
	var _averaged := 0.0
	var _before := 0.0
	## The level whose step up the average after the last step measures, or -1, and whether that step was up.
	var _measuring := -1
	var _went_up := false
	var _sticky := PackedInt32Array()
	## The lowest level reached without a pop.
	var _unpopped: int

	## A step up into a level of `sticky` waits the longest calm, and once undone is not taken again in the session.
	func _init(steps: int, sticky := PackedInt32Array()) -> void:
		bottom = steps
		_wait.resize(steps + 1)
		_wait.fill(CALM_SECONDS)
		_cost.resize(steps + 1)
		_cost.fill(-1.0)
		_sticky = sticky
		_unpopped = steps
		for i in sticky:
			_wait[i] = CALM_SECONDS_MAX
			_unpopped = mini(_unpopped, i)

	## What the step up out of `at` is expected to cost, in milliseconds.
	func cost(at: int, budget_ms: float) -> float:
		return _cost[at] if _cost[at] >= 0.0 else budget_ms * UNMEASURED

	## `settled` is whether the knobs have reached the step: only frames over the budget or at every other refresh
	## judge a step still under way.
	func step(frame_ms: float, budget_ms: float, dt: float, settled := true) -> void:
		_since_up += dt
		if _settle > 0:
			_settle -= 1
			return
		_average = frame_ms if _average == 0.0 else _average + (frame_ms - _average) * minf(dt / AVERAGE_SECONDS, 1.0)
		# A longer gap is a pause, as with the headset off the head, not a rate the runtime holds.
		var dt_ms := dt * 1000.0
		if dt_ms < budget_ms * PAUSE:
			_interval = dt_ms if _interval == 0.0 else _interval + (dt_ms - _interval) * minf(dt / AVERAGE_SECONDS, 1.0)
		var averaged := _averaged >= AVERAGE_SECONDS
		if not averaged:
			_averaged += dt
			if _averaged >= AVERAGE_SECONDS and _measuring >= 0:
				# A step out of every other refresh reads no saving, so a measurement only raises what a step costs.
				var change := _average - _before if _went_up else _before - _average
				_cost[_measuring] = maxf(_cost[_measuring], change)
				_measuring = -1
		var line := budget_ms * LINE
		_hot = _hot + 1 if frame_ms > budget_ms * HOT else 0
		_quiet = _quiet + dt if _average < line else 0.0
		if _quiet >= CALM_SECONDS_MAX:
			_cost[level] = -1.0
		var halved := averaged and _interval > budget_ms * HALVED and _average > budget_ms * HALVED_GPU
		# A step still under way has not shown what it saves, so it may not be followed into one that pops.
		var floor := bottom if settled else mini(_unpopped, bottom)
		_calm = _calm + dt if settled and averaged and not halved and _average + cost(level, budget_ms) < line else 0.0
		if (_hot >= HOT_FRAMES or halved or (settled and averaged and _average > line)) and level < floor:
			if _since_up < REGRET_SECONDS:
				_wait[level] = INF if _sticky.has(level) else minf(_wait[level] * 2.0, CALM_SECONDS_MAX)
			_since_up = INF
			# A step down before the last one's second was in leaves the average from before both.
			if averaged or _went_up or _measuring < 0:
				_before = _average
			var to := mini(level + (2 if frame_ms > budget_ms * SEVERE else 1), floor)
			_measuring = to
			_went_up = false
			_move(to)
		elif level > 0 and _calm >= _wait[level - 1]:
			_before = _average
			_measuring = level
			_went_up = true
			_move(level - 1)
			_since_up = 0.0

	func _move(to: int) -> void:
		level = to
		_hot = 0
		_calm = 0.0
		_quiet = 0.0
		_average = 0.0
		_interval = 0.0
		_averaged = 0.0
		_settle = SETTLE_FRAMES
