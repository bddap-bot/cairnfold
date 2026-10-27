extends "res://../tests/support/suite.gd"

## Scripted and test instances never beacon past loopback, beacons carry each host's name and own avatar to the
## wheel's friends page, and a garden of another build stands there with an X and cannot be joined:
## godot4 --headless --fixed-fps 60 --path game --script ../tests/test_beacon.gd

## A documentation address, which no host answers: joining it reaches no other run's garden.
const NOBODY := "192.0.2.1"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_scripts_are_not_players()
	_names_are_clean_and_short()
	_a_picked_name_is_kept()
	_another_build_is_heard_not_joined()
	await _a_test_instance_beacons_on_loopback_only()
	await _the_picker_shows_each_host_s_name()
	await _the_picker_shows_a_host_s_own_avatar_before_joining()
	finish()


func _scripts_are_not_players() -> void:
	check(Session.played({}, true), "a game launched bare is a player's")
	check(Session.played({"avatar": "1"}, true), "and so is one picking an avatar")
	for args in [{"script": "coop-host.json", "port": "7480", "host-port": "7480"}, {"join": "127.0.0.1:7480", "script": "guest1.json"}, {"join": "192.168.1.2"}, {"port": "7536"}, {"beacon-port": "22000"}]:
		check(not Session.played(args, true), "a game launched with %s is a script's" % args)
	var scripted := Session.new(null, null, 0, Session.PORT, false, 22000)
	check(scripted.beacon_port == 22000, "scripts can select their discovery ports")
	scripted.free()
	var player := Session.new(null, null, 0, Session.PORT, true, 22000)
	check(player.beacon_port == Session.BEACON_PORT, "LAN players keep the standard discovery ports")
	player.free()
	check(not Session.played({}, false), "a game a test builds is not a player's")


func _a_test_instance_beacons_on_loopback_only() -> void:
	boot_main()
	await process_frame
	var session: Session = main.session
	check(session.beacon_to().all(func(a: String) -> bool: return a.begins_with("127.")), "an instance a test made beacons to %s, loopback only" % str(session.beacon_to()))
	session.lan = true
	check(session.beacon_to().any(func(a: String) -> bool: return not a.begins_with("127.")), "a player's game beacons past loopback: %s" % str(session.beacon_to()))
	main.queue_free()


func _names_are_clean_and_short() -> void:
	check(Persona.clean("  Wren\n\tof\u0007 the  Moor ") == "Wren of the Moor", "control characters and runs of spaces fold to one space: %s" % Persona.clean("  Wren\n\tof\u0007 the  Moor "))
	check(Persona.clean("x".repeat(200)).length() == Persona.MAX_NAME, "a name is cut to %d characters" % Persona.MAX_NAME)
	check(Persona.clean("苔むした ミソサザイ") == "苔むした ミソサザイ", "names outside ASCII stand")
	for seed in 50:
		var n := Persona.suggest(seed)
		check(n == Persona.clean(n) and n.contains(" "), "a suggested name is two clean words: %s" % n)
	check(Persona.suggest(7) == Persona.suggest(7), "a machine suggests the same name every start")
	if not Engine.has_singleton("Steam"):
		var steamless := Persona.new("", 480)
		check(not steamless.steam() and steamless.steam_id(1) == 0, "without the Steam extension a Steam app id leaves Steam off")


func _the_beacon_names_nobody_until_they_pick_a_name(s: Session) -> void:
	check(not s.me.shared, "a test player starts with no name picked")
	check(s.port == 0, "a test's garden opens no port, so test runs side by side never meet: %d" % s.port)
	s.port = Session.PORT
	var heard := Session.read_beacon(s.beacon())
	check(heard.get("name") == "" and heard.get("port") == s.port and not s.beacon().get_string_from_utf8().contains(s.me.name), "the beacon carries no name nobody picked: %s" % s.beacon().get_string_from_utf8())
	s.me.pick()
	heard = Session.read_beacon(s.beacon())
	check(heard.get("name") == s.me.name, "a picked name rides the beacon: %s" % heard)
	s.port = 0
	var hostile := JSON.stringify({"cairnfold": 1, "key": 3, "port": Session.PORT, "avatar": 0, "name": "\u0000" + "W".repeat(400)}).to_utf8_buffer()
	heard = Session.read_beacon(hostile)
	check(heard.is_empty() or heard.name.length() <= Persona.MAX_NAME, "a hostile beacon is cut down or dropped: %s" % heard)


func _networked(source: String) -> Script:
	var s := GDScript.new()
	s.source_code = "extends Node\n" + source
	s.reload()
	return s


