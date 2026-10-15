extends SceneTree

## The metrics file: godot4 --headless --path game --script ../tests/test_metrics.gd

var failures := 0


func _initialize() -> void:
	_every_flush_leaves_whole_json_with_every_second()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	quit(1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _read(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _every_flush_leaves_whole_json_with_every_second() -> void:
	var path := OS.get_cache_dir().path_join("cairnfold-test-metrics-%d.json" % OS.get_process_id())
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
