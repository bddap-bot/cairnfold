extends SceneTree

## Scripted and test instances never beacon past loopback, beacons carry each host's name and own avatar to the visit
## picker, and a garden of another build stands there with an X and cannot be joined:
## godot4 --headless --fixed-fps 60 --path game --script ../tests/test_beacon.gd

## A documentation address, which no host answers: joining it reaches no other run's garden.
const NOBODY := "192.0.2.1"

var failures := 0


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
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _scripts_are_not_players() -> void:
	_check(Session.played({}, true), "a game launched bare is a player's")
	_check(Session.played({"avatar": "1"}, true), "and so is one picking an avatar")
	for args in [{"script": "coop-host.json", "port": "7480", "host-port": "7480"}, {"join": "127.0.0.1:7480", "script": "guest1.json"}, {"join": "192.168.1.2"}, {"port": "7536"}, {"beacon-port": "22000"}]:
		_check(not Session.played(args, true), "a game launched with %s is a script's" % args)
	var scripted := Session.new(null, null, 0, Session.PORT, false, 22000)
	_check(scripted.beacon_port == 22000, "scripts can select their discovery ports")
	scripted.free()
	var player := Session.new(null, null, 0, Session.PORT, true, 22000)
	_check(player.beacon_port == Session.BEACON_PORT, "LAN players keep the standard discovery ports")
	player.free()
	_check(not Session.played({}, false), "a game a test builds is not a player's")


func _a_test_instance_beacons_on_loopback_only() -> void:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var session: Session = main.session
	_check(session.beacon_to().all(func(a: String) -> bool: return a.begins_with("127.")), "an instance a test made beacons to %s, loopback only" % str(session.beacon_to()))
	session.lan = true
	_check(session.beacon_to().any(func(a: String) -> bool: return not a.begins_with("127.")), "a player's game beacons past loopback: %s" % str(session.beacon_to()))
	main.queue_free()


func _names_are_clean_and_short() -> void:
	_check(Persona.clean("  Wren\n\tof\u0007 the  Moor ") == "Wren of the Moor", "control characters and runs of spaces fold to one space: %s" % Persona.clean("  Wren\n\tof\u0007 the  Moor "))
	_check(Persona.clean("x".repeat(200)).length() == Persona.MAX_NAME, "a name is cut to %d characters" % Persona.MAX_NAME)
	_check(Persona.clean("苔むした ミソサザイ") == "苔むした ミソサザイ", "names outside ASCII stand")
	for seed in 50:
		var n := Persona.suggest(seed)
		_check(n == Persona.clean(n) and n.contains(" "), "a suggested name is two clean words: %s" % n)
	_check(Persona.suggest(7) == Persona.suggest(7), "a machine suggests the same name every start")
	if not Engine.has_singleton("Steam"):
		var steamless := Persona.new("", 480)
		_check(not steamless.steam() and steamless.steam_id(1) == 0, "without the Steam extension a Steam app id leaves Steam off")


