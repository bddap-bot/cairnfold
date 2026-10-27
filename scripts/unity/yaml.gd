extends RefCounted

## The subset of YAML Unity writes its scenes, prefabs, materials and .meta files in: block mappings and sequences,
## one-line flow mappings and sequences, plain and quoted scalars. Every scalar stays a String.


## A scene or prefab file's objects by file ID: {"class": Unity class ID, "type": its type name, "stripped": whether
## it stands for an object of a prefab it instances, "data": its fields}.
static func objects(text: String) -> Dictionary:
	var out := {}
	var lines := text.split("\n")
	var i := 0
	while i < lines.size():
		var head := lines[i]
		i += 1
		if not head.begins_with("--- !u!"):
			continue
		var parts := head.substr(7).split(" ")
		var body: Array[String] = []
		while i < lines.size() and not lines[i].begins_with("--- "):
			body.append(lines[i])
			i += 1
		var doc := document(body)
		var type: String = doc.keys()[0] if doc.size() == 1 else ""
		out[parts[1].trim_prefix("&").to_int()] = {"class": parts[0].to_int(), "type": type, "stripped": parts.size() > 2 and parts[2] == "stripped", "data": doc.get(type, {}) if doc.get(type) is Dictionary else {}}
	return out


## One YAML document (a .meta or .mat file, or one object of a scene) as nested Dictionaries, Arrays and Strings.
static func document(lines: Array[String]) -> Dictionary:
	var kept: Array[String] = []
	for line in lines:
		if line.strip_edges() != "" and not line.begins_with("%") and not line.begins_with("---"):
			kept.append(line.trim_suffix("\r"))
	var at := [0]
	var out: Variant = _block(kept, at, 0)
	return out if out is Dictionary else {}


static func _indent(line: String) -> int:
	var n := 0
	while n < line.length() and line[n] == " ":
		n += 1
	return n


static func _block(lines: Array[String], at: Array, indent: int) -> Variant:
	if at[0] >= lines.size():
		return ""
	var first := lines[at[0]]
	if _indent(first) == indent and first.substr(indent).begins_with("-"):
		return _sequence(lines, at, indent)
	return _mapping(lines, at, indent)


static func _sequence(lines: Array[String], at: Array, indent: int) -> Array:
	var out := []
	while at[0] < lines.size():
		var line := lines[at[0]]
		var rest := line.substr(indent)
		if _indent(line) != indent or not (rest == "-" or rest.begins_with("- ")):
			break
		var item := rest.substr(2) if rest.length() > 1 else ""
		if item != "" and not item[0] in ["{", "[", "'", "\""] and _key_end(item) >= 0:
			lines[at[0]] = " ".repeat(indent + 2) + item
			out.append(_mapping(lines, at, indent + 2))
		elif item == "":
			at[0] += 1
			out.append(_block(lines, at, _indent(lines[at[0]])) if at[0] < lines.size() and _indent(lines[at[0]]) > indent else "")
		else:
			at[0] += 1
			out.append(_value(item, lines, at, indent))
	return out


static func _mapping(lines: Array[String], at: Array, indent: int) -> Dictionary:
	var out := {}
	while at[0] < lines.size():
		var line := lines[at[0]]
		if _indent(line) != indent or line.substr(indent).begins_with("- "):
			break
		var text := line.substr(indent)
		var end := _key_end(text)
		if end < 0:
			at[0] += 1
			continue
		var key := _scalar(text.left(end))
		var rest := text.substr(end + 1).strip_edges()
		at[0] += 1
		if rest != "":
			out[key] = _value(rest, lines, at, indent)
		elif at[0] < lines.size() and _indent(lines[at[0]]) > indent:
			out[key] = _block(lines, at, _indent(lines[at[0]]))
		elif at[0] < lines.size() and _indent(lines[at[0]]) == indent and lines[at[0]].substr(indent).begins_with("-"):
			out[key] = _sequence(lines, at, indent)
		else:
			out[key] = ""
	return out


