class_name Metrics
extends Node

var path: String
var info := {}
var play_log: PlayLog
var context: Callable
## This frame's ACTIVITIES tags other than "moving", which `_tags` takes from the head.
var activity: Callable
var input: Callable
var checks: Callable
## Replayer.compare: the record's checks were taken at this point of the frame.
var compare: Callable
var _cpu_ms: PackedFloat32Array = []
var frame_times := func() -> Dictionary: return Performance.get_frame_times()
## scripts: every script callback, deferred call and navigation; other: input, audio and the time between frames.
const MAIN_PHASES := ["xr_wait", "physics", "scripts", "sync", "draw", "other"]
var _main_ms := _no_phases()
var _gpu: PackedFloat32Array = []
var _logging_us := 0
var clock := func() -> int: return Time.get_ticks_usec()
var _last_tick: int = clock.call()
var quality: Quality
## Rows record the play-space origin's moves: any the player did not make is a bug.
var head: Node3D
var world: World
var _origin: Transform3D
var _origin_moves := 0
var _landing := {}
var _landings: Array = []
var _moved := false
var _step := 0
var _pinned := true
var _deltas: PackedFloat32Array = []
var _was_late := false
## Logged a frame later: the interval spans two engine frames, and the engine reports a split only once its frame ends.
var _late_line := ""
## On `clock`; -1 before any.
var late_at_us := -1
var _gpu_ns := -1
var _gpu_cycles := -1
var _gpu_counted_ns := 0
var _drm_fds: PackedStringArray = []
var _row := {}
var _gpu_reader: Thread
## Rescans for DRM clients every tenth reading: the runtime may open more later.
var _drm_scan := 0
var _draws := 0
var _prims := 0
## A second with draws skipped for compiling reads low GPU time; shadow skips also count deferred shadows, so go unread.
var _skipped := 0
## Pipelines compiled so far: x while drawing, which holds the frame, y on worker threads.
var _compiled := Vector2i()
## Rows record the eye frusta's widest swing: the sun's shadow map is fitted to them.
var xr: XRInterface
## Read every frame: a Quest starts the session at the shell's rate and switches a few seconds later.
var refresh: Callable
var _eye_lo := PackedFloat32Array()
var _eye_hi := PackedFloat32Array()
const ACTIVITIES := ["moving", "building", "wheel", "still", "coop"]
const MOVING_DEG_S := 30.0
const MOVING_M_S := 0.3
## Fine enough for p99 against an 11 ms refresh, and merges exactly.
const BINS_PER_MS := 2
## Holds what a move starts; a glide moves every frame, so only a move after a still frame opens a window.
const LANDING_S := 0.5
var _by_activity := {}
var _head_was: Variant = null
var _seconds: Array = []
var _file: FileAccess
var _rows := 0
var _rows_end := 0
var _acc := 0.0
var _since_flush := 0.0
## A stall the player sees, listed with its `note`s so the record names its cause.
const STALL_MS := 50.0
const STALLS_A_SECOND := 4
const NOTES_A_FRAME := 8
const SLOW_MS := 4.0
var _stalls: Array = []
static var _notes: Array = []
## The time until the next frame was unseen (loading, headset off, backgrounded): paused, not a frame.
var _unplayed := false
var _paused_s := 0.0


func _init(out: String) -> void:
	path = out


## A negative `ms` means untimed.
static func note(what: String, ms := -1.0) -> void:
	if ms >= 0.0 and ms <= SLOW_MS:
		return
	print(what if ms < 0.0 else "%s took %.1f ms" % [what, ms])
	if _notes.size() < NOTES_A_FRAME:
		_notes.append({"what": what} if ms < 0.0 else {"what": what, "ms": snappedf(ms, 0.1)})


func _ready() -> void:
	_unplayed = true


func _notification(what: int) -> void:
	if what in [NOTIFICATION_UNPAUSED, NOTIFICATION_APPLICATION_RESUMED]:
		_unplayed = true


