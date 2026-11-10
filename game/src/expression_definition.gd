class_name ExpressionDefinition
extends RefCounted

## Material properties a target animates over the atlas regions of the materials it names: docs/model.md "File", a clip
## curve's material property by name.
const REGIONS := ["hue", "color", "tone", "look"]
## Poiyomi's decal Color Blend Modes (_DecalBlendType) a decal region's "colorBlend" names: replace, darken, multiply,
## lighten, screen, subtract, add, overlay and mixed (decal_blend in expression.gdshaderinc).
const DECAL_BLENDS: Array[int] = [0, 1, 2, 5, 6, 7, 8, 9, 20]

## What a "particle" effect sets on its system (docs/particles.md): a curve's scale, a start colour channel, the material
## its renderer draws, or that material's tint or emission channel.
const PARTICLE_FIELDS := ["rate", "distance", "speed", "size", "lifetime", "gravity", "color", "material", "tint", "emission"]


## The region kind `effect` animates, or "" for any other effect.
static func region(effect: Variant) -> String:
	return effect.keys()[0] if effect is Dictionary and effect.size() == 1 and effect.keys()[0] in REGIONS else ""


## VRM files arrive from players. Reject malformed controller data before binding any of it to scene nodes.
static func valid(data: Dictionary) -> bool:
	for key: String in ["parameters", "targets", "clips", "layers", "shown", "springs", "colliders", "contacts", "particles", "menu", "icons"]:
		if not data.get(key, []) is Array:
			return false
	if not _menu(data.get("menu", [])) or not data.get("icons", []).all(func(v: Variant) -> bool: return v is Image):
		return false
	if (data.has("hueMask") and not data.hueMask is Image) or not _untinted(data.get("untinted", {})):
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
			if not curve.keys.all(_key):
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
	var switched: Array = data.get("shown", []) + data.get("springs", []) + data.get("colliders", []) + data.get("contacts", []) + data.get("particles", [])
	for s: Variant in switched:
		if not s is Dictionary or not s.get("when") is Array:
			return false
		for condition: Variant in s.when:
			if not _numbers(condition, 2) or not _index(condition[0], targets.size()):
				return false
	for shown: Dictionary in data.get("shown", []):
		if not _node(shown.get("node")):
			return false
	for spring: Dictionary in data.get("springs", []):
		if not spring.get("joints") is Array or spring.joints.is_empty() or not spring.joints.all(_node):
			return false
	for collider: Dictionary in data.get("colliders", []):
		if not _whole(collider.get("collider")):
			return false
	if not data.get("contacts", []).all(_contact):
		return false
	for particle: Dictionary in data.get("particles", []):
		if not _whole(particle.get("system")):
			return false
	return looks_valid(data.get("looks", {}))


## Looks that name their materials give each its "lighting": "lit" by angle, through a "ramp" of at least two
## brightnesses with a numeric "shadowTint" where it has one, or "flat", lit alike whichever way it faces; a flat or
## ramp-lit one is capped at "cap" when it has one (unity/materials.gd lighting), and an "emission" null or its linear
## "color", "strength" and, optionally, "replace" and "theme", the slot of the global theme colour it glows in among the
## material's "themes" (unity/materials.gd `_theme`). A file whose looks predate lighting would draw flat materials shaded twice, so it is refused
## rather than guessed at (Avatar.shape).
static func looks_valid(looks: Variant) -> bool:
	if not looks is Dictionary:
		return false
	if not looks.get("decals", []) is Array or (looks.has("emission") and not looks.emission is Image) or (looks.has("index") and not looks.index is Image):
		return false
	if not (looks.get("matcaps", []) is Array and looks.get("matcaps", []).all(func(t: Variant) -> bool: return t is Image)) or (looks.has("matcapMasks") and not looks.matcapMasks is Image):
		return false
	if not looks.has("materials"):
		return true
	if not looks.materials is Array or looks.materials.size() > 255:
		push_error("expressions: looks name more than 255 materials")
		return false
	for m: Variant in looks.materials:
		var light: Variant = m.get("lighting") if m is Dictionary else null
		if not light is Dictionary or light.get("model") not in ["lit", "flat"] or not _number(light.get("cap", 0.0)):
			push_error("expressions: a look's material has no lighting (\"lit\" or \"flat\" with a numeric cap): %s; convert the avatar again" % [light])
			return false
		var ramp: Variant = light.get("ramp", [0.0, 1.0])
		if not ramp is Array or ramp.size() < 2 or not ramp.all(_number) or not _number(light.get("shadowTint", 0.0)):
			push_error("expressions: a look's lighting ramp is not two or more numbers with a numeric shadow tint: %s" % [light])
			return false
		var glow: Variant = m.get("emission")
		if glow != null and not (glow is Dictionary and glow.get("color") is Array and glow.color.size() == 3 and glow.color.all(_number) and _number(glow.get("strength")) and _number(glow.get("replace", 0.0))):
			push_error("expressions: a look's emission is not a colour of three numbers, a strength and a numeric replace: %s" % [glow])
			return false
		if glow != null and glow.get("theme") != null and not (_index(glow.theme, 4) and m.get("themes") is Array and m.themes.size() == 4 and _theme(m.themes[int(glow.theme)])):
			push_error("expressions: a look's emission glows in a theme its material does not carry whole: %s" % [m.get("themes")])
			return false
		var matcaps: Variant = m.get("matcaps", [])
		if not (matcaps is Array and matcaps.size() <= 4 and matcaps.all(_matcap)):
			push_error("expressions: a look's matcaps are not four slots, each none or a mapping, colour, texture, strengths, hue and circle: %s" % [matcaps])
			return false
		if not _coat(m.get("clearcoat")):
			push_error("expressions: a look's clear coat lacks its levels, tints, Fresnel, antialiasing, tiling and offset, inversions or a map among the looks' %s" % [m.get("clearcoat")])
			return false
	return true


