extends "res://../tests/support/suite.gd"

## Headless checks of what a photo says of itself (PhotoMeta): written into the PNG, read back, and opened as the
## garden it shows: godot4 --headless --path game --script ../tests/test_photo_meta.gd

var dir := ""


func _initialize() -> void:
	boot_main()
	_run.call_deferred()


func _run() -> void:
	await process_frame
	dir = OS.get_temp_dir().path_join("nestcombe-photo-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(dir)
	check(PhotoMeta.crc32("123456789".to_ascii_buffer()) == 0xCBF43926, "the chunk checksum is PNG's CRC-32")
	await _a_photo_carries_where_and_how_and_opens_as_its_garden()
	_a_garden_too_big_is_left_out_and_says_so()
	_a_damaged_chunk_is_not_read()
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
	finish()


func _play(steps: Array) -> void:
	var d := Driver.new(main, steps)
	main.add_child(d)
	await d.finished
	d.queue_free()


func _png() -> PackedByteArray:
	return Image.create(64, 48, false, Image.FORMAT_RGB8).save_png_to_buffer()


func _a_photo_carries_where_and_how_and_opens_as_its_garden() -> void:
	var bare := main.world.snapshot()
	await _play([
		{"op": "wall", "points": [[-6, -4], [6, -4]], "seconds": 0.3},
		{"op": "tree", "x": 4, "z": 4},
		{"op": "paint", "tool": "flowers", "points": [[-4, 4], [-3, 4]], "radius": 1.0, "seconds": 0.3},
		{"op": "sculpt", "x": 10, "z": 10, "lift": 1.5, "seconds": 0.3},
	])
	main.look.set_time(0.8)
	var picture := var_to_str(main.world.digest())
	var lens := Transform3D(Basis(Vector3.UP, 0.6) * Basis(Vector3.RIGHT, -0.2), Vector3(3, 1.4, 7))
	var around := main._photo_scene()
	var about: Dictionary = around.about.duplicate()
	about.merge({"build": Main.revision(), "settings": PhotoTool.settings(),
		"camera": {"position": PhotoTool._floats(lens.origin), "rotation": PhotoTool._floats(lens.basis.get_rotation_quaternion()), "fov": PhotoTool.FOV}})
	var png := PhotoMeta.embed(_png(), about, around.world)
	check(Image.new().load_png_from_buffer(png) == OK, "a photo with its garden in it is still a PNG")
	check(about.world.has("embedded"), "a small garden goes into the photo: %s" % about.world)
	var got := PhotoMeta.read(png)
	check(got.about.time_of_day == 0.8 and got.about.garden.commands == main.world.seq and got.about.garden.meadow_seed == Meadow.SEED and got.about.build == Main.revision(), "the photo says when in the day, which garden and which build: %s" % got.get("about"))
	check(got.about.settings.msaa == 8 and got.about.settings.size == [3200.0, 2400.0], "and what it was drawn with")
	check(PhotoTool.lens_of(got.about).is_equal_approx(lens), "and where the lens stood and looked")
	check(var_to_str(got.world) == var_to_str(around.world), "the garden comes back as it went in")
	var path := dir.path_join("photo.png")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(png)
	f.close()
	main.world.restore(bare)
	main.look.set_time(Daylight.DEFAULT)
	check(var_to_str(main.world.digest()) != picture, "cleared, the garden is not the photo's")
	check(main.open_photo(path), "a photo with its garden in it opens")
	check(var_to_str(main.world.digest()) == picture, "as the garden it shows")
	check(main.look.time == 0.8, "at its time of day")
	check(main.rig.head.global_transform.is_equal_approx(lens), "seen from its lens")
	check(not main.open_photo(dir.path_join("none.png")), "what is not a photo opens nothing")


func _a_garden_too_big_is_left_out_and_says_so() -> void:
	var noise := PackedByteArray()
	noise.resize(PhotoMeta.WORLD_MAX + 1024)
	var rng := RandomNumberGenerator.new()
	for i in noise.size():
		noise[i] = rng.randi() & 0xFF
	var about := {"time_of_day": 0.5}
	var got := PhotoMeta.read(PhotoMeta.embed(_png(), about, {"format": World.FORMAT, "seq": 0, "cmds": [noise]}))
	check(about.world.has("left out") and got.about.world == about.world, "a garden over %d bytes packed stays out, and the photo says so: %s" % [PhotoMeta.WORLD_MAX, about.world])
	check(got.world == null and got.about.time_of_day == 0.5, "the rest is still written")


func _a_damaged_chunk_is_not_read() -> void:
	var png := PhotoMeta.embed(_png(), {"time_of_day": 0.25}, main.world.snapshot())
	var at := png.size() - 12 - 8
	png[at] ^= 0xFF
	var got := PhotoMeta.read(png)
	check(not got.is_empty() and got.world == null, "a garden whose checksum fails is not read")
	png = PhotoMeta.embed(_png(), {"time_of_day": 0.25})
	at = 0
	while png.slice(at, at + 4).get_string_from_ascii() != "0.25":
		at += 1
	png[at + 3] = "6".unicode_at(0)
	check(PhotoMeta.read(png).is_empty(), "nor what it says of itself")
