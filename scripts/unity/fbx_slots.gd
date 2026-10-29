extends RefCounted

## A binary FBX's material slots: each model's materials that its polygons use, in the order its polygons first use
## them, the order of a Unity renderer's m_Materials where it has one slot for each. Godot drops a surface it finds no
## triangles in, so a surface finds its slot by its material's name.


## Model name to its material names, slot by slot; empty for a file that is not binary FBX.
static func slots(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_buffer(20).get_string_from_ascii() != "Kaydara FBX Binary  ":
		return {}
	f.seek(23)
	var wide := f.get_32() >= 7500
	var names := {}
	var materials := {}
	var uses := {}
	var links := []
	while true:
		var top := _node(f, wide)
		if top.is_empty():
			break
		if top.name == "Objects":
			for o: Dictionary in top.children:
				if o.props.size() >= 2 and o.props[0] is int and o.props[1] is String:
					var name: String = (o.props[1] as String).get_slice("\u0000", 0)
					if o.name == "Model":
						names[o.props[0]] = name
					elif o.name == "Material":
						materials[o.props[0]] = name
					elif o.name == "Geometry":
						uses[o.props[0]] = _first_uses(o)
		elif top.name == "Connections":
			for c: Dictionary in top.children:
				if c.props.size() >= 3 and str(c.props[0]) == "OO":
					links.append([c.props[1], c.props[2]])
	var connected := {}
	var geometry := {}
	for l: Array in links:
		if materials.has(l[0]) and names.has(l[1]):
			connected.get_or_add(l[1], []).append(materials[l[0]])
		elif uses.has(l[0]) and names.has(l[1]):
			geometry[l[1]] = uses[l[0]]
	var out := {}
	for model: int in connected:
		var all: Array = connected[model]
		var order: PackedInt32Array = geometry.get(model, PackedInt32Array(range(all.size())))
		out[names[model]] = Array(order).filter(func(i: int) -> bool: return i < all.size()).map(func(i: int) -> String: return all[i])
	return out


## The material indices a Geometry's polygons use, in the order its polygons first use them, which is the order Unity
## gives its submeshes.
static func _first_uses(geometry: Dictionary) -> PackedInt32Array:
	for layer: Dictionary in geometry.children:
		if layer.name != "LayerElementMaterial":
			continue
		for c: Dictionary in layer.children:
			if c.name == "Materials" and not c.props.is_empty() and c.props[0] is PackedInt32Array:
				var seen := {}
				for i: int in c.props[0]:
					seen[i] = true
				return PackedInt32Array(seen.keys())
	return PackedInt32Array()


## One node record and the records under it, reading only Objects and Connections and what is under them: {"name",
## "props", "children"}; empty at the end of the file's top-level records.
static func _node(f: FileAccess, wide: bool, keep := true) -> Dictionary:
	var end := f.get_64() if wide else f.get_32()
	var count := f.get_64() if wide else f.get_32()
	var _length := f.get_64() if wide else f.get_32()
	var name := f.get_buffer(f.get_8()).get_string_from_ascii()
	if end == 0:
		return {}
	keep = keep and name in ["Objects", "Connections", "Model", "Material", "Geometry", "LayerElementMaterial", "Materials", "C", ""]
	if not keep:
		f.seek(end)
		return {"name": name, "props": [], "children": []}
	var props := []
	for i in count:
		props.append(_property(f))
	var children := []
	var blank := 25 if wide else 13
	while f.get_position() < end - blank:
		var child := _node(f, wide, name in ["Objects", "Connections", "Geometry", "LayerElementMaterial"])
		if child.is_empty():
			break
		children.append(child)
	f.seek(end)
	return {"name": name, "props": props, "children": children}


static func _property(f: FileAccess) -> Variant:
	var t := char(f.get_8())
	match t:
		"Y":
			return f.get_16()
		"C":
			return f.get_8()
		"I":
			return f.get_32()
		"F":
			return f.get_float()
		"D":
			return f.get_double()
		"L":
			return f.get_64()
		"S", "R":
			var raw := f.get_buffer(f.get_32())
			return raw.get_string_from_utf8() if t == "S" else raw
		"f", "d", "l", "i", "b":
			var n := f.get_32()
			var encoding := f.get_32()
			var bytes := f.get_buffer(f.get_32())
			if t != "i":
				return null
			if encoding == 1:
				bytes = bytes.decompress(n * 4, FileAccess.COMPRESSION_DEFLATE)
			return bytes.to_int32_array()
	return null
