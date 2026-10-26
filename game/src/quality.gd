class_name Quality
extends Node

## The game's one graphics configuration: a ladder of steps from full quality down, walked by the GPU time each
## frame takes, so every headset settles on the prettiest step it holds at its refresh rate. A knob is on it only with
## a saving measured on a headset (see "Automatic quality" in docs/design.md), and each moves at no frame cost.

## One rung of the ladder. Reaches are in metres; `blob_detail` is `Meshes.blob`'s subdivisions; settled stones beyond
## `stone_near_m` are drawn with a twelfth of their triangles (Stones.far_mesh), and ivy shrinks away by `ivy_m`.
## `shadows` is whether the sun casts them; `scale_3d` is the share of the swapchain's resolution the 3D scene is drawn
## at. The rest is how the view is drawn (DRAWN): `render_scale` is the share of each eye's width and height the
## runtime is asked for (render_target_size_multiplier), `msaa` the view's MSAA, `reflections` whether surfaces take
## reflected light from the sky, and `foveation` the runtime's fixed foveation level (XR_FB_foveation, 0 to 3).
## `share` is what the rung costs over the next one down, as a share of the frame, until the governor measures it.
class Step:
	var grass_m: float
	var flowers_m: float
	var blob_detail: int
	var stone_near_m: float
	var ivy_m: float
	var shadows: bool
	var scale_3d: float
	var render_scale: float
	var msaa: Viewport.MSAA
	var reflections: bool
	var foveation: int
	var share: float

	func _init(flora: Array, drawn: Dictionary) -> void:
		grass_m = flora[0]
		flowers_m = flora[1]
		blob_detail = flora[2]
		stone_near_m = flora[3]
		ivy_m = flora[4]
		shadows = flora[5] if flora.size() > 5 else true
		scale_3d = flora[6] if flora.size() > 6 else 1.0
		render_scale = drawn.render_scale
		msaa = drawn.msaa
		reflections = drawn.reflections
		foveation = drawn.foveation


## How the view is drawn, richest first, each rung dropping what loses least for what it saves, as measured on the
## Quest 2 at the ladder's bottom ("Which knobs matter" and "Anti-aliasing on the Quest 2" in docs/design.md): the sky's
## reflections on surfaces nearly all rough (0.7 to 1.9 ms), the rim's sharpness to fixed foveation (0.7 to 1.2 ms),
## 4x MSAA to 2x (1.5 to 2.7 ms), and last a smaller swapchain, which the compositor stretches to the display. MSAA stays on at every rung. `share` is each rung's cost over the next as a
## share of the frame from those measurements, the swapchain's its pixels' (the Quest 2's frame grew with them whole,
## 7.3 to 10.7 ms from 0.7 to 0.85 in a governed run of the stress scene). The last
## rung is where every headset starts.
const DRAWN := [
	{"render_scale": 1.0, "msaa": Viewport.MSAA_4X, "reflections": true, "foveation": 0, "share": 0.25},
	{"render_scale": 1.0, "msaa": Viewport.MSAA_4X, "reflections": false, "foveation": 0, "share": 0.17},
	{"render_scale": 1.0, "msaa": Viewport.MSAA_4X, "reflections": false, "foveation": 3, "share": 0.31},
	{"render_scale": 1.0, "msaa": Viewport.MSAA_2X, "reflections": false, "foveation": 3, "share": 0.38},
	{"render_scale": 0.85, "msaa": Viewport.MSAA_2X, "reflections": false, "foveation": 3, "share": 0.47},
	{"render_scale": 0.7, "msaa": Viewport.MSAA_2X, "reflections": false, "foveation": 3, "share": 0.0},
]
## What the ladder cuts below DRAWN's last rung, cheapest loss per millisecond saved first: grass, flowers and blob
## detail, stones in full and ivy (`Step`'s first five), then the sun's shadows and the 3D scale. Flowers beyond 60 m are
## under two pixels across on the Quest 2.
const FLORA := [
	[60.0, 60.0, 2, 16.0, 35.0],
	[48.0, 60.0, 2, 16.0, 35.0],
	[36.0, 60.0, 2, 16.0, 35.0],
	[30.0, 60.0, 2, 16.0, 35.0],
	[24.0, 60.0, 2, 16.0, 35.0],
	[24.0, 60.0, 2, 8.0, 25.0],
	[24.0, 20.0, 2, 8.0, 25.0],
	[24.0, 20.0, 1, 8.0, 25.0],
	[24.0, 20.0, 1, 4.0, 12.0],
	[24.0, 20.0, 1, 4.0, 12.0, false],
	[24.0, 20.0, 1, 4.0, 12.0, false, 0.78],
]
## The rung every headset starts on: the cheapest way of drawing the view with every reach whole. The governor climbs
## from it as the frame shows room and steps down the rest of the ladder below it.
const START := 5
static var ladder: Array[Step] = rungs()


