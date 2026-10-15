extends SceneTree

## Scripted and test instances never beacon past loopback: godot4 --headless --path game --script ../tests/test_beacon.gd

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_scripts_are_not_players()
	await _a_test_instance_beacons_on_loopback_only()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	quit(1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _scripts_are_not_players() -> void:
	_check(Session.played({}, true), "a game launched bare is a player's")
	_check(Session.played({"avatar": "1"}, true), "and so is one picking an avatar")
	for args in [{"script": "coop-host.json", "port": "7480", "host-port": "7480"}, {"join": "127.0.0.1:7480", "script": "guest1.json"}, {"join": "192.168.1.2"}, {"port": "7536"}]:
		_check(not Session.played(args, true), "a game launched with %s is a script's" % args)
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
