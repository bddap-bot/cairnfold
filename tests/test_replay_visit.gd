extends "res://../tests/support/suite.gd"

## A session in which the player plants two trees at home, then joins a garden whose host is at the same command with
## other trees, replays from its record alone: the visited garden comes in whole mid-replay and is compared once it
## is in, never half restored, and the replay plays as the id the host gave the player.

const Replayed := preload("res://../tests/support/replayed.gd")
## The id the host gives the player when it joins.
const JOINED := 7


## The network as a host the player joins gives it: offline until the join, then the player as JOINED.
class Host:
	extends MultiplayerAPIExtension
	var id := 1
	var sender := 0
	var peer: MultiplayerPeer = OfflineMultiplayerPeer.new()

	func _poll() -> Error:
		return OK

	func _set_multiplayer_peer(p: MultiplayerPeer) -> void:
		peer = p

	func _get_multiplayer_peer() -> MultiplayerPeer:
		return peer

	func _get_unique_id() -> int:
		return id

	func _get_peer_ids() -> PackedInt32Array:
		return PackedInt32Array([1]) if id != 1 else PackedInt32Array()

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
	var arrived := [false]
	world.loaded.connect(func() -> void: arrived[0] = true, CONNECT_ONE_SHOT)
	host.id = JOINED
	check(main.session.join("127.0.0.1", Session.PORT + Session.PORT_RANGE - 1), "the player sets out to join")
	host.connected_to_server.emit()
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
	check([0, 0, "join"] in heard and [0, JOINED, "connected"] in heard and [1, 1, "_welcome"] in heard,
		"the record holds the join, the id the host gave, and the host's garden: %s" % [heard])
	var gardens: Array = record.checks.filter(func(c: Dictionary) -> bool: return c.has("garden") and c.seq == 2)
	check(gardens.size() == 2 and gardens[0].garden != gardens[1].garden,
		"the record kept two gardens at command 2, home's and the host's: %s" % [gardens])
	var replayed := Replayed.replay(self, chunk, avatars)
	if not replayed.is_empty():
		check(replayed.diverged.is_empty(), "replayed, every check holds, the host's garden compared once it is in: %s" % [replayed.diverged])
		check(replayed.garden == visited, "the replay ends in the host's garden")
		check(replayed.id == JOINED, "the replay plays as the id the host gave: %d" % replayed.id)

	for name in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(name))
	DirAccess.remove_absolute(folder)
	DirAccess.remove_absolute(Main.player_path(PlayLog.SWITCH))
	main.queue_free()
	await process_frame
	finish()