## DRAWN's rungs with every reach whole, then FLORA's cuts drawn as DRAWN's last.
static func rungs() -> Array[Step]:
	var out: Array[Step] = []
	for d: Dictionary in DRAWN:
		out.append(Step.new(FLORA[0], d))
		out[-1].share = d.share
	for i in range(1, FLORA.size()):
		out.append(Step.new(FLORA[i], DRAWN[-1]))
	return out


## The render layers with a private use, one table so no two uses share a bit; everything else draws on layer 1.
## What the ladder cuts is drawn on LADDER_LAYER, which the headset's views see, and again whole on FULL_LAYER, which
## only a photo sees (PhotoTool): grass and flowers to the garden's edge, every stone whole, ivy at every distance.
## Shaders that shrink things with distance take the photo's camera by `full_layer` (full_detail).
const LADDER_LAYER := 1 << 16
const FULL_LAYER := 1 << 17
## The player's own avatar, which only the camera sees: their eyes would see it from inside.
const SELF_LAYER := 1 << 18
## Stones near are drawn whole on NEAR_LAYER, which only the eyes see, and coarser on SCREEN_LAYER, which only a
## camera's screen sees (PhotoTool, Masonry.Kind.screen): a few hundred pixels wide, the screen shows no difference.
const NEAR_LAYER := 1 << 19
const SCREEN_LAYER := 1 << 15
const VIEW_MASK := 0xFFFFF & ~FULL_LAYER & ~SCREEN_LAYER
const SCREEN_MASK := 0xFFFFF & ~FULL_LAYER & ~NEAR_LAYER
const PHOTO_MASK := 0xFFFFF & ~LADDER_LAYER & ~NEAR_LAYER & ~SCREEN_LAYER
## Grass, flower and ivy reach grow toward a step up at this many metres a second, so the edge comes out rather than
## jumps. A step down takes its reach at once: it was taken because frames ran over, and receding at this rate held a
## budget-full garden over budget for four seconds of a walk into it on the Quest 2.
const REACH_RATE := 8.0
## Seconds of rendered frames the governor sits out at the start: loading's first frames are not the scene's cost.
const WARMUP := 5.0
## Rendered frames drawn at each rung whose knobs switch pipelines (`primed`) as the session starts, among loading's
## late frames, so the pipelines they draw with are compiled then. A 3D scale other than the swapchain's compiles every
## pipeline afresh for its separate pass, and an MSAA level its own: on the Quest 2 that was a 110 to 180 ms frame the
## first time the governor reached the last step, mid-play.
const PRIME_FRAMES := 2

## The session's first walk down the primed rungs is over.
signal rungs_primed

var governor: Governor
var map := Map.new()
## The step held instead of the governor's, for measuring; -1 while governed.
var pin := -1:
	set(n):
		pin = clampi(n, -1, ladder.size() - 1)
var budget_ms := 0.0
## The viewport's GPU time for the last frame measured, in milliseconds, and whether this frame measured one.
var frame_ms := 0.0
var fresh := false
var _viewport_ms := 0.0
var _xr: OpenXRInterface
var _flora: Flora
var _masonry: Masonry
var _look: Look
var view: Viewport
## Whether the runtime foveates by a fixed level, which makes foveation one of the governor's knobs. Where the eyes are
## tracked the runtime's foveation follows the gaze instead (as Valve's does on the Steam Frame), which costs the player
## nothing to look at, so it stays on whole and is not the governor's.
var _foveates := false
var _warm := 0.0
## When the last frame began, in microseconds: the engine's delta is capped, which hides a stall from the governor.
var _tick := 0
var _primed := 0
var _priming := PackedInt32Array()
## The rung whose view knobs were last applied, or -1 to apply them again.
var _applied := -1
## Whether the knobs had reached their step last frame: a step still under way is not judged as one that failed.
var _settled := false


