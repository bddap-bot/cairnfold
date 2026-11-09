class_name ParticleDefinition
extends RefCounted

## An avatar's particles as its root holds them, read into the form AvatarParticles runs: every field checked for its
## type and range, since files arrive from players, each missing one given Unity's default, and colours made linear.

const SHAPES := ["point", "sphere", "hemisphere", "cone", "box", "circle", "edge"]
const MODES := ["billboard", "stretched", "horizontal", "vertical", "mesh"]
const ALIGNS := ["view", "world", "local", "facing", "velocity"]
## The most curve samples, bursts and sub-emitters a system may name, and vertices a mesh may have.
const MAX_SAMPLES := 64
const MAX_BURSTS := 8
const MAX_SUB_EMITTERS := 16
const MAX_VERTICES := 4096
## Past this a number would overflow the 32-bit floats the GPU reads.
const LARGEST := 1e9
## A constant curve of 0, 1 and 5, which a clip may scale.
const ZERO := {"min": [1.0], "max": [1.0], "scale": [0.0, 0.0]}
const ONE := {"min": [1.0], "max": [1.0], "scale": [1.0, 1.0]}
const FIVE := {"min": [1.0], "max": [1.0], "scale": [5.0, 5.0]}
const WHITE := {"min": [[1.0, 1.0, 1.0, 1.0]], "max": [[1.0, 1.0, 1.0, 1.0]]}


## The run form of `particles`, an avatar's particles as its root's "particles" holds them: UNITY_particles with each
## "node" its name and each material's "image" an index into "images", a list of Images. "meshes" become ArrayMeshes
## and each image a mipmapped texture; a system is a sub-emitter ("sub") when another names it, and none names one
## that leads back to itself. Empty if the systems are malformed.
static func read(particles: Variant) -> Dictionary:
	if not particles is Dictionary or not particles.get("systems") is Array or particles.systems.size() > Avatar.MAX_PARTICLE_SYSTEMS:
		return {}
	var meshes: Array[ArrayMesh] = []
	for m: Variant in particles.get("meshes", []) if particles.get("meshes") is Array else []:
		var mesh := _mesh(m)
		if mesh == null:
			return {}
		meshes.append(mesh)
	var textures := []
	for img: Variant in particles.get("images", []) if particles.get("images") is Array else []:
		textures.append(_texture(img))
	var systems := []
	for s: Variant in particles.systems:
		var system := _system(s, textures, meshes, particles.systems.size())
		if system.is_empty():
			return {}
		systems.append(system)
	for i in systems.size():
		systems[i].subEmitters = (systems[i].subEmitters as Array).filter(func(sub: Dictionary) -> bool: return not _leads_to(systems, sub.system, i))
		for sub: Dictionary in systems[i].subEmitters:
			systems[sub.system].sub = true
	var slots := 0
	var vertices := 0
	for s: Dictionary in systems:
		slots += s.max
		vertices += s.max * (meshes[s.renderer.mesh].surface_get_array_len(0) if s.renderer.has("mesh") else 4)
	var share := minf(1.0, minf(float(Avatar.MAX_PARTICLES) / maxi(slots, 1), float(Avatar.MAX_PARTICLE_VERTICES) / maxi(vertices, 1)))
	for s: Dictionary in systems:
		s.max = int(s.max * share)
	return {"systems": systems, "meshes": meshes}


## Whether system `from`, or a sub-emitter it names however far down, is system `to`.
static func _leads_to(systems: Array, from: int, to: int) -> bool:
	var seen := {}
	var pending := [from]
	while not pending.is_empty():
		var at: int = pending.pop_back()
		if at == to:
			return true
		if seen.has(at):
			continue
		seen[at] = true
		for sub: Dictionary in systems[at].subEmitters:
			pending.append(sub.system)
	return false


## A mipmapped texture of `img`, or null where it is none.
static func _texture(img: Variant) -> Texture2D:
	if not img is Image or (img as Image).is_empty():
		return null
	var mipmapped := (img as Image).duplicate() as Image
	mipmapped.generate_mipmaps()
	return ImageTexture.create_from_image(mipmapped)


