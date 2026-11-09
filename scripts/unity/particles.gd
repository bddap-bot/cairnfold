extends RefCounted

## An avatar's Unity ParticleSystems as UNITY_particles carries them (docs/particles.md): each live system's modules
## the runtimes draw, read at import into sampled curves and gradients in the avatar's axes, so a runtime evaluates
## a particle without Unity's types.

const Yaml = preload("res://../scripts/unity/yaml.gd")
const Prefabs = preload("res://../scripts/unity/prefabs.gd")
const Materials = preload("res://../scripts/unity/materials.gd")

## Samples of a curve or gradient over its span; a constant keeps one.
const SAMPLES := 16
## Unity's shape types by ParticleSystemShapeType, each with the share of its radius it emits from inward of the
## surface that the legacy shell types fix at 0.
const SHAPES := {0: ["sphere", -1.0], 1: ["sphere", 0.0], 2: ["hemisphere", -1.0], 3: ["hemisphere", 0.0], 4: ["cone", -1.0], 5: ["box", -1.0], 7: ["cone", 0.0], 8: ["cone", -1.0], 9: ["cone", 0.0], 10: ["circle", -1.0], 11: ["circle", 0.0], 12: ["edge", -1.0], 15: ["box", -1.0], 16: ["box", -1.0], 18: ["box", -1.0]}
## Unity's blend factors (UnityEngine.Rendering.BlendMode) as [source, destination] to the blend a runtime draws.
const BLENDS := {[5, 10]: "alpha", [1, 10]: "premultiplied", [5, 1]: "add", [1, 1]: "add", [4, 1]: "add", [2, 0]: "multiply", [0, 3]: "multiply"}
## The widest a particle texture is kept: particles are small on screen, and each texture is its own image.
const WIDEST := 256
## Unity's clip attributes on a ParticleSystem (class 198) to the field a "particle" effect sets.
const FIELDS := {"EmissionModule.rateOverTime": "rate", "EmissionModule.rateOverDistance": "distance", "InitialModule.startSpeed": "speed", "InitialModule.startSize": "size", "InitialModule.startLifetime": "lifetime", "InitialModule.gravityModifier": "gravity"}
## A sub-emitter's inherited properties, in the order of Unity's ParticleSystemSubEmitterProperties bits.
const INHERITED := ["color", "size", "rotation", "lifetime"]

var systems := []
var meshes := []
var images: Array[Image] = []
## Each system's index by the clip path of its GameObject.
var by_path := {}
## Each system's switch conditions, for the expressions' "particles".
var when := []
## Each system's material choices by GUID, as its renderer's "materials" list them.
var _choices := []
## What import multiplied each system's fields by (its transform's scale and simulation speed), which a clip's values
## for them take too.
var _factors := []
## Whether each of a system's materials tints by a legacy shader's _TintColor.
var _legacy_tint := []
var _materials: Materials
var _prefabs: Prefabs
var _image_of := {}
var _mesh_of := {}


