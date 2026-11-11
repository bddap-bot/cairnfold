extends "res://../tests/support/suite.gd"

## A session in which the player plants two trees at home, then joins a garden whose host is at the same command with
## other trees, replays from its record alone: the visited garden comes in whole mid-replay and is compared once it
## is in, never half restored, and the replay plays as the id the player joined as from the frame it joined.

const Replayed := preload("res://../tests/support/replayed.gd")


## The network as a host the player joins gives it: the player as the id its join's peer took, the host connecting as a real
## one does; the join's own peer is closed, since nothing answers it.
class Host:
	extends MultiplayerAPIExtension
	var id := 1
	var sender := 0
	var peers := PackedInt32Array()
	var peer: MultiplayerPeer = OfflineMultiplayerPeer.new()

	func _poll() -> Error:
		return OK

	func _set_multiplayer_peer(p: MultiplayerPeer) -> void:
		if p is ENetMultiplayerPeer:
			id = p.get_unique_id()
			p.close()
			p = OfflineMultiplayerPeer.new()
		peer = p

	func _get_multiplayer_peer() -> MultiplayerPeer:
		return peer

	func _get_unique_id() -> int:
		return id

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


func _run() -> void:
	var folder := "user://replay-visit-%d" % OS.get_process_id()
	var host := Host.new()
	set_multiplayer(host)
	boot_main({"record-sessions": true, "session-directory": folder, "garden": folder.path_join("garden.save")})
	await process_frame
	var log := main.metrics.play_log
	var world := main.world
	for seed in [7, 8]:
		world.submit({"op": "plant", "kind": "tree", "seed": seed, "at": world.terrain.ground(seed - 10, -2)})
	await until(func() -> bool: return world.seq == 2 and world.answered(), "two trees planted at home")
	var there := world.snapshot()
	for c: Dictionary in there.cmds:
		if c.op == "plant":
			c.seed += 100
	await frames(30)
	var arrived := [false]
	world.loaded.connect(func() -> void: arrived[0] = true, CONNECT_ONE_SHOT)
	check(main.session.join("127.0.0.1", Session.PORT + Session.PORT_RANGE - 1), "the player sets out to join")
	var joined := host.id
	await frames(3)
	host.connected_to_server.emit()
	host.peers.append(1)
	host.peer_connected.emit(1)
	host.sender = 1
	world._welcome(there)
	host.sender = 0
	await until(func() -> bool: return arrived[0], "the host's garden arriving")
	var visited := world.snapshot()
	check(visited.seq == 2 and visited.cmds.map(func(c: Dictionary) -> int: return c.get("seed", 0)).has(107),
		"the visited garden, at the same command as home, has the host's trees: %s" % [visited.cmds.map(func(c: Dictionary) -> String: return c.op)])
	await until(func() -> bool: return not world._record_due, "the visited garden kept in the record")
	await frames(Replay.CHECK_EVERY)
	log.finish()
	main.metrics.play_log = null
	world.play_log = null

	var chunk := folder.path_join(Array(DirAccess.get_files_at(folder)).filter(func(f: String) -> bool: return f.ends_with(".jsonl"))[0])
	var avatars := ProjectSettings.globalize_path(folder.path_join("avatars"))
	var record := Replay.read(chunk, avatars)
	var heard: Array = record.messages.map(func(m: Array) -> Array: return [m[1], m[2], m[3]])
	check(joined != 1 and [0, 0, "join"] in heard and [0, joined, "connected"] in heard and [0, 1, "peer_connected"] in heard and [1, 1, "_welcome"] in heard,
		"the record holds the join, the id it connected as (%d), the host coming and its garden: %s" % [joined, heard])
	var join_frame: int = record.messages.filter(func(m: Array) -> bool: return m[3] == "join")[0][0]
	var gardens: Array = record.checks.filter(func(c: Dictionary) -> bool: return c.has("garden") and c.seq == 2)
	check(gardens.size() == 2 and gardens[0].garden != gardens[1].garden,
		"the record kept two gardens at command 2, home's and the host's: %s" % [gardens])
	var replayed := Replayed.replay(self, chunk, avatars)
	if not replayed.is_empty():
		check(replayed.diverged.is_empty(), "replayed, every check holds, the host's garden compared once it is in: %s" % [replayed.diverged])
		check(replayed.garden == visited, "the replay ends in the host's garden")
		var ids: Array = replayed.ids
		check(join_frame > 20 and ids.size() > join_frame + Replay.CHECK_EVERY and ids.slice(0, join_frame).all(func(i: int) -> bool: return i == 1)
			and ids.slice(join_frame + 1).all(func(i: int) -> bool: return i == joined),
			"the replay plays as the host until frame %d, where the record joins, and as %d from then on: %s" % [join_frame, joined, ids.slice(maxi(join_frame - 2, 0), join_frame + 3)])

	for name in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(name))
	DirAccess.remove_absolute(folder)
	DirAccess.remove_absolute(Main.player_path(PlayLog.SWITCH))
	main.queue_free()
	await process_frame
	finish()
