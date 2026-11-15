class_name ExpressionDefinition
extends RefCounted

const REGIONS := ["hue", "color", "tone", "look"]
## Poiyomi _DecalBlendType values: replace, darken, multiply, lighten, screen, subtract, add, overlay, mixed
## (decal_blend in expression.gdshaderinc).
const DECAL_BLENDS: Array[int] = [0, 1, 2, 5, 6, 7, 8, 9, 20]

const PARTICLE_FIELDS := ["rate", "distance", "speed", "size", "lifetime", "gravity", "color", "material", "tint", "emission"]
const DRIVES := ["set", "add", "random", "copy"]


## "" for an effect that animates no region.
static func region(effect: Variant) -> String:
	return effect.keys()[0] if effect is Dictionary and effect.size() == 1 and effect.keys()[0] in REGIONS else ""


## VRM files arrive from players: reject malformed data before binding any of it to scene nodes.
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
			if not curve is Dictionary or not is_index(curve.get("target"), targets.size()) or not curve.get("keys") is Array:
				return false
			if not curve.keys.all(_key):
				return false
	for l: Variant in data.get("layers", []):
		if not l is Dictionary or not l.get("states") is Array or not _number(l.get("weight", 1.0)):
			return false
		var count: int = l.states.size()
		if count > 0 and not is_index(l.get("default", 0), count):
			return false
		if not _transitions(l.get("any", []), count) or not _transitions(l.get("entry", []), count):
			return false
		for s: Variant in l.states:
			if not s is Dictionary or not _number(s.get("speed", 1.0)) or not _motion(s.get("motion", {}), clips.size()) or not _transitions(s.get("transitions", []), count) or not s.get("drivers", []) is Array:
				return false
			for driver: Variant in s.get("drivers", []):
				if not driver is Dictionary or not driver.get("parameter") is String or not driver.get("source", "") is String or driver.get("drive", "set") not in DRIVES:
					return false
				for key: String in ["value", "min", "max", "chance"]:
					if not _number(driver.get(key, 0.0)):
						return false
	var switched: Array = data.get("shown", []) + data.get("springs", []) + data.get("colliders", []) + data.get("contacts", []) + data.get("particles", [])
	for s: Variant in switched:
		if not s is Dictionary or not s.get("when") is Array:
			return false
		for condition: Variant in s.when:
			if not _numbers(condition, 2) or not is_index(condition[0], targets.size()):
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