## Reads `found`, [[ParticleSystem id, its Transform, its GameObject, its switch conditions, its emitter's bone]...];
## `paths` is each Transform by clip path, and `clips` the controller's clips, whose material swaps on a system's
## renderer add that material to its choices.
func _init(prefabs: Prefabs, materials: Materials, objs: Dictionary, found: Array, paths: Dictionary, clips: Array) -> void:
	_prefabs = prefabs
	_materials = materials
	var path_of := {}
	var by_id := {}
	for p: String in paths:
		path_of[paths[p]] = p
	var swaps := {}
	for clip: Dictionary in clips:
		for c: Dictionary in clip.curves:
			if c["class"] == "199" and str(c.attribute).begins_with("m_Materials.Array.data[0]") and c.has("refs"):
				for k: Array in c.refs:
					if k[1] != "":
						(swaps.get_or_add(c.path, []) as Array).append({"guid": k[1], "fileID": "2100000"})
	for f: Array in found:
		var renderer := 0
		for id: int in Prefabs.components(objs, f[2]):
			if objs.get(id, {}).get("type", "") == "ParticleSystemRenderer":
				renderer = id
		var path: String = path_of.get(f[1], "")
		var refs: Array = Yaml.list(objs.get(renderer, {}).get("data", {}).get("m_Materials")).slice(0, 1).filter(func(r: Variant) -> bool: return Yaml.file_id(r) != 0)
		for swap: Dictionary in swaps.get(path, []):
			if not refs.any(func(r: Variant) -> bool: return r is Dictionary and Yaml.guid(r) == swap.guid):
				refs.append(swap)
		_choices.append(refs.map(func(r: Variant) -> String: return Yaml.guid(r)))
		by_id[f[0]] = systems.size()
		by_path[path] = systems.size()
		var system := _system(objs, f[0], renderer, f[1], refs)
		system.node = f[4]
		systems.append(system)
		when.append(f[3])
	for s: Dictionary in systems:
		for sub: Dictionary in s.get("subEmitters", []):
			sub.system = by_id.get(sub.system, -1)
		s.subEmitters = s.get("subEmitters", []).filter(func(sub: Dictionary) -> bool: return sub.system >= 0)
		if (s.subEmitters as Array).is_empty():
			s.erase("subEmitters")


