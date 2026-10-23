class_name Metrics
extends Node

## Frame-time record: every frame's delta summarised per second with the GPU time the process used in it, the
## most draw calls and primitives any frame drew, and the viewport's GPU time per frame and the lowest quality
## step the governor took (see Quality), and the frames again by what the player was doing in each (ACTIVITIES),
## flushed to JSON as it goes.

var path: String
var info := {}
var play_log: PlayLog
var context: Callable
## The tags (ACTIVITIES) of what the player is doing this frame besides moving, which the head's own motion decides.
var activity: Callable
var _cpu: PackedFloat32Array = []
var _gpu: PackedFloat32Array = []
var _logging_us := 0
var _last_tick := Time.get_ticks_usec()
var quality: Quality
## The tracked head, whose height above the play area's floor each second records, with where its play
## space's origin ended the second and in how many frames it moved: any move the player did not make is a bug.
var head: Node3D
## The garden, whose share of the frame budget (World.fill) each second records.
var world: World
var _origin: Vector3
var _origin_moves := 0
var _step := 0
var _viewport_ms := 0.0
var _viewport_frames := 0
var _deltas: PackedFloat32Array = []
## Whether the last frame ran over 1.5× the refresh period; only the first of a run of late frames is logged.
var _was_late := false
var _gpu_ns := -1
var _drm_fds: PackedStringArray = []
## Counts readings; every tenth looks for the DRM clients again, since the runtime may open more later.
var _drm_scan := 0
var _draws := 0
var _prims := 0
## Pipelines compiled so far, the last frame: x while drawing, which holds the frame, y on worker threads.
var _compiled := Vector2i()
## The headset whose eyes' frusta each second records the widest swing of: the sun's shadow map is fitted to them
## every frame, and holds still only while they do.
var xr: XRInterface
## The refresh rate the runtime runs at now, read every frame: a Quest begins the session at the shell's rate and
## switches the panel to the game's a few seconds later, so the rate read as the session begins can be stale.
var refresh: Callable
var _eye_lo := PackedFloat32Array()
var _eye_hi := PackedFloat32Array()
## A frame's tags: each frame counts once in each of its tags, and in "still" when it has none of the first three.
const ACTIVITIES := ["moving", "building", "wheel", "still", "coop"]
## Faster than this the head is moving: what a player feels is the frame rate while it does.
const MOVING_DEG_S := 30.0
const MOVING_M_S := 0.3
## Frame-time histogram bins per millisecond: fine enough for p99 against a 11 ms refresh, and merges exactly.
const BINS_PER_MS := 2
## This second's frames by tag, as `tally` keeps them.
var _by_activity := {}
var _head_was: Variant = null
## Seconds not yet written.
var _seconds: Array = []
var _file: FileAccess
var _rows := 0
var _rows_end := 0
var _acc := 0.0
var _since_flush := 0.0


func _init(out: String) -> void:
	path = out


func _process(_delta: float) -> void:
	if play_log == null and path.is_empty():
		return
	if refresh.is_valid():
		var hz: float = refresh.call()
		if hz > 0.0 and hz != info.get("refresh_hz", 0.0):
			print("metrics: running at %s Hz" % hz)
			info.refresh_hz = hz
	var now := Time.get_ticks_usec()
	# Engine delta is capped during stalls.
	var elapsed := (now - _last_tick) / 1000000.0
	_last_tick = now
	_deltas.append(elapsed * 1000.0)
	_cpu.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	var late := is_late(elapsed * 1000.0)
	var compiled := _compilations()
	if late and not _was_late:
		var scripts := Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		print("metrics: late frame %.1f ms, the frame before it %.1f ms in scripts and physics, %.1f ms on the GPU, %d pipelines compiled while drawing and %d on worker threads" % [elapsed * 1000.0, scripts * 1000.0, quality.frame_ms if quality != null else 0.0, compiled.x - _compiled.x, compiled.y - _compiled.y])
	_compiled = compiled
	_was_late = late
	var cpu_ms := _cpu[-1]
	var gpu_ms := quality.frame_ms if quality != null and quality.fresh else -1.0
	for tag in _tags(elapsed):
		tally(_by_activity, tag, elapsed * 1000.0, late, cpu_ms, gpu_ms)
	_draws = maxi(_draws, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	_prims = maxi(_prims, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	if quality != null and quality.fresh:
		_step = maxi(_step, quality.step())
		_gpu.append(quality.frame_ms)
		_viewport_ms += quality.frame_ms
		_viewport_frames += 1
	if xr != null and xr.is_initialized():
		var now_eyes := eye_half_angles(xr.get_projection_for_view(0, 1.0, 0.05, 400.0)) + eye_half_angles(xr.get_projection_for_view(1, 1.0, 0.05, 400.0))
		if _eye_lo.is_empty():
			_eye_lo = now_eyes.duplicate()
			_eye_hi = now_eyes.duplicate()
		for i in now_eyes.size():
			_eye_lo[i] = minf(_eye_lo[i], now_eyes[i])
			_eye_hi[i] = maxf(_eye_hi[i], now_eyes[i])
	if head != null:
		var o := head.get_parent_node_3d().global_position
		if o != _origin:
			_origin_moves += 1
			_origin = o
	_acc += elapsed
	if _acc >= 1.0:
		var begin := Time.get_ticks_usec()
		var gpu := gpu_ns() if not path.is_empty() else -1
		var row := summary(_deltas)
		if gpu >= 0 and _gpu_ns >= 0:
			row.gpu_ms = (gpu - _gpu_ns) / 1e6
		_gpu_ns = gpu
		row.draws = _draws
		if head != null:
			row.head_m = snappedf(head.position.y, 0.01)
			row.origin = [snappedf(_origin.x, 0.001), snappedf(_origin.y, 0.001), snappedf(_origin.z, 0.001)]
			row.origin_moves = _origin_moves
			_origin_moves = 0
		row.prims = _prims
		if not _eye_lo.is_empty():
			row.eye_fov_spread_deg = spread(_eye_lo, _eye_hi)
			_eye_lo = PackedFloat32Array()
			_eye_hi = PackedFloat32Array()
		row.activity = _by_activity
		_by_activity = {}
		if world != null:
			row.fill = snappedf(world.fill(), 0.001)
		_draws = 0
		_prims = 0
		if _viewport_frames > 0:
			row.viewport_gpu_ms = _viewport_ms / _viewport_frames
			row.step = _step
			if quality.budget_ms > 0.0:
				row.budget_ms = quality.budget_ms
		_step = quality.step() if quality != null else 0
		_viewport_ms = 0.0
		_viewport_frames = 0
		row.unix = Time.get_unix_time_from_system()
		row.cpu_ms = distribution(_cpu)
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
		if play_log != null:
			play_log.sample(row)
		_cpu.clear()
		_gpu.clear()
		if not path.is_empty():
			_seconds.append(row)
		_logging_us = Time.get_ticks_usec() - begin
		_deltas.clear()
		_acc = 0.0
		_since_flush += 1.0
		if _since_flush >= 5.0:
			flush()


## This frame's tags: moving from the head's motion over `elapsed` seconds, the rest from `activity`.
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


## Counts a frame of `ms` under `tag` in `into`: frames, late frames, the worst, a histogram of BINS_PER_MS bins a
## millisecond keyed by bin, and the CPU and, where `gpu_ms` is not negative, GPU time summed.
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


static func _compilations() -> Vector2i:
	return Vector2i(int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW)), int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION) + Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE) + Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH)))