func _the_beacon_names_nobody_until_they_pick_a_name(s: Session) -> void:
	_check(not s.me.shared, "a test player starts with no name picked")
	_check(s.port == 0, "a test's garden opens no port, so test runs side by side never meet: %d" % s.port)
	s.port = Session.PORT
	var heard := Session.read_beacon(s.beacon())
	_check(heard.get("name") == "" and heard.get("port") == s.port and not s.beacon().get_string_from_utf8().contains(s.me.name), "the beacon carries no name nobody picked: %s" % s.beacon().get_string_from_utf8())
	s.me.pick()
	heard = Session.read_beacon(s.beacon())
	_check(heard.get("name") == s.me.name, "a picked name rides the beacon: %s" % heard)
	s.port = 0
	var hostile := JSON.stringify({"nestcombe": 1, "key": 3, "port": Session.PORT, "avatar": 0, "name": "\u0000" + "W".repeat(400)}).to_utf8_buffer()
	heard = Session.read_beacon(hostile)
	_check(heard.is_empty() or heard.name.length() <= Persona.MAX_NAME, "a hostile beacon is cut down or dropped: %s" % heard)


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
			_check(s in [World, Session], "%s has RPCs, so the protocol fingerprint must cover it" % f)
	var old := Session.read_beacon(JSON.stringify({"nestcombe": 1, "key": 3, "port": Session.PORT, "avatar": 0}).to_utf8_buffer())
	_check(not old.is_empty() and not old.joins, "a garden from a build before the protocol fingerprint is heard, not to be joined: %s" % old)
	var other := Session.read_beacon(JSON.stringify({"nestcombe": Session.protocol() + 1, "key": 3, "port": Session.PORT, "avatar": 0}).to_utf8_buffer())
	_check(not other.is_empty() and not other.joins, "a garden from a build with other RPCs is heard, not to be joined: %s" % other)
	var same := Session.read_beacon(JSON.stringify({"nestcombe": Session.protocol(), "key": 3, "port": Session.PORT, "avatar": 0}).to_utf8_buffer())
	_check(not same.is_empty() and same.joins, "a garden from this build is heard and joins: %s" % same)
	var unversioned := JSON.stringify({"key": 3, "port": Session.PORT, "avatar": 0}).to_utf8_buffer()
	_check(Session.read_beacon(unversioned).is_empty(), "a packet without the nestcombe field is no garden")
	var before := _networked("@rpc(\"any_peer\")\nfunc _propose(c): pass\n@rpc(\"any_peer\")\nfunc _resend(): pass\n")
	var after := _networked("@rpc(\"any_peer\")\nfunc _device(d): pass\n@rpc(\"any_peer\")\nfunc _propose(c): pass\n@rpc(\"any_peer\")\nfunc _resend(): pass\n")
	var takes := _networked("@rpc(\"any_peer\")\nfunc _propose(c): pass\n@rpc(\"any_peer\")\nfunc _resend(by): pass\n")
	var plain := _networked("@rpc(\"any_peer\")\nfunc _propose(c): pass\n@rpc(\"any_peer\")\nfunc _resend(): pass\nfunc helper(): pass\n")
	_check(Session.fingerprint([before]) != Session.fingerprint([after]), "an RPC added changes the fingerprint")
	_check(Session.fingerprint([before]) != Session.fingerprint([takes]), "an RPC's arguments change it")
	_check(Session.fingerprint([before]) == Session.fingerprint([plain]), "a method that is not an RPC leaves it")


func _a_picked_name_is_kept() -> void:
	var keep := "user://test-beacon-name"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(keep))
	var me := Persona.new("", 0, keep, 11)
	_check(me.name == Persona.suggest(11) and not me.shared, "a first start offers the machine's name, not shown to others: %s" % me.name)
	_check(not FileAccess.file_exists(keep), "and keeps nothing")
	me.pick()
	_check(me.shared and me.name == Persona.suggest(11), "the first pick shows that name")
	me.pick()
	_check(me.name != Persona.suggest(11), "the next pick offers another: %s" % me.name)
	var again := Persona.new("", 0, keep, 11)
	_check(again.name == me.name and again.shared, "the picked name is kept, shown, for the next start")
	_check(Persona.new("Clover Lark", 0, keep, 11).name == "Clover Lark", "a launch argument names a scripted player over the kept name")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(keep))


func _the_picker_shows_each_host_s_name() -> void:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var session: Session = main.session
	_the_beacon_names_nobody_until_they_pick_a_name(session)
	var tool: VisitTool = main.visit_tool
	var where := "%s:%d" % [NOBODY, Session.PORT + 5]
	var unnamed := "%s:%d" % [NOBODY, Session.PORT + 6]
	session.nearby[where] = {"address": NOBODY, "port": Session.PORT + 5, "key": 5, "avatar": 2, "colour": Session.COLOURS[1], "name": "Hazel Otter", "joins": true, "seen": INF}
	session.nearby[unnamed] = {"address": NOBODY, "port": Session.PORT + 6, "key": 6, "avatar": 1, "colour": Session.COLOURS[2], "name": "", "joins": true, "seen": INF}
	var other := "%s:%d" % [NOBODY, Session.PORT + 7]
	session.nearby[other] = {"address": NOBODY, "port": Session.PORT + 7, "key": 7, "avatar": 3, "colour": Session.COLOURS[3], "name": "Moss Wren", "joins": false, "seen": INF}
	main.rig.left.tool = Hand.Tool.VISIT
	await process_frame
	await process_frame
	var label := _label(tool, where)
	_check(label != null and label.text == "Hazel Otter", "the host's name stands under its figure")
	_check(tool.figures.has(unnamed) and _label(tool, unnamed) == null, "a host who picked no name stands without one")
	_check(tool.figures.has(other) and tool.figures[other].has_node("Cross") and _label(tool, other).text == "Moss Wren", "a garden of another build stands, named, with an X over it")
	_check(not tool.figures[where].has_node("Cross") and not tool.figures[unnamed].has_node("Cross"), "a garden of this build stands without one")
	tool.go(other)
	_check(session.visiting.is_empty(), "picking a garden of another build joins nothing: %s" % session.visiting)
	tool.go(where)
	_check(session.visiting.get("port") == Session.PORT + 5, "picking a garden of this build joins it: %s" % session.visiting)
	await process_frame
	await process_frame
	_check(main.rig.left.tool != Hand.Tool.VISIT and _figures_left(tool) == 0, "joining puts the tool away and its figures go: %d left" % _figures_left(tool))
	session.go_home()
	main.rig.left.tool = Hand.Tool.VISIT
	await process_frame
	await process_frame
	var was := session.me.name
	_check(_label(tool, VisitTool.ME) != null and _label(tool, VisitTool.ME).text == was, "without Steam your own figure stands under your name")
	tool.go(VisitTool.ME)
	await process_frame
	_check(_label(tool, VisitTool.ME).text != was and _label(tool, VisitTool.ME).modulate.a == 1.0, "picking it again offers the next name, shown: %s, was %s" % [_label(tool, VisitTool.ME).text, was])
	session.nearby.erase(where)
	session.nearby.erase(unnamed)
	session.nearby.erase(other)
	main.queue_free()


