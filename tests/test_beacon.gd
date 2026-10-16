extends SceneTree

## Scripted and test instances never beacon past loopback, and beacons carry each host's name to the visit picker:
## godot4 --headless --path game --script ../tests/test_beacon.gd

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_scripts_are_not_players()
	_names_are_clean_and_short()
	_a_picked_name_is_kept()
	await _a_test_instance_beacons_on_loopback_only()
	await _the_picker_shows_each_host_s_name()
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
	var heard := Session.read_beacon(s.beacon())
	_check(heard.get("name") == "" and heard.get("port") == s.port and not s.beacon().get_string_from_utf8().contains(s.me.name), "the beacon carries no name nobody picked: %s" % s.beacon().get_string_from_utf8())
	s.me.pick()
	heard = Session.read_beacon(s.beacon())
	_check(heard.get("name") == s.me.name, "a picked name rides the beacon: %s" % heard)
	var hostile := JSON.stringify({"nestcombe": 1, "key": 3, "port": Session.PORT, "avatar": 0, "name": "\u0000" + "W".repeat(400)}).to_utf8_buffer()
	heard = Session.read_beacon(hostile)
	_check(heard.is_empty() or heard.name.length() <= Persona.MAX_NAME, "a hostile beacon is cut down or dropped: %s" % heard)


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
	var where := "127.0.0.1:%d" % (Session.PORT + 5)
	var unnamed := "127.0.0.1:%d" % (Session.PORT + 6)
	session.nearby[where] = {"address": "127.0.0.1", "port": Session.PORT + 5, "key": 5, "avatar": 2, "colour": Session.COLOURS[1], "name": "Hazel Otter", "seen": INF}
	session.nearby[unnamed] = {"address": "127.0.0.1", "port": Session.PORT + 6, "key": 6, "avatar": 1, "colour": Session.COLOURS[2], "name": "", "seen": INF}
	main.rig.left.tool = Hand.Tool.VISIT
	await process_frame
	await process_frame
	var label := _label(tool, where)
	_check(label != null and label.text == "Hazel Otter", "the host's name stands under its figure")
	_check(tool.figures.has(unnamed) and _label(tool, unnamed) == null, "a host who picked no name stands without one")
	var was := session.me.name
	_check(_label(tool, VisitTool.ME) != null and _label(tool, VisitTool.ME).text == was, "without Steam your own figure stands under your name")
	tool.go(VisitTool.ME)
	await process_frame
	_check(_label(tool, VisitTool.ME).text != was and _label(tool, VisitTool.ME).modulate.a == 1.0, "picking it again offers the next name, shown: %s, was %s" % [_label(tool, VisitTool.ME).text, was])
	session.nearby.erase(where)
	session.nearby.erase(unnamed)
	main.queue_free()


func _label(tool: VisitTool, k: String) -> Label3D:
	var tag: Node = tool.figures[k].get_node_or_null("Tag") if tool.figures.has(k) else null
	return tag.find_children("*", "Label3D", false, false)[0] if tag else null