## Emission, rim and rim shade colours are linear; an emission's "theme" is a slot in its material's "themes";
## "outlineWidth" is in metres. Looks without lighting are refused: their flat materials would draw shaded twice
## (Avatar.shape).
static func looks_valid(looks: Variant) -> bool:
	if not looks is Dictionary:
		push_error("expressions: the looks are not a dictionary")
		return false
	if not looks.get("decals", []) is Array or ["emission", "index", "shade", "shade2", "rimTint"].any(func(k: String) -> bool: return looks.has(k) and not looks[k] is Image):
		push_error("expressions: the looks' decals, emission map, material index, shade layers or rim tint are not images")
		return false
	if not (looks.get("matcaps", []) is Array and looks.get("matcaps", []).all(func(t: Variant) -> bool: return t is Image)) or (looks.has("matcapMasks") and not looks.matcapMasks is Image):
		push_error("expressions: the looks' matcaps or matcap masks are not images")
		return false
	if looks.has("outline") and not (looks.outline is Image and _number(looks.get("outlineWidth")) and float(looks.outlineWidth) > 0.0):
		push_error("expressions: looks carry an outline layer without a positive outlineWidth")
		return false
	if looks.has("rimTint") and not (looks.get("materials") is Array and looks.materials.any(func(m: Variant) -> bool: return m is Dictionary and m.get("rim") is Dictionary)):
		push_error("expressions: looks carry a rim tint where no material draws a rim")
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
		var shadow: Variant = light.get("shadow")
		if shadow != null and not _shadow(shadow):
			push_error("expressions: a look's shadow is not a border, blur and strength with a null or numeric second shade and edge: %s" % [shadow])
			return false
		var glow: Variant = m.get("emission")
		if glow != null and not (glow is Dictionary and glow.get("color") is Array and glow.color.size() == 3 and glow.color.all(_number) and _number(glow.get("strength")) and _number(glow.get("replace", 0.0))):
			push_error("expressions: a look's emission is not a colour of three numbers, a strength and a numeric replace: %s" % [glow])
			return false
		if glow != null and glow.get("theme") != null and not (is_index(glow.theme, 4) and m.get("themes") is Array and m.themes.size() == 4 and _theme(m.themes[int(glow.theme)])):
			push_error("expressions: a look's emission glows in a theme its material does not carry whole: %s" % [m.get("themes")])
			return false
		var matcaps: Variant = m.get("matcaps", [])
		if not (matcaps is Array and matcaps.size() <= Avatar.MATCAPS and matcaps.all(_matcap)):
			push_error("expressions: a look's matcaps are not four slots, each none or a mapping, colour, texture, strengths, hue and circle: %s" % [matcaps])
			return false
		if not _coat(m.get("clearcoat")):
			push_error("expressions: a look's clear coat lacks its levels, tints, Fresnel, antialiasing, tiling and offset, inversions, a map or a fallback among the looks' %s" % [m.get("clearcoat")])
			return false
		var rim: Variant = m.get("rim")
		if rim != null and not (rim is Dictionary and _numbers(rim.get("color"), 3) and ["strength", "main", "border", "blur", "power", "lit", "shadowMask"].all(func(k: String) -> bool: return _number(rim.get(k))) and rim.get("backface") is bool):
			push_error("expressions: a look's rim is not a colour of three numbers with a strength, main, border, blur, power, lit and shadowMask, and a backface flag: %s" % [rim])
			return false
		var rim_shade: Variant = m.get("rimShade")
		if rim_shade != null and not (rim_shade is Dictionary and _numbers(rim_shade.get("color"), 3) and ["strength", "border", "blur", "power"].all(func(k: String) -> bool: return _number(rim_shade.get(k))) and float(rim_shade.power) > 0.0):
			push_error("expressions: a look's rim shade is not a colour of three numbers with a strength, border, blur and positive power: %s" % [rim_shade])
			return false
	return true


## "hue", "saturation", "value" and "speed" are offsets.
static func _theme(v: Variant) -> bool:
	return v is Dictionary and _numbers(v.get("hsv"), 3) and ["exposure", "hue", "saturation", "value", "speed"].all(func(k: String) -> bool: return _number(v.get(k)))


## "image" is absent once the model's texture holds it. At most 255 "cells": the shader scans them per recoloured texel.
static func _untinted(untinted: Variant) -> bool:
	if not untinted is Dictionary:
		return false
	var cells: Variant = untinted.get("cells", [])
	return (not untinted.has("image") or untinted.image is Image) and cells is Array and cells.size() <= 255 and cells.all(_cell)


## A cell's albedo rect then its rect in the untinted colours' image, each [x0, y0, x1, y1] in UV, none empty.
static func _cell(c: Variant) -> bool:
	return c is Array and c.size() == 8 and c.all(_number) and c[0] < c[2] and c[1] < c[3] and c[4] < c[6] and c[5] < c[7]


## null is an empty slot. "texture" indexes the looks' "matcaps", null for plain white; "color" is linear.
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


## "gsaa" is [variance, threshold]; "st" is Unity's tiling and offset. "map" indexes the looks' "clearcoatMaps" and
## "fallback" their "clearcoatFallbacks", -1 or past the end drawing none. "fresnelStrength" is null before Poiyomi 9.2,
## whose "fresnel" alone then weighs a grazing reflectance following smoothness.
static func _coat(coat: Variant) -> bool:
	if coat == null:
		return true
	if not coat is Dictionary or not ["strength", "smoothness", "reflection", "specular", "fresnel"].all(func(k: String) -> bool: return _number(coat.get(k))):
		return false
	if not (_numbers(coat.get("specularTint"), 3) and _numbers(coat.get("reflectionTint"), 3) and _numbers(coat.get("st"), 4) and _numbers(coat.get("gsaa"), 2)):
		return false
	if not (coat.get("inverts") is Array and coat.inverts.size() == 4 and coat.inverts.all(func(v: Variant) -> bool: return v is bool)):
		return false
	if not (coat.get("litFallback") is bool and coat.get("forceFallback") is bool and _number(coat.get("exposureOcclusion"))):
		return false
	if not (coat.has("fresnelStrength") and (coat.fresnelStrength == null or _number(coat.fresnelStrength))):
		return false
	return [coat.get("map"), coat.get("fallback")].all(func(v: Variant) -> bool: return _number(v) and (float(v) == -1.0 or _whole(v)))


