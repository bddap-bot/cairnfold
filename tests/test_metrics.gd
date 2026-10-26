extends "res://../tests/support/suite.gd"

## The metrics file: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_metrics.gd


func _initialize() -> void:
	_every_flush_leaves_whole_json_with_every_second()
	_stalls_are_not_capped_by_engine_delta()
	_eye_frusta_swing_is_the_widest_edge_change()
	_frames_tally_by_activity()
	_late_and_refresh_follow_the_runtime_rate()
	await _a_landing_keeps_every_frame_of_its_window()
	await _head_motion_is_moving()
	_a_stall_names_what_ran_in_it()
	_a_pause_is_no_frame()
	finish()


func _read(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _every_flush_leaves_whole_json_with_every_second() -> void:
	var path := OS.get_cache_dir().path_join("cairnfold-test-metrics-%d.json" % OS.get_process_id())
	var m := Metrics.new(path)
	m.info = {"xr": false, "label": "a long label to shrink later"}
	m.flush()
	var d: Variant = _read(path)
	check(d is Dictionary and d.seconds == [] and d.info.label == "a long label to shrink later", "an empty flush is whole JSON")
	m._seconds.append({"t": 1.0})
	m._seconds.append({"t": 2.0})
	m.flush()
	m.info.label = "b"
	m._seconds.append({"t": 3.0})
	m.flush()
	d = _read(path)
	check(d is Dictionary and d.seconds.map(func(s): return s.t) == [1.0, 2.0, 3.0], "every second is kept once, in order: %s" % [d])
	check(d is Dictionary and d.info.label == "b", "info is the latest")
	m.flush()
	check(_read(path) == d, "a flush with nothing new changes nothing")
	m.free()
	DirAccess.remove_absolute(path)


func _stalls_are_not_capped_by_engine_delta() -> void:
	var m := Metrics.new("user://unused-metrics-test.json")
	m._last_tick = Time.get_ticks_usec() - 100000
	m._process(0.05)
	check(m._deltas[0] >= 99.0, "a 100 ms stall is recorded even when engine delta is capped to 50 ms")
	m.free()


func _eye_frusta_swing_is_the_widest_edge_change() -> void:
	var a := Metrics.eye_half_angles(Projection.create_frustum(-1.0, 1.0, -1.0, 1.0, 1.0, 100.0))
	check(a.size() == 4 and absf(a[0] - 45.0) < 0.001 and absf(a[3] - 45.0) < 0.001, "a symmetric 90 degree frustum has 45 degree edges: %s" % [a])
	var b := Metrics.eye_half_angles(Projection.create_frustum(-1.0, 1.2, -1.0, 1.0, 1.0, 100.0))
	var lo := a.duplicate()
	var hi := a.duplicate()
	for i in b.size():
		lo[i] = minf(lo[i], b[i])
		hi[i] = maxf(hi[i], b[i])
	check(absf(Metrics.spread(lo, hi) - (rad_to_deg(atan(1.2)) - 45.0)) < 0.001, "the swing is the widest edge's change")
	check(Metrics.spread(a, a) == 0.0, "frusta that hold still swing 0")


## A Quest 3 began the session at the shell's 90 Hz and ran it at 72: every second then read 90 Hz with 72 frames,
## and an 18 ms frame, on time at 72 Hz, counted late against 90 Hz's 16.7 ms line.
func _late_and_refresh_follow_the_runtime_rate() -> void:
	var m := Metrics.new(OS.get_cache_dir().path_join("cairnfold-test-refresh-%d.json" % OS.get_process_id()))
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
	m._finish_row()
	var row: Dictionary = m._seconds[-1]
	check(row.refresh_hz == 72.0 and row.late == 0 and row.frames == 51, "a second at 72 Hz reads 72 Hz with no 18 ms frame late: %s" % [row])
	check(m.is_late(21.0) and not m.is_late(20.0), "late is past 1.5 refresh periods of the rate the runtime runs")
	m.free()


func _frames_tally_by_activity() -> void:
	var by := {}
	Metrics.tally(by, "moving", 13.9, false, 2.0, 9.0)
	Metrics.tally(by, "moving", 30.2, true, 4.0, -1.0)
	Metrics.tally(by, "still", 13.9, false, 1.0, 8.0)
	var m: Dictionary = by.moving
	check(m.frames == 2 and m.late == 1 and is_equal_approx(m.max, 30.2), "a tag counts its frames, late ones and the worst: %s" % [m])
	check(m.hist == {"27": 1, "60": 1}, "frame times fall in half-millisecond bins: %s" % [m.hist])
	check(is_equal_approx(m.cpu_ms, 6.0) and is_equal_approx(m.gpu_ms, 9.0) and m.gpu_frames == 1, "GPU time sums only over frames that have one")
	check(by.still.frames == 1, "tags count apart")
	var row: Variant = JSON.parse_string(JSON.stringify(by))
	check(row.moving.hist["27"] == 1, "the histogram survives JSON")


## The Frame's bench read a landing's one moving frame, 15 ms, as the worst of its second, which held a 21 ms frame.
func _a_landing_keeps_every_frame_of_its_window() -> void:
	var m := Metrics.new(OS.get_cache_dir().path_join("cairnfold-test-landing-%d.json" % OS.get_process_id()))
	m.info = {"refresh_hz": 72.0, "label": "-"}
	var origin := Node3D.new()
	var head := Node3D.new()
	origin.add_child(head)
	root.add_child(origin)
	await process_frame
	m.head = head
	var frame := func(ms: float) -> void:
		m._last_tick = Time.get_ticks_usec() - int(ms * 1000.0)
		m._process(ms / 1000.0)
	frame.call(13.9)
	m._acc = 0.0
	m.info.label = "standing/along"
	origin.position = Vector3(-10.5, 4.5, 3.5)
	frame.call(15.0)
	for i in 10:
		frame.call(13.9)
	frame.call(21.3)
	for i in 40:
		frame.call(13.9)
	frame.call(30.0)
	var w: Dictionary = m._landings[0]
	check(m._landings.size() == 1 and w.label == "standing/along", "one move opens one window under its phase: %s" % [m._landings])
	check(w.frames_ms[0] >= 15.0 and w.frames_ms[0] < 15.5, "the window starts at the frame the origin is seen moved in: %s" % [w.frames_ms.slice(0, 3)])
	check(w.max >= 21.3 and w.max < 22.0 and w.late == 1, "a late frame after the move frame counts against the landing: %s" % [w])
	var lasted: float = w.frames_ms.reduce(func(a: float, b: float) -> float: return a + b, 0.0)
	check(lasted >= Metrics.LANDING_S * 1000.0 and lasted < Metrics.LANDING_S * 1000.0 + 25.0, "the window lasts LANDING_S: %s ms" % lasted)
	m._landings.clear()
	for i in 10:
		origin.position.x += 0.01
		frame.call(13.9)
	check(m._landings.is_empty() and m._landing.frames_ms.size() == 10, "a glide is one landing, not one a frame: %s" % [m._landing])
	m._landing = {}
	frame.call(13.9)
	origin.rotate_y(0.5)
	frame.call(13.9)
	check(not m._landing.is_empty(), "turning the play space in place is a landing")
	frame.call(13.9)
	origin.position.x += 1.0
	m._acc = 1.0
	frame.call(13.9)
	m._finish_row()
	var row: Dictionary = m._seconds[-1]
	check(m._landings.is_empty() and row.landings.size() == 1 and row.landings[0].frames_ms.size() == 2, "a window closed by the next move goes out with its second: %s" % [row.get("landings")])
	origin.free()
	m.free()


func _head_motion_is_moving() -> void:
	var m := Metrics.new("")
	var head := Node3D.new()
	root.add_child(head)
	await process_frame
	m.head = head
	check(m._tags(1.0 / 72.0) == ["still"], "the first frame has no motion to measure")
	check(m._tags(1.0 / 72.0) == ["still"], "a head holding still is still")
	head.rotate_y(deg_to_rad(1.0))
	check(m._tags(1.0 / 72.0) == ["moving"], "a head turning 72 degrees a second is moving")
	head.position.x += 0.001
	check(m._tags(1.0 / 72.0) == ["still"], "a head drifting 7 cm a second is still")
	m.activity = func() -> Array: return ["building", "coop"]
	check(m._tags(1.0 / 72.0) == ["building", "coop"], "building is not still, and co-op counts beside it")
	m.activity = func() -> Array: return ["coop"]
	check(m._tags(1.0 / 72.0) == ["coop", "still"], "co-op alone is still too")
	head.free()
	m.free()


## A wipe held a Quest 3's frame for 437 ms in a played session whose record could not say what had run.
func _a_stall_names_what_ran_in_it() -> void:
	var m := Metrics.new(OS.get_cache_dir().path_join("cairnfold-test-stall-%d.json" % OS.get_process_id()))
	m.info = {"refresh_hz": 72.0, "label": "-"}
	var frame := func(ms: float) -> void:
		m._last_tick = Time.get_ticks_usec() - int(ms * 1000.0)
		m._process(ms / 1000.0)
	frame.call(13.9)
	Metrics.note("world: applying wipe", 420.0)
	Metrics.note("world: applying paint", 1.0)
	m._acc = 1.0
	frame.call(430.0)
	check(m._seconds.is_empty(), "the stall's second waits for the frame after it, which reports its script time")
	frame.call(13.9)
	m._finish_row()
	var row: Dictionary = m._seconds[-1]
	var stalls: Array = row.get("stalls", [])
	check(stalls.size() == 1 and stalls[0].ms >= 430.0 and stalls[0].ms < 435.0, "the stall is listed with its length: %s" % [stalls])
	check(not stalls.is_empty() and stalls[0].notes == [{"what": "world: applying wipe", "ms": 420.0}], "with the long work noted in it and not the short: %s" % [stalls])
	check(not stalls.is_empty() and stalls[0].has("scripts_after_ms") and stalls[0].tags == ["still"], "its script time after it, and what the player was doing")
	frame.call(13.9)
	m._acc = 1.0
	frame.call(13.9)
	m._finish_row()
	check(not m._seconds[-1].has("stalls"), "a second without one lists none")
	m.free()


## Headset-off spans read as frames of a minute and more in a played session's worst frames.
func _a_pause_is_no_frame() -> void:
	var m := Metrics.new(OS.get_cache_dir().path_join("cairnfold-test-pause-%d.json" % OS.get_process_id()))
	m.info = {"refresh_hz": 72.0, "label": "-"}
	var frame := func(ms: float) -> void:
		m._last_tick = Time.get_ticks_usec() - int(ms * 1000.0)
		m._process(ms / 1000.0)
	frame.call(13.9)
	m._notification(Node.NOTIFICATION_UNPAUSED)
	frame.call(60000.0)
	m._acc = 1.0
	frame.call(13.9)
	m._finish_row()
	var row: Dictionary = m._seconds[-1]
	check(absf(row.get("paused_s", 0.0) - 60.0) < 0.1, "the paused span is counted as paused: %s" % [row])
	check(row.max < 20.0 and row.frames == 2 and not row.has("stalls"), "and is no frame, nor a stall: %s" % [row])
	m.free()