func _system(objs: Dictionary, id: int, renderer: int, transform: int, refs: Array) -> Dictionary:
	var d: Dictionary = objs[id].data
	var main: Dictionary = d.get("InitialModule", {})
	var mode := _int(d, "scalingMode", 0)
	var world := _int(d, "moveWithTransform", 0) == 1
	var lossy := 1.0
	for t: int in Prefabs.ancestors(objs, transform) if mode == 0 else [transform]:
		var s: Variant = objs[t].data.get("m_LocalScale")
		lossy *= absf(Prefabs.number(s, "x", 1.0) * Prefabs.number(s, "y", 1.0) * Prefabs.number(s, "z", 1.0)) ** (1.0 / 3.0)
	var sized := lossy if mode != 2 else 1.0
	# Unity's simulation speed runs the whole system faster; here its times shorten and its rates and speeds rise.
	var fast := maxf(Prefabs.number(d, "simulationSpeed", 1.0), 0.001)
	var moving := (lossy if not world else 1.0) * fast
	_factors.append({"size": sized, "speed": moving, "lifetime": 1.0 / fast, "rate": fast, "gravity": fast * fast})
	var out := {
		"duration": Prefabs.number(d, "lengthInSec", 5.0) / fast,
		"loop": _int(d, "looping", 1) == 1,
		"awake": _int(d, "playOnAwake", 1) == 1,
		"world": world,
		"delay": _constant(d.get("startDelay")) / fast,
		"max": _int(main, "maxNumParticles", 1000),
		"lifetime": curve(main.get("startLifetime"), 1.0 / fast),
		"speed": curve(main.get("startSpeed"), moving),
		"color": gradient(main.get("startColor")),
		"gravity": curve(main.get("gravityModifier"), fast * fast),
	}
	if _int(main, "size3D", 0) == 1:
		out.size = [curve(main.get("startSize"), sized), curve(main.get("startSizeY"), sized), curve(main.get("startSizeZ"), sized)]
	else:
		out.size = curve(main.get("startSize"), sized)
	# Mirroring X turns rotations about Y and Z the other way.
	if _int(main, "rotation3D", 0) == 1:
		out.rotation = [curve(main.get("startRotationX")), curve(main.get("startRotationY"), -1.0), curve(main.get("startRotation"), -1.0)]
	else:
		out.rotation = curve(main.get("startRotation"), -1.0)
	var emission: Dictionary = d.get("EmissionModule", {})
	if _on(emission):
		out.rate = curve(emission.get("rateOverTime"), fast)
		out.distance = curve(emission.get("rateOverDistance"))
		var bursts := []
		for b: Variant in Yaml.list(emission.get("m_Bursts")):
			var burst: Dictionary = b
			var count: Variant = burst.get("countCurve")
			bursts.append({"time": Prefabs.number(burst, "time") / fast, "count": curve(count) if count is Dictionary else {"min": [1.0], "max": [1.0], "scale": [Prefabs.number(burst, "minCount"), Prefabs.number(burst, "maxCount")]}, "cycles": _int(burst, "cycleCount", 1), "interval": Prefabs.number(burst, "repeatInterval", 0.01) / fast, "probability": Prefabs.number(burst, "probability", 1.0)})
		if not bursts.is_empty():
			out.bursts = bursts
	var shape: Dictionary = d.get("ShapeModule", {})
	out.shape = _shape(shape, lossy) if _on(shape) else {"type": "point"}
	var velocity: Dictionary = d.get("VelocityModule", {})
	if _on(velocity):
		out.velocity = {"x": curve(velocity.get("x"), -moving), "y": curve(velocity.get("y"), moving), "z": curve(velocity.get("z"), moving), "world": _int(velocity, "inWorldSpace", 0) == 1}
	var limit: Dictionary = d.get("ClampVelocityModule", {})
	if _on(limit):
		out.limit = {"speed": curve(limit.get("magnitude"), moving), "dampen": Prefabs.number(limit, "dampen", 1.0)}
	var inherit: Dictionary = d.get("InheritVelocityModule", {})
	if _on(inherit):
		out.inherit = curve(inherit.get("m_Curve"))
	var noise: Dictionary = d.get("NoiseModule", {})
	if _on(noise):
		out.noise = {"strength": curve(noise.get("strength"), moving), "frequency": Prefabs.number(noise, "frequency", 0.5) * fast}
	var size: Dictionary = d.get("SizeModule", {})
	if _on(size):
		out.sizeOverLife = [curve(size.get("curve")), curve(size.get("y")), curve(size.get("z"))] if _int(size, "separateAxes", 0) == 1 else curve(size.get("curve"))
	var colour: Dictionary = d.get("ColorModule", {})
	if _on(colour):
		out.colorOverLife = gradient(colour.get("gradient"))
	var spin: Dictionary = d.get("RotationModule", {})
	if _on(spin):
		out.spin = [curve(spin.get("x"), fast), curve(spin.get("y"), -fast), curve(spin.get("curve"), -fast)] if _int(spin, "separateAxes", 0) == 1 else curve(spin.get("curve"), -fast)
	var by_speed: Dictionary = d.get("SizeBySpeedModule", {})
	if _on(by_speed):
		out.sizeBySpeed = {"size": curve(by_speed.get("curve")), "range": _range(by_speed.get("range"), moving)}
	var colour_by_speed: Dictionary = d.get("ColorBySpeedModule", {})
	if _on(colour_by_speed):
		out.colorBySpeed = {"color": gradient(colour_by_speed.get("gradient")), "range": _range(colour_by_speed.get("range"), moving)}
	var subs: Dictionary = d.get("SubModule", {})
	if _on(subs):
		var list := []
		for s: Variant in Yaml.list(subs.get("subEmitters")):
			var on: String = {0: "birth", 2: "death"}.get(_int(s, "type", -1), "")
			var properties := _int(s, "properties", 0)
			if on != "":
				list.append({"system": Yaml.file_id((s as Dictionary).get("emitter")), "on": on, "inherit": INHERITED.filter(func(p: String) -> bool: return properties & (1 << INHERITED.find(p)) != 0)})
		out.subEmitters = list
	out.renderer = _renderer(objs, renderer, refs)
	return out


