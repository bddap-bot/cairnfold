class_name Session
extends Node

## Who shares this garden (docs/multiplayer.md). Every instance hosts its own garden, which alone is
## single player, and announces it on the local network; joining someone swaps in their garden until
## you leave or they go. Each player's head and hands travel to the others as poses, and the newest VRM
## in their avatar folder travels once to everyone they meet.

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
## How often the avatar folder is looked at, in seconds.
const FOLDER_EVERY := 2.0
## Avatar files travel on a channel of their own, so building commands never wait behind one.
const FILE_CHANNEL := 1
const COLOURS: Array[Color] = [Color(0.8, 0.45, 0.32), Color(0.45, 0.62, 0.42), Color(0.86, 0.66, 0.3), Color(0.38, 0.5, 0.72), Color(0.62, 0.4, 0.6), Color(0.3, 0.6, 0.6)]

## Peers or nearby gardens came or went.
signal changed

var world: World
var rig: Rig
var avatar := 0
var colour := COLOURS[0]
var me: Persona
var port := 0
## 0 for an instance a test or script made without a port: it opens nothing, so runs side by side never meet.
var first_port := PORT
var beacon_port := BEACON_PORT
## Whether beacons reach the network, or only this machine.
var lan := true
## The garden we are visiting, {address, port}, or empty at home.
var visiting := {}
## Gardens announcing themselves nearby, by "address:port": {address, port, key, avatar, colour, name, joins, seen}.
var nearby := {}
## Remote players' avatars by peer id.
var avatars := {}
## The folder whose newest .vrm is this player's avatar, or "" for a built-in one.
var folder := ""
## That file once it has read as an avatar within the limits; sent to every player met.
var worn := PackedByteArray()
## Each remote player's built-in avatar and colour, and the hash of the file they wear ("" for none).
var _looks := {}
var _wearing := {}
## Avatars read from others' files, by hash, while someone here wears one.
var _scenes := {}
## Files being read on worker threads: {task, peer, done, out}, where only the worker writes `out` until the task
## completes; each player's latest file waiting to be.
var _jobs: Array[Dictionary] = []
var _waiting := {}
var _seen_file := ""
var _since_folder := INF
var _home := {}
var _key := 0
var _clock := 0.0
var _since_beacon := INF
var _since_pose := 0.0
var _beacon := PacketPeerUDP.new()
var _listen := PacketPeerUDP.new()
var _targets := {}
static var _protocol := 0


func _init(garden: World, player: Rig, look: int, from_port := PORT, on_lan := true, from_beacon := BEACON_PORT, who: Persona = null) -> void:
	name = "Session"
	lan = on_lan
	beacon_port = BEACON_PORT if lan else clampi(from_beacon, 1024, 65536 - BEACON_PORTS)
	world = garden
	rig = player
	first_port = clampi(from_port, PORT, PORT + PORT_RANGE - PORTS) if from_port else 0
	var id := hash(OS.get_unique_id())
	avatar = posmod(look if look >= 0 else id, Avatar.BUILT_IN.size())
	colour = COLOURS[posmod(id / 7 + maxi(first_port - PORT, 0), COLOURS.size())]
	_key = randi()
	me = who if who else Persona.new("", 0, "", id)
	for i in Avatar.BUILT_IN.size():
		Avatar.built_in(i)


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
	for p in (BEACON_PORTS if first_port else 0):
		if _listen.bind(beacon_port + p, "*" if lan else "127.0.0.1") == OK:
			break
	me.offer(_key)
	host()


## Opens this garden to others; with nobody joining it is single player, on the same code path.
func host() -> void:
	visiting = {}
	var peer := ENetMultiplayerPeer.new()
	for p in (range(first_port, first_port + PORTS) if first_port else []):
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
	if not worn.is_empty():
		_wear.rpc_id(id, worn)
	changed.emit()


func _on_gone(id: int) -> void:
	if avatars.has(id):
		avatars[id].queue_free()
		avatars.erase(id)
		_targets.erase(id)
	_looks.erase(id)
	_wearing.erase(id)
	_waiting.erase(id)
	_prune()
	changed.emit()


func _drop_avatars() -> void:
	for a in avatars.values():
		a.queue_free()
	avatars.clear()
	_targets.clear()
	_looks.clear()
	_wearing.clear()
	_waiting.clear()
	_prune()


