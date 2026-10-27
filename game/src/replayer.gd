class_name Replayer
extends MultiplayerAPIExtension

## Plays a session record (`Replay.read`, Main's --replay) in place of the headset's runtime and the network; see
## "Local play-session history" in docs/design.md.
signal finished

var record: Dictionary
var _main: Main
var _frame := 0
var _count := 0
var _next := 0
var _id := 1
var _sender := 0
var _peers := PackedInt32Array()
var _peer: MultiplayerPeer = OfflineMultiplayerPeer.new()


func _init(on: Main, played: Dictionary) -> void:
	_main = on
	record = played
	_count = record.frames.size() / Replay.FRAME_BYTES


## Runs where the tree polls the network, before anything of the frame: the frame's messages, then its input.
func _poll() -> Error:
	if _frame > _count:
		return OK
	var messages: Array = record.messages
	while _next < messages.size() and messages[_next][0] <= _frame:
		_next += 1
		_deliver(messages[_next - 1])
	if _frame == _count:
		_frame += 1
		_let_go()
		finished.emit()
		return OK
	_apply(Replay.unpack(record.frames, _frame))
	_frame += 1
	_pace()
	return OK


## Scales the next frame to its recorded delta, taking this frame's own step, unscaled, as the next one's: exact when the
## run steps by a fixed rate (--fixed-fps), as close as its frame times allow when it runs in real time.
func _pace() -> void:
	var step := _main.get_process_delta_time() / Engine.time_scale if Engine.time_scale > 0.0 else 0.0
	Engine.time_scale = record.frames.decode_double(_frame * Replay.FRAME_BYTES) / step if _frame < _count and step > 0.0 else 1.0


func _apply(f: Dictionary) -> void:
	_main.rig.head.transform = f.head
	for i in Replay.HANDS.size():
		var h: Hand = _main.rig.hands[i]
		var got: Dictionary = f.hands[i]
		h.held_still = got.flags.tracked or got.flags.bare
		h.held_reaches = got.flags.reaches
		h.transform = got.pose
		Hand.injected_sticks[h.tracker] = got.stick
		for input: String in got.held:
			if got.held[input]:
				Buttons.injected["%s/%s" % [h.tracker, input]] = true
			else:
				Buttons.injected.erase("%s/%s" % [h.tracker, input])


func _let_go() -> void:
	for h: Hand in _main.rig.hands:
		h.held_still = false
		h.held_reaches = false
		Hand.injected_sticks.erase(h.tracker)
		for input in Replay.inputs(h.tracker):
			Buttons.injected.erase("%s/%s" % [h.tracker, input])


## A message as the network gave it; what this machine did itself is the input's to do again, but for its peers coming
## and going and its host dropping it, which the network decided.
func _deliver(m: Array) -> void:
	var whose: int = m[2]
	match m[3]:
		"peer_connected":
			_peers.append(whose)
			peer_connected.emit(whose)
		"peer_disconnected":
			if whose in _peers:
				_peers.remove_at(_peers.find(whose))
			peer_disconnected.emit(whose)
		"connected":
			connected_to_server.emit()
		"dropped":
			server_disconnected.emit()
		_ when m[1] != 0:
			_sender = m[1]
			(_main.world if _main.world.has_method(m[3]) else _main.session).callv(m[3], m[4].map(_unfiled))
			_sender = 0


## A file the record kept only as its hash (PlayLog._without_files) arrives as no file.
static func _unfiled(a: Variant) -> Variant:
	return PackedByteArray() if a is Dictionary and a.has("sha256") and a.size() == 2 else a


## A garden this game sets out to join is never reached: it stands for the player the record says this machine
## became there.
func _set_multiplayer_peer(peer: MultiplayerPeer) -> void:
	_peers.clear()
	_id = 1
	if peer is ENetMultiplayerPeer:
		if peer.get_unique_id() != 1:
			_id = _joined_as(peer.get_unique_id())
		peer.close()
		peer = OfflineMultiplayerPeer.new()
	_peer = peer


## The id the host gave this machine when this join connected, else `otherwise`.
func _joined_as(otherwise: int) -> int:
	for i in range(_next, record.messages.size()):
		match record.messages[i][3]:
			"connected":
				return record.messages[i][2]
			"join", "dropped", "home":
				break
	return otherwise


func _get_multiplayer_peer() -> MultiplayerPeer:
	return _peer


func _get_unique_id() -> int:
	return _id


func _get_peer_ids() -> PackedInt32Array:
	return _peers


func _get_remote_sender_id() -> int:
	return _sender


func _rpc(_peer_id: int, _object: Object, _method: StringName, _args: Array) -> Error:
	return OK


func _object_configuration_add(_object: Object, _configuration: Variant) -> Error:
	return OK


func _object_configuration_remove(_object: Object, _configuration: Variant) -> Error:
	return OK
