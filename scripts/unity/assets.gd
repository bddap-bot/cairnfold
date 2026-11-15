extends RefCounted

## Assets by GUID, from an Assets folder with each .meta beside its asset, or an unpacked .unitypackage.

const Yaml = preload("res://../scripts/unity/yaml.gd")

const IMAGES := ["png", "jpg", "jpeg", "tga", "bmp", "webp", "exr", "hdr"]

## GUID to {"file": where its bytes are, "path": its path in the project, "meta": its .meta file}.
var by_guid := {}
## Where the avatar is looked for.
var own := {}
var _metas := {}
## Set by the converter's --names; otherwise messages print numbers and counts, and the engine's messages while it
## reads a package's files, which name them, are held back (quietly).
static var print_names := false


static func quietly(read: Callable) -> Variant:
	var shown := Engine.print_error_messages
	Engine.print_error_messages = shown and print_names
	var out: Variant = read.call()
	Engine.print_error_messages = shown
	return out


## `lent` packages lend what `dir` lacks, an earlier one's over a later's. `packages` lends only images, the shader
## textures avatars reference by GUID but never ship, so its prefabs and scenes cannot change which avatar converts.
func _init(dir: String, lent: PackedStringArray = [], packages := "") -> void:
	by_guid = _scan(dir)
	own = by_guid.duplicate()
	for other in lent:
		by_guid.merge(_scan(other))
	if packages == "":
		return
	var installed := _scan(packages)
	for guid: String in installed:
		if not by_guid.has(guid) and (installed[guid].path as String).get_extension().to_lower() in IMAGES:
			by_guid[guid] = installed[guid]


static func _scan(dir: String) -> Dictionary:
	var out := {}
	var pending := [dir]
	while not pending.is_empty():
		var at: String = pending.pop_back()
		if FileAccess.file_exists(at.path_join("pathname")):
			var path := FileAccess.get_file_as_string(at.path_join("pathname")).split("\n")[0].strip_edges()
			_add(out, at.path_join("asset"), path, at.path_join("asset.meta"))
			continue
		for sub in DirAccess.get_directories_at(at):
			pending.append(at.path_join(sub))
		for f in DirAccess.get_files_at(at):
			var file := at.path_join(f.trim_suffix(".meta"))
			if f.ends_with(".meta") and FileAccess.file_exists(file):
				_add(out, file, file.trim_prefix(dir).trim_prefix("/"), at.path_join(f))
	return out


static func _add(out: Dictionary, file: String, path: String, meta: String) -> void:
	if not FileAccess.file_exists(meta):
		return
	for line in FileAccess.get_file_as_string(meta).split("\n", false, 4):
		if line.begins_with("guid: "):
			out[line.trim_prefix("guid: ").strip_edges()] = {"file": file, "path": path, "meta": meta}
			return


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


func of(extensions: Array) -> Array:
	return by_guid.keys().filter(func(g: String) -> bool: return extension(g) in extensions)
