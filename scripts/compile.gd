extends SceneTree

## Loads every game and test script, so check.sh sees each one's analyzer errors, including those an override.cfg
## raises. A test that fails to compile would otherwise idle until test.sh's timeout.


func _init() -> void:
	var dirs := ["res://", "res://../tests"]
	while not dirs.is_empty():
		var dir: String = dirs.pop_back()
		var path := ProjectSettings.globalize_path(dir).simplify_path()
		for sub in DirAccess.get_directories_at(path):
			if not sub.begins_with("."):
				dirs.append(dir.path_join(sub))
		for file in DirAccess.get_files_at(path):
			if file.get_extension() == "gd":
				load(dir.path_join(file))
	quit()
