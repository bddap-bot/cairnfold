class_name Metrics
extends Node

## Frame-time record: every frame's delta summarised per second with the GPU time the process used in it, the
## most draw calls and primitives any frame drew, and the viewport's GPU time per frame and the lowest quality
## step the governor took (see Quality), flushed to JSON as it goes.

var path: String
var info := {}
var quality: Quality
## The tracked head, whose height above the play area's floor each second records.
var head: Node3D
var _step := 0
var _viewport_ms := 0.0
var _viewport_frames := 0
var _deltas: PackedFloat32Array = []
## Whether the last frame ran over 1.5× the refresh period; only the first of a run of late frames is logged.
var _late := false
var _gpu_ns := -1
var _drm_fds: PackedStringArray = []
## Counts readings; every tenth looks for the DRM clients again, since the runtime may open more later.
var _drm_scan := 0
var _draws := 0
var _prims := 0
var _seconds: Array = []
var _acc := 0.0
var _since_flush := 0.0


func _init(out: String) -> void:
	path = out


func _process(delta: float) -> void:
	_deltas.append(delta * 1000.0)
	var hz: float = info.get("refresh_hz", 0.0)
	var late := hz > 0.0 and delta * 1000.0 > 1500.0 / hz
	if late and not _late:
		print("metrics: late frame %.1f ms" % (delta * 1000.0))
	_late = late
	_draws = maxi(_draws, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	_prims = maxi(_prims, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	if quality != null and quality.fresh:
		_step = maxi(_step, quality.step())
		_viewport_ms += quality.frame_ms
		_viewport_frames += 1
	_acc += delta
	if _acc >= 1.0:
		var gpu := gpu_ns()
		var row := summary(_deltas)
		if gpu >= 0 and _gpu_ns >= 0:
			row.gpu_ms = (gpu - _gpu_ns) / 1e6
		_gpu_ns = gpu
		row.draws = _draws
		if head != null:
			row.head_m = snappedf(head.position.y, 0.01)
		row.prims = _prims
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
		_seconds.append(row)
		_deltas.clear()
		_acc = 0.0
		_since_flush += 1.0
		if _since_flush >= 5.0:
			flush()


func summary(d: PackedFloat32Array) -> Dictionary:
	var ds := Array(d)
	ds.sort()
	var hz: float = info.get("refresh_hz", 0.0)
	var late := 0
	if hz > 0.0:
		for x in ds:
			if x > 1500.0 / hz:
				late += 1
	return {"t": Time.get_ticks_msec() / 1000.0, "frames": ds.size(), "p50": _q(ds, 0.5), "p95": _q(ds, 0.95), "p99": _q(ds, 0.99), "max": ds[-1], "late": late, "label": info.get("label", "")}


## GPU time this process has used, summed over its DRM clients, from the kernel's fdinfo; -1 where the driver reports none.
func gpu_ns() -> int:
	if _drm_scan % 10 == 0:
		var dir := DirAccess.open("/proc/self/fdinfo")
		if dir == null:
			return -1
		_drm_fds.clear()
		for fd in dir.get_files():
			if _fdinfo(fd).contains("drm-client-id:"):
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


func flush() -> void:
	_since_flush = 0.0
	if path.is_empty():
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"info": info, "seconds": _seconds}, " "))
