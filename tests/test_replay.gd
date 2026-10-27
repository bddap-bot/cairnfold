extends "res://../tests/support/suite.gd"

## A scripted session, a remote player's build among it, replays from its record alone (--replay, in a fresh game):
## the head where it was frame for frame, and the garden it ended with.

const Replayed := preload("res://../tests/support/replayed.gd")
const VISITOR := 2
const COMES := 30
const PROPOSES := 90


## The network as one visitor's game gives it: it comes, then proposes a tree.
class Visitor:
	extends MultiplayerAPIExtension
	var main: Main
	var frame := 0
	var sender := 0
	var peers := PackedInt32Array()
	var peer: MultiplayerPeer = OfflineMultiplayerPeer.new()

	func _poll() -> Error:
		frame += 1
		if frame == COMES:
			peers.append(VISITOR)
			peer_connected.emit(VISITOR)
		if frame == PROPOSES:
			sender = VISITOR
			main.world._propose({"op": "plant", "kind": "tree", "seed": 7, "at": main.world.terrain.ground(3, -2), "token": 1})
			sender = 0
		return OK

	func _set_multiplayer_peer(p: MultiplayerPeer) -> void:
		peer = p

	func _get_multiplayer_peer() -> MultiplayerPeer:
		return peer

	func _get_unique_id() -> int:
		return 1

	func _get_peer_ids() -> PackedInt32Array:
		return peers

	func _get_remote_sender_id() -> int:
		return sender

	func _rpc(_peer: int, _object: Object, _method: StringName, _args: Array) -> Error:
		return OK

	func _object_configuration_add(_object: Object, _configuration: Variant) -> Error:
		return OK

	func _object_configuration_remove(_object: Object, _configuration: Variant) -> Error:
		return OK


func _initialize() -> void:
	var folder := "user://replay-%d" % OS.get_process_id()
	var visitor := Visitor.new()
	set_multiplayer(visitor)
	boot_main({"record-sessions": true, "session-directory": folder})
	visitor.main = main
	var probe := Replayed.watch(main)
	await process_frame
	var log := main.metrics.play_log
	var hill: Dictionary = Lessons.PAGES.filter(func(p: Dictionary) -> bool: return p.effect == "hill")[0]
	await play([
		{"op": "view", "eye": [0, 1.65, 6], "at": [0, 1.2, 0]},
		{"op": "aim", "dir": [0, -0.3, -1], "seconds": 0.5, "settle": 1.0},
		hill.merged({"op": "gesture"}),
	])
	# Frames of another length than the run's own, which only the recorded deltas give the replay.
	Engine.time_scale = 0.5
	await play([{"op": "glide", "eye": [3, 1.65, 4], "at": [0, 1.2, 0], "seconds": 1.0}])
	Engine.time_scale = 1.0
	await until(func() -> bool: return visitor.frame > PROPOSES and main.world.seq >= 2, "the visitor's tree and the hill in the garden")
	await frames(60)
	log.finish()
	var recorded := log._frames
	main.metrics.play_log = null
	main.world.play_log = null
	main.world.settle()
	var garden := main.world.snapshot()
	var heads := probe.heads.slice(0, recorded)
	check(garden.cmds.any(func(c: Dictionary) -> bool: return c.op == "heights") and garden.cmds.any(func(c: Dictionary) -> bool: return c.op == "plant"),
		"the session raised a hill and took a tree: %s" % [garden.cmds.map(func(c: Dictionary) -> String: return c.op)])

	var chunk := folder.path_join(Array(DirAccess.get_files_at(folder)).filter(func(f: String) -> bool: return f.ends_with(".jsonl"))[0])
	var heard: Array = Replay.read(chunk).messages.map(func(m: Array) -> Array: return [m[1], m[2], m[3]])
	check([0, VISITOR, "peer_connected"] in heard and [VISITOR, VISITOR, "_propose"] in heard and [0, VISITOR, "ordered"] in heard,
		"the record holds the visitor coming and its tree as it proposed it and as this host ordered it: %s" % [heard])
	var out := ProjectSettings.globalize_path(folder.path_join("replayed"))
	var said := []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--fixed-fps", "60", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "../tests/support/replayed.gd", "--", "--replay", ProjectSettings.globalize_path(chunk), "--out", out], said, true)
	check(code == 0 and FileAccess.file_exists(out), "the replay runs: exit %d\n%s" % [code, said[0].right(4000)])
	if FileAccess.file_exists(out):
		var f := FileAccess.open(out, FileAccess.READ)
		var replayed: Dictionary = f.get_var()
		f.close()
		check(replayed.heads.size() == recorded and recorded > 300, "the replay plays every one of the %d frames recorded: %d" % [recorded, replayed.heads.size()])
		var off := []
		var late := []
		var moved := 0
		for i in mini(recorded, replayed.heads.size()):
			if heads[i] != replayed.heads[i]:
				off.append(i)
			if probe.deltas[i] != replayed.deltas[i]:
				late.append(i)
			if i > 0 and heads[i] != heads[i - 1]:
				moved += 1
		check(off.is_empty(), "the replayed head is where the recorded one was every frame: %d of %d differ, first %s" % [off.size(), recorded, off.slice(0, 5)])
		check(late.is_empty() and probe.deltas.slice(0, recorded).any(func(d: float) -> bool: return d < 1.0 / 60.0),
			"every replayed frame takes the recorded delta, the slowed ones too: %d differ, first %s" % [late.size(), late.slice(0, 5).map(func(i: int) -> String: return "%d %.20f %.20f" % [i, probe.deltas[i], replayed.deltas[i]])])
		check(moved > 60, "the head moved in %d frames, the teleport and the glide among them" % moved)
		var differ := range(maxi(garden.cmds.size(), replayed.garden.cmds.size())).filter(func(i: int) -> bool:
			return i >= garden.cmds.size() or i >= replayed.garden.cmds.size() or garden.cmds[i] != replayed.garden.cmds[i])
		check(replayed.garden == garden, "the replayed garden equals the recorded one: seq %d against %d, commands %s differ" % [replayed.garden.seq, garden.seq, differ])

	for name in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(name))
	DirAccess.remove_absolute(folder)
	DirAccess.remove_absolute(Main.player_path(PlayLog.SWITCH))
	main.queue_free()
	await process_frame
	finish()
