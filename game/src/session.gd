class_name Session
extends Node

## Who shares this garden (docs/multiplayer.md). Every instance hosts its own garden, which alone is
## single player, and announces it on the local network; joining someone swaps in their garden until
## you leave or they go. Each player's head and hands travel to the others as poses.

const PORT := 7480
## A host takes the first free of PORTS ports from its first; beacons may name any in PORT_RANGE from PORT.
const PORTS := 8
const PORT_RANGE := 64
## Beacons go to each of these ports, so several instances on one machine each find the others.
const BEACON_PORT := 7469
const BEACON_PORTS := 4
const BEACON_EVERY := 1.0
const FORGET_AFTER := 4.0
## At most this many beacons are read a frame and this many gardens remembered, whatever the network sends.
const HEAR_PER_FRAME := 16
const MAX_NEARBY := 12
const MAX_PLAYERS := 8
const POSE_EVERY := 1.0 / 30.0
## How fast a remote avatar closes on its latest pose, per second.
const FOLLOW := 18.0
const COLOURS: Array[Color] = [Color(0.8, 0.45, 0.32), Color(0.45, 0.62, 0.42), Color(0.86, 0.66, 0.3), Color(0.38, 0.5, 0.72), Color(0.62, 0.4, 0.6), Color(0.3, 0.6, 0.6)]

## Peers or nearby gardens came or went.
signal changed

var world: World
var rig: Rig
var avatar := 0
var colour := COLOURS[0]
var port := 0
var first_port := PORT
var beacon_port := BEACON_PORT
## Whether beacons reach the network, or only this machine.
var lan := true
## The garden we are visiting, {address, port}, or empty at home.
var visiting := {}
## Gardens announcing themselves nearby, by "address:port": {address, port, avatar, colour, seen}.
var nearby := {}
## Remote players' avatars by peer id.
var avatars := {}
var _home := {}
var _key := 0
var _clock := 0.0
var _since_beacon := INF
var _since_pose := 0.0
var _beacon := PacketPeerUDP.new()
var _listen := PacketPeerUDP.new()
var _targets := {}


func _init(garden: World, player: Rig, look: int, from_port := PORT, on_lan := true, from_beacon := BEACON_PORT) -> void:
	name = "Session"
	lan = on_lan
	beacon_port = BEACON_PORT if lan else clampi(from_beacon, 1024, 65536 - BEACON_PORTS)
	world = garden
	rig = player
	first_port = clampi(from_port, PORT, PORT + PORT_RANGE - PORTS)
	var id := hash(OS.get_unique_id())
	avatar = posmod(look if look >= 0 else id, Avatar.BUILT_IN.size())
	colour = COLOURS[posmod(id / 7 + first_port - PORT, COLOURS.size())]
	_key = randi()
	for path in Avatar.BUILT_IN:
		Avatar.prepare(path)


## A game a player launched, as opposed to one a script or a test runs. Only it beacons on the network.
static func played(args: Dictionary, launched: bool) -> bool:
	return launched and not (args.has("script") or args.has("join") or args.has("port") or args.has("beacon-port"))


## Where beacons go: a script's or a test's stay on this machine, so players never see them.
func beacon_to() -> Array:
	return ["255.255.255.255", "127.0.0.1"] if lan else ["127.0.0.1"]


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer)
	multiplayer.peer_disconnected.connect(_on_gone)
	multiplayer.server_disconnected.connect(go_home, CONNECT_DEFERRED)
	multiplayer.connection_failed.connect(go_home, CONNECT_DEFERRED)
	_beacon.set_broadcast_enabled(true)
	for p in BEACON_PORTS:
		if _listen.bind(beacon_port + p, "*" if lan else "127.0.0.1") == OK:
			break
	host()


## Opens this garden to others; with nobody joining it is single player, on the same code path.
func host() -> void:
	visiting = {}
	var peer := ENetMultiplayerPeer.new()
	for p in range(first_port, first_port + PORTS):
		var probe := PacketPeerUDP.new()
		if probe.bind(p) != OK:
			continue
		probe.close()
		if peer.create_server(p, MAX_PLAYERS - 1) == OK:
			port = p
			multiplayer.multiplayer_peer = peer
			print("session: hosting on port %d" % p)
			return
	port = 0
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


## Leaves this garden for another's; ours waits in memory until we come back.
func join(address: String, at_port: int) -> void:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(address, at_port) != OK:
		return
	if visiting.is_empty():
		_home = world.snapshot()
	multiplayer.multiplayer_peer.close()
	_drop_avatars()
	multiplayer.multiplayer_peer = peer
	visiting = {"address": address, "port": at_port}
	changed.emit()


