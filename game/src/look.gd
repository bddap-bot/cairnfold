class_name Look
extends RefCounted

## Sky, sun, fog and grading: the mood of a late-morning meadow.

const FLAGSTONE_TEXELS := 256

static var _detail: NoiseTexture2D


static func detail_noise() -> NoiseTexture2D:
	if _detail == null:
		var n := FastNoiseLite.new()
		n.seed = 3
		n.frequency = 0.02
		n.fractal_octaves = 4
		_detail = NoiseTexture2D.new()
		_detail.width = 256
		_detail.height = 256
		_detail.seamless = true
		_detail.generate_mipmaps = true
		_detail.noise = n
	return _detail


## Flagstones for stone ground, tiling: red rises from 0 along the joints between slabs, green is each
## slab's own value.
static func flagstones() -> ImageTexture:
	var seams := _cells(FastNoiseLite.RETURN_DISTANCE2_SUB).get_data()
	var cells := _cells(FastNoiseLite.RETURN_CELL_VALUE).get_data()
	var rg := PackedByteArray()
	rg.resize(seams.size() * 2)
	for i in seams.size():
		rg[i * 2] = seams[i]
		rg[i * 2 + 1] = cells[i]
	var img := Image.create_from_data(FLAGSTONE_TEXELS, FLAGSTONE_TEXELS, false, Image.FORMAT_RG8, rg)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _cells(returns: FastNoiseLite.CellularReturnType) -> Image:
	var n := FastNoiseLite.new()
	n.seed = 31
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.frequency = 0.05
	n.fractal_type = FastNoiseLite.FRACTAL_NONE
	n.cellular_jitter = 0.85
	n.cellular_return_type = returns
	return n.get_seamless_image(FLAGSTONE_TEXELS, FLAGSTONE_TEXELS)


static func cloud_noise() -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = 21
	n.noise_type = FastNoiseLite.TYPE_PERLIN
	n.frequency = 0.012
	n.fractal_octaves = 5
	n.fractal_gain = 0.55
	var t := NoiseTexture2D.new()
	t.width = 512
	t.height = 512
	t.seamless = true
	t.generate_mipmaps = true
	t.noise = n
	return t


static func build(parent: Node) -> DirectionalLight3D:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://src/sky.gdshader")
	sky_mat.set_shader_parameter("clouds", cloud_noise())
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 0.75
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.80, 0.85, 0.90)
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.35
	env.fog_depth_begin = 18.0
	env.fog_depth_end = 140.0
	env.fog_depth_curve = 1.6
	env.fog_density = 0.55
	env.fog_aerial_perspective = 0.55
	env.fog_sky_affect = 0.15
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.04
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.93, 0.80)
	sun.light_energy = 1.7
	sun.rotation = Vector3(deg_to_rad(-34.0), deg_to_rad(-150.0), 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 45.0
	sun.shadow_blur = 1.5
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	parent.add_child(sun)
	return sun