func _shape(s: Dictionary, scale: float) -> Dictionary:
	var type := _int(s, "type", 4)
	var kind: Array = SHAPES.get(type, ["point", -1.0])
	var radius: Dictionary = s.get("radius", {}) if s.get("radius") is Dictionary else {}
	var arc: Dictionary = s.get("arc", {}) if s.get("arc") is Dictionary else {}
	var thickness: float = kind[1] if kind[1] >= 0.0 else Prefabs.number(s, "radiusThickness", 1.0)
	var rot: Variant = s.get("m_Rotation")
	var euler := Vector3(Prefabs.number(rot, "x"), Prefabs.number(rot, "y"), Prefabs.number(rot, "z")) * PI / 180.0
	# Unity turns by Euler angles about Z, then X, then Y.
	var unity := Quaternion(Vector3(0, 1, 0), euler.y) * Quaternion(Vector3(1, 0, 0), euler.x) * Quaternion(Vector3(0, 0, 1), euler.z)
	var sc: Variant = s.get("m_Scale")
	var place := Transform3D(Basis(Prefabs.turn({"x": unity.x, "y": unity.y, "z": unity.z, "w": unity.w})).scaled_local(Vector3(Prefabs.number(sc, "x", 1.0), Prefabs.number(sc, "y", 1.0), Prefabs.number(sc, "z", 1.0)) * scale), Prefabs.mirrored(s.get("m_Position")) * scale)
	var out := {"type": kind[0], "radius": Prefabs.number(radius, "value", Prefabs.number(s, "radius", 1.0)), "thickness": thickness, "angle": deg_to_rad(Prefabs.number(s, "angle", 25.0)), "arc": deg_to_rad(Prefabs.number(arc, "value", Prefabs.number(s, "arc", 360.0))), "matrix": Prefabs.matrix(place), "randomDirection": Prefabs.number(s, "randomDirectionAmount"), "spherical": Prefabs.number(s, "sphericalDirectionAmount"), "randomPosition": Prefabs.number(s, "randomPositionAmount")}
	if type in [8, 9]:
		out.length = Prefabs.number(s, "length", 5.0)
	return out


## How a system's renderer draws it, with the materials `refs` a clip may choose among, its own first.
func _renderer(objs: Dictionary, id: int, refs: Array) -> Dictionary:
	var tints := []
	_legacy_tint.append(tints)
	if id == 0:
		return {"draw": false, "materials": []}
	var d: Dictionary = objs[id].data
	var pivot := Prefabs.mirrored(d.get("m_Pivot"))
	var out := {"draw": _int(d, "m_Enabled", 1) == 1 and not refs.is_empty(), "mode": ParticleDefinition.MODES[clampi(_int(d, "m_RenderMode", 0), 0, ParticleDefinition.MODES.size() - 1)], "align": ParticleDefinition.ALIGNS[clampi(_int(d, "m_RenderAlignment", 0), 0, ParticleDefinition.ALIGNS.size() - 1)], "pivot": [pivot.x, pivot.y, pivot.z], "length": Prefabs.number(d, "m_LengthScale", 2.0), "velocityScale": Prefabs.number(d, "m_VelocityScale"), "maxSize": Prefabs.number(d, "m_MaxParticleSize", 0.5), "materials": []}
	for r: Variant in refs:
		out.materials.append(_material(r if r is Dictionary else {}, tints))
	if out.mode == "mesh":
		var mesh := _mesh(d.get("m_Mesh", {}))
		if mesh < 0:
			out.draw = false
		else:
			out.mesh = mesh
	return out


## A particle material's texture, tint, emission and blend. Unity's particle shaders tint by _Color, or by _TintColor
## doubled in linear light in the legacy ones (recorded in `tints`), and blend by their _SrcBlend and _DstBlend.
func _material(ref: Dictionary, tints: Array) -> Dictionary:
	var m: Dictionary = _materials.materials[_materials.use(ref, Color.WHITE)]
	var floats: Dictionary = m.get("floats", {})
	var colours: Dictionary = m.get("colours", {})
	var tint: Color = m.colour
	var legacy: bool = colours.get("_TintColor") is Dictionary and not colours.has("_Color")
	tints.append(legacy)
	if legacy:
		tint = Materials._colour(colours._TintColor, Color.WHITE)
		tint = Color(_doubled(tint.r), _doubled(tint.g), _doubled(tint.b), minf(tint.a * 2.0, 1.0))
	var out := {"color": [tint.r, tint.g, tint.b, tint.a]}
	# A built-in shader, which no package carries, is known only by the factors it saves.
	var declared: bool = (m.get("properties", {}) as Dictionary).is_empty() or m.properties.has("_DstBlend")
	var pair := [str(floats.get("_SrcBlend", "-1")).to_int(), str(floats.get("_DstBlend", "-1")).to_int()] if declared else []
	out.blend = BLENDS.get(pair, "alpha" if m.alpha == Materials.Alpha.BLEND else "cutout" if m.alpha == Materials.Alpha.CUTOUT else "opaque")
	if out.blend == "cutout":
		out.cutoff = m.cutoff
	var glow: Variant = colours.get("_EmissionColor")
	if glow is Dictionary and (str(floats.get("_EmissionEnabled", "0")) == "1" or "_EMISSION" in m.get("keywords", [])):
		var c := Materials._colour(glow, Color.BLACK)
		out.emission = [c.r, c.g, c.b]
	if m.image != null:
		out.image = _image(m.texture, m.image)
		out.uv = [m.scale.x, m.scale.y, m.offset.x, m.offset.y]
	return out


