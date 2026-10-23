extends "res://../tests/support/suite.gd"

## Headless checks of the action feedback table: every action resolves to an entry whose sound exists, every action
## is played from the game and listed in the design document, and the voices stay pooled:
## godot4 --headless --fixed-fps 60 --path game --script ../tests/test_cues.gd


func _initialize() -> void:
	_every_action_has_an_entry()
	_every_action_is_played_and_listed()
	await _voices_are_pooled_and_continuous_actions_thinned()
	finish()


func _every_action_has_an_entry() -> void:
	for name: String in Cues.Act.keys():
		var act: int = Cues.Act[name]
		check(Cues.TABLE.has(act), "%s has a table entry" % name)
		if not Cues.TABLE.has(act):
			continue
		var cue: Dictionary = Cues.TABLE[act]
		var sound: String = cue.get("sound", "")
		var feel: Array = cue.get("feel", [])
		check(sound != "" or not feel.is_empty(), "%s sounds or is felt" % name)
		check(sound == "" or Cues.SOUNDS.has(sound), "%s's sound %s is one of the sounds" % [name, sound])
		check(sound == "" or cue.has("db"), "%s's sound has a level" % name)
		check(feel.is_empty() or (feel.size() == 4 and feel[0] > 0.0 and feel[0] <= 1.0 and feel[1] > 0.0), "%s's pulse is [amplitude, seconds, pulses, gap]: %s" % [name, feel])
	check(Cues.TABLE.size() == Cues.Act.size(), "no entry is for an action that is gone")
	for kind: String in Cues.SOUNDS:
		for i in Cues.SOUNDS[kind]:
			check(load("res://audio/fx/%s%d.ogg" % [kind, i]) != null, "sound %s%d loads" % [kind, i])
		check(not FileAccess.file_exists("res://audio/fx/%s%d.ogg" % [kind, Cues.SOUNDS[kind]]), "%s has no clip past its count" % kind)
		check(Cues.TABLE.values().any(func(c: Dictionary) -> bool: return c.get("sound", "") == kind), "%s is played by some action" % kind)


## Each action is played somewhere in the game, and docs/design.md's "Action feedback" lists it with what it is given.
func _every_action_is_played_and_listed() -> void:
	var source := ""
	for f in DirAccess.get_files_at("res://src"):
		if f.ends_with(".gd") and f != "cues.gd":
			source += FileAccess.get_file_as_string("res://src".path_join(f))
	var design := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../docs/design.md"))
	var at := design.find("## Action feedback")
	check(at >= 0, "the design document has its action feedback section")
	var section := design.substr(at, design.find("\n## ", at + 4) - at)
	for name: String in Cues.Act.keys():
		check(source.contains("Cues.Act.%s" % name), "%s is played from the game" % name)
		check(section.contains("| `%s` |" % name), "%s is listed in docs/design.md" % name)
	var listed := RegEx.create_from_string("\\| `([A-Z_]+)` \\|")
	for m in listed.search_all(section):
		check(Cues.Act.has(m.get_string(1)), "%s, listed in docs/design.md, is an action" % m.get_string(1))


func _voices_are_pooled_and_continuous_actions_thinned() -> void:
	var cues := Cues.new()
	root.add_child(cues)
	await process_frame
	var hand := XRController3D.new()
	root.add_child(hand)
	for i in 40:
		Cues.play(Cues.Act.WALL_SETTLE, Vector3(i, 0, 0))
	var voices := cues.get_children().filter(func(c: Node) -> bool: return c is AudioStreamPlayer3D)
	check(voices.size() == Cues.VOICES, "sounds share %d voices: %d" % [Cues.VOICES, voices.size()])
	var before := cues._next_voice
	for i in 10:
		Cues.play(Cues.Act.HOUSE_MOVE, Vector3.ZERO, hand)
	check(cues._next_voice == (before + 1) % Cues.VOICES, "a drag played every frame sounds once within its `every`")
	var low := cues._voices[cues._next_voice]
	Cues.play(Cues.Act.HOUSE_STRETCH, Vector3.ZERO, hand, 0.0)
	await create_timer(Cues.TABLE[Cues.Act.HOUSE_STRETCH].every + 0.05).timeout
	var high := cues._voices[cues._next_voice]
	Cues.play(Cues.Act.HOUSE_STRETCH, Vector3.ZERO, hand, 1.0)
	check(high.pitch_scale > low.pitch_scale * 1.5, "a stretch drawn tight creaks higher: %.2f against %.2f" % [high.pitch_scale, low.pitch_scale])
	for i in 200:
		Cues.play(Cues.Act.BOULDER_PLACE, Vector3.ZERO, null, 1.0, 64.0)
		check(cues._voices[(cues._next_voice + Cues.VOICES - 1) % Cues.VOICES].volume_db <= Cues.LOUDEST, "nothing plays louder than LOUDEST, its spread of level included")
	hand.queue_free()
	cues.queue_free()
	await process_frame