## Where a "key: value" line's key ends, or -1 if it is no key.
static func _key_end(text: String) -> int:
	if text.begins_with("'") or text.begins_with("\""):
		var close := text.find(text[0], 1)
		while close >= 0 and text[0] == "'" and close + 1 < text.length() and text[close + 1] == "'":
			close = text.find("'", close + 2)
		if close < 0 or close + 1 >= text.length() or text[close + 1] != ":":
			return -1
		return close + 1
	var i := text.find(": ")
	if i >= 0:
		return i
	return text.length() - 1 if text.ends_with(":") else -1


## A value and any lines it continues onto: a flow collection until its brackets close, a quoted string until its
## quote does, a plain scalar over every deeper line.
static func _value(text: String, lines: Array[String], at: Array, indent: int) -> Variant:
	if text[0] in ["{", "["]:
		while not _closed(text) and at[0] < lines.size():
			text += " " + lines[at[0]].strip_edges()
			at[0] += 1
		return _flow(text, [0])
	if text[0] in ["'", "\""]:
		while not _quoted(text) and at[0] < lines.size():
			var next := lines[at[0]].strip_edges()
			text += ("\n" if next == "" else " ") + next
			at[0] += 1
		return _scalar(text)
	while at[0] < lines.size() and _indent(lines[at[0]]) > indent and not lines[at[0]].strip_edges().begins_with("- "):
		text += " " + lines[at[0]].strip_edges()
		at[0] += 1
	return text


static func _closed(text: String) -> bool:
	var depth := 0
	var quote := ""
	for c in text:
		if quote != "":
			if c == quote:
				quote = ""
		elif c in ["'", "\""]:
			quote = c
		elif c in ["{", "["]:
			depth += 1
		elif c in ["}", "]"]:
			depth -= 1
	return depth <= 0


static func _quoted(text: String) -> bool:
	var s := text.replace("''", "") if text[0] == "'" else text.replace("\\\"", "")
	return s.length() >= 2 and s.ends_with(text[0])


static func _flow(text: String, at: Array) -> Variant:
	_skip(text, at)
	var open := text[at[0]]
	at[0] += 1
	var close := "}" if open == "{" else "]"
	var out: Variant = {} if open == "{" else []
	while true:
		_skip(text, at)
		if at[0] >= text.length() or text[at[0]] == close:
			at[0] += 1
			return out
		if open == "{":
			var key := _flow_scalar(text, at, ":")
			at[0] += 1
			_skip(text, at)
			out[key] = _flow(text, at) if text[at[0]] in ["{", "["] else _flow_scalar(text, at, ",}")
		else:
			out.append(_flow(text, at) if text[at[0]] in ["{", "["] else _flow_scalar(text, at, ",]"))
		_skip(text, at)
		if at[0] < text.length() and text[at[0]] == ",":
			at[0] += 1
	return out


static func _skip(text: String, at: Array) -> void:
	while at[0] < text.length() and text[at[0]] == " ":
		at[0] += 1


static func _flow_scalar(text: String, at: Array, stops: String) -> String:
	var start: int = at[0]
	if text[start] in ["'", "\""]:
		var i := start + 1
		while i < text.length() and not (text[i] == text[start] and not (text[start] == "'" and i + 1 < text.length() and text[i + 1] == "'")):
			i += 2 if text[start] == "'" and text[i] == "'" else 1
		at[0] = i + 1
		return _scalar(text.substr(start, i + 1 - start))
	while at[0] < text.length() and not text[at[0]] in stops:
		at[0] += 1
	return text.substr(start, at[0] - start).strip_edges()


static func _scalar(s: String) -> String:
	s = s.strip_edges()
	if s.length() >= 2 and s[0] == "'" and s[-1] == "'":
		return s.substr(1, s.length() - 2).replace("''", "'")
	if s.length() >= 2 and s[0] == "\"" and s[-1] == "\"":
		return s.substr(1, s.length() - 2).c_unescape()
	return s
