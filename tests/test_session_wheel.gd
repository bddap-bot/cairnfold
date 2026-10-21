extends SceneTree

var failures := 0
var main: Node

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)

func _run() -> void:
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var hand: Hand = main.rig.right
	var session: Session = main.session
	_check(hand.people.friends() == ["empty"], "zero peers has one empty slot")
	for i in 25:
		session.nearby["192.0.2.1:%d" % (8000 + i)] = {"address": "192.0.2.1", "port": 8000 + i, "key": i, "avatar": i % 3, "colour": Color.WHITE, "name": "Friend %d" % i, "joins": true, "seen": INF}
	var tree := hand.inventory()
	var paths := ToolWheel.paths(tree)
	for i in 25:
		var key := "join:192.0.2.1:%d" % (8000 + i)
		var wheel := ToolWheel.new(tree)
		for at in ToolWheel.sweep(tree, paths[key]):
			_check(at.length() < 0.5, "friend paging stays within reach: %s at %s" % [key, at])
			wheel.move(at)
		_check(wheel.chosen() == key, "every friend is reachable through bounded pages: " + key)
	session.nearby.clear()
	var button := "right_hand/" + Controls.input("wheel", "right_hand")
	Buttons.injected[button] = true
	await process_frame
	await process_frame
	tree = hand.inventory()
	for at in ToolWheel.sweep(tree, ToolWheel.paths(tree)["avatar:1"]):
		Hand.injected_reach[hand.tracker] = at
		await process_frame
		await process_frame
	_check(not hand._wheel_root.find_children("*", "Avatar", true, false).is_empty(), "the open avatar page contains figures")
	for figure in hand._wheel_root.find_children("*", "Avatar", true, false):
		for mesh in figure.find_children("*", "MeshInstance3D", true, false):
			for surface in mesh.mesh.get_surface_count():
				var material := mesh.get_active_material(surface) as BaseMaterial3D
				_check(material != null and material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "preview figures use the shared icon lighting")
	for mesh in main.rig.body.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as BaseMaterial3D
			_check(material != null and material.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED, "world avatars retain world lighting")
	Buttons.injected.erase(button)
	await process_frame
	await process_frame
	_check(session.avatar == 1, "release on the avatar slot selects it")
	_check(not hand._wheel_root.visible and hand._wheel_root.get_children().all(func(i: Node3D) -> bool: return not i.visible), "release leaves no wheel figure shown")
	var built: Array = hand._wheel_root.get_children()
	Buttons.injected[button] = true
	await process_frame
	await process_frame
	tree = hand.inventory()
	for at in ToolWheel.sweep(tree, ToolWheel.paths(tree)["avatar:1"]):
		Hand.injected_reach[hand.tracker] = at
		await process_frame
	_check(hand._wheel_root.get_children() == built, "opening and sweeping the wheel again builds no icon")
	Buttons.injected.erase(button)
	await process_frame
	await process_frame
	Hand.injected_reach.erase(hand.tracker)
	Buttons.injected[button] = true
	await process_frame
	await process_frame
	tree = hand.inventory()
	for at in ToolWheel.sweep(tree, ToolWheel.paths(tree)["empty"]):
		Hand.injected_reach[hand.tracker] = at
		await process_frame
		await process_frame
	_check(hand.picking and hand._wheel_root.get_child_count() > 0, "zero-peer friends page is open before switching tools")
	hand.tool = Hand.Tool.SEEDS
	await process_frame
	_check(not hand.picking and hand._wheel_root.get_children().all(func(i: Node3D) -> bool: return not i.visible), "zero-peer tool switch leaves no menu figure shown")
	Hand.injected_reach.erase(hand.tracker)
	Buttons.injected.erase(button)
	await process_frame
	var bytes := FileAccess.get_file_as_bytes(Avatar.BUILT_IN[0])
	var key := Session._hash(bytes)
	session._put_on(key, bytes, Avatar.built_in(0), session._seen_file)
	hand.people.activate("avatar:2")
	_check(session.worn.is_empty() and session.avatar == 2, "a built-in choice replaces the loaded file")
	_check(ToolWheel.paths(hand.inventory()).has("avatar:file"), "the loaded file stays available on the wheel")
	hand.people.activate("avatar:file")
	_check(session.worn_key == key and main.rig.body.source == key, "the loaded file can be selected again")
	var cached := -1
	for repeat in 3:
		var preview := hand.people.figure("avatar:0")
		for mesh in preview.find_children("*", "MeshInstance3D", true, false):
			Hand.unshade(mesh)
		preview.free()
		if cached >= 0:
			_check(Hand._unshaded.size() == cached, "closing repeated previews does not retain their tint materials")
		cached = Hand._unshaded.size()
	var vanished := hand.people.figure("join:192.0.2.1:8000")
	vanished.free()
	main.queue_free()
	await process_frame
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)