func _label(tool: VisitTool, k: String) -> Label3D:
	var tag: Node = tool.figures[k].get_node_or_null("Tag") if tool.figures.has(k) else null
	return tag.find_children("*", "Label3D", false, false)[0] if tag else null


## Report (verbatim): "I look at my wife's avatar, and it's just one of the default little pointy wizards, and then I
## load the game and only then do I see her actual avatar". The beacon carried only a built-in avatar's number.
func _the_picker_shows_a_host_s_own_avatar_before_joining() -> void:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
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
	var tool := VisitTool.new(main.rig, viewer)
	main.add_child(tool)
	main.rig.left.tool = Hand.Tool.VISIT
	while host.worn_key == "" and (host._seen_file == "" or not host._jobs.is_empty()):
		await process_frame
	_check(host.worn_key != "" and Session.read_beacon(host.beacon()).wears == host.worn_key, "a host wearing its own file names it in the beacon")
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
	_check(_worn_by(tool, unreachable) == "", "until a host's file arrives they stand in a built-in avatar")
	viewer.nearby.erase(unreachable)
	while viewer.previewing():
		await process_frame
	await process_frame
	_check(viewer.previews.get(host.worn_key) != null, "the viewer fetched and read the host's file without joining")
	_check(_worn_by(tool, where) == host.worn_key, "the host's figure in the picker wears their own avatar: %s" % _worn_by(tool, where))
	_check(viewer.visiting.is_empty() and viewer.players() == 1, "and nobody joined anybody")
	var from: Vector3 = main.rig.head.global_position
	main.rig.teleport(Terrain.ground(from.x + 12.0, from.z - 9.0), 0.0)
	while main.rig._pending != null:
		await process_frame
	await process_frame
	await process_frame
	var head: Vector3 = main.rig.head.global_position
	var behind := tool.find_children("*", "Avatar", true, false).filter(func(a: Node) -> bool: return not a.is_queued_for_deletion() and (a as Node3D).global_position.distance_to(head) > VisitTool.ARC + 1.0)
	_check(behind.is_empty(), "teleporting away leaves no figure standing behind: %d" % behind.size())
	_check(_worn_by(tool, where) == host.worn_key, "and the arc stands again where the player arrived, the host in their own avatar")
	var forged := "ab".repeat(32)
	viewer.nearby["127.0.0.1:1"] = viewer.nearby[where].merged({"wears": forged, "seen": INF}, true)
	await process_frame
	while viewer.previewing():
		await process_frame
	_check(not viewer.previews.has(forged) and viewer._failed.has(forged), "a file whose hash is not the one its beacon names is not shown")
	viewer.nearby.erase("127.0.0.1:1")
	for s in sessions:
		s.get_parent().queue_free()
	tool.queue_free()
	main.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(folder.path_join("crimsom.vrm")))
	await process_frame


func _worn_by(tool: VisitTool, k: String) -> String:
	if not tool.figures.has(k):
		return "no figure"
	var a: Avatar = tool.figures[k].get_child(0)
	return a.source


## Avatars still standing in the picker, not counting those already let go.
func _figures_left(tool: VisitTool) -> int:
	return tool.find_children("*", "Avatar", true, false).filter(func(a: Node) -> bool: return not a.is_queued_for_deletion()).size()
