extends RefCounted

## A Unity package's assets by GUID: an Assets folder with each asset's .meta beside it, or a .unitypackage unpacked
## as Unity ships it, one folder per GUID holding `asset`, `asset.meta` and `pathname`.

const Yaml = preload("res://../scripts/unity/yaml.gd")

## GUID to {"file": where its bytes are, "path": its path in the project, "meta": its .meta file}.
var by_guid := {}
var _metas := {}


func _init(dir: String) -> void:
	var pending := [dir]
	while not pending.is_empty():
		var at: String = pending.pop_back()
		if FileAccess.file_exists(at.path_join("pathname")):
			var path := FileAccess.get_file_as_string(at.path_join("pathname")).split("\n")[0].strip_edges()
			_add(at.path_join("asset"), path, at.path_join("asset.meta"))
			continue
		for sub in DirAccess.get_directories_at(at):
			pending.append(at.path_join(sub))
		for f in DirAccess.get_files_at(at):
			if f.ends_with(".meta") and FileAccess.file_exists(at.path_join(f.trim_suffix(".meta"))):
				var file := at.path_join(f.trim_suffix(".meta"))
				_add(file, file.trim_prefix(dir).trim_prefix("/"), at.path_join(f))


func _add(file: String, path: String, meta: String) -> void:
	if not FileAccess.file_exists(meta):
		return
	for line in FileAccess.get_file_as_string(meta).split("\n", false, 4):
		if line.begins_with("guid: "):
			by_guid[line.trim_prefix("guid: ").strip_edges()] = {"file": file, "path": path, "meta": meta}
			return


## The asset's .meta as a document, or empty for an unknown GUID.
func meta(guid: String) -> Dictionary:
	if not by_guid.has(guid):
		return {}
	if not _metas.has(guid):
		var lines: Array[String] = []
		lines.assign(FileAccess.get_file_as_string(by_guid[guid].meta).split("\n"))
		_metas[guid] = Yaml.document(lines)
	return _metas[guid]


func extension(guid: String) -> String:
	return (by_guid[guid].path as String).get_extension().to_lower() if by_guid.has(guid) else ""


func name(guid: String) -> String:
	return (by_guid[guid].path as String).get_file().get_basename() if by_guid.has(guid) else ""


func text(guid: String) -> String:
	return FileAccess.get_file_as_string(by_guid[guid].file) if by_guid.has(guid) else ""


## The GUIDs of every asset whose path ends in one of `extensions`.
func of(extensions: Array) -> Array:
	return by_guid.keys().filter(func(g: String) -> bool: return extension(g) in extensions)
