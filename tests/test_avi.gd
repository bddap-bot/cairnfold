extends SceneTree

## The video file: godot4 --headless --path game --script ../tests/test_avi.gd
## ffprobe and ffmpeg (shell.nix) read it back as a player would.

var failures := 0


func _initialize() -> void:
	await process_frame
	_a_clip_reads_back_with_its_frames_and_sound()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _a_clip_reads_back_with_its_frames_and_sound() -> void:
	var path := ProjectSettings.globalize_path("user://test-avi.avi")
	var avi := Avi.open(path, Vector2i(64, 48), 24, 48000)
	var sound := PackedVector2Array()
	sound.resize(2000)
	for i in sound.size():
		sound[i] = Vector2.ONE * sin(i * 0.1) * 0.5
	for c in [Color.RED, Color.GREEN, Color.BLUE, Color.WHITE, Color.BLACK]:
		var img := Image.create(64, 48, false, Image.FORMAT_RGB8)
		img.fill(c)
		var jpg := img.save_jpg_to_buffer(0.8)
		if c == Color.WHITE:
			jpg.append(0)
		_check(avi.sound(sound.slice(0, 400).to_byte_array()) and avi.frame(jpg), "a frame and its sound are written")
		sound = sound.slice(400)
	_check(avi.close() == OK, "the file closes")
	_the_chunks_are_where_the_index_says(FileAccess.get_file_as_bytes(path), 5, 2000)
	var out := []
	OS.execute("ffprobe", ["-v", "error", "-count_frames", "-show_entries", "stream=codec_name,width,height,r_frame_rate,nb_read_frames,sample_rate,channels,duration", "-of", "json", path], out, true)
	var probe: Variant = JSON.parse_string(out[0])
	_check(probe is Dictionary and probe.get("streams", []).size() == 2, "ffprobe finds a video and a sound stream: %s" % out[0])
	if not probe is Dictionary or probe.get("streams", []).size() != 2:
		return
	var video: Dictionary = probe.streams[0]
	var audio: Dictionary = probe.streams[1]
	_check(video.codec_name == "mjpeg" and video.width == 64 and video.height == 48 and video.r_frame_rate == "24/1", "the video is 64×48 MJPEG at 24 fps: %s" % video)
	_check(video.nb_read_frames == "5", "every frame reads back: %s" % video.nb_read_frames)
	_check(audio.codec_name == "pcm_f32le" and audio.sample_rate == "48000" and audio.channels == 2, "the sound is stereo float at 48 kHz: %s" % audio)
	var raw := path.get_base_dir().path_join("test-avi.f32")
	OS.execute("ffmpeg", ["-v", "error", "-y", "-i", path, "-map", "0:a", "-f", "f32le", raw])
	var back := FileAccess.get_file_as_bytes(raw).to_float32_array()
	_check(back.size() == 4000 and absf(back[2 * 1234] - sin(1234 * 0.1) * 0.5) < 1e-6, "every sound sample reads back as written: %d of 4000" % back.size())
	DirAccess.remove_absolute(raw)
	var errors := []
	var code := OS.execute("ffmpeg", ["-v", "error", "-i", path, "-f", "null", "-"], errors, true)
	_check(code == 0 and errors[0].strip_edges() == "", "ffmpeg decodes it without complaint: %s" % errors[0])
	DirAccess.remove_absolute(path)


## Walks the file as a strict reader would: every chunk padded to an even length, the counts in the headers,
## and each index entry pointing at its chunk. ffmpeg forgives all of these, so they are checked here.
func _the_chunks_are_where_the_index_says(b: PackedByteArray, frames: int, sounds: int) -> void:
	var tag := func(at: int) -> String: return b.slice(at, at + 4).get_string_from_ascii()
	_check(tag.call(0) == "RIFF" and b.decode_u32(4) == b.size() - 8 and tag.call(8) == "AVI ", "the RIFF header holds the file's length")
	var at := 12
	var movi := -1
	var index := -1
	while at + 8 <= b.size():
		var size := b.decode_u32(at + 4)
		if tag.call(at) == "LIST" and tag.call(at + 8) == "movi":
			movi = at + 8
			var c := at + 12
			while c < at + 8 + size:
				c += 8 + b.decode_u32(c + 4) + b.decode_u32(c + 4) % 2
			_check(c == at + 8 + size, "the movi list ends where its chunks do")
		elif tag.call(at) == "idx1":
			index = at
		at += 8 + size + size % 2
	_check(at == b.size(), "the chunks fill the file exactly")
	var avih := 12 + 12
	_check(tag.call(avih) == "avih" and b.decode_u32(avih + 8 + 16) == frames, "the main header counts %d frames" % frames)
	_check(b.decode_u32(avih + 64 + 12 + 8 + 32) == frames, "the video stream's length is %d frames" % frames)
	_check(b.decode_u32(avih + 64 + 12 + 64 + 48 + 12 + 8 + 32) == sounds, "the sound stream's length is %d samples" % sounds)
	_check(movi > 0 and index > 0, "there is a movi list and an index")
	if movi < 0 or index < 0:
		return
	var entries := b.decode_u32(index + 4) / 16
	_check(entries == frames * 2, "the index has an entry for every chunk: %d" % entries)
	for e in entries:
		var id := tag.call(index + 8 + 16 * e) as String
		var off := movi + b.decode_u32(index + 8 + 16 * e + 8)
		_check(tag.call(off) == id and b.decode_u32(off + 4) == b.decode_u32(index + 8 + 16 * e + 12), "index entry %d points at its %s chunk" % [e, id])