func _process(delta: float) -> void:
	if compare.is_valid():
		compare.call()
	if play_log == null and path.is_empty():
		return
	if play_log != null and input.is_valid():
		play_log.record(input.call(delta))
		if checks.is_valid() and play_log.frames() % Replay.CHECK_EVERY == 0:
			play_log.check(checks.call())
	if refresh.is_valid():
		var hz: float = refresh.call()
		if hz > 0.0 and hz != info.get("refresh_hz", 0.0):
			print("metrics: running at %s Hz" % hz)
			info.refresh_hz = hz
	var now: int = clock.call()
	# Engine delta is capped during stalls.
	var elapsed := (now - _last_tick) / 1000000.0
	_last_tick = now
	if _unplayed:
		_unplayed = false
		_paused_s += elapsed
		_late_line = ""
		_notes.clear()
		_head_was = null
		return
	_deltas.append(elapsed * 1000.0)
	var split := main_split(frame_times.call())
	for phase in MAIN_PHASES:
		_main_ms[phase].append(split[phase])
	var cpu_ms := main_work_ms(split)
	_cpu_ms.append(cpu_ms)
	var late := is_late(elapsed * 1000.0)
	var compiled := _compilations()
	if not _late_line.is_empty():
		print(_late_line % split_text(split))
		_late_line = ""
	if late and not _was_late:
		_late_line = "metrics: late frame %.1f ms, the engine frame it began in %s, the one it ended in %%s, %.1f ms on the GPU, %d pipelines compiled while drawing and %d on worker threads, at %.3f s" % [elapsed * 1000.0, split_text(split), quality.frame_ms if quality != null else 0.0, compiled.x - _compiled.x, compiled.y - _compiled.y, now / 1e6]
	var gpu_ms := quality.frame_ms if quality != null and quality.fresh else -1.0
	var tags := _tags(elapsed)
	for tag in tags:
		tally(_by_activity, tag, elapsed * 1000.0, late, cpu_ms, gpu_ms)
	if not _stalls.is_empty() and not _stalls[-1].has("main_after_ms"):
		_stalls[-1].main_after_ms = rounded_split(split)
	if elapsed * 1000.0 > STALL_MS and _stalls.size() < STALLS_A_SECOND:
		_stalls.append({"ms": snappedf(elapsed * 1000.0, 0.1), "tags": tags, "main_ms": rounded_split(split),
			"compiled": [compiled.x - _compiled.x, compiled.y - _compiled.y], "notes": _notes.duplicate()})
	_notes.clear()
	_compiled = compiled
	_was_late = late
	if late:
		late_at_us = now
	_draws = maxi(_draws, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	_prims = maxi(_prims, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	var view := get_viewport()
	if view != null:
		_skipped = maxi(_skipped, RenderingServer.viewport_get_render_info(view.get_viewport_rid(),
				RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_SKIPPED_DRAWS_IN_FRAME))
	if quality != null and quality.fresh:
		_step = maxi(_step, quality.step())
		_pinned = _pinned and quality.held()
		_gpu.append(quality.frame_ms)
	if xr != null and xr.is_initialized():
		var now_eyes := eye_half_angles(xr.get_projection_for_view(0, 1.0, 0.05, 400.0)) + eye_half_angles(xr.get_projection_for_view(1, 1.0, 0.05, 400.0))
		if _eye_lo.is_empty():
			_eye_lo = now_eyes.duplicate()
			_eye_hi = now_eyes.duplicate()
		for i in now_eyes.size():
			_eye_lo[i] = minf(_eye_lo[i], now_eyes[i])
			_eye_hi[i] = maxf(_eye_hi[i], now_eyes[i])
	if head != null:
		var o := head.get_parent_node_3d().global_transform
		var moved := o != _origin
		if moved:
			_origin_moves += 1
			_origin = o
			if not _moved:
				_close_landing()
				_landing = {"label": info.get("label", ""), "frames_ms": [], "s": 0.0}
		_moved = moved
	if not _landing.is_empty():
		_landing.frames_ms.append(snappedf(elapsed * 1000.0, 0.001))
		_landing.s += elapsed
		if _landing.s >= LANDING_S:
			_close_landing()
	_acc += elapsed
	# A stall's split shows whole only on the frame after it, so its second waits for that frame.
	if _acc >= 1.0 and (_stalls.is_empty() or _stalls[-1].has("main_after_ms")):
		var begin := Time.get_ticks_usec()
		_finish_row()
		var row := summary(_deltas)
		row.draws = _draws
		if head != null:
			row.head_m = snappedf(head.position.y, 0.01)
			row.origin = [snappedf(_origin.origin.x, 0.001), snappedf(_origin.origin.y, 0.001), snappedf(_origin.origin.z, 0.001)]
			row.origin_moves = _origin_moves
			_origin_moves = 0
			if not _landings.is_empty():
				row.landings = _landings
				_landings = []
		row.prims = _prims
		row.skipped = _skipped
		var frames := maxi(_deltas.size(), 1)
		row.paint_steps = roundi(Canvas.laid / frames)
		Canvas.laid = 0.0
		row.paint_cpu_ms = Canvas.cpu_us / 1000.0 / frames
		Canvas.cpu_us = 0
		row.springs_ms = Avatar.springs_us / 1000.0 / frames
		Avatar.springs_us = 0
		row.expressions_ms = ExpressionPlayer.process_us / 1000.0 / frames
		ExpressionPlayer.process_us = 0
		row.paint_gpu_ms = Canvas.gpu_ms()
		if not _eye_lo.is_empty():
			row.eye_fov_spread_deg = spread(_eye_lo, _eye_hi)
			_eye_lo = PackedFloat32Array()
			_eye_hi = PackedFloat32Array()
		row.activity = _by_activity
		_by_activity = {}
		if not _stalls.is_empty():
			row.stalls = _stalls
			_stalls = []
		if _paused_s > 0.0:
			row.paused_s = snappedf(_paused_s, 0.001)
			_paused_s = 0.0
		if world != null:
			row.fill = snappedf(world.fill(), 0.001)
			var charges := Budget.charges(world.units)
			for k in charges:
				charges[k] = snappedf(charges[k], 0.001)
			row.charges = charges
		_draws = 0
		_prims = 0
		_skipped = 0
		if not _gpu.is_empty():
			var sum := 0.0
			for ms in _gpu:
				sum += ms
			row.viewport_gpu_ms = sum / _gpu.size()
			row.step = _step
			row.pinned = _pinned
			if quality.budget_ms > 0.0:
				row.budget_ms = quality.budget_ms
		_step = quality.step() if quality != null else 0
		_pinned = true
		row.unix = Time.get_unix_time_from_system()
		row.cpu_ms = distribution(_cpu_ms)
		var main_ms := {}
		for phase in MAIN_PHASES:
			main_ms[phase] = distribution(_main_ms[phase])
		row.main_ms = main_ms
		_main_ms = _no_phases()
		row.gpu_frame_ms = distribution(_gpu)
		row.refresh_hz = info.get("refresh_hz", Budget.REFRESH_HZ)
		if context.is_valid():
			row.context = context.call()
		if head != null:
			var pos := head.global_position
			var forward := -head.global_basis.z.normalized()
			row.head_position = [pos.x, pos.y, pos.z]
			row.view_direction = [forward.x, forward.y, forward.z]
		row.logging_us = _logging_us
		row.mem_mb = memory_mb()
		_cpu_ms.clear()
		_gpu.clear()
		_row = row
		if not path.is_empty():
			_gpu_reader = Thread.new()
			_gpu_reader.start(gpu_time)
		else:
			_finish_row()
		_logging_us = Time.get_ticks_usec() - begin
		_deltas.clear()
		_acc = 0.0
	if _gpu_reader != null and not _gpu_reader.is_alive():
		_finish_row()


## The GPU time is read on its own thread, not the main one (up to 8 ms on the Steam Frame) nor a pool's (busy laying).
func _finish_row() -> void:
	if _row.is_empty():
		return
	if _gpu_reader != null:
		var gpu: PackedInt64Array = _gpu_reader.wait_to_finish()
		_gpu_reader = null
		if gpu[0] >= 0 and _gpu_ns >= 0:
			_row.gpu_ms = (gpu[0] - _gpu_ns) / 1e6
			if gpu[1] >= 0 and _gpu_cycles >= 0 and gpu[2] > _gpu_counted_ns:
				_row.gpu_mhz = snappedf(float(gpu[1] - _gpu_cycles) / (gpu[2] - _gpu_counted_ns) * 1000.0, 1.0)
		_gpu_ns = gpu[0]
		_gpu_cycles = gpu[1]
		_gpu_counted_ns = gpu[2]
	if play_log != null:
		play_log.sample(_row)
	if not path.is_empty():
		_seconds.append(_row)
	_row = {}
	_since_flush += 1.0
	if _since_flush >= 5.0:
		flush()


func _close_landing() -> void:
	if _landing.is_empty():
		return
	var frames: Array = _landing.frames_ms
	_landings.append({"label": _landing.label, "frames_ms": frames, "max": frames.max(),
		"late": frames.filter(is_late).size()})
	_landing = {}


func _tags(elapsed: float) -> Array:
	var tags: Array = activity.call() if activity.is_valid() else []
	if head != null:
		var now := head.global_transform
		if _head_was != null and elapsed > 0.0:
			var was: Transform3D = _head_was
			var turned := rad_to_deg(was.basis.get_rotation_quaternion().angle_to(now.basis.get_rotation_quaternion()))
			if turned / elapsed > MOVING_DEG_S or was.origin.distance_to(now.origin) / elapsed > MOVING_M_S:
				tags.append("moving")
		_head_was = now
	if not ("moving" in tags or "building" in tags or "wheel" in tags):
		tags.append("still")
	return tags


## A negative `gpu_ms` means no reading.
static func tally(into: Dictionary, tag: String, ms: float, late: bool, cpu_ms: float, gpu_ms: float) -> void:
	if not into.has(tag):
		into[tag] = {"frames": 0, "late": 0, "max": 0.0, "hist": {}, "cpu_ms": 0.0, "gpu_ms": 0.0, "gpu_frames": 0}
	var t: Dictionary = into[tag]
	t.frames += 1
	t.late += int(late)
	t.max = maxf(t.max, ms)
	var bin := str(int(ms * BINS_PER_MS))
	t.hist[bin] = t.hist.get(bin, 0) + 1
	t.cpu_ms += cpu_ms
	if gpu_ms >= 0.0:
		t.gpu_ms += gpu_ms
		t.gpu_frames += 1


static func memory_mb() -> Dictionary:
	const MIB := 1048576.0
	return {"textures": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / MIB, 0.1),
		"buffers": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED) / MIB, 0.1),
		"video": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / MIB, 0.1)}


