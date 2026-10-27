extends "res://../tests/support/suite.gd"


func _initialize() -> void:
	_run.call_deferred()


## Every subtree's icon in `tree` draws its items as their own icons draw them, so none shows what its menu lacks.
func _check_icons(tree: Array, people: SessionWheel) -> void:
	for item in tree:
		if item is Array:
			var model := Hand.miniature(item, people.figure)
			check(_shows(model, item, people, 2), "the icon of %s shows what it holds" % [item])
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
	boot_main()
	await process_frame
	var hand: Hand = main.rig.right
	var session: Session = main.session
	check(hand.people.friends() == ["empty"], "zero peers has one empty slot")
	_check_icons(hand.inventory(), hand.people)
	var empty := hand.people.figure("empty")
	check(not _meshes(empty).any(func(m: Array) -> bool: return m[0] == "TorusMesh") and not empty.find_children("*", "Avatar", true, false).is_empty(), "no one to join shows a figure's outline")
	for mesh: MeshInstance3D in empty.find_children("*", "MeshInstance3D", true, false):
		check(mesh.material_override is BaseMaterial3D and mesh.material_override.albedo_color.a < 0.5, "the outline of no one is faint")
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
			check(at.length() < 0.5, "friend paging stays within reach: %s at %s" % [key, at])
			wheel.move(at)
		check(wheel.chosen() == key, "every friend is reachable through bounded pages: " + key)
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
	check(not hand._wheel_root.find_children("*", "Avatar", true, false).is_empty(), "the open avatar page contains figures")
	var drawn_as_icons := func(n: Node) -> bool:
		return (n.find_children("*", "MeshInstance3D", true, false) + n.find_children("*", "MultiMeshInstance3D", true, false)).all(func(g: GeometryInstance3D) -> bool:
			var mi := g as MeshInstance3D
			var count := mi.mesh.get_surface_count() if mi != null and g.material_override == null else 1
			return range(count).all(func(i: int) -> bool:
				var m: Material = g.material_override if g.material_override != null else mi.get_active_material(i)
				return m is ShaderMaterial and m.shader.code.contains('#include "res://src/icon.gdshaderinc"')))
	check(not hand._wheel_root.find_children("*", "Avatar", true, false).is_empty() and hand._wheel_root.find_children("*", "Avatar", true, false).all(drawn_as_icons), "preview figures draw in the icon look")
	check(hand._built.size() > 20 and hand._built.values().all(drawn_as_icons), "every wheel icon draws in the icon look alone, lit by nothing in the garden")
	check(not drawn_as_icons.call(main.rig.body), "world avatars keep the garden's light")
	Buttons.injected.erase(button)
	await process_frame
	await process_frame
	check(session.avatar == 1, "release on the avatar slot selects it")
	check(not hand._wheel_root.visible and hand._wheel_root.get_children().all(func(i: Node3D) -> bool: return not i.visible), "release leaves no wheel figure shown")
	var built: Array = hand._wheel_root.get_children()
	Buttons.injected[button] = true
	await process_frame
	await process_frame
	tree = hand.inventory()
	for at in ToolWheel.sweep(tree, ToolWheel.paths(tree)["avatar:1"]):
		Hand.injected_reach[hand.tracker] = at
		await process_frame
	check(hand._wheel_root.get_children() == built, "opening and sweeping the wheel again builds no icon")
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
	check(hand.picking and hand._wheel_root.get_child_count() > 0, "zero-peer friends page is open before switching tools")
	hand.tool = Hand.Tool.SEEDS
	await process_frame
	check(not hand.picking and hand._wheel_root.get_children().all(func(i: Node3D) -> bool: return not i.visible), "zero-peer tool switch leaves no menu figure shown")
	Hand.injected_reach.erase(hand.tracker)
	Buttons.injected.erase(button)
	await process_frame
	await _every_file_in_the_folder_is_on_the_wheel(session, hand)
	var cached := -1
	for repeat in 3:
		var preview := hand.people.figure("avatar:0")
		Hand.unlit(preview)
		preview.free()
		if cached >= 0:
			check(Hand._icon_mats.size() == cached, "closing repeated previews does not retain their tint materials")
		cached = Hand._icon_mats.size()
	var vanished := hand.people.figure("join:192.0.2.1:8000")
	vanished.free()
	main.queue_free()
	await process_frame
	finish()


## Each .vrm in the folder that reads is a slot of its own; the newest to arrive is worn, and the worn one removed, the
## built-in avatar is.
func _every_file_in_the_folder_is_on_the_wheel(session: Session, hand: Hand) -> void:
	var source := ProjectSettings.globalize_path("res://").path_join("../tests/avatars")
	var vrms := Array(DirAccess.get_files_at(source)).filter(func(f: String) -> bool: return f.get_extension() == "vrm")
	vrms.sort()
	var folder := ProjectSettings.globalize_path("user://test-wheel-avatars")
	DirAccess.make_dir_recursive_absolute(folder)
	session.folder = folder
	var keys := {}
	for f: String in ["b.vrm", "a.vrm"]:
		var bytes := FileAccess.get_file_as_bytes(source.path_join(vrms[keys.size()]))
		keys[f] = Session._hash(bytes)
		var out := FileAccess.open(folder.path_join(f), FileAccess.WRITE)
		out.store_buffer(bytes)
		out.close()
		session._look_in_folder()
		while session._reading != "":
			await process_frame
		check(session.worn_key == keys[f] and main.rig.body.source == keys[f], "the newest file to arrive is worn: " + f)
	var slots := ToolWheel.paths(hand.people.avatars()).keys().filter(func(k: String) -> bool: return k.begins_with("file:"))
	check(slots == ["file:a.vrm", "file:b.vrm"], "two files are two slots, in name order: %s" % [slots])
	session._look_in_folder()
	check(session._reading == "" and session._jobs.is_empty(), "an unchanged file is not read again")
	hand.people.activate("avatar:2")
	check(session.worn.is_empty() and session.avatar == 2, "a built-in choice replaces a worn file")
	for f: String in keys:
		hand.people.activate("file:" + f)
		check(session.worn_key == keys[f] and main.rig.body.source == keys[f], "choosing a file's slot wears it: " + f)
	DirAccess.remove_absolute(folder.path_join("a.vrm"))
	session._look_in_folder()
	check(session.worn_key == "" and session.worn.is_empty(), "removing the worn file brings the built-in avatar back")
	check(not ToolWheel.paths(hand.inventory()).has("file:a.vrm") and ToolWheel.paths(hand.inventory()).has("file:b.vrm"), "and takes its slot off the wheel")
	session.folder = ""
	session.files.clear()
