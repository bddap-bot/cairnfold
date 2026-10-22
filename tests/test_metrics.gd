extends SceneTree

## The metrics file: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_metrics.gd

var failures := 0


func _initialize() -> void:
	_every_flush_leaves_whole_json_with_every_second()
	_stalls_are_not_capped_by_engine_delta()
	_eye_frusta_swing_is_the_widest_edge_change()
	_frames_tally_by_activity()
	_late_and_refresh_follow_the_runtime_rate()
	await _head_motion_is_moving()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _read(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _every_flush_leaves_whole_json_with_every_second() -> void:
	var path := OS.get_cache_dir().path_join("nestcombe-test-metrics-%d.json" % OS.get_process_id())
	var m := Metrics.new(path)
	m.info = {"xr": false, "label": "a long label to shrink later"}
	m.flush()
	var d: Variant = _read(path)
	_check(d is Dictionary and d.seconds == [] and d.info.label == "a long label to shrink later", "an empty flush is whole JSON")
	m._seconds.append({"t": 1.0})
	m._seconds.append({"t": 2.0})
	m.flush()
	m.info.label = "b"
	m._seconds.append({"t": 3.0})
	m.flush()
	d = _read(path)
	_check(d is Dictionary and d.seconds.map(func(s): return s.t) == [1.0, 2.0, 3.0], "every second is kept once, in order: %s" % [d])
	_check(d is Dictionary and d.info.label == "b", "info is the latest")
	m.flush()
	_check(_read(path) == d, "a flush with nothing new changes nothing")
	m.free()
	DirAccess.remove_absolute(path)


func _stalls_are_not_capped_by_engine_delta() -> void:
	var m := Metrics.new("user://unused-metrics-test.json")
	m._last_tick = Time.get_ticks_usec() - 100000
	m._process(0.05)
	_check(m._deltas[0] >= 99.0, "a 100 ms stall is recorded even when engine delta is capped to 50 ms")
	m.free()


func _eye_frusta_swing_is_the_widest_edge_change() -> void:
	var a := Metrics.eye_half_angles(Projection.create_frustum(-1.0, 1.0, -1.0, 1.0, 1.0, 100.0))
	_check(a.size() == 4 and absf(a[0] - 45.0) < 0.001 and absf(a[3] - 45.0) < 0.001, "a symmetric 90 degree frustum has 45 degree edges: %s" % [a])
	var b := Metrics.eye_half_angles(Projection.create_frustum(-1.0, 1.2, -1.0, 1.0, 1.0, 100.0))
	var lo := a.duplicate()
	var hi := a.duplicate()
	for i in b.size():
		lo[i] = minf(lo[i], b[i])
		hi[i] = maxf(hi[i], b[i])
	_check(absf(Metrics.spread(lo, hi) - (rad_to_deg(atan(1.2)) - 45.0)) < 0.001, "the swing is the widest edge's change")
	_check(Metrics.spread(a, a) == 0.0, "frusta that hold still swing 0")


## A Quest 3 began the session at the shell's 90 Hz and ran it at 72: every second then read 90 Hz with 72 frames,
## and an 18 ms frame, on time at 72 Hz, counted late against 90 Hz's 16.7 ms line.
func _late_and_refresh_follow_the_runtime_rate() -> void:
	var m := Metrics.new(OS.get_cache_dir().path_join("nestcombe-test-refresh-%d.json" % OS.get_process_id()))
	m.info = {"refresh_hz": 90.0}
	var hz := [90.0]
	m.refresh = func() -> float: return hz[0]
	hz[0] = 72.0
	for i in 50:
		m._last_tick = Time.get_ticks_usec() - 18000
		m._process(0.018)
	m._acc = 1.0
	m._last_tick = Time.get_ticks_usec() - 13900
	m._process(0.0139)
	var row: Dictionary = m._seconds[-1]
	_check(row.refresh_hz == 72.0 and row.late == 0 and row.frames == 51, "a second at 72 Hz reads 72 Hz with no 18 ms frame late: %s" % [row])
	_check(m.is_late(21.0) and not m.is_late(20.0), "late is past 1.5 refresh periods of the rate the runtime runs")
	m.free()


func _frames_tally_by_activity() -> void:
	var by := {}
	Metrics.tally(by, "moving", 13.9, false, 2.0, 9.0)
	Metrics.tally(by, "moving", 30.2, true, 4.0, -1.0)
	Metrics.tally(by, "still", 13.9, false, 1.0, 8.0)
	var m: Dictionary = by.moving
	_check(m.frames == 2 and m.late == 1 and is_equal_approx(m.max, 30.2), "a tag counts its frames, late ones and the worst: %s" % [m])
	_check(m.hist == {"27": 1, "60": 1}, "frame times fall in half-millisecond bins: %s" % [m.hist])
	_check(is_equal_approx(m.cpu_ms, 6.0) and is_equal_approx(m.gpu_ms, 9.0) and m.gpu_frames == 1, "GPU time sums only over frames that have one")
	_check(by.still.frames == 1, "tags count apart")
	var row: Variant = JSON.parse_string(JSON.stringify(by))
	_check(row.moving.hist["27"] == 1, "the histogram survives JSON")


func _head_motion_is_moving() -> void:
	var m := Metrics.new("")
	var head := Node3D.new()
	root.add_child(head)
	await process_frame
	m.head = head
	_check(m._tags(1.0 / 72.0) == ["still"], "the first frame has no motion to measure")
	_check(m._tags(1.0 / 72.0) == ["still"], "a head holding still is still")
	head.rotate_y(deg_to_rad(1.0))
	_check(m._tags(1.0 / 72.0) == ["moving"], "a head turning 72 degrees a second is moving")
	head.position.x += 0.001
	_check(m._tags(1.0 / 72.0) == ["still"], "a head drifting 7 cm a second is still")
	m.activity = func() -> Array: return ["building", "coop"]
	_check(m._tags(1.0 / 72.0) == ["building", "coop"], "building is not still, and co-op counts beside it")
	m.activity = func() -> Array: return ["coop"]
	_check(m._tags(1.0 / 72.0) == ["coop", "still"], "co-op alone is still too")
	head.free()
	m.free()