## An sRGB channel the legacy particle shaders double: twice its linear value, back in sRGB.
static func _doubled(c: float) -> float:
	return Color(Color(c, c, c).srgb_to_linear().r * 2.0, 0, 0).linear_to_srgb().r


func _image(guid: String, img: Image) -> int:
	if not _image_of.has(guid):
		var small := img.duplicate() as Image
		Avatar.scale_down(small, ceili(maxi(small.get_width(), small.get_height()) / float(WIDEST)), false)
		_image_of[guid] = images.size()
		images.append(small)
	return _image_of[guid]


## The mesh a mesh-mode renderer draws, from its model, as arrays; -1 if the model has no such mesh.
func _mesh(ref: Dictionary) -> int:
	var guid := Yaml.guid(ref)
	var key := "%s:%s" % [guid, Yaml.file_id(ref)]
	if _mesh_of.has(key):
		return _mesh_of[key]
	_mesh_of[key] = -1
	if not _prefabs.assets.by_guid.has(guid):
		return -1
	var model := _prefabs.model(guid)
	if model.is_empty():
		return -1
	for o: Dictionary in (model.objects as Dictionary).values():
		if o.has("node") and Yaml.file_id(o.data.get("m_Mesh")) == Yaml.file_id(ref):
			var state: GLTFState = model.state
			var arrays := (state.get_meshes()[state.get_nodes()[o.node].mesh].mesh as ImporterMesh).get_surface_arrays(0)
			var flat := func(v: Variant, n: int) -> Array:
				var out := []
				for x: Variant in v:
					for k in n:
						out.append(snappedf(x[k], 1e-5))
				return out
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var entry := {"positions": flat.call(vertices, 3), "indices": Array(arrays[Mesh.ARRAY_INDEX]) if arrays[Mesh.ARRAY_INDEX] != null else range(vertices.size())}
			if arrays[Mesh.ARRAY_TEX_UV] != null:
				entry.uvs = flat.call(arrays[Mesh.ARRAY_TEX_UV], 2)
			_mesh_of[key] = meshes.size()
			meshes.append(entry)
			break
	return _mesh_of[key]


