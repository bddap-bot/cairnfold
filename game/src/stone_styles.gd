class_name StoneStyles
extends RefCounted

## The painted stone ground's styles: the one table the style wheel lists and the ground is shaded from
## (stone_ground.gdshaderinc). Each style's pattern tiles a square `tile` metres a side, baked once on the GPU by
## stone_bake.glsl: `kind` of stone, `across` stones a tile, `jitter`
## and `warp` to break the grid, `joint` metres of bevel into the soil between stones, `dome` how much each rounds
## from its centre, `grain` how rough its face, `relief` metres from joint to crown, and `elongation` a pebble's
## longest over shortest. The ground shades it between `dark` and `light` stones, with `moss` on the stones and
## `meadow` of the joints grassed rather than earth.

enum Kind { CELLS, PEBBLES }

const TEXELS := 512
## Room in the shaders' per-style arrays.
const ROOM := 8

## Indices into STYLES that paths lay (PathLayout.Surface's cobbles and flagstones).
const MOSSY := 0
const RIVER_COBBLE := 1
const STYLES: Array[Dictionary] = [
	{"name": "mossy", "kind": Kind.CELLS, "tile": 5.5, "across": 8, "jitter": 1.0, "warp": 0.25, "joint": 0.12, "dome": 0.6, "grain": 0.4, "relief": 0.12, "elongation": 1.0,
		"light": Color(0.58, 0.57, 0.50), "dark": Color(0.33, 0.33, 0.30), "moss": 0.65, "meadow": 0.75},
	{"name": "river cobble", "kind": Kind.PEBBLES, "tile": 3.2, "across": 14, "jitter": 0.35, "warp": 0.0, "joint": 0.0, "dome": 1.0, "grain": 0.04, "relief": 0.06, "elongation": 1.6,
		"light": Color(0.75, 0.71, 0.65), "dark": Color(0.36, 0.35, 0.34), "moss": 0.0, "meadow": 0.12},
]

static var _patterns: Texture2DArray


## Every style's pattern, one layer each, baked on first use. Without a GPU (headless) each is one level texel.
static func patterns() -> Texture2DArray:
	if _patterns != null:
		return _patterns
	assert(STYLES.size() <= ROOM)
	var began := Time.get_ticks_usec()
	var images: Array[Image] = []
	var rd := RenderingServer.create_local_rendering_device()
	if rd == null:
		for s in STYLES:
			images.append(Image.create_from_data(1, 1, false, Image.FORMAT_RGBA8, PackedByteArray([255, 128, 128, 128])))
	else:
		images = _bake(rd)
		rd.free()
	for img in images:
		img.generate_mipmaps()
	_patterns = Texture2DArray.new()
	_patterns.create_from_images(images)
	print("stone: %d styles baked in %.1f ms" % [STYLES.size(), (Time.get_ticks_usec() - began) / 1000.0])
	return _patterns


static func _bake(rd: RenderingDevice) -> Array[Image]:
	var shader := rd.shader_create_from_spirv((preload("res://src/stone_bake.glsl") as RDShaderFile).get_spirv())
	var pipeline := rd.compute_pipeline_create(shader)
	var fmt := RDTextureFormat.new()
	fmt.texture_type = RenderingDevice.TEXTURE_TYPE_2D_ARRAY
	fmt.width = TEXELS
	fmt.height = TEXELS
	fmt.array_layers = STYLES.size()
	fmt.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var tex := rd.texture_create(fmt, RDTextureView.new())
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = 0
	u.add_id(tex)
	var set := rd.uniform_set_create([u], shader, 0)
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, pipeline)
	rd.compute_list_bind_uniform_set(list, set, 0)
	for i in STYLES.size():
		var s: Dictionary = STYLES[i]
		var push := PackedInt32Array([s.kind, s.across, i, 0]).to_byte_array()
		push.append_array(PackedFloat32Array([s.jitter, s.warp, s.joint, s.dome, s.grain, s.relief, s.tile, s.elongation]).to_byte_array())
		rd.compute_list_set_push_constant(list, push, push.size())
		rd.compute_list_dispatch(list, TEXELS / 8, TEXELS / 8, 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	var out: Array[Image] = []
	for i in STYLES.size():
		out.append(Image.create_from_data(TEXELS, TEXELS, false, Image.FORMAT_RGBA8, rd.texture_get_data(tex, i)))
	rd.free_rid(set)
	rd.free_rid(tex)
	rd.free_rid(pipeline)
	rd.free_rid(shader)
	return out


## Gives `mat`, a shader including stone_ground.gdshaderinc, the styles.
static func apply(mat: ShaderMaterial) -> void:
	var look := PackedVector3Array()
	var light := PackedVector3Array()
	var dark := PackedVector3Array()
	for i in ROOM:
		var s: Dictionary = STYLES[mini(i, STYLES.size() - 1)]
		look.append(Vector3(s.tile, s.moss, s.meadow))
		light.append(_linear(s.light))
		dark.append(_linear(s.dark))
	mat.set_shader_parameter("stone_patterns", patterns())
	mat.set_shader_parameter("stone_look", look)
	mat.set_shader_parameter("stone_light", light)
	mat.set_shader_parameter("stone_dark", dark)


static func _linear(c: Color) -> Vector3:
	var l := c.srgb_to_linear()
	return Vector3(l.r, l.g, l.b)