## A global theme colour: its colour's "hsv" and "exposure", and its "hue", "saturation", "value" and "speed" offsets.
static func _theme(v: Variant) -> bool:
	return v is Dictionary and _numbers(v.get("hsv"), 3) and ["exposure", "hue", "saturation", "value", "speed"].all(func(k: String) -> bool: return _number(v.get(k)))


## The untinted colours: the "image" holding them cell by cell, gone once the model's texture holds it, and the "cells"
## a colour control draws from it, at most 255, since the shader looks through them for each texel it recolours.
static func _untinted(untinted: Variant) -> bool:
	if not untinted is Dictionary:
		return false
	var cells: Variant = untinted.get("cells", [])
	return (not untinted.has("image") or untinted.image is Image) and cells is Array and cells.size() <= 255 and cells.all(_cell)


## A cell's albedo rect then its rect in the untinted colours' image, each [x0, y0, x1, y1] in UV, none empty.
static func _cell(c: Variant) -> bool:
	return c is Array and c.size() == 8 and c.all(_number) and c[0] < c[2] and c[1] < c[3] and c[4] < c[6] and c[5] < c[7]


## A look's matcap slot: null, or its "mode" ("normal" or "reflection"), its "texture" (an index among the looks'
## "matcaps", or null for plain white), its linear "color", its "border", "intensity", "baseMix", "replace", "multiply",
## "add", "screen", "mixed", "lightAdd", "emission" and "lightMask", its "hue" (null, or its "shift", "space" and
## "select") and its "circle" (null, or its "border" and "blur").
static func _matcap(c: Variant) -> bool:
	if c == null:
		return true
	if not c is Dictionary or c.get("mode") not in ["normal", "reflection"] or not (c.get("texture") == null or _whole(c.get("texture"))) or not _numbers(c.get("color"), 4):
		return false
	if not ["border", "intensity", "baseMix", "replace", "multiply", "add", "screen", "mixed", "lightAdd", "emission", "lightMask"].all(func(k: String) -> bool: return _number(c.get(k))):
		return false
	var hue: Variant = c.get("hue")
	var circle: Variant = c.get("circle")
	return (hue == null or hue is Dictionary and ["shift", "space", "select"].all(func(k: String) -> bool: return _number(hue.get(k)))) and (circle == null or circle is Dictionary and _number(circle.get("border")) and _number(circle.get("blur")))


## A look's "clearcoat": null, or its "strength", "smoothness", "reflection", "specular" and "fresnel", its
## "specularTint" and "reflectionTint", its "gsaa" variance and threshold, its maps' "st" (Unity's tiling and offset),
## its four "inverts" and its "map", -1 or an index among the looks' "clearcoatMaps"; an index past them draws as none.
static func _coat(coat: Variant) -> bool:
	if coat == null:
		return true
	if not coat is Dictionary or not ["strength", "smoothness", "reflection", "specular", "fresnel"].all(func(k: String) -> bool: return _number(coat.get(k))):
		return false
	if not (_numbers(coat.get("specularTint"), 3) and _numbers(coat.get("reflectionTint"), 3) and _numbers(coat.get("st"), 4) and _numbers(coat.get("gsaa"), 2)):
		return false
	if not (coat.get("inverts") is Array and coat.inverts.size() == 4 and coat.inverts.all(func(v: Variant) -> bool: return v is bool)):
		return false
	return _number(coat.get("map")) and (float(coat.map) == -1.0 or _whole(coat.map))


