extends SceneTree

## Headless checks of the animals' calls: godot4 --headless --path game --script ../tests/test_calls.gd

const STEP := 1.0 / 30.0

var failures := 0


func _initialize() -> void:
	_every_clip_is_sourced()
	await _calls_are_sparse_and_varied()
	await _animals_near_the_head_stay_calm()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


## Each clip the game plays is cut by sources.json from a recording whose page, author and licence it names,
## and every clip cut there is played.
func _every_clip_is_sourced() -> void:
	var sources: Array = JSON.parse_string(FileAccess.get_file_as_string("res://audio/animals/sources.json"))
	var cut := {}
	for s: Dictionary in sources:
		_check(s.page.begins_with("https://") and s.audio.begins_with("https://") and not s.author.is_empty(), "%s names where it is from" % s.title)
		_check(s.licence.begins_with("CC0"), "%s is CC0" % s.title)
		for name in s.clips:
			cut[name] = true
	var played := {}
	for kind in Calls.CLIPS:
		for i in Calls.CLIPS[kind]:
			var name := "%s%d" % [kind, i]
			played[name] = true
			_check(cut.has(name), "%s is cut from a listed recording" % name)
			_check(load("res://audio/animals/%s.ogg" % name) != null, "%s loads" % name)
	for name in cut:
		_check(played.has(name), "%s is played" % name)
	for f in DirAccess.get_files_at("res://audio/animals"):
		if f.ends_with(".ogg"):
			_check(played.has(f.get_basename()), "%s is played" % f)


func _calls(far := true) -> Calls:
	var eyes := Node3D.new()
	root.add_child(eyes)
	eyes.position = Vector3(0, 1.6, 0) if far else Vector3(10, 1.6, 0)
	var c := Calls.new(eyes, 3)
	root.add_child(c)
	await process_frame
	return c


func _calls_are_sparse_and_varied() -> void:
	var c: Calls = await _calls()
	var at := Vector3(10, 1, 0)
	_check(c.call_out("chirp", at), "a first chirp calls")
	_check(not c.call_out("chirp", at), "a second chirp right after does not")
	_check(not c.call_out("bleat", at), "nor does another kind right after")
	for i in int(Calls.ANY_GAP / STEP) + 1:
		c.tick(STEP)
	_check(c.call_out("bleat", at), "another kind calls once the calls are apart")
	var heard := 0
	var last: AudioStream = null
	var repeats := 0
	for i in int(600.0 / STEP):
		c.tick(STEP)
		if c.now_and_then("quack", at, 20.0, STEP):
			heard += 1
			var playing := c._voices[(c._next_voice + Calls.VOICES - 1) % Calls.VOICES].stream
			repeats += int(playing == last)
			last = playing
	_check(heard >= 600.0 / 40.0 and heard <= 600.0 / Calls.GAP["quack"], "%d quacks in ten minutes at one each 20 s" % heard)
	_check(repeats == 0, "%d quacks repeated the one before" % repeats)
	await process_frame


func _animals_near_the_head_stay_calm() -> void:
	var c: Calls = await _calls(false)
	var near := Vector3(11, 1.2, 0)
	var heard := 0
	for i in int(300.0 / STEP):
		c.tick(STEP)
		heard += int(c.now_and_then("chatter", near, 10.0, STEP))
	_check(heard == 0, "a conure beside the head chattered %d times" % heard)
	_check(c.call_out("quack", near), "a duck landing beside the head still quacks")
