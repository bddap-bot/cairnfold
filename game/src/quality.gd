class_name Quality
extends Node

## A knob is on the ladder only with a saving measured on a headset (docs/design.md "Automatic quality").

## `scale_3d` is a share of the swapchain's resolution; `share`: the rung's cost over the next one down, as a share of
## the frame, until measured. `files`: other people drawn in their own avatar files rather than a built-in body.
class Step:
	var grass_m: float
	var flowers_m: float
	var blob_detail: int
	var stone_near_m: float
	var ivy_m: float
	var shadows: bool
	var scale_3d: float
	var files: bool
	var outlines: bool
	var toon: bool
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
		files = flora[7] if flora.size() > 7 else true
		outlines = flora[8] if flora.size() > 8 else true
		toon = flora[9] if flora.size() > 9 else true
		render_scale = drawn.render_scale
		msaa = drawn.msaa
		reflections = drawn.reflections
		foveation = drawn.foveation
		share = drawn.share


## Least loss per saving first, measured on the Quest 2 (docs/design.md "Which knobs matter"): reflections 0.7 to
## 1.9 ms, fixed foveation 0.7 to 1.2 ms, 4x to 2x MSAA 1.5 to 2.7 ms; the swapchain's share is its pixels'.
const DRAWN := [
	{"render_scale": 1.0, "msaa": Viewport.MSAA_4X, "reflections": true, "foveation": 0, "share": 0.25},
	{"render_scale": 1.0, "msaa": Viewport.MSAA_4X, "reflections": false, "foveation": 0, "share": 0.17},
	{"render_scale": 1.0, "msaa": Viewport.MSAA_4X, "reflections": false, "foveation": 3, "share": 0.31},
	{"render_scale": 1.0, "msaa": Viewport.MSAA_2X, "reflections": false, "foveation": 3, "share": 0.38},
	{"render_scale": 0.85, "msaa": Viewport.MSAA_2X, "reflections": false, "foveation": 3, "share": 0.47},
	{"render_scale": 0.7, "msaa": Viewport.MSAA_2X, "reflections": false, "foveation": 3, "share": 0.0},
]
## Cuts below DRAWN's last rung, columns in `Step`'s field order, least loss per saving first: toon shading (1.65 to
## 4.28 ms an avatar on the Quest 2) before outlines (0.6 to 0.8 ms). Flowers past 60 m are under two pixels there.
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
	[24.0, 20.0, 1, 4.0, 12.0, true, 1.0, true, true, false],
	[24.0, 20.0, 1, 4.0, 12.0, true, 1.0, true, false, false],
	[24.0, 20.0, 1, 4.0, 12.0, false, 1.0, true, false, false],
	[24.0, 20.0, 1, 4.0, 12.0, false, 0.78, true, false, false],
	[24.0, 20.0, 1, 4.0, 12.0, false, 0.78, false, false, false],
]
## The cheapest way of drawing the view with every reach whole.
const START := 5
static var ladder: Array[Step] = rungs()


static func rungs() -> Array[Step]:
	var out: Array[Step] = []
	for d: Dictionary in DRAWN:
		out.append(Step.new(FLORA[0], d))
	for i in range(1, FLORA.size()):
		out.append(Step.new(FLORA[i], DRAWN[-1]))
	return out