## Report (verbatim): "I'm unable to make a pond". The headset visited a garden hosted by a build without one of
## World's RPCs; its proposals reached the host as other methods, so no dig, pond or plant of the visitor's landed.
func _another_build_is_heard_not_joined() -> void:
	var dir := DirAccess.open("res://src")
	for f in dir.get_files():
		var s: Variant = load("res://src/" + f) if f.ends_with(".gd") else null
		if s is Script and not (s as Script).get_rpc_config().is_empty():
			check(s in [World, Session], "%s has RPCs, so the protocol fingerprint must cover it" % f)
	var old := Session.read_beacon(JSON.stringify({"cairnfold": 1, "key": 3, "port": Session.PORT, "avatar": 0}).to_utf8_buffer())
	check(not old.is_empty() and not old.joins, "a garden from a build before the protocol fingerprint is heard, not to be joined: %s" % old)
	var other := Session.read_beacon(JSON.stringify({"cairnfold": Session.protocol() + 1, "key": 3, "port": Session.PORT, "avatar": 0}).to_utf8_buffer())
	check(not other.is_empty() and not other.joins, "a garden from a build with other RPCs is heard, not to be joined: %s" % other)
	var same := Session.read_beacon(JSON.stringify({"cairnfold": Session.protocol(), "key": 3, "port": Session.PORT, "avatar": 0}).to_utf8_buffer())
	check(not same.is_empty() and same.joins, "a garden from this build is heard and joins: %s" % same)
	var unversioned := JSON.stringify({"key": 3, "port": Session.PORT, "avatar": 0}).to_utf8_buffer()
	check(Session.read_beacon(unversioned).is_empty(), "a packet without the cairnfold field is no garden")
	var before := _networked("@rpc(\"any_peer\")\nfunc _propose(c): pass\n@rpc(\"any_peer\")\nfunc _resend(): pass\n")
	var after := _networked("@rpc(\"any_peer\")\nfunc _device(d): pass\n@rpc(\"any_peer\")\nfunc _propose(c): pass\n@rpc(\"any_peer\")\nfunc _resend(): pass\n")
	var takes := _networked("@rpc(\"any_peer\")\nfunc _propose(c): pass\n@rpc(\"any_peer\")\nfunc _resend(by): pass\n")
	var plain := _networked("@rpc(\"any_peer\")\nfunc _propose(c): pass\n@rpc(\"any_peer\")\nfunc _resend(): pass\nfunc helper(): pass\n")
	check(Session.fingerprint([before]) != Session.fingerprint([after]), "an RPC added changes the fingerprint")
	check(Session.fingerprint([before]) != Session.fingerprint([takes]), "an RPC's arguments change it")
	check(Session.fingerprint([before]) == Session.fingerprint([plain]), "a method that is not an RPC leaves it")


func _a_picked_name_is_kept() -> void:
	var keep := "user://test-beacon-name"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(keep))
	var me := Persona.new("", 0, keep, 11)
	check(me.name == Persona.suggest(11) and not me.shared, "a first start offers the machine's name, not shown to others: %s" % me.name)
	check(not FileAccess.file_exists(keep), "and keeps nothing")
	me.pick()
	check(me.shared and me.name == Persona.suggest(11), "the first pick shows that name")
	me.pick()
	check(me.name != Persona.suggest(11), "the next pick offers another: %s" % me.name)
	var again := Persona.new("", 0, keep, 11)
	check(again.name == me.name and again.shared, "the picked name is kept, shown, for the next start")
	check(Persona.new("Clover Lark", 0, keep, 11).name == "Clover Lark", "a launch argument names a scripted player over the kept name")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(keep))


func _the_picker_shows_each_host_s_name() -> void:
	boot_main()
	await process_frame
	var session: Session = main.session
	_the_beacon_names_nobody_until_they_pick_a_name(session)
	var wheel := SessionWheel.new(session)
	var where := "%s:%d" % [NOBODY, Session.PORT + 5]
	session.nearby[where] = {"address": NOBODY, "port": Session.PORT + 5, "key": 5, "avatar": 2, "colour": Session.COLOURS[1], "name": "Hazel Otter", "joins": false, "seen": INF}
	var figure := wheel.figure("join:" + where)
	var labels := figure.find_children("*", "Label3D", true, false)
	check(labels.any(func(n: Label3D) -> bool: return n.text == "Hazel Otter"), "the wheel figure carries the host name")
	check(labels.any(func(n: Label3D) -> bool: return n.text == "×"), "an incompatible garden has a cross")
	figure.free()
	wheel.activate("join:" + where)
	check(session.visiting.is_empty(), "an incompatible garden cannot be joined")
	session.nearby[where].joins = true
	wheel.activate("join:" + where)
	check(session.visiting.get("port") == Session.PORT + 5, "the wheel action joins a compatible garden")
	session.go_home()
	var was := session.me.name
	wheel.activate("name")
	check(session.me.name != was and session.me.shared, "name choice remains an explicit wheel action")
	main.queue_free()
	await process_frame


