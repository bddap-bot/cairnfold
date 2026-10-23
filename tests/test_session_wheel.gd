extends SceneTree

var failures := 0
var main: Node

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)

## Every subtree's icon in `tree` draws its items as their own icons draw them, so none shows what its menu lacks.
func _check_icons(tree: Array, people: SessionWheel) -> void:
	for item in tree:
		if item is Array:
			var model := Hand.miniature(item, people.figure)
			_check(_shows(model, item, people, 2), "the icon of %s shows what it holds" % [item])
			model.free()
			_check_icons(item, people)


func _shows(model: Node3D, item: Variant, people: SessionWheel, depth: int) -> bool:
	if item is Array:
		var shown := range(mini(item.size(), 4)).filter(func(j: int) -> bool: return depth > 1 or not item[j] is Array)
		return model.get_child_count() == shown.size() and range(shown.size()).all(func(c: int) -> bool: return _shows(model.get_child(c), item[shown[c]], people, depth - 1))
	var drawn := people.figure(item) if item is String else Hand.miniature(item)
	var same := _meshes(model) == _meshes(drawn)
	drawn.free()
	return same


func _meshes(model: Node) -> Array:
	return model.find_children("*", "MeshInstance3D", true, false).map(func(m: MeshInstance3D) -> Array: return [m.mesh.get_class(), m.mesh.get_aabb()])


func _run() -> void:
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var hand: Hand = main.rig.right
	var session: Session = main.session
	_check(hand.people.friends() == ["empty"], "zero peers has one empty slot")
	_check_icons(hand.inventory(), hand.people)
	var empty := hand.people.figure("empty")
	_check(not _meshes(empty).any(func(m: Array) -> bool: return m[0] == "TorusMesh") and not empty.find_children("*", "Avatar", true, false).is_empty(), "no one to join shows a figure's outline")
	for mesh: MeshInstance3D in empty.find_children("*", "MeshInstance3D", true, false):
		_check(mesh.material_override is BaseMaterial3D and mesh.material_override.albedo_color.a < 0.5, "the outline of no one is faint")
	empty.free()
	for i in 25:
		session.nearby["192.0.2.1:%d" % (8000 + i)] = {"address": "192.0.2.1", "port": 8000 + i, "key": i, "avatar": i % 3, "colour": Color.WHITE, "name": "Friend %d" % i, "joins": true, "seen": INF}
	var tree := hand.inventory()
	_check_icons(tree, hand.people)
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
	var drawn_as_icons := func(n: Node) -> bool:
		return (n.find_children("*", "MeshInstance3D", true, false) + n.find_children("*", "MultiMeshInstance3D", true, false)).all(func(g: GeometryInstance3D) -> bool:
			var mi := g as MeshInstance3D
			var count := mi.mesh.get_surface_count() if mi != null and g.material_override == null else 1
			return range(count).all(func(i: int) -> bool:
				var m: Material = g.material_override if g.material_override != null else mi.get_active_material(i)
				return m is ShaderMaterial and m.shader.code.contains('#include "res://src/icon.gdshaderinc"')))
	_check(not hand._wheel_root.find_children("*", "Avatar", true, false).is_empty() and hand._wheel_root.find_children("*", "Avatar", true, false).all(drawn_as_icons), "preview figures draw in the icon look")
	_check(hand._built.size() > 20 and hand._built.values().all(drawn_as_icons), "every wheel icon draws in the icon look alone, lit by nothing in the garden")
	_check(not drawn_as_icons.call(main.rig.body), "world avatars keep the garden's light")
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
		Hand.unlit(preview)
		preview.free()
		if cached >= 0:
			_check(Hand._icon_mats.size() == cached, "closing repeated previews does not retain their tint materials")
		cached = Hand._icon_mats.size()
	var vanished := hand.people.figure("join:192.0.2.1:8000")
	vanished.free()
	main.queue_free()
	await process_frame
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)