## Private render layers, one table so no two uses share a bit. What the ladder cuts draws on LADDER_LAYER for the
## headset's views, and whole on FULL_LAYER, which only a photo sees (PhotoTool).
const LADDER_LAYER := 1 << 16
const FULL_LAYER := 1 << 17
## Only cameras and mirrors see the player's own avatar: their eyes would see its head from inside.
const SELF_LAYER := 1 << 18
## What only the eyes see: the player's own avatar without its head (Avatar.headless), a camera's style dial.
const EYES_LAYER := 1 << 19
## Every body drawn for a person but the player's own: what a mirror reflects (MirrorTool).
const PEOPLE_LAYER := 1 << 14
## A mirror's own light, which lights only the people it reflects.
const MIRROR_LAYER := 1 << 13
## Past the 20 layers a node is ever put on, so only a camera holds it: that camera draws the garden white
## (sculpture.gdshaderinc).
const SCULPTURE_LAYER := 1 << 20
const VIEW_MASK := 0xFFFFF & ~FULL_LAYER & ~MIRROR_LAYER & ~EYES_LAYER
const PHOTO_MASK := 0xFFFFF & ~LADDER_LAYER & ~MIRROR_LAYER & ~EYES_LAYER
const MIRROR_MASK := PEOPLE_LAYER | SELF_LAYER | MIRROR_LAYER
## A step down takes its reach at once: receding at this rate held a full garden over budget for 4 s on the Quest 2.
const REACH_M_PER_S := 8.0
const WARMUP_S := 5.0
## Frames drawn at each `primed` rung while loading, so pipelines and buffers exist before play (scripts/engine.patch):
## unprimed, a 3D scale or MSAA level cost the Quest 2 a 110 to 180 ms frame mid-play.
const PRIME_FRAMES := 2

signal rungs_primed

var governor: Governor
var map := Map.new()
var people := People.new()
## The figure whose file People measures, and the step and density map it is measured under.
var _watched: Avatar
var _watched_under := []
var _said := ""
## A step held for measuring; -1 while governed.
var pin := -1:
	set(n):
		pin = clampi(n, -1, ladder.size() - 1)
var _pace: Callable
var budget_ms := 0.0
var frame_ms := 0.0
var fresh := false
var _viewport_ms := 0.0
var _xr: OpenXRInterface
var _flora: Flora
var _masonry: Masonry
var _look: Look
var view: Viewport
var covered := func() -> bool: return false
## Eye-tracked runtimes foveate along the gaze at no visible cost, so only a fixed level is a knob.
var _foveates := false
var _warm := 0.0
## Microseconds: the engine's delta is capped, which hides a stall.
var clock := func() -> int: return Time.get_ticks_usec()
var _tick := 0
var _primed := 0
var _priming := PackedInt32Array()
## -1 to apply the view knobs again.
var _applied := -1
var _settled := false


func _init(pace: Callable, xr: OpenXRInterface, flora: Flora, masonry: Masonry = null, look: Look = null) -> void:
	_pace = pace
	_xr = xr
	_flora = flora
	_masonry = masonry
	_look = look
	budget_ms = _budget()
	_foveates = xr != null and xr.is_foveation_supported() and not xr.is_eye_gaze_interaction_supported()
	governor = Governor.new(ladder.size() - 1, popping(), START if budget_ms > 0.0 else 0, shares(_foveates), idle(_foveates))
	if budget_ms > 0.0:
		_priming = primed()
	if xr != null:
		# The runtime drops a foveation level set before its session begins.
		xr.session_begun.connect(func() -> void: _applied = -1)


func _ready() -> void:
	view = get_viewport()
	_apply(ladder[step()], step())
	RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(), true)


## Levels whose step up switches a knob seen at once across the view or on everyone, which must not flicker.
static func popping() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in _changed(func(a: Step, b: Step) -> bool: return a.shadows != b.shadows or a.scale_3d != b.scale_3d or a.render_scale != b.render_scale or a.msaa != b.msaa or a.files != b.files or a.outlines != b.outlines or a.toon != b.toon):
		out.append(i - 1)
	return out


## Foveation on or off is another framebuffer, which `Map` also switches.
static func primed() -> PackedInt32Array:
	var out := PackedInt32Array([0])
	out.append_array(_changed(func(a: Step, b: Step) -> bool: return a.render_scale != b.render_scale or a.msaa != b.msaa or a.reflections != b.reflections or a.shadows != b.shadows or a.scale_3d != b.scale_3d or (a.foveation > 0) != (b.foveation > 0)))
	out.append(START)
	return out


static func idle(foveates: bool) -> PackedInt32Array:
	if foveates:
		return PackedInt32Array()
	return _changed(func(a: Step, b: Step) -> bool: return a.foveation != b.foveation and a.render_scale == b.render_scale and a.msaa == b.msaa and a.reflections == b.reflections)


