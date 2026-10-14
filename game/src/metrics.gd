class_name Metrics
extends Node

## Frame-time record: every frame's delta summarised per second with the GPU time the process used in it, flushed to JSON as it goes.

var path: String
var info := {}
var _deltas: PackedFloat32Array = []
var _gpu_ns := -1
var _seconds: Array = []
var _acc := 0.0
var _since_flush := 0.0


func _init(out: String) -> void:
	path = out


func _process(delta: float) -> void:
	_deltas.append(delta * 1000.0)
	_acc += delta
	if _acc >= 1.0:
		var gpu := gpu_ns()
		var row := summary(_deltas)
		if gpu >= 0 and _gpu_ns >= 0:
			row.gpu_ms = (gpu - _gpu_ns) / 1e6
		_gpu_ns = gpu
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
static func gpu_ns() -> int:
	var dir := DirAccess.open("/proc/self/fdinfo")
	if dir == null:
		return -1
	var by_client := {}
	for fd in dir.get_files():
		var text := FileAccess.get_file_as_string("/proc/self/fdinfo/" + fd)
		var client := ""
		var ns := 0
		for line in text.split("\n"):
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


static func _q(a: Array, q: float) -> float:
	return a[clampi(int(q * (a.size() - 1)), 0, a.size() - 1)] if a.size() > 0 else 0.0


func flush() -> void:
	_since_flush = 0.0
	if path.is_empty():
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"info": info, "seconds": _seconds}, " "))