static func _compilations() -> Vector2i:
	return Vector2i(int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW)), int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION) + Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE) + Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH)))


## Left, right, down and up half-angles of an eye's frustum, in degrees.
static func eye_half_angles(p: Projection) -> PackedFloat32Array:
	return PackedFloat32Array([rad_to_deg(atan((1.0 - p.z.x) / p.x.x)), rad_to_deg(atan((1.0 + p.z.x) / p.x.x)),
		rad_to_deg(atan((1.0 - p.z.y) / p.y.y)), rad_to_deg(atan((1.0 + p.z.y) / p.y.y))])


static func spread(lo: PackedFloat32Array, hi: PackedFloat32Array) -> float:
	var most := 0.0
	for i in lo.size():
		most = maxf(most, hi[i] - lo[i])
	return most


func summary(d: PackedFloat32Array) -> Dictionary:
	var ds := Array(d)
	ds.sort()
	return {"t": Time.get_ticks_msec() / 1000.0, "frames": ds.size(), "mean": ds.reduce(func(sum: float, ms: float) -> float: return sum + ms, 0.0) / ds.size(), "p50": _q(ds, 0.5), "p95": _q(ds, 0.95), "p99": _q(ds, 0.99), "max": ds[-1], "late": ds.filter(is_late).size(), "label": info.get("label", "")}