## With no headset nothing is measured, so the view is drawn at the ladder's top.
func _init(xr: OpenXRInterface, flora: Flora, masonry: Masonry = null, look: Look = null) -> void:
	_xr = xr
	_flora = flora
	_masonry = masonry
	_look = look
	_foveates = xr != null and xr.is_foveation_supported() and not xr.is_eye_gaze_interaction_supported()
	governor = Governor.new(ladder.size() - 1, popping(), START if xr != null else 0, shares(_foveates), idle(_foveates))
	if xr != null:
		_priming = primed()
		# The runtime drops a foveation level set before its session begins.
		xr.session_begun.connect(func() -> void: _applied = -1)


func _ready() -> void:
	view = get_viewport()
	_apply(ladder[step()], step())
	RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(), true)


## The levels a step up into would switch the sun's shadows, the 3D scale, the swapchain or MSAA back, which
## shows at once across the whole view or reallocates what it is drawn into: a governor crossing that line back and
## forth would flicker every shadow or the horizon, or drop a frame each time.
static func popping() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in ladder.size() - 1:
		var a := ladder[i]
		var b := ladder[i + 1]
		if a.shadows != b.shadows or a.scale_3d != b.scale_3d or a.render_scale != b.render_scale or a.msaa != b.msaa:
			out.append(i)
	return out


## The rungs drawn for PRIME_FRAMES each as the session starts: the top and every rung whose swapchain, MSAA,
## reflections, sun's shadows, 3D scale or foveation on or off differ from the one above, then START, where the
## governor takes over. Foveation on or off is another framebuffer to draw into, as `Map` also switches it.
static func primed() -> PackedInt32Array:
	var out := PackedInt32Array([0])
	for i in range(1, ladder.size()):
		var a := ladder[i - 1]
		var b := ladder[i]
		if a.render_scale != b.render_scale or a.msaa != b.msaa or a.reflections != b.reflections or a.shadows != b.shadows or a.scale_3d != b.scale_3d or (a.foveation > 0) != (b.foveation > 0):
			out.append(i)
	out.append(START)
	return out


## The levels that change nothing over the one above where the runtime has no fixed foveation (`foveates` false).
static func idle(foveates: bool) -> PackedInt32Array:
	var out := PackedInt32Array()
	if foveates:
		return out
	for i in range(1, ladder.size()):
		var a := ladder[i - 1]
		var b := ladder[i]
		if a.foveation != b.foveation and a.render_scale == b.render_scale and a.msaa == b.msaa and a.reflections == b.reflections:
			out.append(i)
	return out


## Each level's `share`, nothing for a rung no knob of this headset tells from the next.
static func shares(foveates: bool) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for step: Step in ladder:
		out.append(step.share)
	for i in idle(foveates):
		out[i - 1] = 0.0
	return out


