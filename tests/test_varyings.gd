extends "res://../tests/support/suite.gd"

## Every shader fits the varyings a Quest 2 gives one: Godot refuses a shader past the device's limit when it parses it
## on the headset, and the desktop's renderer allows more, so nothing else here would meet the refusal. Counted as
## servers/rendering/shader_language.cpp counts them: the renderer's own varyings for its shader type, then one per
## varying the preprocessed code declares, a matrix one per column and an array one per element, each include once.

const Shaders := preload("res://../tests/test_shaders.gd")

## The Quest 2's Vulkan limit: maxVertexOutputComponents / 4, as the device reports it.
const LIMIT := 28
## The varyings each shader type's renderer takes before a shader's own (base_varying_index in the forward mobile and
## clustered scene shaders, the canvas renderer and the sky).
const BASE := {"spatial": 15, "canvas_item": 9, "sky": 10, "particles": 10}
const MATRIX_COLUMNS := {"mat2": 2, "mat3": 3, "mat4": 4}


func _init() -> void:
	_counts_as_the_engine_does()
	for path in Shaders._shader_files("res://"):
		var used := varyings(path)
		check(used <= LIMIT, "%s uses %d varyings, past a Quest 2's %d" % [path, used, LIMIT])
	finish()


func _counts_as_the_engine_does() -> void:
	var at := "user://varyings"
	DirAccess.make_dir_recursive_absolute(at)
	var inc := at.path_join("parts.gdshaderinc")
	_write(inc, "varying vec3 shared;\n#ifdef TWO // set by two\nvarying mat3 frame;\n#endif\n#ifndef TWO\nvarying vec4 alone;\n#endif\n")
	var two := at.path_join("two.gdshader")
	_write(two, "shader_type spatial;\n// varying vec4 commented;\n#define TWO\n#include \"%s\"\n#include \"%s\"\nvarying flat int kind[2];\n#if defined(TWO) && !defined(THREE)\nvarying float more;\n#else\nvarying mat2 less;\n#endif\n" % [inc, inc])
	check(varyings(two) == 15 + 1 + 3 + 2 + 1, "a matrix counts its columns, an array its elements, an include once, a comment nothing")
	var one := at.path_join("one.gdshader")
	_write(one, "shader_type canvas_item;\n#include \"%s\"\n#if defined(TWO) && !defined(THREE)\nvarying float more;\n#else\nvarying vec2 less;\nvarying vec2 lesser;\n#endif\n" % inc)
	check(varyings(one) == 9 + 1 + 1 + 2, "what a branch leaves out counts nothing")


static func _write(path: String, code: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(code)
	f.close()


## How many varyings the shader at `path` takes as Godot counts them, or a number past any limit where it cannot read
## the shader.
static func varyings(path: String) -> int:
	var lines := PackedStringArray()
	if not _expand(path, {}, {}, lines):
		return 1 << 20
	var used := -1
	var declared := RegEx.create_from_string("^varying\\s+(?:(?:flat|smooth)\\s+)?(?:(?:lowp|mediump|highp)\\s+)?(\\w+)\\s+\\w+\\s*(?:\\[\\s*(\\d+)\\s*\\])?\\s*;")
	var typed := RegEx.create_from_string("^shader_type\\s+(\\w+)\\s*;")
	for line in lines:
		var t := typed.search(line)
		if t != null:
			used = BASE.get(t.get_string(1), -1)
		if not line.begins_with("varying"):
			continue
		var m := declared.search(line)
		if m == null or used < 0:
			push_error("%s: cannot count %s" % [path, line])
			return 1 << 20
		used += MATRIX_COLUMNS.get(m.get_string(1), 1) * (int(m.get_string(2)) if m.get_string(2) != "" else 1)
	return used


## Appends the lines of the file at `path` that the preprocessor keeps, with `defines` set, to `out`; false where it
## meets a directive it does not know.
static func _expand(path: String, defines: Dictionary, included: Dictionary, out: PackedStringArray) -> bool:
	if included.has(path):
		return true
	included[path] = true
	var comment := RegEx.create_from_string("(?<!:)//.*$")
	var live := [true]
	var taken := [true]
	for raw in FileAccess.get_file_as_string(path).split("\n"):
		var line := comment.sub(raw, "").strip_edges()
		if not line.begins_with("#"):
			if live.back():
				out.append(line)
			continue
		var word := line.substr(1).strip_edges().get_slice(" ", 0)
		var rest := line.substr(1).strip_edges().trim_prefix(word).strip_edges()
		var outer: bool = live.back()
		match word:
			"ifdef", "ifndef", "if":
				var on: Variant = defines.has(rest) if word == "ifdef" else not defines.has(rest) if word == "ifndef" else _holds(rest, defines)
				if on == null:
					push_error("%s: cannot read #if %s" % [path, rest])
					return false
				live.append(outer and on)
				taken.append(on)
			"else":
				live.pop_back()
				live.append(live.back() and not taken.back())
			"endif":
				live.pop_back()
				taken.pop_back()
			"define":
				if outer:
					defines[rest.get_slice(" ", 0)] = true
			"undef":
				if outer:
					defines.erase(rest)
			"include":
				if outer and not _expand(rest.trim_prefix("\"").trim_suffix("\""), defines, included, out):
					return false
			_:
				push_error("%s: no directive #%s" % [path, word])
				return false
	return true


## Whether an #if's `condition` of defined() checks joined by !, && and || holds, or null where it is anything else.
static func _holds(condition: String, defines: Dictionary) -> Variant:
	var named := RegEx.create_from_string("defined\\s*\\(\\s*(\\w+)\\s*\\)")
	var text := condition
	for m in named.search_all(condition):
		text = text.replace(m.get_string(), "true" if defines.has(m.get_string(1)) else "false")
	text = text.replace("&&", " and ").replace("||", " or ").replace("!", " not ")
	if RegEx.create_from_string("[^\\s()]+").search_all(text).any(func(m: RegExMatch) -> bool: return m.get_string() not in ["true", "false", "and", "or", "not"]):
		return null
	var e := Expression.new()
	if e.parse(text) != OK:
		return null
	return e.execute()