static func _blend(region: Dictionary) -> bool:
	if not str(region.get("field", "")).begins_with("decal"):
		return true
	var mode: Variant = region.get("colorBlend")
	return _whole(mode) and int(mode) in DECAL_BLENDS


static func _shadow(v: Variant) -> bool:
	if not v is Dictionary or not ["border", "blur", "strength"].all(func(k: String) -> bool: return _number(v.get(k))):
		return false
	var second: Variant = v.get("second")
	var edge: Variant = v.get("edge")
	return (second == null or second is Dictionary and ["border", "blur", "weight"].all(func(k: String) -> bool: return _number(second.get(k)))) and (edge == null or edge is Dictionary and _numbers(edge.get("color"), 3) and _number(edge.get("range")))


## null where the region's image holds its colour; a "decalHue" region needs one: the shader cannot guess its space.
static func _hue(region: Dictionary) -> bool:
	var v: Variant = region.get("hue")
	if v == null:
		return region.get("field") != "decalHue"
	return v is Dictionary and _number(v.get("shift", 0.0)) and _number(v.get("space", 0.0)) and _number(v.get("select", 1.0))


## A shape with a "tail" is a capsule; "receiver" fields are Contacts'.
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


static func is_index(v: Variant, size: int) -> bool:
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
		return is_index(m.clip, clips) and m.get("time", "") is String
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
		if not t is Dictionary or not _number(t.get("to")) or (t.to != -1 and not is_index(t.to, states)) or not t.get("conditions", []) is Array or not _number(t.get("exitTime", 0.0)):
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
		return effect.scale is Dictionary and _node(effect.scale.get("node")) and is_index(effect.scale.get("axis"), 3)
	if effect.has("material"):
		return effect.material is Dictionary and _node(effect.material.get("node")) and effect.material.get("choices") is Array and not effect.material.choices.is_empty() and effect.material.choices.all(func(c: Variant) -> bool: return _numbers(c, 4))
	if effect.has("rotation"):
		var rest: Variant = effect.rotation.get("rest") if effect.rotation is Dictionary else null
		return rest is Array and (_numbers(rest, 3) or _numbers(rest, 4)) and _node(effect.rotation.get("node")) and is_index(effect.rotation.get("axis"), rest.size())
	if effect.has("parameter"):
		return effect.parameter is String
	if effect.has("constraint"):
		return effect.constraint is Dictionary and _node(effect.constraint.get("node"))
	if effect.has("particle"):
		var p: Variant = effect.particle
		return p is Dictionary and _whole(p.get("system")) and p.get("field") in PARTICLE_FIELDS and p.get("end", "both") in ["min", "max", "both"] and is_index(p.get("channel", 0), 3 if p.field == "emission" else 4)
	if effect.has("translation"):
		return effect.translation is Dictionary and _node(effect.translation.get("node")) and _numbers(effect.translation.get("direction"), 3)
	var kind: String = effect.keys()[0]
	if kind in REGIONS and effect[kind] is Array:
		return effect[kind].all(func(r: Variant) -> bool: return r is Dictionary and _node(r.get("node")) and _numbers(r.get("rect"), 4) and _number(r.get("space", 0.0)) and _number(r.get("shift", 1.0)) and is_index(r.get("channel", 0), 4 if kind == "tone" else 3) and _numbers(r.get("color", [1, 1, 1]), 3) and is_index(r.get("slot", 0), 4) and _number(r.get("alpha", 1.0)) and is_index(r.get("image", 0), 1 << 16) and _blend(r) and _hue(r))
	return false
