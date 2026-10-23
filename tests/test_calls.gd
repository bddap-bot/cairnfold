extends "res://../tests/support/suite.gd"

## Headless checks of the animals' calls: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_calls.gd

const STEP := 1.0 / 30.0


func _initialize() -> void:
	_every_clip_is_sourced()
	_every_conure_doing_has_its_calls()
	await _calls_are_sparse_and_varied()
	await _animals_near_the_head_stay_calm()
	finish()


## Each clip the game plays is cut by sources.json from a recording whose page, author and licence it names,
## and every clip cut there is played.
func _every_clip_is_sourced() -> void:
	var sources: Array = JSON.parse_string(FileAccess.get_file_as_string("res://audio/animals/sources.json"))
	var cut := {}
	for s: Dictionary in sources:
		check(s.page.begins_with("https://") and s.audio.begins_with("https://") and not s.author.is_empty(), "%s names where it is from" % s.title)
		check(s.licence.begins_with("CC0"), "%s is CC0" % s.title)
		for name in s.clips:
			cut[name] = true
	var played := {}
	for kind in Calls.CALLS:
		for i in Calls.CALLS[kind].clips:
			var name := "%s%d" % [kind, i]
			played[name] = true
			check(cut.has(name), "%s is cut from a listed recording" % name)
			check(load("res://audio/animals/%s.ogg" % name) != null, "%s loads" % name)
	for name in cut:
		check(played.has(name), "%s is played" % name)
	for f in DirAccess.get_files_at("res://audio/animals"):
		if f.ends_with(".ogg"):
			check(played.has(f.get_basename()), "%s is played" % f)


## Whatever a conure is doing, it has calls of its own for it, and each is a call with clips.
func _every_conure_doing_has_its_calls() -> void:
	var doings: Array = Birds.State.keys() + ["PREEN", "WATCH"]
	check(Birds.VOICE.keys().all(func(d: String) -> bool: return d in doings), "every voiced doing is one a conure does")
	var kinds := {}
	for doing: String in doings:
		var calls: Array = Birds.VOICE.get(doing, [])
		check(not calls.is_empty(), "a conure says something while %s" % doing)
		for call: Array in calls:
			check(Calls.CALLS.has(call[0]) and call[1] > 0.0, "%s's %s is a call with clips" % [doing, call[0]])
			kinds[call[0]] = true
	check(kinds.size() >= 6, "conures have %d kinds of call" % kinds.size())


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
	check(c.call_out("chirp", at), "a first chirp calls")
	check(not c.call_out("chirp", at), "a second chirp right after does not")
	check(not c.call_out("bleat", at), "nor does another kind right after")
	for i in int(Calls.ANY_GAP / STEP) + 1:
		c.tick(STEP)
	check(c.call_out("bleat", at), "another kind calls once the calls are apart")
	for i in int(Calls.ANY_GAP / STEP) + 1:
		c.tick(STEP)
	check(c.call_out("murmur", at), "a murmur calls")
	check(c.call_out("quack", at), "and holds off no other call")
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
	check(heard >= 600.0 / 40.0 and heard <= 600.0 / Calls.CALLS.quack.gap, "%d quacks in ten minutes at one each 20 s" % heard)
	check(repeats == 0, "%d quacks repeated the one before" % repeats)
	await process_frame


func _animals_near_the_head_stay_calm() -> void:
	var c: Calls = await _calls(false)
	var near := Vector3(11, 1.2, 0)
	var heard := 0
	for i in int(300.0 / STEP):
		c.tick(STEP)
		heard += int(c.now_and_then("chatter", near, 10.0, STEP))
	check(heard == 0, "a conure beside the head chattered %d times" % heard)
	for i in int(60.0 / STEP):
		c.tick(STEP)
		heard += int(c.now_and_then("murmur", near, 10.0, STEP))
	check(heard > 0, "a conure beside the head murmurs")
	check(c.call_out("quack", near), "a duck landing beside the head still quacks")