func is_late(ms: float) -> bool:
	var hz: float = info.get("refresh_hz", 0.0)
	return hz > 0.0 and ms > 1500.0 / hz


## [busy ns, cycles, busy ns of the clients that count cycles], -1 where the driver reports none. Busy time stretches as
## the GPU clocks down and cycles do not, so together they tell more work from a slower clock.
func gpu_time() -> PackedInt64Array:
	if _drm_scan % 10 == 0:
		var dir := DirAccess.open("/proc/self/fd")
		if dir == null:
			return PackedInt64Array([-1, -1, 0])
		_drm_fds.clear()
		# Reading every fd's info held the Steam Frame's main thread for up to 15 ms; a link read costs the kernel nothing.
		for fd in dir.get_files():
			if dir.read_link(fd).begins_with("/dev/dri/"):
				_drm_fds.append(fd)
	_drm_scan += 1
	var by_client := {}
	for fd in _drm_fds:
		var client := ""
		var used := PackedInt64Array([0, -1])
		for line in _fdinfo(fd).split("\n"):
			var value := line.get_slice(":", 1).strip_edges().get_slice(" ", 0)
			if line.begins_with("drm-client-id:"):
				client = value
			elif line.begins_with("drm-engine-") and not line.begins_with("drm-engine-capacity"):
				used[0] += int(value)
			elif line.begins_with("drm-cycles-"):
				used[1] = maxi(used[1], 0) + int(value)
		if client != "":
			by_client[client] = used
	if by_client.is_empty():
		return PackedInt64Array([-1, -1, 0])
	var total := PackedInt64Array([0, -1, 0])
	for v: PackedInt64Array in by_client.values():
		total[0] += v[0]
		if v[1] >= 0:
			total[1] = maxi(total[1], 0) + v[1]
			total[2] += v[0]
	return total


