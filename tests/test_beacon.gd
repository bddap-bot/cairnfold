extends SceneTree

## Scripted and test instances never beacon past loopback, beacons carry each host's name to the visit picker, and a
## garden of another build stands there with an X and cannot be joined:
## godot4 --headless --path game --script ../tests/test_beacon.gd

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
	session.go_home()
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
