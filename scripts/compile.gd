extends SceneTree

## Loads every game script, so check.sh sees each one's analyzer errors, including those its override.cfg raises.


func _init() -> void:
	var dirs := ["res://"]
	while not dirs.is_empty():
		var dir: String = dirs.pop_back()
		for sub in DirAccess.get_directories_at(dir):
			if not sub.begins_with("."):
				dirs.append(dir.path_join(sub))
		for file in DirAccess.get_files_at(dir):
			if file.get_extension() == "gd":
				load(dir.path_join(file))
	quit()