func _process(delta: float) -> void:
	_clock += delta
	_since_beacon += delta
	if _since_beacon >= BEACON_EVERY:
		_since_beacon = 0.0
		_announce()
	_hear()
	_since_folder += delta
	if _since_folder >= FOLDER_EVERY:
		_since_folder = 0.0
		_look_in_folder()
	_finish_jobs()
	_since_pose += delta
	if _since_pose >= POSE_EVERY and not multiplayer.get_peers().is_empty():
		_since_pose = 0.0
		_pose.rpc(rig.head.global_transform, rig.left.body.global_transform, rig.right.body.global_transform)
	var k := 1.0 - exp(-FOLLOW * delta)
	for id in _targets:
		var a: Avatar = avatars[id]
		var t: Array = _targets[id]
		a.pose(a.eyes.interpolate_with(t[0], k), a.hands[0].interpolate_with(t[1], k), a.hands[1].interpolate_with(t[2], k))


func _announce() -> void:
	if port == 0 or not visiting.is_empty():
		return
	var msg := beacon()
	for dest in beacon_to():
		for p in BEACON_PORTS:
			_beacon.set_dest_address(dest, beacon_port + p)
			_beacon.put_packet(msg)


## Every second, to anyone on the network: nothing identifying, unless the player picked a name to show.
func beacon() -> PackedByteArray:
	var msg := {"nestcombe": protocol(), "key": _key, "port": port, "avatar": avatar, "colour": colour.to_html(false), "players": players()}
	if me.shared and not me.steam():
		msg.name = me.name
	return JSON.stringify(msg).to_utf8_buffer()


## Godot numbers a node's RPCs by name, so two builds whose networked methods differ call the wrong methods
## on each other and every edit a visitor makes is lost: a garden is joined only by builds with the same ones.
static func protocol() -> int:
	if _protocol == 0:
		_protocol = fingerprint([World, Session])
	return _protocol


static func fingerprint(scripts: Array[Script]) -> int:
	var parts := PackedStringArray()
	for s in scripts:
		var rpcs: Dictionary = s.get_rpc_config()
		for m in s.get_script_method_list():
			if rpcs.has(m.name):
				parts.append("%s.%s/%d %s" % [s.get_global_name(), m.name, m.args.size(), rpcs[m.name]])
	parts.sort()
	return hash(parts)


## A beacon's garden, or empty when the packet is not one; `joins` is false for a build with other networked methods.
static func read_beacon(raw: PackedByteArray) -> Dictionary:
	var json := JSON.new()
	if json.parse(raw.slice(0, 512).get_string_from_utf8()) != OK:
		return {}
	var msg: Variant = json.data
	if not (msg is Dictionary and msg.get("nestcombe") is float and msg.get("key") is float and msg.get("port") is float and msg.get("avatar") is float):
		return {}
	var at := int(msg.port)
	if at < PORT or at >= PORT + PORT_RANGE:
		return {}
	return {"key": int(msg.key), "port": at, "avatar": posmod(int(msg.avatar), Avatar.BUILT_IN.size()), "colour": Color.from_string(str(msg.get("colour", "")), COLOURS[0]).clamp(), "name": Persona.clean(str(msg.get("name", ""))), "joins": msg.nestcombe == float(protocol())}


func _hear() -> void:
	var before := nearby.keys()
	for n in HEAR_PER_FRAME:
		if _listen.get_available_packet_count() <= 0:
			break
		var garden := read_beacon(_listen.get_packet())
		var ip := _listen.get_packet_ip()
		if garden.is_empty() or garden.key == _key:
			continue
		var where := "%s:%d" % [ip, garden.port]
		if not (nearby.has(where) or nearby.size() < MAX_NEARBY):
			continue
		garden.address = ip
		garden.seen = _clock
		nearby[where] = garden
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
	_looks[id] = [posmod(look, Avatar.BUILT_IN.size()), tint.clamp()]
	_dress(id, Avatar.built_in(look), "")


## A player's own VRM, sent to each player they meet and again whenever it changes; empty for their built-in one.
## They keep their built-in avatar until the file has been read, on a worker thread, and passes the limits.
@rpc("any_peer", "reliable", "call_remote", FILE_CHANNEL)
func _wear(bytes: PackedByteArray) -> void:
	var id := multiplayer.get_remote_sender_id()
	print("session: player %d sent %d bytes of avatar%s" % [id, bytes.size(), "" if _looks.has(id) else " before appearing"])
	if not _looks.has(id) or bytes.size() > Avatar.MAX_BYTES:
		return
	_waiting[id] = bytes
	_read_waiting()


