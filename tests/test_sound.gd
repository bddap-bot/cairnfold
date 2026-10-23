extends "res://../tests/support/suite.gd"

## Headless checks of the rendered audio against its manifest: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_sound.gd

const TAIL := 3.0


func _init() -> void:
	_every_section_has_its_stems()
	_every_effect_loads()
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
	check(load("res://audio/meadow.ogg") != null, "meadow bed")