## Report (verbatim): "I look at my wife's avatar, and it's just one of the default little pointy wizards, and then I
## load the game and only then do I see her actual avatar". The beacon carried only a built-in avatar's number.
func _the_picker_shows_a_host_s_own_avatar_before_joining() -> void:
	boot_main()
	await process_frame
	var folder := "user://test-beacon-avatars"
	DirAccess.make_dir_recursive_absolute(folder)
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://").path_join("../tests/avatars/crimsom-0.x.vrm"), ProjectSettings.globalize_path(folder.path_join("crimsom.vrm")))
	var beacons := 20000 + randi() % 20000
	var sessions: Array[Session] = []
	for i in 2:
		var branch := Node.new()
		root.add_child(branch)
		set_multiplayer(SceneMultiplayer.new(), branch.get_path())
		var s := Session.new(main.world, main.rig, i, Session.PORT, false, beacons)
		branch.add_child(s)
		sessions.append(s)
	var viewer := sessions[0]
	var host := sessions[1]
	host.folder = folder
	var tool := SessionWheel.new(viewer)
	while host.worn_key == "" and (host.files.is_empty() or host._reading != ""):
		await process_frame
	check(host.worn_key != "" and Session.read_beacon(host.beacon()).wears == host.worn_key, "a host wearing its own file names it in the beacon")
	var where := "127.0.0.1:%d" % host.port
	for n in 600:
		if viewer.nearby.has(where) and viewer.nearby[where].wears == host.worn_key:
			break
		host._announce()
		await process_frame
	var unreachable := "%s:%d" % [NOBODY, Session.PORT + 9]
	viewer.nearby[unreachable] = viewer.nearby[where].merged({"address": NOBODY, "port": Session.PORT + 9, "wears": "cd".repeat(32), "name": "", "seen": INF}, true)
	await process_frame
	await process_frame
	check(_worn_by(tool, unreachable) == "", "until a host's file arrives they stand in a built-in avatar")
	viewer.nearby.erase(unreachable)
	while viewer.previewing():
		await process_frame
	await process_frame
	check(viewer.previews.get(host.worn_key) != null, "the viewer fetched and read the host's file without joining")
	check(_worn_by(tool, where) == host.worn_key, "the host's figure in the picker wears their own avatar: %s" % _worn_by(tool, where))
	check(viewer.visiting.is_empty() and viewer.players() == 1, "and nobody joined anybody")
	var forged := "ab".repeat(32)
	viewer.nearby["127.0.0.1:1"] = viewer.nearby[where].merged({"wears": forged, "seen": INF}, true)
	await process_frame
	while viewer.previewing():
		await process_frame
	check(not viewer.previews.has(forged) and viewer._failed.has(forged), "a file whose hash is not the one its beacon names is not shown")
	viewer.nearby.erase("127.0.0.1:1")
	var junk := "not a vrm".to_utf8_buffer()
	var junk_key := Session.sha256(junk)
	var shelved := host._shelved
	host._shelved = PackedByteArray([0, 0, 0, 0]) + junk
	host._shelved.encode_u32(0, junk.size())
	viewer.nearby["127.0.0.1:1"] = viewer.nearby[where].merged({"wears": junk_key, "seen": INF}, true)
	await process_frame
	while viewer.previewing():
		await process_frame
	check(not viewer.previews.has(junk_key) and viewer._failed.has(junk_key), "a file that is the one named but does not read is not shown")
	viewer._clock += Session.RETRY + 1.0
	await process_frame
	await process_frame
	check(not viewer._fetches.has(junk_key) and viewer._failed.get(junk_key) == INF, "and while its beacon names it, it is not fetched again")
	host._shelved = shelved
	viewer.nearby.erase("127.0.0.1:1")
	for s in sessions:
		set_multiplayer(null, s.get_parent().get_path())
		s.get_parent().queue_free()
	main.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(folder.path_join("crimsom.vrm")))
	await process_frame


func _worn_by(tool: SessionWheel, k: String) -> String:
	var figure := tool.figure("join:" + k)
	var a: Avatar = figure.get_node("Figure")
	var source := a.source
	figure.free()
	return source
