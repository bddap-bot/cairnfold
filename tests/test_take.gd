extends "res://../tests/support/suite.gd"

## A session's record holds microphone audio only when a take is armed, and the arm holds for that one session.


func _initialize() -> void:
	var folder := "user://take-%d" % OS.get_process_id()
	var tone := _tone()

	await _session(folder, tone)
	check(not _files(folder).any(func(f: String) -> bool: return f.ends_with(".wav")), "a default recording keeps no audio file")
	check(_events(folder).all(func(e: Dictionary) -> bool: return e.event != "take" and not e.has("take")), "and its record names no take")
	_clear(folder)

	_arm(0)
	var log := await _session(folder, tone)
	check(not FileAccess.file_exists(Main.player_path(PlayLog.ARM)), "the session that finds the arm removes it as it starts")
	var bus := AudioServer.get_bus_index(Take.BUS)
	check(bus != -1 and AudioServer.get_bus_effect_count(bus) == 0, "the take's capture goes with its session")
	var events := _events(folder)
	var starts := events.filter(func(e: Dictionary) -> bool: return e.event == "start")
	check(starts.all(func(e: Dictionary) -> bool: return e.get("take", {}) == {"file": log.take.get_file(), "rate": float(AudioServer.get_mix_rate())}),
		"every chunk of the armed session names its take, at the mix rate: %s" % [starts.map(func(e): return e.get("take"))])
	check(events.filter(func(e: Dictionary) -> bool: return e.event == "take").size() == 1, "and the input frame it began at, once")
	var wav := FileAccess.get_file_as_bytes(log.take)
	var data := wav.size() - 44
	check(wav.size() > 44 and wav.decode_u32(4) == 36 + data and wav.decode_u32(40) == data and wav.decode_u16(22) == 1
		and wav.decode_u16(34) == 16, "the take is a whole mono 16-bit WAV")
	var loud := 0
	for i in range(44, wav.size() - 1, 2):
		loud += int(absi(wav.decode_s16(i)) > 8000)
	check(data > 0 and loud > data / 2 / 2, "what reached the take's bus is in it: %d of %d samples loud" % [loud, data / 2])
	var out := []
	var code := OS.execute("python3", [ProjectSettings.globalize_path("res://../scripts/sessions.py"), ProjectSettings.globalize_path(folder), "--json"], out, true)
	var read: Variant = JSON.parse_string(out[0]) if code == 0 else null
	check(read is Array and read.size() == 1 and read[0].take is Dictionary and is_equal_approx(float(read[0].take.seconds), snappedf(data / 2.0 / AudioServer.get_mix_rate(), 0.1)),
		"scripts/sessions.py reads the take back: %s" % [out])
	_clear(folder)

	await _session(folder, tone)
	check(not _files(folder).any(func(f: String) -> bool: return f.ends_with(".wav")), "the next session keeps no audio: the arm did not outlive its session")
	_clear(folder)

	_arm(PlayLog.ARM_SECONDS + 60)
	var stale := PlayLog.open_enabled({})
	check(stale.take.is_empty() and not FileAccess.file_exists(Main.player_path(PlayLog.ARM)), "an arm left standing too long is spent unused")
	stale.finish()
	FileAccess.open(folder.path_join("1-2-3.wav"), FileAccess.WRITE).close()
	PlayLog.new(folder).finish()
	check(not FileAccess.file_exists(folder.path_join("1-2-3.wav")), "a take whose session the ring dropped goes with it")
	_clear(folder)

	_arm(0)
	DirAccess.remove_absolute(Main.player_path(PlayLog.SWITCH))
	check(PlayLog.open_enabled({}) == null and not FileAccess.file_exists(Main.player_path(PlayLog.ARM)),
		"an arm on a device that records nothing records nothing, and is spent all the same")
	DirAccess.remove_absolute(folder)
	finish()


## Arms a take as a dev tool does, the file `age` seconds old.
func _arm(age: int) -> void:
	FileAccess.open(Main.player_path(PlayLog.ARM), FileAccess.WRITE).close()
	var at := int(Time.get_unix_time_from_system()) - age
	OS.execute("touch", ["-d", "@%d" % at, ProjectSettings.globalize_path(Main.player_path(PlayLog.ARM))])


## Plays a recorded session, launched as a recording device is, with `tone` sounding on the take's bus whenever there is
## a take, as the microphone would, until three of its seconds and a second and a half of any take are written.
func _session(folder: String, tone: AudioStreamWAV) -> PlayLog:
	boot_main({"record-sessions": true, "session-directory": folder})
	await process_frame
	var log := main.metrics.play_log
	var takes := main.get_children().filter(func(n: Node) -> bool: return n is Take)
	check(takes.size() == int(not log.take.is_empty()), "a session listens only when it is a take")
	if log.take.is_empty():
		check(not _microphone_open(main), "and nothing opens the microphone")
	var voice := AudioStreamPlayer.new()
	voice.stream = tone
	voice.bus = Take.BUS if takes else "Master"
	main.add_child(voice)
	voice.play()
	var writes := [0, 0]
	var heard := [false]
	await until(func() -> bool:
		if log._frames != writes[1]:
			writes[0] += 1
			writes[1] = log._frames
		if takes and AudioServer.get_bus_peak_volume_left_db(AudioServer.get_bus_index(Take.BUS), 0) > -60.0:
			heard[0] = true
		var held := FileAccess.get_size(log.take) if not log.take.is_empty() and FileAccess.file_exists(log.take) else 0
		return writes[0] >= 3 and (log.take.is_empty() or held > 44 + 3 * AudioServer.get_mix_rate()), "the session's seconds written")
	check(not heard[0], "nothing on the take's bus leaves it to be played")
	main.metrics.close()
	await process_frame
	await process_frame
	check(main.get_children().all(func(n: Node) -> bool: return not n is Take) and not _microphone_open(main), "nothing listens once the record has ended")
	main.queue_free()
	await process_frame
	main = null
	return log


static func _microphone_open(under: Node) -> bool:
	return under.find_children("*", "AudioStreamPlayer", true, false).any(
		func(p: AudioStreamPlayer) -> bool: return p.playing and p.stream is AudioStreamMicrophone)


## A loud 440 Hz tone, looping.
static func _tone() -> AudioStreamWAV:
	var rate := 44100
	var pcm := PackedByteArray()
	pcm.resize(rate * 2)
	for i in rate:
		pcm.encode_s16(i * 2, int(sin(TAU * 440.0 * i / rate) * 24000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = pcm
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = rate
	return wav


static func _files(folder: String) -> Array:
	return Array(DirAccess.get_files_at(folder))


static func _events(folder: String) -> Array:
	var events := []
	for name in _files(folder):
		if name.ends_with(".jsonl"):
			for line in FileAccess.get_file_as_string(folder.path_join(name)).strip_edges().split("\n"):
				events.append(JSON.parse_string(line))
	return events


static func _clear(folder: String) -> void:
	for name in _files(folder):
		DirAccess.remove_absolute(folder.path_join(name))