## The "particle" effect of a clip curve on a system's ParticleSystem (198) or its renderer (199), or {} for one no
## runtime draws: the field it sets and, for a curve's scalars, which end of a random range ("min", "max" or "both").
func effect(c: Dictionary) -> Dictionary:
	if not by_path.has(c.path):
		return {}
	var i: int = by_path[c.path]
	var system: Dictionary = systems[i]
	var attribute: String = c.attribute
	if c["class"] == "199":
		if attribute.begins_with("m_Materials.Array.data[0]") and (system.renderer.materials as Array).size() > 1:
			return {"system": i, "field": "material"}
		var channel := "rgba".find(attribute.right(1))
		if (system.renderer.materials as Array).is_empty():
			return {}
		if attribute.length() > 2 and attribute[-2] == "." and channel >= 0:
			var property := attribute.trim_prefix("material.").left(-2)
			if property == "_EmissionColor" and channel < 3:
				return {"system": i, "field": "emission", "channel": channel}
			if property in ["_Color", "_TintColor", "_BaseColor"]:
				return {"system": i, "field": "tint", "channel": channel}
		return {}
	if attribute.begins_with("InitialModule.startColor."):
		var end := attribute.get_slice(".", 2)
		var channel := "rgba".find(attribute.get_slice(".", 3))
		if channel < 0 or end not in ["maxColor", "minColor"]:
			return {}
		# A lone colour is Unity's maxColor, and the whole start colour.
		var lone: bool = system.color.min == system.color.max and (system.color.max as Array).size() == 1
		return {"system": i, "field": "color", "end": "both" if lone else "max" if end == "maxColor" else "min", "channel": channel}
	var field: String = FIELDS.get(attribute.get_slice(".", 0) + "." + attribute.get_slice(".", 1), "")
	if field == "" or (field == "size" and system.size is Array):
		return {}
	var part := attribute.get_slice(".", 2)
	var value: Dictionary = system.get(field, {})
	if value.is_empty():
		return {}
	# Two constants are the one form whose ends differ in scale alone; Unity's scalar is its upper end, a lone
	# constant's or curve's whole multiplier.
	var ranged: bool = value.min.size() == 1 and value.max.size() == 1 and value.scale[0] != value.scale[1]
	if part == "scalar":
		return {"system": i, "field": field, "end": "max" if ranged else "both"}
	if part == "minScalar" and ranged:
		return {"system": i, "field": field, "end": "min"}
	return {}


## A clip's value `v` for effect `e` as the file holds that field: scaled as import scaled it, a legacy tint doubled.
func value(e: Dictionary, v: float) -> float:
	if e.field == "tint" and _legacy_tint[e.system][0]:
		return _doubled(v) if e.channel < 3 else minf(v * 2.0, 1.0)
	return v * float((_factors[e.system] as Dictionary).get(e.field, 1.0))


## The value a "particle" effect rests at: the field as the file saves it.
func rest(e: Dictionary) -> float:
	var system: Dictionary = systems[e.system]
	match e.field:
		"material":
			return 0.0
		"emission":
			return float((system.renderer.materials[0] as Dictionary).get("emission", [0.0, 0.0, 0.0])[e.channel])
		"tint":
			return float(system.renderer.materials[0].color[e.channel])
		"color":
			return float(system.color[e.end if e.end != "both" else "max"][0][e.channel])
	var c: Dictionary = system[e.field]
	return float(c.scale[0 if e.end == "min" else 1])


## The index of the material with GUID `guid` among system `i`'s choices, or -1.
func choice(i: int, guid: String) -> int:
	return (_choices[i] as Array).find(guid)


## A MinMaxCurve as UNITY_particles carries it, `by` times Unity's: {"min", "max" samples over its span, "scale":
## [low, high]}, its value at t the low end's sample times low blended toward the high end's times high by the
## particle's random.
static func curve(v: Variant, by := 1.0) -> Dictionary:
	var d: Dictionary = v if v is Dictionary else {}
	var scalar := Prefabs.number(d, "scalar") * by
	match _int(d, "minMaxState", 0):
		1:
			var s := _samples(d.get("maxCurve"))
			return {"min": s, "max": s, "scale": [scalar, scalar]}
		2:
			return {"min": _samples(d.get("minCurve")), "max": _samples(d.get("maxCurve")), "scale": [scalar, scalar]}
		3:
			return {"min": [1.0], "max": [1.0], "scale": [Prefabs.number(d, "minScalar") * by, scalar]}
	return {"min": [1.0], "max": [1.0], "scale": [scalar, scalar]}