static func _system(s: Variant, textures: Array, meshes: Array[ArrayMesh], systems: int) -> Dictionary:
	if not s is Dictionary or not s.get("node") is String or s.node == "":
		return {}
	var out := {
		"node": s.node,
		"duration": maxf(_number(s.get("duration"), 5.0), 0.01),
		"loop": s.get("loop", true) == true,
		"awake": s.get("awake", true) == true,
		"world": s.get("world", false) == true,
		"sub": false,
		"delay": maxf(_number(s.get("delay"), 0.0), 0.0),
		"max": int(clampf(_number(s.get("max"), 1000.0), 0.0, Avatar.MAX_PARTICLES)),
		"lifetime": _curve(s.get("lifetime"), FIVE),
		"speed": _curve(s.get("speed"), FIVE),
		"gravity": _curve(s.get("gravity"), ZERO),
		"rate": _curve(s.get("rate"), ZERO),
		"distance": _curve(s.get("distance"), ZERO),
		"size": _axes(s.get("size"), ONE),
		"rotation": _axes(s.get("rotation"), ZERO),
		"color": _gradient(s.get("color")),
	}
	var bursts := []
	for b: Variant in s.get("bursts", []) if s.get("bursts") is Array else []:
		if b is Dictionary and bursts.size() < MAX_BURSTS:
			bursts.append({"time": maxf(_number(b.get("time"), 0.0), 0.0), "count": _curve(b.get("count"), ZERO), "cycles": int(clampf(_number(b.get("cycles"), 1.0), 1.0, 1000.0)), "interval": maxf(_number(b.get("interval"), 0.01), 0.001), "probability": clampf(_number(b.get("probability"), 1.0), 0.0, 1.0)})
	out.bursts = bursts
	var shape: Dictionary = s.get("shape") if s.get("shape") is Dictionary else {}
	out.shape = {
		"type": shape.get("type") if shape.get("type") in SHAPES else "point",
		"radius": maxf(_number(shape.get("radius"), 1.0), 0.0),
		"thickness": clampf(_number(shape.get("thickness"), 1.0), 0.0, 1.0),
		"angle": clampf(_number(shape.get("angle"), 0.0), 0.0, PI / 2),
		"arc": clampf(_number(shape.get("arc"), TAU), 0.0, TAU),
		"length": maxf(_number(shape.get("length"), 0.0), 0.0),
		"matrix": _matrix(shape.get("matrix")),
		"randomDirection": clampf(_number(shape.get("randomDirection"), 0.0), 0.0, 1.0),
		"spherical": clampf(_number(shape.get("spherical"), 0.0), 0.0, 1.0),
		"randomPosition": maxf(_number(shape.get("randomPosition"), 0.0), 0.0),
	}
	var velocity: Variant = s.get("velocity")
	if velocity is Dictionary:
		out.velocity = {"x": _curve(velocity.get("x"), ZERO), "y": _curve(velocity.get("y"), ZERO), "z": _curve(velocity.get("z"), ZERO), "world": velocity.get("world", false) == true}
	var limit: Variant = s.get("limit")
	if limit is Dictionary:
		out.limit = {"speed": _curve(limit.get("speed"), ONE), "dampen": clampf(_number(limit.get("dampen"), 1.0), 0.0, 1.0)}
	if s.has("inherit"):
		out.inherit = _curve(s.get("inherit"), ZERO)
	var noise: Variant = s.get("noise")
	if noise is Dictionary:
		out.noise = {"strength": _curve(noise.get("strength"), ONE), "frequency": clampf(_number(noise.get("frequency"), 0.5), 0.0, 100.0)}
	if s.has("sizeOverLife"):
		out.sizeOverLife = _axes(s.get("sizeOverLife"), ONE)
	if s.has("colorOverLife"):
		out.colorOverLife = _gradient(s.get("colorOverLife"))
	if s.has("spin"):
		out.spin = _axes(s.get("spin"), ZERO)
	for key: String in ["sizeBySpeed", "colorBySpeed"]:
		var by: Variant = s.get(key)
		if by is Dictionary:
			var r: Variant = by.get("range")
			var low := _number(r[0], 0.0) if r is Array and r.size() == 2 else 0.0
			var high := _number(r[1], 1.0) if r is Array and r.size() == 2 else 1.0
			out[key] = {"range": [low, high if high > low else low + 1.0]}
			if key == "sizeBySpeed":
				out[key].size = _curve(by.get("size"), ONE)
			else:
				out[key].color = _gradient(by.get("color"))
	var subs := []
	for sub: Variant in s.get("subEmitters", []) if s.get("subEmitters") is Array else []:
		if sub is Dictionary and ExpressionDefinition._index(sub.get("system"), systems) and sub.get("on") in ["birth", "death"] and subs.size() < MAX_SUB_EMITTERS:
			var inherit: Array = sub.get("inherit") if sub.get("inherit") is Array else []
			subs.append({"system": int(sub.system), "on": sub.on, "inherit": inherit.filter(func(p: Variant) -> bool: return p in ["color", "size", "rotation", "lifetime"])})
	out.subEmitters = subs
	var r: Dictionary = s.get("renderer") if s.get("renderer") is Dictionary else {}
	var renderer := {
		"draw": r.get("draw", false) == true,
		"mode": r.get("mode") if r.get("mode") in MODES else "billboard",
		"align": r.get("align") if r.get("align") in ALIGNS else "view",
		"pivot": _vector(r.get("pivot")),
		"length": _number(r.get("length"), 2.0),
		"velocityScale": _number(r.get("velocityScale"), 0.0),
		"maxSize": maxf(_number(r.get("maxSize"), 0.5), 0.0),
		"materials": [],
	}
	if renderer.mode == "mesh":
		if ExpressionDefinition._index(r.get("mesh"), meshes.size()):
			renderer.mesh = int(r.mesh)
		else:
			renderer.draw = false
	for m: Variant in r.get("materials", []) if r.get("materials") is Array else []:
		if not m is Dictionary:
			return {}
		var material := {
			"color": _colour(m.get("color"), Color.WHITE),
			"blend": m.get("blend") if AvatarParticles.SHADERS.has(m.get("blend")) else "alpha",
			"cutoff": clampf(_number(m.get("cutoff"), 0.5), 0.0, 1.0),
			"emission": _colour(m.get("emission"), Color.BLACK),
		}
		var uv: Variant = m.get("uv")
		material.uv = Vector4(uv[0], uv[1], uv[2], uv[3]) if uv is Array and uv.size() == 4 and uv.all(_finite) else Vector4(1, 1, 0, 0)
		if m.has("image"):
			if not ExpressionDefinition._index(m.image, textures.size()) or textures[int(m.image)] == null:
				return {}
			material.texture = textures[int(m.image)]
		renderer.materials.append(material)
	if renderer.materials.is_empty():
		renderer.draw = false
	out.renderer = renderer
	return out