## A decal region names its "colorBlend", one of DECAL_BLENDS.
static func _blend(region: Dictionary) -> bool:
	if not str(region.get("field", "")).begins_with("decal"):
		return true
	var mode: Variant = region.get("colorBlend")
	return _whole(mode) and int(mode) in DECAL_BLENDS


## A region's decal hue turn, {"shift", "space", "select"}, or null where its image holds its colour; one that drives
## the turn names the colour space and mode it turns in, which the shader cannot guess.
static func _hue(region: Dictionary) -> bool:
	var v: Variant = region.get("hue")
	if v == null:
		return region.get("field") != "decalHue"
	return v is Dictionary and _number(v.get("shift", 0.0)) and _number(v.get("space", 0.0)) and _number(v.get("select", 1.0))


## A contact: its "node", a "shape" of an "offset", a "radius" and, for a capsule, a "tail", its "tags" and, for a
## receiver, its "receiver" fields (Contacts).
static func _contact(c: Dictionary) -> bool:
	var shape: Variant = c.get("shape")
	if not _node(c.get("node")) or not shape is Dictionary or not _numbers(shape.get("offset"), 3) or not _number(shape.get("radius")) or shape.radius < 0 or (shape.has("tail") and not _numbers(shape.tail, 3)):
		return false
	if not c.get("tags") is Array or not c.tags.all(func(t: Variant) -> bool: return t is String) or not c.get("body", false) is bool:
		return false
	if not c.has("receiver"):
		return true
	var r: Variant = c.receiver
	return r is Dictionary and r.get("type") in Contacts.RECEIVERS and r.get("parameter") is String and _number(r.get("minVelocity")) and ["self", "others", "local"].all(func(k: String) -> bool: return r.get(k) is bool)


static func _number(v: Variant) -> bool:
	return (v is int or v is float) and is_finite(float(v))


static func _whole(v: Variant) -> bool:
	return _number(v) and float(v) == floorf(float(v)) and v >= 0


static func _index(v: Variant, size: int) -> bool:
	return _whole(v) and v < size


static func _node(v: Variant) -> bool:
	return v is String or v is StringName or _whole(v)


## [time, value], or with Unity's in and out slopes (null where infinite), optionally followed by their weights.
static func _key(v: Variant) -> bool:
	if not v is Array or not v.size() in [2, 4, 6] or not _number(v[0]) or not _number(v[1]):
		return false
	return v.slice(2, 4).all(func(s: Variant) -> bool: return s == null or _number(s)) and v.slice(4).all(_number)


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
	if not m.get("normalized", false) is bool:
		return false
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
	if effect.has("rotation"):
		var rest: Variant = effect.rotation.get("rest") if effect.rotation is Dictionary else null
		return rest is Array and (_numbers(rest, 3) or _numbers(rest, 4)) and _node(effect.rotation.get("node")) and _index(effect.rotation.get("axis"), rest.size())
	if effect.has("parameter"):
		return effect.parameter is String
	if effect.has("constraint"):
		return effect.constraint is Dictionary and _node(effect.constraint.get("node"))
	if effect.has("particle"):
		var p: Variant = effect.particle
		return p is Dictionary and _whole(p.get("system")) and p.get("field") in PARTICLE_FIELDS and p.get("end", "both") in ["min", "max", "both"] and _index(p.get("channel", 0), 3 if p.field == "emission" else 4)
	if effect.has("translation"):
		return effect.translation is Dictionary and _node(effect.translation.get("node")) and _numbers(effect.translation.get("direction"), 3)
	var kind: String = effect.keys()[0]
	if kind in REGIONS and effect[kind] is Array:
		return effect[kind].all(func(r: Variant) -> bool: return r is Dictionary and _node(r.get("node")) and _numbers(r.get("rect"), 4) and _number(r.get("space", 0.0)) and _number(r.get("shift", 1.0)) and _index(r.get("channel", 0), 3) and _numbers(r.get("color", [1, 1, 1]), 3) and _index(r.get("slot", 0), 4) and _number(r.get("alpha", 1.0)) and _index(r.get("image", 0), 1 << 16) and _blend(r) and _hue(r))
	return false
