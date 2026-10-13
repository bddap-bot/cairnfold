class_name Metrics
extends Node

## Frame-time record: every frame's delta and GPU time, summarised per second, flushed to JSON as it goes.

var path: String
var info := {}
var _deltas: PackedFloat32Array = []
var _gpu: PackedFloat32Array = []
var _seconds: Array = []
var _acc := 0.0
var _since_flush := 0.0


func _init(out: String) -> void:
	path = out


func _ready() -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _process(delta: float) -> void:
	_deltas.append(delta * 1000.0)
	_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
	_acc += delta
	if _acc >= 1.0:
		_seconds.append(summary(_deltas, _gpu))
		_deltas.clear()
		_gpu.clear()
		_acc = 0.0
		_since_flush += 1.0
		if _since_flush >= 5.0:
			flush()


func summary(d: PackedFloat32Array, g: PackedFloat32Array) -> Dictionary:
	var ds := Array(d)
	ds.sort()
	var gs := Array(g)
	gs.sort()
	var hz: float = info.get("refresh_hz", 0.0)
	var late := 0
	if hz > 0.0:
		for x in ds:
			if x > 1500.0 / hz:
				late += 1
	return {"t": Time.get_ticks_msec() / 1000.0, "frames": ds.size(), "p50": _q(ds, 0.5), "p95": _q(ds, 0.95), "p99": _q(ds, 0.99), "max": ds[-1], "late": late, "gpu_p50": _q(gs, 0.5), "gpu_p95": _q(gs, 0.95), "label": info.get("label", "")}


static func _q(a: Array, q: float) -> float:
	return a[clampi(int(q * (a.size() - 1)), 0, a.size() - 1)] if a.size() > 0 else 0.0


func flush() -> void:
	_since_flush = 0.0
	if path.is_empty():
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"info": info, "seconds": _seconds}, " "))