## Left, right, down and up half-angles of an eye's frustum, in degrees.
static func eye_half_angles(p: Projection) -> PackedFloat32Array:
	return PackedFloat32Array([rad_to_deg(atan((1.0 - p.z.x) / p.x.x)), rad_to_deg(atan((1.0 + p.z.x) / p.x.x)),
		rad_to_deg(atan((1.0 - p.z.y) / p.y.y)), rad_to_deg(atan((1.0 + p.z.y) / p.y.y))])


## The widest of the swings between each pair of lowest and highest.
static func spread(lo: PackedFloat32Array, hi: PackedFloat32Array) -> float:
	var most := 0.0
	for i in lo.size():
		most = maxf(most, hi[i] - lo[i])
	return most


func summary(d: PackedFloat32Array) -> Dictionary:
	var ds := Array(d)
	ds.sort()
	var late := 0
	for x in ds:
		if is_late(x):
			late += 1
	return {"t": Time.get_ticks_msec() / 1000.0, "frames": ds.size(), "p50": _q(ds, 0.5), "p95": _q(ds, 0.95), "p99": _q(ds, 0.99), "max": ds[-1], "late": late, "label": info.get("label", "")}


## Whether a frame of `ms` ran over 1.5× the refresh period.
func is_late(ms: float) -> bool:
	var hz: float = info.get("refresh_hz", 0.0)
	return hz > 0.0 and ms > 1500.0 / hz


## GPU time this process has used, summed over its DRM clients, from the kernel's fdinfo; -1 where the driver reports none.
func gpu_ns() -> int:
	if _drm_scan % 10 == 0:
		var dir := DirAccess.open("/proc/self/fd")
		if dir == null:
			return -1
		_drm_fds.clear()
		# Reading every fd's info held the Steam Frame's main thread for up to 15 ms, enough to drop a second to every
		# other refresh. A link is read without the kernel writing anything, and a DRM fd's info is read once a second.
		for fd in dir.get_files():
			if dir.read_link(fd).begins_with("/dev/dri/"):
				_drm_fds.append(fd)
	_drm_scan += 1
	var by_client := {}
	for fd in _drm_fds:
		var client := ""
		var ns := 0
		for line in _fdinfo(fd).split("\n"):
			if line.begins_with("drm-client-id:"):
				client = line.get_slice(":", 1).strip_edges()
			elif line.begins_with("drm-engine-") and not line.begins_with("drm-engine-capacity"):
				ns += int(line.get_slice(":", 1).strip_edges().get_slice(" ", 0))
		if client != "":
			by_client[client] = ns
	if by_client.is_empty():
		return -1
	var total := 0
	for v in by_client.values():
		total += v
	return total


## procfs reports no length, and the kernel writes a DRM fd's info afresh on every read, so it is taken in one read.
static func _fdinfo(fd: String) -> String:
	var f := FileAccess.open("/proc/self/fdinfo/" + fd, FileAccess.READ)
	return f.get_buffer(65536).get_string_from_utf8() if f != null else ""


static func _q(a: Array, q: float) -> float:
	return a[clampi(int(q * (a.size() - 1)), 0, a.size() - 1)] if a.size() > 0 else 0.0


## Appends the seconds since the last flush and rewrites only the closing `info`, so a flush costs the same in the
## second hour as in the first and the file is whole JSON after each one.
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


static func distribution(samples: PackedFloat32Array) -> Variant:
	if samples.is_empty():
		return null
	var sorted := Array(samples)
	sorted.sort()
	return {"p50": _q(sorted, 0.5), "p95": _q(sorted, 0.95), "max": sorted[-1]}


func close() -> void:
	flush()
	if play_log != null:
		play_log.finish()


func _exit_tree() -> void:
	close()
