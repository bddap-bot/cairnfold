extends "res://../tests/support/suite.gd"

## Headless checks of the rendered audio against its manifest: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_sound.gd

const TAIL := 3.0


func _init() -> void:
	_every_section_has_its_stems()
	_every_effect_loads()
	_birds_keep_the_hour_and_the_ground()
	finish()


func _every_section_has_its_stems() -> void:
	var manifest: Array = JSON.parse_string(FileAccess.get_file_as_string("res://audio/music.json"))
	check(manifest.size() >= 8, "%d music sections" % manifest.size())
	for s in manifest:
		var musical: float = s.beats * 60.0 / s.bpm
		for stem in Soundscape.STEMS:
			var path := "res://audio/music/%s.%s.ogg" % [s.name, stem]
			var ogg: AudioStream = load(path)
			check(ogg != null, "%s loads" % path)
			if ogg != null:
				var len := ogg.get_length()
				check(len >= musical and len <= musical + TAIL + 0.1, "%s is %.2f s for %.2f s of music" % [path, len, musical])


func _every_effect_loads() -> void:
	for kind in Cues.SOUNDS:
		for i in Cues.SOUNDS[kind]:
			check(load("res://audio/fx/%s%d.ogg" % [kind, i]) != null, "effect %s%d" % [kind, i])
	check(load("res://audio/meadow.ogg") != null, "meadow wind")
	check(load("res://audio/night.ogg") != null, "night bed")
	for i in Soundscape.SONGS:
		check(load("res://audio/birds/song%d.ogg" % i) != null, "song %d" % i)
	for i in Soundscape.HOOTS:
		check(load("res://audio/birds/hoot%d.ogg" % i) != null, "hoot %d" % i)


func _birds_keep_the_hour_and_the_ground() -> void:
	var noon := Daylight.elevation(0.5)
	var midnight := Daylight.elevation(0.0)
	check(Soundscape.song_level(noon, 1.7, false) > 0.99, "songbirds sing at noon on the ground")
	check(Soundscape.night_level(noon, 1.7, false) == 0.0, "no crickets at noon")
	check(Soundscape.song_level(midnight, 1.7, false) == 0.0, "no songbirds at midnight")
	check(Soundscape.night_level(midnight, 1.7, false) > 0.99, "crickets at midnight")
	check(Soundscape.song_level(Daylight.elevation(0.25), 1.7, false) > 0.3, "a dawn chorus at sunrise")
	for elevation in [noon, midnight]:
		check(Soundscape.song_level(elevation, 30.0, false) == 0.0 and Soundscape.night_level(elevation, 30.0, false) == 0.0, "silent 30 m up at %.0f°" % elevation)
		check(Soundscape.song_level(elevation, 1.7, true) == 0.0 and Soundscape.night_level(elevation, 1.7, true) == 0.0, "silent under water at %.0f°" % elevation)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for head in [Vector3(0, 1.7, 0), Vector3(20, 31.7, -15)]:
		for i in 50:
			var at := Soundscape.perch(head, rng)
			var away := Vector2(at.x - head.x, at.z - head.z).length()
			var over := at.y - Terrain.height_at(at.x, at.z)
			check(away >= Soundscape.AWAY.x - 0.01 and away <= Soundscape.AWAY.y + 0.01, "a bird %.1f m off across the ground" % away)
			check(over >= Soundscape.PERCH.x - 0.01 and over <= Soundscape.PERCH.y + 0.01, "a bird %.1f m over the ground" % over)
	check(Soundscape.song_level(noon, 12.0, false) > 0.2 and Soundscape.song_level(noon, 12.0, false) < 0.9, "fainter 12 m up")