## A curve, its samples floats and its scale two numbers; `otherwise` where it is malformed.
static func _curve(v: Variant, otherwise: Dictionary) -> Dictionary:
	var ok := func(a: Variant) -> bool: return a is Array and a.size() >= 1 and a.size() <= MAX_SAMPLES and a.all(_finite)
	if not v is Dictionary or not ok.call(v.get("min")) or not ok.call(v.get("max")) or not (v.get("scale") is Array and v.scale.size() == 2 and v.scale.all(_finite)):
		v = otherwise
	return {"min": PackedFloat32Array(v.min), "max": PackedFloat32Array(v.max), "scale": [float(v.scale[0]), float(v.scale[1])]}


## One curve, or three per axis.
static func _axes(v: Variant, otherwise: Dictionary) -> Array:
	if v is Array and v.size() == 3:
		return v.map(func(c: Variant) -> Dictionary: return _curve(c, otherwise))
	return [_curve(v, otherwise)]


## A gradient's two ends, each linear colours.
static func _gradient(v: Variant) -> Dictionary:
	var ok := func(a: Variant) -> bool: return a is Array and a.size() >= 1 and a.size() <= MAX_SAMPLES and a.all(func(c: Variant) -> bool: return c is Array and c.size() == 4 and c.all(_finite))
	if not v is Dictionary or not ok.call(v.get("min")) or not ok.call(v.get("max")):
		v = WHITE
	var linear := func(samples: Array) -> PackedColorArray:
		return PackedColorArray(samples.map(func(c: Array) -> Color: return _colour(c, Color.WHITE)))
	return {"min": linear.call(v.min), "max": linear.call(v.max)}


static func _mesh(m: Variant) -> ArrayMesh:
	if not m is Dictionary or not m.get("positions") is Array or not m.get("indices") is Array:
		return null
	var p: Array = m.positions
	var count := p.size() / 3
	if p.size() % 3 != 0 or count > MAX_VERTICES or not p.all(_finite) or not m.indices.all(func(i: Variant) -> bool: return ExpressionDefinition._index(i, count)) or m.indices.size() % 3 != 0:
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var vertices := PackedVector3Array()
	for i in count:
		vertices.append(Vector3(p[3 * i], p[3 * i + 1], p[3 * i + 2]))
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var uv: Variant = m.get("uvs")
	if uv is Array and uv.size() == 2 * count and uv.all(_finite):
		var uvs := PackedVector2Array()
		for i in count:
			uvs.append(Vector2(uv[2 * i], uv[2 * i + 1]))
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(m.indices)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _matrix(v: Variant) -> Transform3D:
	if not (v is Array and v.size() == 16 and v.all(_finite)):
		return Transform3D.IDENTITY
	return Transform3D(Vector3(v[0], v[1], v[2]), Vector3(v[4], v[5], v[6]), Vector3(v[8], v[9], v[10]), Vector3(v[12], v[13], v[14]))


static func _vector(v: Variant) -> Vector3:
	return Vector3(v[0], v[1], v[2]) if v is Array and v.size() == 3 and v.all(_finite) else Vector3.ZERO


## An sRGB colour with linear alpha, as the file carries it, made linear.
static func _colour(v: Variant, otherwise: Color) -> Color:
	if v is Array and (v.size() == 3 or v.size() == 4) and v.all(_finite):
		return Color(v[0], v[1], v[2], v[3] if v.size() == 4 else 1.0).srgb_to_linear()
	return otherwise


static func _number(v: Variant, otherwise: float) -> float:
	return float(v) if _finite(v) else otherwise


static func _finite(v: Variant) -> bool:
	return ExpressionDefinition._number(v) and absf(float(v)) <= LARGEST