## procfs reports no length, and the kernel writes a DRM fd's info afresh on every read, so it is taken in one.
static func _fdinfo(fd: String) -> String:
	var f := FileAccess.open("/proc/self/fdinfo/" + fd, FileAccess.READ)
	return f.get_buffer(65536).get_string_from_utf8() if f != null else ""


static func _q(a: Array, q: float) -> float:
	return a[clampi(int(q * (a.size() - 1)), 0, a.size() - 1)] if a.size() > 0 else 0.0


## Rewrites only the closing `info`, so a flush costs the same in the second hour and leaves whole JSON.
func flush() -> void:
	_since_flush = 0.0
	if path.is_empty():
		return
	if _file == null:
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		_file = FileAccess.open(path, FileAccess.WRITE)
		if _file == null:
			push_error("metrics: cannot write %s" % path)
			path = ""
			return
		_file.store_string("{\"seconds\": [")
		_rows_end = _file.get_position()
	_file.seek(_rows_end)
	for row in _seconds:
		_file.store_string(("\n" if _rows == 0 else ",\n") + JSON.stringify(row))
		_rows += 1
	_seconds.clear()
	_rows_end = _file.get_position()
	_file.store_string("\n], \"info\": %s}\n" % JSON.stringify(info))
	_file.resize(_file.get_position())
	_file.flush()


static func _no_phases() -> Dictionary:
	var by := {}
	for phase in MAIN_PHASES:
		by[phase] = PackedFloat32Array()
	return by


static func main_split(times_s: Dictionary) -> Dictionary:
	var split := {}
	for phase in MAIN_PHASES:
		split[phase] = times_s[phase] * 1000.0
	return split


static func main_work_ms(split: Dictionary) -> float:
	return split.physics + split.scripts + split.sync + split.draw


static func rounded_split(split: Dictionary) -> Dictionary:
	var out := {}
	for phase in split:
		out[phase] = snappedf(split[phase], 0.1)
	return out


static func split_text(split: Dictionary) -> String:
	return ", ".join(MAIN_PHASES.map(func(phase: String) -> String: return "%s %.1f ms" % [phase, split[phase]]))


static func distribution(samples: PackedFloat32Array) -> Variant:
	if samples.is_empty():
		return null
	var sorted := Array(samples)
	sorted.sort()
	return {"p50": _q(sorted, 0.5), "p95": _q(sorted, 0.95), "max": sorted[-1]}


func close() -> void:
	_finish_row()
	flush()
	if play_log != null:
		play_log.finish()


func _exit_tree() -> void:
	close()