## A MinMaxGradient as UNITY_particles carries it: {"min", "max" each a list of [r, g, b, a] samples}, sRGB colour as
## Unity saves it and linear alpha. Unity's random colour picks a point of its gradient; its ends stand for it.
static func gradient(v: Variant) -> Dictionary:
	var d: Dictionary = v if v is Dictionary else {}
	var c := func(k: String) -> Array:
		var col := Materials._colour(d.get(k), Color.WHITE)
		return [[col.r, col.g, col.b, col.a]]
	match _int(d, "minMaxState", 0):
		1:
			var g := _gradient(d.get("maxGradient"))
			return {"min": g, "max": g}
		2:
			return {"min": c.call("minColor"), "max": c.call("maxColor")}
		3:
			return {"min": _gradient(d.get("minGradient")), "max": _gradient(d.get("maxGradient"))}
		4:
			var g := _gradient(d.get("maxGradient"))
			return {"min": [g[0]], "max": [g[-1]]}
	return {"min": c.call("maxColor"), "max": c.call("maxColor")}


static func _samples(v: Variant) -> Array:
	var keys := []
	for k: Variant in Yaml.list((v as Dictionary).get("m_Curve") if v is Dictionary else null):
		var slope := func(s: String) -> Variant:
			var x := str((k as Dictionary).get(s, "0"))
			return null if x.contains("Infinity") else x.to_float()
		var key := [Prefabs.number(k, "time"), Prefabs.number(k, "value"), slope.call("inSlope"), slope.call("outSlope")]
		if _int(k, "weightedMode", 0) != 0:
			key.append_array([Prefabs.number(k, "inWeight", 1.0 / 3.0), Prefabs.number(k, "outWeight", 1.0 / 3.0)])
		keys.append(key)
	if keys.is_empty():
		return [1.0]
	var out := []
	for i in SAMPLES:
		out.append(snappedf(ExpressionState.sample(keys, float(i) / (SAMPLES - 1), false), 1e-5))
	return [out[0]] if out.all(func(x: float) -> bool: return is_equal_approx(x, out[0])) else out


static func _gradient(v: Variant) -> Array:
	var d: Dictionary = v if v is Dictionary else {}
	var colours := []
	var alphas := []
	for i in clampi(_int(d, "m_NumColorKeys", 2), 1, 8):
		colours.append([Prefabs.number(d, "ctime%d" % i) / 65535.0, Materials._colour(d.get("key%d" % i), Color.WHITE)])
	for i in clampi(_int(d, "m_NumAlphaKeys", 2), 1, 8):
		alphas.append([Prefabs.number(d, "atime%d" % i) / 65535.0, Materials._colour(d.get("key%d" % i), Color.WHITE).a])
	var fixed := _int(d, "m_Mode", 0) == 1
	var at := func(keys: Array, t: float) -> Variant:
		if t <= keys[0][0] or keys.size() == 1:
			return keys[0][1]
		for k in range(1, keys.size()):
			if t <= keys[k][0]:
				if fixed:
					return keys[k][1]
				var span: float = keys[k][0] - keys[k - 1][0]
				var p: float = (t - keys[k - 1][0]) / span if span > 0.0 else 1.0
				return lerp(keys[k - 1][1], keys[k][1], p)
		return keys[-1][1]
	var out := []
	for i in SAMPLES:
		var t := float(i) / (SAMPLES - 1)
		var col: Color = at.call(colours, t)
		out.append([snappedf(col.r, 1e-4), snappedf(col.g, 1e-4), snappedf(col.b, 1e-4), snappedf(at.call(alphas, t), 1e-4)])
	return [out[0]] if out.all(func(x: Array) -> bool: return x == out[0]) else out


## A by-speed range in m/s at the system's scale.
static func _range(v: Variant, by: float) -> Array:
	return [Prefabs.number(v, "x") * by, Prefabs.number(v, "y", 1.0) * by]


static func _constant(v: Variant) -> float:
	var c := curve(v)
	return 0.5 * (float(c.scale[0]) * float(c.min[0]) + float(c.scale[1]) * float(c.max[0]))


static func _on(module: Dictionary) -> bool:
	return _int(module, "enabled", 0) == 1


static func _int(v: Variant, k: String, otherwise: int) -> int:
	return str((v as Dictionary).get(k, otherwise)).to_int() if v is Dictionary else otherwise
