extends "res://../tests/support/suite.gd"

## game/shaders.tres holds one material for every shader the game draws with, each .gdshader's and each
## StandardMaterial3D set up as a booted game sets one up: the export's shader baker compiles only shaders it meets in
## exported materials, and the game makes its own in code, so without this list a fresh install compiles them on the
## headset as it loads. `scripts/shaders.sh` rewrites it.

const LIST := "res://shaders.tres"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	boot_main()
	await frames(4)
	var made := {}
	for path in _shader_files("res://"):
		var m := ShaderMaterial.new()
		m.shader = load(path)
		made[key(m)] = m
	_gather(root, made, {})
	if "--write" in OS.get_cmdline_user_args():
		var list := Resource.new()
		var keys := made.keys()
		keys.sort()
		list.set_meta("materials", keys.map(func(k: String) -> Material: return _bare(made[k])))
		check(ResourceSaver.save(list, LIST) == OK, "writes %s" % LIST)
	else:
		var listed := {}
		for m: Material in load(LIST).get_meta("materials"):
			listed[key(m)] = true
		for k: String in made:
			check(listed.has(k), "%s lacks %s; run scripts/shaders.sh" % [LIST, k])
		for k: String in listed:
			check(made.has(k), "%s lists %s, which the game no longer makes; run scripts/shaders.sh" % [LIST, k])
	finish()


## What picks a material's shader: a ShaderMaterial's file, or a BaseMaterial3D's class and its switches, every int
## and bool it stores, the ones BaseMaterial3D builds its shader code from among them.
static func key(m: Material) -> String:
	if m is ShaderMaterial:
		return "shader " + m.shader.resource_path
	var parts := [m.get_class()]
	for p in _switches(m):
		parts.append("%s=%s" % [p, m.get(p)])
	return " ".join(parts)


static func _switches(m: Material) -> PackedStringArray:
	var out := PackedStringArray()
	for p in m.get_property_list():
		if p.usage & PROPERTY_USAGE_STORAGE and p.type in [TYPE_INT, TYPE_BOOL] and p.name not in ["render_priority", "resource_local_to_scene"]:
			out.append(p.name)
	out.sort()
	return out


## A copy of `m` holding only what picks its shader.
static func _bare(m: Material) -> Material:
	if m is ShaderMaterial:
		var s := ShaderMaterial.new()
		s.shader = m.shader
		return s
	var b: Material = ClassDB.instantiate(m.get_class())
	for p in _switches(m):
		b.set(p, m.get(p))
	return b


static func _shader_files(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for d in DirAccess.get_directories_at(dir):
		if not d.begins_with("."):
			out.append_array(_shader_files(dir.path_join(d)))
	for f in DirAccess.get_files_at(dir):
		if f.get_extension() == "gdshader":
			out.append(dir.path_join(f))
	return out


## Every material reached from `o`'s stored properties, through nodes, meshes, arrays and dictionaries.
static func _gather(o: Variant, made: Dictionary, seen: Dictionary) -> void:
	if o is Node:
		for c: Node in o.get_children(true):
			_gather(c, made, seen)
	if o is Object:
		if seen.has(o):
			return
		seen[o] = true
		if o is ShaderMaterial and o.shader != null and o.shader.resource_path != "" or o is BaseMaterial3D:
			made[key(o)] = o
		for p in o.get_property_list():
			if p.type in [TYPE_OBJECT, TYPE_ARRAY, TYPE_DICTIONARY] and p.usage & PROPERTY_USAGE_STORAGE:
				_gather(o.get(p.name), made, seen)
	elif o is Array:
		for v in o:
			_gather(v, made, seen)
	elif o is Dictionary:
		for v in o.values():
			_gather(v, made, seen)
