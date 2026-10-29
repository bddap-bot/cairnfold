class_name ExpressionDefinition
extends RefCounted

## Material properties a target animates over the atlas regions of the materials it names: docs/model.md "File", a clip
## curve's material property by name.
const REGIONS := ["hue", "color", "tone", "look"]


## The region kind `effect` animates, or "" for any other effect.
static func region(effect: Variant) -> String:
	return effect.keys()[0] if effect is Dictionary and effect.size() == 1 and effect.keys()[0] in REGIONS else ""

## VRM files arrive from players. Reject malformed controller data before binding any of it to scene nodes.
static func valid(data: Dictionary) -> bool:
	for key: String in ["parameters", "targets", "clips", "layers", "shown", "menu", "icons"]:
		if not data.get(key, []) is Array:
			return false
	if not _menu(data.get("menu", [])) or not data.get("icons", []).all(func(v: Variant) -> bool: return v is String):
		return false
	for p: Variant in data.get("parameters", []):
		if not p is Dictionary or not p.get("name") is String or p.get("type") not in ["float", "int", "bool"] or not _number(p.get("default", 0.0)):
			return false
	var targets: Array = data.get("targets", [])
	for t: Variant in targets:
		if not t is Dictionary or not _number(t.get("default", 0.0)) or not _effect(t.get("effect")):
			return false
	var clips: Array = data.get("clips", [])
	for c: Variant in clips:
		if not c is Dictionary or not _number(c.get("length", 0.0)) or not c.get("curves", []) is Array:
			return false
		for curve: Variant in c.get("curves", []):
			if not curve is Dictionary or not _index(curve.get("target"), targets.size()) or not curve.get("keys") is Array:
				return false
			if not curve.keys.all(func(k: Variant) -> bool: return _numbers(k, 2)):
				return false
	for l: Variant in data.get("layers", []):
		if not l is Dictionary or not l.get("states") is Array or not _number(l.get("weight", 1.0)):
			return false
		var count: int = l.states.size()
		if count > 0 and not _index(l.get("default", 0), count):
			return false
		if not _transitions(l.get("any", []), count) or not _transitions(l.get("entry", []), count):
			return false
		for s: Variant in l.states:
			if not s is Dictionary or not _number(s.get("speed", 1.0)) or not _motion(s.get("motion", {}), clips.size()) or not _transitions(s.get("transitions", []), count) or not s.get("drivers", []) is Array:
				return false
			for driver: Variant in s.get("drivers", []):
				if not driver is Dictionary or not driver.get("parameter") is String or not driver.get("source", "") is String:
					return false
				for key: String in ["value", "min", "max", "chance"]:
					if not _number(driver.get(key, 0.0)):
						return false
	for shown: Variant in data.get("shown", []):
		if not shown is Dictionary or not _node(shown.get("node")) or not shown.get("when") is Array:
			return false
		for condition: Variant in shown.when:
			if not _numbers(condition, 2) or not _index(condition[0], targets.size()):
				return false
	return true


static func _number(v: Variant) -> bool:
	return (v is int or v is float) and is_finite(float(v))


static func _index(v: Variant, size: int) -> bool:
	return _number(v) and float(v) == floorf(float(v)) and v >= 0 and v < size


static func _node(v: Variant) -> bool:
	return v is String or v is StringName or (_number(v) and float(v) == floorf(float(v)) and v >= 0)


static func _numbers(v: Variant, size: int) -> bool:
	return v is Array and v.size() == size and v.all(_number)


static func _menu(controls: Array) -> bool:
	if controls.size() > ToolWheel.SLOTS:
		return false
	for c: Variant in controls:
		if not c is Dictionary or c.get("type") not in ["button", "toggle", "submenu", "radial", "twoAxis", "fourAxis"] or not c.get("name", "") is String or not c.get("parameter", "") is String or not _number(c.get("value", 1.0)) or not c.get("axes", []) is Array:
			return false
		if not c.get("axes", []).all(func(v: Variant) -> bool: return v is String):
			return false
		if c.type == "submenu" and (not c.get("controls") is Array or not _menu(c.controls)):
			return false
	return true


static func _motion(m: Variant, clips: int) -> bool:
	if not m is Dictionary:
		return false
	if m.has("clip"):
		return _index(m.clip, clips) and m.get("time", "") is String
	if not m.get("children", []) is Array or not m.get("parameters", []) is Array or not m.get("parameters", []).all(func(v: Variant) -> bool: return v is String):
		return false
	for c: Variant in m.get("children", []):
		if not c is Dictionary or not _motion(c.get("motion"), clips):
			return false
		for key: String in ["speed", "offset", "threshold"]:
			if not _number(c.get(key, 0.0)):
				return false
		if m.get("blend") == "2d" and not _numbers(c.get("position"), 2):
			return false
		if m.get("blend") == "direct" and not c.get("parameter") is String:
			return false
	return true


static func _transitions(list: Variant, states: int) -> bool:
	if not list is Array:
		return false
	for t: Variant in list:
		if not t is Dictionary or not _number(t.get("to")) or (t.to != -1 and not _index(t.to, states)) or not t.get("conditions", []) is Array or not _number(t.get("exitTime", 0.0)):
			return false
		for c: Variant in t.get("conditions", []):
			if not c is Dictionary or not c.get("parameter") is String or c.get("mode") not in ["if", "ifNot", "greater", "less", "equals", "notEqual"] or not _number(c.get("threshold", 0.0)):
				return false
	return true


static func _effect(effect: Variant) -> bool:
	if effect is String:
		return effect == "switch"
	if not effect is Dictionary or effect.size() != 1:
		return false
	if effect.has("morph"):
		return effect.morph is Array and effect.morph.all(func(b: Variant) -> bool: return b is Array and b.size() == 2 and _node(b[0]) and _node(b[1]))
	if effect.has("scale"):
		return effect.scale is Dictionary and _node(effect.scale.get("node")) and _index(effect.scale.get("axis"), 3)
	if effect.has("material"):
		return effect.material is Dictionary and _node(effect.material.get("node")) and effect.material.get("choices") is Array and not effect.material.choices.is_empty() and effect.material.choices.all(func(c: Variant) -> bool: return _numbers(c, 4))
	var kind: String = effect.keys()[0]
	if kind in REGIONS and effect[kind] is Array:
		return effect[kind].all(func(r: Variant) -> bool: return r is Dictionary and _node(r.get("node")) and _numbers(r.get("rect"), 4) and _number(r.get("space", 0.0)) and _number(r.get("shift", 1.0)) and _index(r.get("channel", 0), 3) and _numbers(r.get("color", [1, 1, 1]), 3) and _index(r.get("slot", 0), 4) and _number(r.get("alpha", 1.0)))
	return false
