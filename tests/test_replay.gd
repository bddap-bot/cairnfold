extends "res://../tests/support/suite.gd"

const Replayed := preload("res://../tests/support/replayed.gd")
const VISITOR := 2
const COMES := 30
const PROPOSES := 90
## Top bit set, so it reads back negative.
const TOP_BIT_SEED := -5385056196784741867
var _avatars := ""


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
	boot_main({"record-sessions": true, "session-directory": folder, "seed": TOP_BIT_SEED, "garden": folder.path_join("garden.save")})
	visitor.main = main
	var probe := Replayed.watch(main)
	await process_frame
	var log := main.metrics.play_log
	var hill: Dictionary = Lessons.PAGES.filter(func(p: Dictionary) -> bool: return p.effect == "hill")[0]
	await play([
		{"op": "view", "eye": [0, 1.65, 6], "at": [0, 1.2, 0]},
		{"op": "aim", "dir": [0, -0.3, -1], "seconds": 0.5, "settle": 1.0},
		hill.merged({"op": "gesture"}),
		{"op": "pond", "x": -6, "z": -12},
		{"op": "sculpt", "x": -6, "z": -12, "lift": -0.5, "radius": 2.0, "seconds": 0.3},
	])
	# Losing focus mid-aim ends the aim, so the stick let go meanwhile teleports nowhere.
	main.rig.left.global_transform = Driver.aim_pose(main.rig.head.global_transform, [0, -0.3, -1])
	Hand.injected_sticks[main.rig.left.tracker] = Vector2(0, 1)
	await until(func() -> bool: return main.rig.aim_ground != null, "the player aiming a teleport")
	var aimed := main.rig.global_transform
	main._xr_state(OpenXRInterface.SESSION_STATE_VISIBLE)
	Hand.injected_sticks.erase(main.rig.left.tracker)
	await frames(5)
	main._xr_state(OpenXRInterface.SESSION_STATE_FOCUSED)
	await frames(Replay.CHECK_EVERY)
	check(main.rig.global_transform == aimed, "the aim a pause ended teleports nowhere")
	var avatars := ProjectSettings.globalize_path(folder.path_join("avatars"))
	_avatars = avatars
	DirAccess.make_dir_recursive_absolute(avatars)
	var file := FileAccess.get_file_as_bytes(avatar_file("godette-0.x.vrm"))
	var out := FileAccess.open(avatars.path_join("mine.vrm"), FileAccess.WRITE)
	out.store_buffer(file)
	out.close()
	main.session.folder = avatars
	await until(func() -> bool: return main.rig.body.source == Session.sha256(file) and main.rig.world_scale != 1.0 and main.rig._fade_t < 0.0,
		"the player's own file worn, and the rig refitted to it")
	# Frames of another length than the run's own, which only the recorded deltas give the replay.
	Engine.time_scale = 0.5
	await play([{"op": "glide", "eye": [3, 1.65, 4], "at": [0, 1.2, 0], "seconds": 1.0}])
	Engine.time_scale = 1.0
	await until(func() -> bool: return visitor.frame > PROPOSES and main.world.seq >= 2 and not main.world._keep_due,
		"the visitor's tree and the hill in the garden, and the garden saved")
	await frames(Replay.CHECK_EVERY)
	log.finish()
	var recorded := log._frames
	main.metrics.play_log = null
	main.world.play_log = null
	main.world.settle()
	var garden := main.world.snapshot()
	var heads := probe.heads.slice(0, recorded)
	var waited: Array = probe.waited.map(func(c: Dictionary) -> String: return c.op)
	check("heights" in waited and "ponds" in waited, "the host's own reshaping and filling of a pond waited for its water: %s" % [waited])
	check(garden.cmds.any(func(c: Dictionary) -> bool: return c.op == "heights") and garden.cmds.any(func(c: Dictionary) -> bool: return c.op == "plant"),
		"the session raised a hill and took a tree: %s" % [garden.cmds.map(func(c: Dictionary) -> String: return c.op)])

	var chunk := folder.path_join(Array(DirAccess.get_files_at(folder)).filter(func(f: String) -> bool: return f.ends_with(".jsonl"))[0])
	var record := Replay.read(chunk, avatars)
	var heard: Array = record.messages.map(func(m: Array) -> Array: return [m[1], m[2], m[3]])
	check([0, VISITOR, "peer_connected"] in heard and [VISITOR, VISITOR, "_propose"] in heard and [0, VISITOR, "ordered"] in heard,
		"the record holds the visitor coming and its tree as it proposed it and as this host ordered it: %s" % [heard])
	var looks: Array = record.messages.filter(func(m: Array) -> bool: return m[3] == "look")
	check(looks.size() == 2 and looks[0][0] == 0 and looks[0][4][0].is_empty() and looks[1][4][0].get("sha256") == Session.sha256(file)
		and record.avatars.keys() == [Session.sha256(file)],
		"the record holds the look the session began in and the file put on, as its hash: %s" % [looks.map(func(m: Array) -> Array: return [m[0], m[4][0]])])
	check(["paused", "resumed"] == heard.map(func(m: Array) -> String: return m[2]).filter(func(c: String) -> bool: return c in ["paused", "resumed"]),
		"the record holds the headset leaving focus and coming back")
	var unfiled := Replay.read(chunk)
	check(Session.sha256(file) in unfiled.get("error", ""), "without the folder holding the file worn, the record is refused, naming it: %s" % unfiled.get("error"))
	var other := Replayed.copy(chunk, "other-events", func(e: Dictionary) -> Dictionary:
		if e.event == "start":
			e.events = Replayer.events() + 1
		return e)
	check("deliver" in Replay.read(other, avatars).get("error", ""), "a record whose events and messages this build delivers otherwise is refused: %s" % Replay.read(other, avatars).get("error"))
	_every_event_heard_is_delivered()
	check(record.seeds.wildlife == str(TOP_BIT_SEED), "the wildlife grew from the seed given, top bit and all: %s" % record.seeds.wildlife)
	var gardens: Array = record.checks.filter(func(c: Dictionary) -> bool: return c.has("garden"))
	check(record.checks.size() > 5 and gardens.size() >= 2 and gardens[-1].seq == garden.seq,
		"the record took %d checks, %d of them of the garden, the last at command %s" % [record.checks.size(), gardens.size(), gardens[-1].seq if not gardens.is_empty() else -1])
	var replayed := Replayed.replay(self, chunk, _avatars)
	if not replayed.is_empty():
		check(replayed.diverged.is_empty(), "replayed on the build that recorded it, every check holds: %s" % [replayed.diverged])
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
		var moved_on := probe.applied_at.keys().filter(func(q: int) -> bool: return probe.applied_at[q] < recorded and replayed.applied_at.get(q) != probe.applied_at[q])
		check(moved_on.is_empty() and probe.applied_at.size() == garden.seq, "every command of the %d comes into the replayed garden at the frame it came into the session's: %s" % [probe.applied_at.size(),
			moved_on.map(func(q: int) -> String: return "%d at %d, replayed at %s" % [q, probe.applied_at[q], replayed.applied_at.get(q)])])
		check(moved > 60, "the head moved in %d frames, the teleport and the glide among them" % moved)
		var differ := range(maxi(garden.cmds.size(), replayed.garden.cmds.size())).filter(func(i: int) -> bool:
			return i >= garden.cmds.size() or i >= replayed.garden.cmds.size() or garden.cmds[i] != replayed.garden.cmds[i])
		check(replayed.garden == garden, "the replayed garden equals the recorded one: seq %d against %d, commands %s differ" % [replayed.garden.seq, garden.seq, differ])

	# A later revision whose tools make nothing of the input, so neither the hill nor the teleport comes.
	var later := Replayed.copy(chunk, "later", func(e: Dictionary) -> Dictionary:
		if e.event == "start":
			e.revision = "a later revision"
		elif e.event == "input":
			var raw := Replay.inflated(e.data, e.bytes)
			for i in int(e.frames):
				for h in Replay.HANDS.size():
					var o := i * Replay.FRAME_BYTES + Replay.DELTA_BYTES + Replay.POSE_BYTES + h * Replay.HAND_BYTES + Replay.POSE_BYTES
					for b in 10:
						raw[o + b] = 0
			e.data = Replay.deflated(raw)
		return e)
	replayed = Replayed.replay(self, later, _avatars)
	if not replayed.is_empty():
		check(replayed.garden == garden, "on a later build that makes nothing of the input the garden still comes out as recorded, from the record's commands")
		var player: Dictionary = replayed.diverged.get("player", {})
		check(player.get("frame") == record.checks[0].frame and not replayed.diverged.has("garden"),
			"it says the player first stands elsewhere at frame %d, the first check after the teleport, and the garden holds: %s" % [record.checks[0].frame, replayed.diverged])

	var tree: Dictionary = record.messages.filter(func(m: Array) -> bool: return m[3] == "ordered" and m[2] == VISITOR)[0][4][0]
	var flown: int = record.checks[3].frame
	var diverging := Replayed.copy(chunk, "diverged", func(e: Dictionary) -> Dictionary:
		if e.event == "replay":
			e.seeds.wildlife = str(int(e.seeds.wildlife) + 1)
		elif e.event == "checks":
			for c: Dictionary in e.checks:
				if c.frame == flown:
					c.physics = "0000000000000000"
		elif e.event == "net":
			var args: Array = bytes_to_var(Replay.inflated(e.data, e.bytes))
			for a: Array in args:
				if not a.is_empty() and a[0] is Dictionary and a[0].get("seq") == tree.seq:
					a[0].seed += 1
			var raw := var_to_bytes(args)
			e.bytes = raw.size()
			e.data = Replay.deflated(raw)
		return e)
	replayed = Replayed.replay(self, diverging, _avatars)
	if not replayed.is_empty():
		var caught: Dictionary = gardens.filter(func(c: Dictionary) -> bool: return c.seq >= tree.seq)[0]
		var before: Array = gardens.filter(func(c: Dictionary) -> bool: return c.seq < tree.seq)
		var held: int = before[-1].seq if not before.is_empty() else 0
		var d: Dictionary = replayed.diverged
		check(d.get("garden", {}).get("frame") == caught.frame and "%d plant" % tree.seq in d.garden.commands
			and d.garden.commands.size() == caught.seq - held,
			"it says the garden first differs at frame %d, naming the %d commands since it last held, the changed tree's among them: %s" % [caught.frame, caught.seq - held, d.get("garden")])
		check(d.get("wildlife", {}).get("frame") == record.checks[0].frame, "it says the wildlife first differs at the first check, frame %d: %s" % [record.checks[0].frame, d.get("wildlife")])
		check(d.get("physics", {}).get("frame") == flown and d.physics.second > 0.0, "it says the handfuls first differ at frame %d and when: %s" % [flown, d.get("physics")])
		check(not d.has("player"), "and the player, played from the same input, holds: %s" % [d.get("player")])

	for sub in ["later", "diverged", "avatars", ""]:
		for name in DirAccess.get_files_at(folder.path_join(sub)):
			DirAccess.remove_absolute(folder.path_join(sub).path_join(name))
		DirAccess.remove_absolute(folder.path_join(sub))
	DirAccess.remove_absolute(Main.player_path(PlayLog.SWITCH))
	main.queue_free()
	await process_frame
	finish()


func _every_event_heard_is_delivered() -> void:
	var delivered := Array(Replayer.delivered())
	for s: Script in [World, Session]:
		delivered.append_array(s.get_rpc_config().keys())
	var heard := RegEx.create_from_string("hear\\(([^\\[\\n]*),\\s*\\[")
	var named := RegEx.create_from_string("\"([^\"]+)\"")
	var lost := []
	for file in DirAccess.get_files_at("res://src"):
		if file.ends_with(".gd"):
			for call in heard.search_all(FileAccess.get_file_as_string("res://src".path_join(file))):
				for name in named.search_all(call.get_string(1)):
					if name.get_string(1) not in delivered:
						lost.append("%s %s" % [file, name.get_string(1)])
	check(lost.is_empty() and delivered.size() > 20, "every event the game passes to hear() is one a replay delivers: %s" % [lost])