static func full_detail(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter(&"full_layer", FULL_LAYER)


## A reach `now` moved toward `to` over `delta` seconds: out at REACH_RATE, in at once.
static func reach(now: float, to: float, delta: float) -> float:
	return to if to < now else move_toward(now, to, REACH_RATE * delta)


## Whether the session is still drawing its primed rungs.
func priming() -> bool:
	return _primed < _priming.size() * PRIME_FRAMES


## The step the knobs are heading to.
func step() -> int:
	return pin if pin >= 0 else governor.level


func _process(delta: float) -> void:
	var ms := RenderingServer.viewport_get_measured_render_time_gpu(view.get_viewport_rid())
	var now := Time.get_ticks_usec()
	var dt := (now - _tick) / 1000000.0 if _tick > 0 else delta
	_tick = now
	# The timer holds its last reading while the runtime skips rendering, as with the headset off the head.
	fresh = ms > 0.0 and ms != _viewport_ms
	_viewport_ms = ms
	# The viewport's timer leaves out the paint the canvases run on the GPU outside it.
	frame_ms = ms + Canvas.gpu_ms()
	if _xr != null and fresh:
		# The runtime may report the shell's rate for the first frames, so the budget follows it every frame.
		var hz := _xr.display_refresh_rate if _xr.display_refresh_rate > 0.0 else Budget.REFRESH_HZ
		budget_ms = 1000.0 / hz
		_warm += delta
		_primed += 1
		if _primed == _priming.size() * PRIME_FRAMES:
			rungs_primed.emit()
		if pin < 0 and _warm > WARMUP:
			var was := governor.level
			governor.step(frame_ms, budget_ms, dt, _settled)
			if governor.level != was:
				print("quality: step %d to %d, the GPU at %.1f ms of %.1f, %s" % [was, governor.level, frame_ms, budget_ms, governor.why])
	var n := _priming[_primed / PRIME_FRAMES] if priming() else step()
	var at := ladder[n]
	if _foveates and fresh and _warm > WARMUP and at.foveation > 0:
		var was_on := map.on
		map.step(frame_ms, budget_ms * Governor.LINE, delta)
		if map.on != was_on:
			print("quality: foveation map %s, the GPU at %.1f ms" % ["on" if map.on else "off", frame_ms])
			_applied = -1
	if n != _applied:
		_apply(at, n)
	_settled = _flora.approach(at, delta)
	if _look != null and _look.sun.shadow_enabled != at.shadows:
		_look.sun.shadow_enabled = at.shadows
	if not is_equal_approx(view.scaling_3d_scale, at.scale_3d):
		view.scaling_3d_scale = at.scale_3d
	if _masonry != null:
		_settled = Wall.approach(at, delta, _masonry) and _settled


## Sets how the view is drawn to `at`'s, level `n`, once as it is reached: a measurement that holds one of these knobs
## itself (Driver's `antialias`) keeps it while the step holds.
func _apply(at: Step, n: int) -> void:
	_applied = n
	view.msaa_3d = at.msaa
	if _look != null:
		_look.env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY if at.reflections else Environment.REFLECTION_SOURCE_DISABLED
	if _xr == null:
		return
	if not is_equal_approx(_xr.render_target_size_multiplier, at.render_scale):
		_xr.render_target_size_multiplier = at.render_scale
		print("quality: step %d swapchain %.2f msaa %dx foveation %d" % [n, at.render_scale, 2 << (at.msaa - 1), at.foveation])
	if _foveates:
		# The Mobile renderer reads the runtime's foveation map only with the view's VRS mode at XR.
		view.vrs_mode = Viewport.VRS_XR if at.foveation > 0 and map.on else Viewport.VRS_DISABLED
		_xr.foveation_level = at.foveation


## Whether a foveated rung draws with the runtime's density map, by what the map costs the scene as measured. On the
## Quest 2 the map can cost a scene five times its frame: with it, some views' tiles each run every vertex of the
## walls in view, 1.46 M a tile, against 15 k without it or in other views with it ("Fixed foveation on the Quest 2" in
## docs/design.md). Which views do is the driver's choice and is not known ahead, so while the frame runs over the line
## the map is taken off for a trial, and stays off only if that saved a share of the frame; it goes back on for a
## trial once the frame has been calm, and stays on only if that cost no more than the share.
class Map:
	## A trial reads the median of at least this many frames over at least this long, once its first frames have let
	## the timer catch up: at five frames a second, a time average of half a second was mostly the frames before the
	## switch. The frame's median runs over the line this long before the map is tried off.
	const TRIAL_FRAMES := 12
	const TRIAL_SECONDS := 0.5
	const SETTLE_FRAMES := 4
	## The map stays off only where the frame without it reads under this share of the frame with it.
	const SAVES := 0.8
	## Seconds the frame reads under the line before the map is tried again, doubling with each trial it fails.
	const CALM_SECONDS := 2.0
	const CALM_SECONDS_MAX := 64.0
	## Seconds after a trial of the map off that saved nothing before the next.
	const RETRY_SECONDS := 8.0

	var on := true
	var _recent := PackedFloat32Array()
	var _settle := 0
	var _trial := false
	var _trial_s := 0.0
	var _before := 0.0
	var _calm := 0.0
	var _over := 0.0
	var _wait := CALM_SECONDS
	var _since := INF

	## `line_ms` is the governor's line.
	func step(frame_ms: float, line_ms: float, dt: float) -> void:
		_since += dt
		if _settle > 0:
			_settle -= 1
			return
		_recent.append(frame_ms)
		if _trial:
			_trial_s += dt
			if _recent.size() >= TRIAL_FRAMES and _trial_s >= TRIAL_SECONDS:
				_settle_trial(_median())
			return
		if _recent.size() > TRIAL_FRAMES:
			_recent.remove_at(0)
		var now := _median()
		_calm = _calm + dt if now < line_ms else 0.0
		_over = _over + dt if now > line_ms else 0.0
		if on and _over >= TRIAL_SECONDS and _since > RETRY_SECONDS:
			_start(false)
		elif not on and _calm >= _wait:
			_start(true)

	func _median() -> float:
		var sorted := _recent.duplicate()
		sorted.sort()
		return sorted[sorted.size() / 2]

	func _start(to: bool) -> void:
		_before = _median()
		on = to
		_recent.clear()
		_trial = true
		_trial_s = 0.0
		_settle = SETTLE_FRAMES

	func _settle_trial(read: float) -> void:
		_trial = false
		_calm = 0.0
		_over = 0.0
		if not on and read >= _before * SAVES:
			on = true
			_since = 0.0
		elif on and read * SAVES > _before:
			on = false
			_wait = minf(_wait * 2.0, CALM_SECONDS_MAX)
		_recent.clear()


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
	## Frames ignored after any step while the GPU timer catches up with the change. Six, from when a step down's
	## reaches receded over seconds, left a walk into a budget-full garden on the Quest 2 missing refreshes between steps.
	const SETTLE_FRAMES := 3
	## Frames this far apart on average, as a share of the refresh period, are the runtime's every other refresh; one
	## frame this far from the last is a missed refresh.
	const HALVED := 1.5
	## Every other refresh counts only with the timer above this share of the budget: lower, the CPU held the frame.
	const HALVED_GPU := 0.6
	## A frame this far from the last, as a share of the refresh period, followed a pause (the headset off the head)
	## or a stall on the main thread (a build laid at once): the frames after it draw what it built, not the scene's
	## cost, so the governor starts its averages again rather than judge them. Judged, two such stalls in a Steam
	## Frame tour stepped it from 14 to the bottom and, the second right after a step up, held it there for the rest.
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
	## The frame time that took the last step down.
	var _took := INF
	## The level whose step up the average after the last step measures, or -1, and whether that step was up.
	var _measuring := -1
	var _went_up := false
	var _sticky := PackedInt32Array()
	var _shares := PackedFloat32Array()
	var _idle := PackedInt32Array()
	## The level the last step up left.
	var _up_from := 0
	## What took the last step, for the log.
	var why := ""

	## The governor starts at `start`. A step up across a level of `sticky` (ascending) waits the longest calm once a
	## step down has crossed it, and once undone is not taken again in the session: above the start it is crossed
	## at the calm of any other step until the scene first asks for less. `shares` are what each level costs over the
	## next down as a share of the frame, the floor under a step up not yet measured; a level of `idle` changes
	## nothing over the one above, so the governor passes it by.
	func _init(steps: int, sticky := PackedInt32Array(), start := 0, shares := PackedFloat32Array(), idle := PackedInt32Array()) -> void:
		bottom = steps
		level = start
		_wait.resize(steps + 1)
		_wait.fill(CALM_SECONDS)
		_cost.resize(steps + 1)
		_cost.fill(-1.0)
		_sticky = sticky
		_shares = shares
		_shares.resize(steps + 1)
		_idle = idle
		for i in sticky:
			if i >= start:
				_wait[i] = CALM_SECONDS_MAX

	## The level a step up from `at` reaches.
	func up(at: int) -> int:
		var to := at - 1
		while to > 0 and _idle.has(to):
			to -= 1
		return to

	## What the step up out of `at` is expected to cost, in milliseconds.
	func cost(at: int, budget_ms: float) -> float:
		if _cost[at] >= 0.0:
			return _cost[at]
		var share := 0.0
		for i in range(up(at), at):
			share += _shares[i]
		return maxf(budget_ms * UNMEASURED, _average * share)

	## The lowest level a step down may reach while the step under way has not shown what it saves: the next pop below.
	func _unpopped() -> int:
		for i in _sticky:
			if i >= level:
				while i > level and _idle.has(i):
					i -= 1
				return i
		return bottom

	## `settled` is whether the knobs have reached the step: only frames over the budget or at every other refresh
	## judge a step still under way.
	func step(frame_ms: float, budget_ms: float, dt: float, settled := true) -> void:
		var dt_ms := dt * 1000.0
		if dt_ms >= budget_ms * PAUSE:
			_restart()
			return
		_since_up += dt
		if _settle > 0:
			_settle -= 1
			return
		_average = frame_ms if _average == 0.0 else _average + (frame_ms - _average) * minf(dt / AVERAGE_SECONDS, 1.0)
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
		# The Quest 2 misses refreshes from about 0.84 of the period, short of HOT: walking into a budget-full garden
		# there dropped 36 frames while the average stepped down once a second. A missed refresh with the GPU over
		# the line steps down two at once, as a frame far over budget does; one the CPU held, the GPU under it, does not.
		var missed := dt_ms > budget_ms * HALVED and frame_ms > line
		# A refresh missed after a step down, before the average shows what it saved, at no lower a reading than the one
		# that took it, reads what the ladder does not draw: on the Steam Frame, after a village was laid at once, the
		# timer read 12.6 to 14.3 ms at every step from 5 to 16 while each miss took two more.
		missed = missed and (averaged or _went_up or frame_ms < _took)
		# A step still under way, or a step down whose second is not yet in, has not shown what it saves, so it may not be followed
		# into one that pops: on the Steam Frame two seconds of a village and the garden it replaced drawn at once took
		# the governor through the shadows and the 3D scale on single frames, and each pop crossed holds the longest calm.
		var floor := bottom if settled and (_went_up or _measuring < 0) else _unpopped()
		_calm = _calm + dt if settled and averaged and not halved and _average + cost(level, budget_ms) < line else 0.0
		if (_hot >= HOT_FRAMES or missed or halved or (settled and averaged and _average > line)) and level < floor:
			if _since_up < REGRET_SECONDS:
				for i in range(level, _up_from):
					_wait[i] = INF if _sticky.has(i) else minf(_wait[i] * 2.0, CALM_SECONDS_MAX)
			_since_up = INF
			# A step down before the last one's second was in leaves the average from before both.
			if averaged or _went_up or _measuring < 0:
				_before = _average
			var to := mini(level + (2 if missed or frame_ms > budget_ms * SEVERE else 1), floor)
			while _idle.has(to) and to < floor:
				to += 1
			for i in range(level, to):
				if _sticky.has(i):
					_wait[i] = maxf(_wait[i], CALM_SECONDS_MAX)
			_measuring = to
			_went_up = false
			_took = frame_ms
			why = "%s, %.1f ms since the last frame, averaging %.1f ms" % ["over budget" if _hot >= HOT_FRAMES else "missed" if missed else "every other refresh" if halved else "average over the line", dt_ms, _average]
			_move(to)
		elif level > 0 and _calm >= _climb_wait():
			_before = _average
			_measuring = level
			_went_up = true
			_up_from = level
			why = "calm for %.1f s, averaging %.1f ms" % [_calm, _average]
			_move(up(level))
			_since_up = 0.0

	## The calm a step up from here waits: the longest of the levels it crosses.
	func _climb_wait() -> float:
		var most := 0.0
		for i in range(up(level), level):
			most = maxf(most, _wait[i])
		return most

	func _move(to: int) -> void:
		level = to
		_calm = 0.0
		_quiet = 0.0
		_restart()

	func _restart() -> void:
		_hot = 0
		_average = 0.0
		_interval = 0.0
		_averaged = 0.0
		_settle = SETTLE_FRAMES