## Reads at most one file per player at a time, the latest each sent, so nobody can queue up reads.
func _read_waiting() -> void:
	for id in _waiting.keys():
		if _jobs.any(func(j: Dictionary) -> bool: return j.peer == id):
			continue
		var bytes: PackedByteArray = _waiting[id]
		_waiting.erase(id)
		if bytes.is_empty():
			_wearing[id] = ""
			_dress(id, Avatar.built_in(_looks[id][0]), "")
			_prune()
		else:
			_read(bytes, "", _worn_by_peer.bind(id), id)


func _worn_by_peer(key: String, _bytes: PackedByteArray, scene: PackedScene, id: int) -> void:
	if not _looks.has(id):
		return
	if scene == null:
		print("session: player %d sent a file that is not an avatar within the limits" % id)
		return
	print("session: player %d wears %s" % [id, key])
	_wearing[id] = key
	_scenes.get_or_add(key, scene)
	_dress(id, _scenes[key], key)
	_prune()


## Gives player `id` the avatar in `scene`, in their pose.
func _dress(id: int, scene: PackedScene, key: String) -> void:
	var a := Avatar.open(scene, _looks[id][1], key)
	var old: Avatar = avatars.get(id)
	a.visible = old != null and old.visible
	if old != null:
		a.pose(old.eyes, old.hands[0], old.hands[1])
		old.queue_free()
	add_child(a)
	avatars[id] = a


func _prune() -> void:
	for key in _scenes.keys():
		if not _wearing.values().has(key):
			_scenes.erase(key)


static func _hash(bytes: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(bytes)
	return h.finish().hex_encode()


## Where a player drops their avatar: in user data, except on Android, whose user data only the game can reach;
## there it is the app's external files folder, which a file manager or adb can write.
static func own_folder() -> String:
	if OS.get_name() == "Android":
		return "/sdcard/Android/data/%s/files/avatars" % OS.get_user_data_dir().get_base_dir().get_file()
	return "user://avatars"


## Wears the newest .vrm in the avatar folder once it reads as an avatar; with none there, the built-in one.
func _look_in_folder() -> void:
	if folder == "":
		return
	var newest := ""
	var when := -1
	for f in DirAccess.get_files_at(folder):
		var path := folder.path_join(f)
		if f.get_extension().to_lower() == "vrm" and FileAccess.get_modified_time(path) > when:
			newest = path
			when = FileAccess.get_modified_time(path)
	var seen := "%s %d %d" % [newest, when, FileAccess.get_size(newest) if newest != "" else 0]
	if seen == _seen_file:
		return
	_seen_file = seen
	if newest == "":
		_put_on("", PackedByteArray(), null, seen)
	else:
		_read(PackedByteArray(), newest, _put_on.bind(seen))


## Wears a file read from the folder, unless the folder has changed since.
func _put_on(key: String, bytes: PackedByteArray, scene: PackedScene, seen: String) -> void:
	if seen != _seen_file:
		return
	if key != "" and scene == null:
		print("session: %s is not an avatar within the limits" % _seen_file)
		return
	worn = bytes
	print("session: wearing %s" % (key if key != "" else "a built-in avatar"))
	if not multiplayer.get_peers().is_empty():
		_wear.rpc(worn)


## Reads a VRM, from `bytes` or the file at `path`, and hashes it on a worker thread; `done(hash, bytes, scene)`
## follows on this one, with a null scene if it is not an avatar within the limits. `peer` is whose file it is,
## 0 for this player's own.
func _read(bytes: PackedByteArray, path: String, done: Callable, peer := 0) -> void:
	var out := {}
	var task := WorkerThreadPool.add_task(func() -> void:
		var b := bytes
		if path != "":
			var f := FileAccess.open(path, FileAccess.READ)
			b = f.get_buffer(f.get_length()) if f != null and f.get_length() <= Avatar.MAX_BYTES else PackedByteArray()
		out.merge({"key": _hash(b), "bytes": b, "scene": Avatar.read(b) if not b.is_empty() else null}))
	_jobs.append({"task": task, "peer": peer, "done": done, "out": out})


func _exit_tree() -> void:
	for job in _jobs:
		WorkerThreadPool.wait_for_task_completion(job.task)
	_jobs.clear()


func _finish_jobs() -> void:
	for i in range(_jobs.size() - 1, -1, -1):
		var job := _jobs[i]
		if WorkerThreadPool.is_task_completed(job.task):
			WorkerThreadPool.wait_for_task_completion(job.task)
			_jobs.remove_at(i)
			job.done.call(job.out.key, job.out.bytes, job.out.scene)
			_read_waiting()


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
