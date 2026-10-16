class_name Look
extends Node

## Sky, sun, fog and grading, lit for the time of day (Daylight).

## Each change to the sky restarts its radiance update, which takes several frames and is where the ambient
## light comes from; so while the sun is dragged the sky changes this often, letting each update finish,
## and the light and the sun's disc, which follow every frame, stay out of the sky.
const SKY_EVERY := 0.2
const DISC_DISTANCE := 350.0
## Degrees from the sun's centre: the quad's half-width, and the disc's radius at rest and while a hand
## points at it.
const DISC_SPAN_DEG := 6.5
const DISC_RADIUS_DEG := 1.8
const DISC_SWELL_DEG := 3.6

const FLAGSTONE_TEXELS := 256
## Shadows and fog follow the eye's height above the ground (`lift`): up to STANDING, the sun's shadows reach
## SHADOW_REACH metres and the nearer of their two splits covers the first SHADOW_NEAR; floating higher, both
## stretch with the distance down to the ground, so the near split falls on the ground rather than the empty
## air around the eye. Fog begins and ends farther out the same way: from above, the ground is seen through
## the air the eye floats over, and depth fog would grey a garden a standing eye sees clear.
const STANDING := 2.0
const SHADOW_REACH := 45.0
const SHADOW_NEAR := 6.0
const SHADOW_FARTHEST := 90.0
const FOG_BEGIN := 18.0
const FOG_END := 140.0

static var _detail: NoiseTexture2D
static var _flagstones: ImageTexture

var sun: DirectionalLight3D
var env: Environment
var sky_mat: ShaderMaterial
var disc: MeshInstance3D
var disc_mat := ShaderMaterial.new()
var bounce := Bounce.new()
var _lift := -1.0
var time := -1.0
var _sky_time := -1.0
var _since_sky := INF


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
	if _flagstones != null:
		return _flagstones
	var seams := _cells(FastNoiseLite.RETURN_DISTANCE2_SUB).get_data()
	var cells := _cells(FastNoiseLite.RETURN_CELL_VALUE).get_data()
	var rg := PackedByteArray()
	rg.resize(seams.size() * 2)
	for i in seams.size():
		rg[i * 2] = seams[i]
		rg[i * 2 + 1] = cells[i]
	var img := Image.create_from_data(FLAGSTONE_TEXELS, FLAGSTONE_TEXELS, false, Image.FORMAT_RG8, rg)
	img.generate_mipmaps()
	_flagstones = ImageTexture.create_from_image(img)
	return _flagstones


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


static func build(parent: Node) -> Look:
	var look := Look.new()
	parent.add_child(look)
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
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.35
	env.fog_depth_curve = 1.6
	env.fog_density = 0.55
	env.fog_aerial_perspective = 0.8
	env.fog_sky_affect = 0.15
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.04
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.light_cull_mask &= ~Hand.WHEEL_LAYER
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.shadow_blur = 1.5
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	parent.add_child(sun)
	look.sun = sun
	look.env = env
	look.sky_mat = sky_mat
	var quad := QuadMesh.new()
	var half := DISC_DISTANCE * tan(deg_to_rad(DISC_SPAN_DEG))
	quad.size = Vector2.ONE * 2.0 * half
	look.disc = MeshInstance3D.new()
	look.disc.mesh = quad
	look.disc_mat.shader = load("res://src/sun_disc.gdshader")
	look.disc.material_override = look.disc_mat
	look.disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The quad turns to the eye in its shader, so its bounds must hold it facing any way.
	look.disc.custom_aabb = AABB(-Vector3.ONE * half * sqrt(2.0), Vector3.ONE * half * 2.0 * sqrt(2.0))
	look.add_child(look.disc)
	look.swell(false)
	look.bounce.install()
	look.lift_to(0.0)
	look.set_time(Daylight.DEFAULT)
	look._paint_sky()
	return look


func set_time(t: float) -> void:
	t = clampf(t, 0.0, 1.0)
	if t == time:
		return
	time = t
	var l := Daylight.light(t)
	sun.basis = Basis.looking_at(-Daylight.toward_sun(t))
	sun.light_color = l.sun
	sun.light_energy = l.energy
	disc_mat.set_shader_parameter("tint", l.sun)
	env.ambient_light_energy = l.ambient
	env.fog_light_color = l.fog
	bounce.set_sun(Daylight.toward_sun(t), l.sun * l.energy)


## Fits the sun's shadow splits and the fog to an eye `lift` metres above the ground.
static func shadow_and_fog(lift: float) -> Dictionary:
	var up := maxf(lift - STANDING, 0.0)
	var reach := minf(SHADOW_REACH + up * 1.8, SHADOW_FARTHEST)
	return {
		"shadow_reach": reach,
		"near_split": minf((SHADOW_NEAR + up * 1.3) / reach, 0.5),
		"fog_begin": FOG_BEGIN + up * 2.2,
		"fog_end": FOG_END + up * 2.5,
	}


func lift_to(lift: float) -> void:
	lift = snappedf(maxf(lift, 0.0), 0.5)
	if lift == _lift:
		return
	_lift = lift
	var f := shadow_and_fog(lift)
	sun.directional_shadow_max_distance = f.shadow_reach
	sun.directional_shadow_split_1 = f.near_split
	env.fog_depth_begin = f.fog_begin
	env.fog_depth_end = f.fog_end


func _exit_tree() -> void:
	bounce.stop()


func swell(on: bool) -> void:
	disc_mat.set_shader_parameter("radius", (DISC_SWELL_DEG if on else DISC_RADIUS_DEG) / DISC_SPAN_DEG)


func _process(delta: float) -> void:
	var eye := get_viewport().get_camera_3d()
	if eye != null:
		var at := eye.global_position
		disc.global_position = at + Daylight.toward_sun(time) * DISC_DISTANCE
		lift_to(at.y - Terrain.height_at(at.x, at.z))
	bounce.update()
	_since_sky += delta
	if _sky_time != time and _since_sky >= SKY_EVERY:
		_paint_sky()


func _paint_sky() -> void:
	_sky_time = time
	_since_sky = 0.0
	var l := Daylight.light(time)
	sky_mat.set_shader_parameter("sun_dir", Daylight.toward_sun(time))
	sky_mat.set_shader_parameter("zenith", l.zenith)
	sky_mat.set_shader_parameter("horizon", l.horizon)
	sky_mat.set_shader_parameter("sun_glow", l.glow)
	sky_mat.set_shader_parameter("cloud_light", l.clouds)
