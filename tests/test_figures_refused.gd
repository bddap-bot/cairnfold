extends "res://../tests/support/booted.gd"

## A file that does not read reaches the step as a null read, as one too heavy to read does.


func _run() -> void:
	var path := ProjectSettings.globalize_path("user://refused.vrm")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer("not a VRM".to_utf8_buffer())
	f.close()
	await play([{"op": "figures", "file": path, "spots": [[6, 6], [10, 2], [14, -2]]}])
	var stood := main.get_children().filter(func(n: Node) -> bool: return n is Avatar and n.is_in_group(Contacts.BODIES) and n != main.rig.body)
	check(stood.size() == 3, "the step stands its three figures: %d" % stood.size())
	check(stood.all(func(a: Avatar) -> bool: return a.source == "" and a.scene == Avatar.built_in(0)), "each stands as a built-in avatar")
	finish()