static func _changed(differ: Callable) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in range(1, ladder.size()):
		if differ.call(ladder[i - 1], ladder[i]):
			out.append(i)
	return out


static func shares(foveates: bool) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for step: Step in ladder:
		out.append(step.share)
	for i in idle(foveates):
		out[i - 1] = 0.0
	return out


static func full_detail(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter(&"full_layer", FULL_LAYER)


static func reach(now: float, to: float, delta: float) -> float:
	return to if to < now else move_toward(now, to, REACH_M_PER_S * delta)


static func median(values: PackedFloat32Array) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


## A runtime may report no rate for its first frames: until it does, the weakest headset's.
func _budget() -> float:
	if not _pace.is_valid():
		return 0.0
	var hz: float = _pace.call()
	return 1000.0 / (hz if hz > 0.0 else Budget.REFRESH_HZ)


func priming() -> bool:
	return _primed < _priming.size() * PRIME_FRAMES


func held() -> bool:
	return pin >= 0 or budget_ms == 0.0


func step() -> int:
	return pin if pin >= 0 else governor.level


func files() -> bool:
	return ladder[step()].files and (budget_ms == 0.0 or people.measured())


## Starts the measuring of figure `a`'s file where People.admit has just let it in to be measured, at the step and
## density map it is measured under.
func watch(a: Avatar) -> void:
	if people.trial != null and a.source == people.trial.key and not a.stand_in and not is_instance_valid(_watched):
		_watched = a
		_watched_under = [step(), map.on]


## Whether the frame of `viewport` drew all it was given: a draw whose pipeline is still compiling is skipped, and a
## frame that skipped one reads the GPU time of what it did not draw.
static func nothing_skipped(viewport: RID) -> bool:
	var skipped := RenderingServer.VIEWPORT_RENDER_INFO_SKIPPED_DRAWS_IN_FRAME
	return RenderingServer.viewport_get_render_info(viewport, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, skipped) == 0 and RenderingServer.viewport_get_render_info(viewport, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, skipped) == 0


## Whether figure `a` stands in the view from its eyes to its hips, which a figure near enough to talk to still does: one
## at its edge costs a fraction of what it does in view. Its pose places it, not its node, which another player's avatar
## keeps at the origin.
func _whole_in_view(a: Avatar) -> bool:
	var camera := view.get_camera_3d()
	if camera == null or not a.is_visible_in_tree():
		return false
	var eyes := a.global_transform * a.eyes.origin
	var half := a.eye_height / 4.0
	for c in 8:
		var corner := eyes + Vector3(half if c & 1 else -half, a.eye_height * 0.1 if c & 2 else -a.eye_height / 2.0, half if c & 4 else -half)
		if not camera.is_position_in_frustum(corner):
			return false
	return true


## Whether the file `key` is drawn whole (People.admit); unpaced, nothing is priced, and a built-in is always itself.
func admit(key: String) -> bool:
	if key == "":
		return true
	if budget_ms == 0.0 or not files():
		return files()
	var whole := people.admit(key, budget_ms * Governor.LINE)
	var said := "quality: a file drawn %s, %s" % ["whole" if whole else "as a built-in body", people.why]
	if said != _said:
		print(said)
		_said = said
	return whole


func _process(delta: float) -> void:
	frame(RenderingServer.viewport_get_measured_render_time_gpu(view.get_viewport_rid()), delta)


func frame(ms: float, delta: float) -> void:
	var now: int = clock.call()
	var dt := (now - _tick) / 1000000.0 if _tick > 0 else delta
	_tick = now
	# The timer holds its last reading while the runtime skips rendering, as with the headset off the head.
	fresh = ms > 0.0 and ms != _viewport_ms
	_viewport_ms = ms
	# The viewport's timer leaves out the paint the canvases run on the GPU outside it.
	frame_ms = ms + Canvas.gpu_ms()
	if budget_ms > 0.0 and fresh:
		# The runtime may report the shell's rate for the first frames, so the budget follows it every frame.
		budget_ms = _budget()
		if _warm > WARMUP_S and not priming() and not covered.call():
			var measuring := people.trial
			if measuring != null and not is_instance_valid(_watched):
				people.abandon("its figure gone")
			elif measuring != null and _watched_under != [step(), map.on]:
				people.abandon("the step or the density map changed under it")
			people.measure(frame_ms, people.trial != null and is_instance_valid(_watched) and _whole_in_view(_watched) and nothing_skipped(view.get_viewport_rid()))
			if measuring != null and people.trial == null:
				_watched = null
				print("quality: %s" % people.why)
		_warm += delta
		_primed += 1
		if _primed == _priming.size() * PRIME_FRAMES:
			rungs_primed.emit()
		if pin < 0 and _warm > WARMUP_S:
			var was := governor.level
			governor.step(frame_ms, budget_ms, dt, _settled, not covered.call())
			if governor.level != was:
				print("quality: step %d to %d, the GPU at %.1f ms of %.1f, %s, at %.3f s" % [was, governor.level, frame_ms, budget_ms, governor.why, now / 1e6])
	var n := _priming[_primed / PRIME_FRAMES] if priming() else step()
	var at := ladder[n]
	if _foveates and fresh and _warm > WARMUP_S and at.foveation > 0:
		var was_on := map.on
		map.step(frame_ms, budget_ms, delta)
		if map.on != was_on:
			print("quality: foveation map %s, the GPU at %.1f ms, %s" % ["on" if map.on else "off", frame_ms, map.why])
			_applied = -1
	if n != _applied:
		_apply(at, n)
	_settled = _flora.approach(at, delta)
	if Avatar.outlines != at.outlines:
		Avatar.show_outlines(at.outlines)
	if Avatar.toon != at.toon:
		Avatar.show_toon(at.toon)
	if _look != null and _look.sun.shadow_enabled != at.shadows:
		_look.sun.shadow_enabled = at.shadows
	var scale := at.scale_3d if _xr != null else at.scale_3d * at.render_scale
	if not is_equal_approx(view.scaling_3d_scale, scale):
		view.scaling_3d_scale = scale
	if _masonry != null:
		_settled = Wall.approach(at, delta, _masonry) and _settled


## Once per step, so a measurement that sets a knob itself (Driver's `antialias`) keeps it while the step holds.
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


## A file is priced by its own frames: the median of its first frames with its figure whole in view, once the GPU's
## timer shows it, less the median before. Neither its triangles nor its primitives track that cost ("People past the
## headset" in docs/design.md). A file is let in only within the headroom its own step's frames leave: walking down to
## make room ran at a third of the refresh on the Quest 2.
class People:
	signal refused(key: String)
	## The headroom is measured afresh: figures standing in for a file may be offered again.
	signal reopened
	const FRAMES := 36
	## A file let in counts against the headroom until the median of the frames holds it.
	const SHOWN_FRAMES := FRAMES / 2 + 1
	## A measurement unfinished after this many frames ends unpriced, since its figure may never stand in view.
	const PATIENCE := FRAMES * 10

	## A file let in to be measured, by Map's settle and trial: `limit` is the GPU time its frames may take, the line less
	## what files let in still take, and `before` the median it adds to with those, both read as it is let in.
	class Trial:
		var key: String
		var before: float
		var limit: float
		var settle := Map.SETTLE_FRAMES
		var frames := PackedFloat32Array()
		var waited := 0

		func _init(file: String, frame: float, most: float) -> void:
			key = file
			before = frame
			limit = most

	var why := ""
	var trial: Trial
	var _ms := PackedFloat32Array()
	## x: a file's cost in milliseconds; y: frames measured since it was let in.
	var _let_in: Array[Vector2] = []
	## Each file's measured cost a figure, in milliseconds, by key.
	var _costs := {}
	## Frames until the window holds none from before a measurement ended.
	var _stale := 0
	var _idle := 0
	## By key, a file left unmeasured: x the offers it sits out, y the offers its next abandon sits out.
	var _waits := {}

	func measured() -> bool:
		return _ms.size() == FRAMES

	## `ms`, a frame's GPU time; `in_view`, whether the figure being measured stands whole in it, all drawn.
	func measure(ms: float, in_view := false) -> void:
		if _stale > 0:
			_stale -= 1
		elif trial == null:
			_idle += 1
			if _idle >= FRAMES:
				_idle = 0
				reopened.emit()
				for key: String in _waits:
					_waits[key] -= Vector2i(1, 0)
		if trial != null:
			_try(ms, in_view)
		_ms.append(ms)
		if _ms.size() > FRAMES:
			_ms.remove_at(0)
		for i in _let_in.size():
			_let_in[i].y += 1.0
		_let_in = _let_in.filter(func(l: Vector2) -> bool: return l.y < SHOWN_FRAMES)

	func admit(key: String, line_ms: float) -> bool:
		var frame := Quality.median(_ms)
		var room := _headroom(line_ms)
		if trial != null or _stale > 0:
			why = "the headroom held while a file is measured"
			return false
		if not _costs.has(key):
			if (_waits.get(key, Vector2i.ZERO) as Vector2i).x > 0:
				why = "unmeasured, waiting %d offers after its last measuring was left" % _waits[key].x
				return false
			if room <= 0.0:
				why = "unmeasured, no headroom, the GPU at %.2f ms of a %.2f ms line" % [frame, line_ms]
				return false
			why = "to be measured, %.2f ms of headroom" % room
			trial = Trial.new(key, line_ms - room, frame + room)
			return true
		var cost: float = _costs[key]
		why = "%.2f ms measured of %.2f ms headroom, the GPU at %.2f ms of a %.2f ms line" % [cost, room, frame, line_ms]
		if cost > room:
			return false
		_let_in.append(Vector2(cost, 0.0))
		return true

	## Ends the measuring of a file unpriced, its figure standing in for it until it is offered again, after as many offers
	## as it sat out last time, doubled, so a file that cannot be measured leaves the measuring to others.
	func abandon(reason: String) -> void:
		var wait: Vector2i = _waits.get(trial.key, Vector2i(0, 1))
		_waits[trial.key] = Vector2i(wait.y, wait.y * 2)
		why = "a file left unmeasured, %s" % reason
		refused.emit(_end())

	func _headroom(line_ms: float) -> float:
		var room := line_ms - Quality.median(_ms)
		for l in _let_in:
			room -= l.x
		return room

	func _end() -> String:
		var key := trial.key
		trial = null
		_stale = FRAMES
		_idle = FRAMES
		return key

	## Out of view, its settle and frames start over.
	func _try(ms: float, in_view: bool) -> void:
		trial.waited += 1
		if trial.waited > PATIENCE:
			abandon("its figure not in view in %d frames" % PATIENCE)
			return
		if not in_view:
			trial.settle = Map.SETTLE_FRAMES
			trial.frames.clear()
			return
		if trial.settle > 0:
			trial.settle -= 1
			return
		trial.frames.append(ms)
		if trial.frames.size() < Map.TRIAL_FRAMES:
			return
		var drawn := Quality.median(trial.frames)
		var cost := maxf(drawn - trial.before, 0.0)
		var fits := drawn <= trial.limit
		why = "a file measured at %.2f ms of %.2f ms headroom, the GPU at %.2f ms with it and %.2f ms before" % [cost, trial.limit - trial.before, drawn, trial.before]
		_costs[trial.key] = cost
		_waits.erase(trial.key)
		var key := _end()
		if not fits:
			refused.emit(key)


## On the Quest 2 the density map can cost a view five times its frame (docs/design.md "Fixed foveation on the Quest
## 2"), in views the driver chooses, so it is tried off and on by measurement.
class Map:
	## A trial reads the median of at least this many frames over this long, after SETTLE_FRAMES for the timer.
	const TRIAL_FRAMES := 12
	const TRIAL_SECONDS := 0.5
	const SETTLE_FRAMES := 4
	## The map stays off only where the frame without it reads under this share of the frame with it.
	const SAVES := 0.8
	## Seconds under the line before the map is tried again, doubling with each trial it fails.
	const CALM_SECONDS := 2.0
	const CALM_SECONDS_MAX := 64.0
	## Seconds after a trial of the map off that saved nothing before the next.
	const RETRY_SECONDS := 8.0
	## The GPU this many times the line this long tries the map off, or ends a trial of it on, without the median,
	## which at a few frames a second takes seconds to turn.
	const DEAR := 3.0
	const DEAR_SECONDS := 0.25
	const DEAR_FRAMES := 2

	var on := true
	var why := ""
	var _recent := PackedFloat32Array()
	var _settle := 0
	var _trial := false
	var _trial_s := 0.0
	var _before := 0.0
	var _calm := 0.0
	var _over := 0.0
	var _dear := 0
	var _dear_s := 0.0
	var _dear_trial := false
	var _dear_failed := false
	var _dear_off := false
	var _wait := CALM_SECONDS
	var _since := INF

	func step(frame_ms: float, period_ms: float, dt: float) -> void:
		var line_ms := period_ms * Governor.LINE
		_since += dt
		if frame_ms > line_ms * DEAR:
			_dear += 1
			_dear_s += dt
		else:
			_dear = 0
			_dear_s = 0.0
		var dear := _dear >= DEAR_FRAMES and _dear_s >= DEAR_SECONDS
		if _trial and on and dear and frame_ms > maxf(_before, line_ms) * DEAR:
			_settle_trial(frame_ms)
			why = "dear with it on, %.1f ms against %.1f" % [frame_ms, _before]
			return
		if _settle > 0:
			_settle -= 1
			return
		_recent.append(frame_ms)
		if _trial:
			_trial_s += dt
			if _recent.size() >= TRIAL_FRAMES and _trial_s >= TRIAL_SECONDS:
				_settle_trial(Quality.median(_recent))
			return
		if on and dear and (not _dear_failed or _since > RETRY_SECONDS):
			_start(false, frame_ms)
			_dear_trial = true
			why = "tried off, dear"
			return
		if _recent.size() > TRIAL_FRAMES:
			_recent.remove_at(0)
		var now := Quality.median(_recent)
		_calm = _calm + dt if now < line_ms else 0.0
		_over = _over + dt if now > period_ms else 0.0
		if on and _over >= TRIAL_SECONDS and _since > RETRY_SECONDS:
			_start(false)
			why = "tried off, over the period at %.1f ms" % _before
		elif not on and (_calm >= _wait or _dear_off and _since > RETRY_SECONDS):
			_start(true)
			why = "tried on, %s" % ("calm" if _calm >= _wait else "rechecking a dear trial")

	func _start(to: bool, before := -1.0) -> void:
		_before = before if before >= 0.0 else Quality.median(_recent)
		_dear = 0
		_dear_s = 0.0
		_dear_trial = false
		on = to
		_recent.clear()
		_trial = true
		_trial_s = 0.0
		_settle = SETTLE_FRAMES

	func _settle_trial(read: float) -> void:
		_trial = false
		_calm = 0.0
		_over = 0.0
		_dear_failed = false
		_dear_off = false
		if not on and read >= _before * SAVES:
			_dear_failed = _dear_trial
			on = true
			why = "off saved nothing, %.1f ms against %.1f" % [read, _before]
			_since = 0.0
		elif not on:
			# One dear frame judged this, which a spike the map had no part in can pass: it is tried on again later.
			_dear_off = _dear_trial
			_since = 0.0
		elif read * SAVES > _before:
			on = false
			why = "on cost the frame, %.1f ms against %.1f" % [read, _before]
			_wait = minf(_wait * 2.0, CALM_SECONDS_MAX)
		_recent.clear()


## Down at once over the cliff or the line, up after a calm spell, slower each time a step up is undone.
class Governor:
	## The Steam Frame's runtime halves the rate once the GPU nears 0.88 of the period, which this timer reads 0.3 ms under.
	const CLIFF := 0.86
	const HOT_FRAMES := 2
	## Past the cliff but under this share of the budget, a step down not yet shown is not followed: the timer jitters
	## by 1 ms.
	const HOT := 1.05
	const SEVERE := 1.25
	const SETTLE_FRAMES := 3
	## A share of the period: frames this far apart on average are every other refresh, which holds a step up; one is a
	## missed refresh. Neither steps down with the timer under the line, as the CPU or the runtime held those frames.
	const HALVED := 1.5
	## Below this share of the budget the CPU held every other refresh, which a step up does not load.
	const HALVED_GPU := 0.6
	## A gap this many periods, or medians of the last GAPS gaps if longer, is a pause or stall, which restarts the
	## averages: judged, two stalls took a Steam Frame tour to the bottom.
	const PAUSE := 4.0
	const GAPS := 9
	## A share of the budget: at 0.85 the houses of demo/headset.json sat under it while the runtime halved the rate.
	const LINE := 0.8
	const AVERAGE_SECONDS := 1.0
	const CALM_SECONDS := 2.0
	const CALM_SECONDS_MAX := 64.0
	## A step up waits this long after a missed refresh: a hitch is often a scene changing the average has not caught.
	const MISSED_SECONDS := 1.0
	## Half the gap between the line and the Steam Frame's cliff at 0.88, the floor of an unmeasured step's cost.
	const UNMEASURED := 0.04
	## A step down this soon after the step up that reached it doubles the calm needed to climb again, for the session,
	## up to REGRET_MAX across a pop, so one halved second cannot hold a headset at the bottom.
	const REGRET_SECONDS := 10.0
	const REGRET_MAX := 4.0 * CALM_SECONDS_MAX

	## 0 is full quality; each step down adds one.
	var level := 0
	var bottom: int
	var _past_cliff := 0
	var _over := 0
	var _late := false
	var _settle := 0
	var _calm := 0.0
	var _quiet := 0.0
	var _average := 0.0
	var _interval := 0.0
	var _since_up := INF
	var _calm_needed := PackedFloat32Array()
	## The step up's cost out of each level as a share of its frame (knobs cost by the pixel), -1 while unmeasured.
	var _cost := PackedFloat32Array()
	var _since_missed := INF
	var _averaged := 0.0
	var _before := 0.0
	var _took := INF
	## -1 while no step is being measured.
	var _measuring := -1
	var _went_up := false
	var _sticky := PackedInt32Array()
	var _shares := PackedFloat32Array()
	var _idle := PackedInt32Array()
	var _up_from := 0
	var why := ""
	## Kept across restarts.
	var _gaps := PackedFloat32Array()

	## A step up across a `sticky` level (ascending) waits the longest calm once a step down crossed it; `shares` floor
	## a step up not yet measured; `idle` levels are passed by.
	func _init(steps: int, sticky := PackedInt32Array(), start := 0, shares := PackedFloat32Array(), idle := PackedInt32Array()) -> void:
		bottom = steps
		level = start
		_calm_needed.resize(steps + 1)
		_calm_needed.fill(CALM_SECONDS)
		_cost.resize(steps + 1)
		_cost.fill(-1.0)
		_sticky = sticky
		_shares = shares
		_shares.resize(steps + 1)
		_idle = idle
		for i in sticky:
			if i >= start:
				_calm_needed[i] = CALM_SECONDS_MAX

	func up(at: int) -> int:
		var to := at - 1
		while to > 0 and _idle.has(to):
			to -= 1
		return to

	## Never under the levels' `shares`, since what is in view changes it too.
	func cost(at: int, budget_ms: float) -> float:
		var share := 0.0
		for i in range(up(at), at):
			share += _shares[i]
		if _cost[at] >= 0.0:
			return _average * maxf(_cost[at], share)
		return maxf(budget_ms * UNMEASURED, _average * share)

	## The lowest level a step down may reach while the step under way has not shown what it saves: the next pop below.
	func _unpopped() -> int:
		for i in _sticky:
			if i >= level:
				while i > level and _idle.has(i):
					i -= 1
				return i
		return bottom

	## Only the cliff or a missed refresh judges a step not yet `settled`; a frame the player does not `see` is a pause.
	func step(frame_ms: float, budget_ms: float, dt: float, settled := true, see := true) -> void:
		var dt_ms := dt * 1000.0
		var paused := dt_ms >= PAUSE * maxf(budget_ms, Quality.median(_gaps) if _gaps.size() == GAPS else 0.0)
		if see:
			_gaps.append(dt_ms)
			if _gaps.size() > GAPS:
				_gaps.remove_at(0)
		if paused or not see:
			_restart()
			return
		_since_up += dt
		_since_missed = 0.0 if dt_ms > HALVED * maxf(budget_ms, Quality.median(_gaps)) else _since_missed + dt
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
				var at := _before if _went_up else _average
				if at > 0.0:
					_cost[_measuring] = maxf(_cost[_measuring], change / at)
				_measuring = -1
		var line := budget_ms * LINE
		_past_cliff = _past_cliff + 1 if frame_ms > budget_ms * CLIFF else 0
		_quiet = _quiet + dt if _average < line else 0.0
		if _quiet >= CALM_SECONDS_MAX:
			_cost[level] = -1.0
		var halved := averaged and _interval > budget_ms * HALVED and _average > budget_ms * HALVED_GPU
		# The Quest 2 misses refreshes from about 0.84 of the period, short of CLIFF, so a miss among HOT_FRAMES over the
		# line steps down two; a single one does not.
		_over = _over + 1 if frame_ms > line else 0
		_late = _over > 0 and (_late or dt_ms > budget_ms * HALVED)
		var missed := _late and _over >= HOT_FRAMES
		# A miss before the last step down shows its saving, reading no lower than the frame that took it, is load the
		# ladder does not draw.
		var shown := averaged or _went_up or _measuring < 0
		missed = missed and (shown or frame_ms < _took)
		var hot := _past_cliff >= HOT_FRAMES and (shown or frame_ms > budget_ms * HOT)
		var floor := bottom if settled and (_went_up or _measuring < 0) else _unpopped()
		_calm = _calm + dt if settled and averaged and not halved and _average + cost(level, budget_ms) < line else 0.0
		# The average steps down only while the frame still reads over the line: it lags load already gone.
		if (hot or missed or (settled and averaged and _average > line and frame_ms > line)) and level < floor:
			if _since_up < REGRET_SECONDS:
				for i in range(level, _up_from):
					_calm_needed[i] = minf(maxf(_calm_needed[i], CALM_SECONDS_MAX) * 2.0, REGRET_MAX) if _sticky.has(i) else minf(_calm_needed[i] * 2.0, CALM_SECONDS_MAX)
			_since_up = INF
			# A step down before the last one's second was in leaves the average from before both.
			if shown:
				_before = _average
			var to := mini(level + (2 if missed or frame_ms > budget_ms * SEVERE else 1), floor)
			while _idle.has(to) and to < floor:
				to += 1
			for i in range(level, to):
				if _sticky.has(i):
					_calm_needed[i] = maxf(_calm_needed[i], CALM_SECONDS_MAX)
			_measuring = to
			_went_up = false
			_took = frame_ms
			why = "%s, %.1f ms since the last frame, averaging %.1f ms" % ["over the cliff" if hot else "missed" if missed else "average over the line", dt_ms, _average]
			_move(to)
		elif level > 0 and _calm >= _climb_wait() and _since_missed >= MISSED_SECONDS:
			_before = _average
			_measuring = level
			_went_up = true
			_up_from = level
			why = "calm for %.1f s, averaging %.1f ms" % [_calm, _average]
			_move(up(level))
			_since_up = 0.0

	func _climb_wait() -> float:
		var most := 0.0
		for i in range(up(level), level):
			most = maxf(most, _calm_needed[i])
		return most

	func _move(to: int) -> void:
		level = to
		_calm = 0.0
		_quiet = 0.0
		_restart()

	func _restart() -> void:
		_past_cliff = 0
		_over = 0
		_late = false
		_average = 0.0
		_interval = 0.0
		_averaged = 0.0
		_settle = SETTLE_FRAMES