func go_home() -> void:
	if visiting.is_empty() and multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		return
	multiplayer.multiplayer_peer.close()
	_drop_avatars()
	host()
	if not _home.is_empty():
		world.restore(_home)
	_home = {}
	changed.emit()


func players() -> int:
	return multiplayer.get_peers().size() + 1


func _on_peer(id: int) -> void:
	if multiplayer.is_server():
		world.welcome(id)
	_appear.rpc_id(id, avatar, colour)
	changed.emit()


func _on_gone(id: int) -> void:
	if avatars.has(id):
		avatars[id].queue_free()
		avatars.erase(id)
		_targets.erase(id)
	changed.emit()


func _drop_avatars() -> void:
	for a in avatars.values():
		a.queue_free()
	avatars.clear()
	_targets.clear()


func _process(delta: float) -> void:
	_clock += delta
	_since_beacon += delta
	if _since_beacon >= BEACON_EVERY:
		_since_beacon = 0.0
		_announce()
	_hear()
	_since_pose += delta
	if _since_pose >= POSE_EVERY and not multiplayer.get_peers().is_empty():
		_since_pose = 0.0
		_pose.rpc(rig.head.global_transform, rig.left.global_transform, rig.right.global_transform)
	var k := 1.0 - exp(-FOLLOW * delta)
	for id in _targets:
		var a: Avatar = avatars[id]
		var t: Array = _targets[id]
		a.pose(a.eyes.interpolate_with(t[0], k), a.hands[0].interpolate_with(t[1], k), a.hands[1].interpolate_with(t[2], k))


func _announce() -> void:
	if port == 0 or not visiting.is_empty():
		return
	var msg := JSON.stringify({"nestcombe": 1, "key": _key, "port": port, "avatar": avatar, "colour": colour.to_html(false), "players": players()}).to_utf8_buffer()
	for dest in beacon_to():
		for p in BEACON_PORTS:
			_beacon.set_dest_address(dest, beacon_port + p)
			_beacon.put_packet(msg)


func _hear() -> void:
	var before := nearby.keys()
	for n in HEAR_PER_FRAME:
		if _listen.get_available_packet_count() <= 0:
			break
		var raw := _listen.get_packet()
		var ip := _listen.get_packet_ip()
		var json := JSON.new()
		if json.parse(raw.slice(0, 512).get_string_from_utf8()) != OK:
			continue
		var msg: Variant = json.data
		if not (msg is Dictionary and msg.get("nestcombe") == 1.0 and msg.get("key") is float and msg.get("port") is float and msg.get("avatar") is float):
			continue
		var at := int(msg.port)
		var where := "%s:%d" % [ip, at]
		if int(msg.key) == _key or at < PORT or at >= PORT + PORT_RANGE or not (nearby.has(where) or nearby.size() < MAX_NEARBY):
			continue
		nearby[where] = {"address": ip, "port": at, "avatar": posmod(int(msg.avatar), Avatar.BUILT_IN.size()), "colour": Color.from_string(str(msg.get("colour", "")), COLOURS[0]).clamp(), "seen": _clock}
	for key in nearby.keys():
		if _clock - nearby[key].seen > FORGET_AFTER:
			nearby.erase(key)
	if nearby.keys() != before:
		changed.emit()


## A player's avatar and colour, sent once to each player they meet.
@rpc("any_peer", "reliable")
func _appear(look: int, tint: Color) -> void:
	var id := multiplayer.get_remote_sender_id()
	if avatars.has(id):
		return
	var a := Avatar.open(Avatar.BUILT_IN[posmod(look, Avatar.BUILT_IN.size())], tint.clamp())
	a.visible = false
	add_child(a)
	avatars[id] = a


@rpc("any_peer", "unreliable_ordered")
func _pose(eyes: Transform3D, left: Transform3D, right: Transform3D) -> void:
	var id := multiplayer.get_remote_sender_id()
	var room := Terrain.bounds().grow(40.0)
	for t in [eyes, left, right]:
		if not (t.is_finite() and absf(t.basis.determinant()) > 1e-3 and room.has_point(t.origin)):
			return
	if not avatars.has(id):
		return
	var target := [eyes.orthonormalized(), left.orthonormalized(), right.orthonormalized()]
	var a: Avatar = avatars[id]
	if not a.visible:
		a.visible = true
		a.pose(target[0], target[1], target[2])
	_targets[id] = target
