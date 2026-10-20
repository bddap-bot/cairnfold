class_name Look
extends Node

## Sky, sun, fog and grading, lit for the time of day (Daylight).

## Each change to the sky restarts its radiance update, which takes several frames and is where the ambient
## light comes from; so while the sky is turned the sky changes this often, letting each update finish,
## and the light and the sun's disc, which follow every frame, stay out of the sky.
const SKY_EVERY := 0.2
const DISC_DISTANCE := 2400.0
## Degrees from the sun's centre: the quad's half-width and the disc's radius.
const DISC_SPAN_DEG := 6.5
const DISC_RADIUS_DEG := 1.8

# A fade or split selected by view depth changes a fixed object's shade when the head turns.
# One stabilized map covers the garden's diagonal, including its height and floating views.
const SHADOW_REACH := 256.0
const STANDING := 2.0
const FOG_BEGIN := 18.0
const FOG_END := 140.0
const AIR_FOG := {"fog_depth_curve": 1.6, "fog_density": 0.55, "fog_aerial_perspective": 0.8, "fog_sun_scatter": 0.35, "fog_sky_affect": 0.15}
## Under a pond the view is gone to the water's blue-green within a few metres, thickest close in.
const WATER_FOG := {"fog_depth_begin": 0.0, "fog_depth_end": 7.0, "fog_depth_curve": 0.6, "fog_density": 1.0, "fog_aerial_perspective": 0.0, "fog_sun_scatter": 0.0, "fog_sky_affect": 1.0}
const UNDER_FOG := Color(0.07, 0.25, 0.27)
## Water takes red first, then green: what reaches the eye through it keeps this much of each.
const UNDER_KEEPS := Color(0.55, 0.92, 1.0)
## The eye adapts to the sky it sees (Bounce.sky_at): under a roof with none, exposure rises this many times
## over the open garden's, closing most of the gap in ADAPT_SECONDS, so a house's inside reads once entered
## and its doorway glows.
const EXPOSURE := 1.05
const ADAPT_INDOOR := 1.8
const ADAPT_SECONDS := 0.7

static var _detail: NoiseTexture2D
static var _absorb: GradientTexture1D

var sun: DirectionalLight3D
## The sun as a photo sees it (Quality.FULL_LAYER); turned with `sun` as its child, lit as it is.
var photo_sun: DirectionalLight3D
var env: Environment
var sky_mat: ShaderMaterial
var disc: MeshInstance3D
var disc_mat := ShaderMaterial.new()
var mountains_mat := ShaderMaterial.new()
var bounce := Bounce.new()
var _lift := -1.0
var time := -1.0
var _sky_time := -1.0
var _since_sky := INF
var _adapt := 1.0
var under := false


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
	env.reflected_light_source = Quality.HEADSET.reflections
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = EXPOSURE
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_energy = 1.0
	for k in AIR_FOG:
		env.set(k, AIR_FOG[k])
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.04
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = SHADOW_REACH
	sun.directional_shadow_fade_start = 1.0
	sun.shadow_blur = 0.2
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	parent.add_child(sun)
	look.sun = sun
	look.photo_sun = sun.duplicate()
	sun.layers = Quality.LADDER_LAYER
	look.photo_sun.layers = Quality.FULL_LAYER
	look.photo_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	look.photo_sun.directional_shadow_max_distance = SHADOW_REACH
	look.photo_sun.directional_shadow_blend_splits = true
	sun.add_child(look.photo_sun)
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
	look.disc_mat.set_shader_parameter("radius", DISC_RADIUS_DEG / DISC_SPAN_DEG)
	look.mountains_mat.shader = load("res://src/mountains.gdshader")
	look.add_child(Mountains.build(look.mountains_mat))
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
	for light in [sun, photo_sun]:
		light.light_color = l.sun
		light.light_energy = l.energy
	disc_mat.set_shader_parameter("tint", l.sun)
	env.ambient_light_energy = l.ambient
	env.fog_light_color = UNDER_FOG * under_light(l) if under else l.fog
	mountains_mat.set_shader_parameter("sun_dir", Daylight.toward_sun(t))
	mountains_mat.set_shader_parameter("sun", l.sun)
	mountains_mat.set_shader_parameter("energy", l.energy)
	mountains_mat.set_shader_parameter("sky", l.zenith)
	mountains_mat.set_shader_parameter("ambient", l.ambient)
	mountains_mat.set_shader_parameter("horizon", l.horizon)
	mountains_mat.set_shader_parameter("haze", l.fog)
	bounce.set_sun(Daylight.toward_sun(t), l.sun * l.energy)


static func fog_at_height(lift: float) -> Dictionary:
	var up := maxf(lift - STANDING, 0.0)
	return {
		"fog_depth_begin": FOG_BEGIN + up * 2.2,
		"fog_depth_end": FOG_END + up * 2.5,
	}


## How bright the water around an eye under it is at this hour's `l` (Daylight.light).
static func under_light(l: Dictionary) -> float:
	return 0.25 + 0.45 * l.energy


func submerge(on: bool) -> void:
	if on == under:
		return
	under = on
	if on and _absorb == null:
		var g := Gradient.new()
		g.set_color(0, Color.BLACK)
		g.set_color(1, UNDER_KEEPS)
		_absorb = GradientTexture1D.new()
		_absorb.gradient = g
	_set_fog(WATER_FOG if on else AIR_FOG.merged(fog_at_height(_lift)))
	env.adjustment_color_correction = _absorb if on else null
	var l := Daylight.light(time)
	env.fog_light_color = UNDER_FOG * under_light(l) if on else l.fog


func lift_to(lift: float) -> void:
	lift = snappedf(maxf(lift, 0.0), 0.5)
	if lift == _lift:
		return
	_lift = lift
	if not under:
		_set_fog(fog_at_height(lift))


func _set_fog(fog: Dictionary) -> void:
	for k in fog:
		env.set(k, fog[k])


## Moves the exposure toward an eye seeing `sky` of the sky.
func adapt(sky: float, delta: float) -> void:
	var to := lerpf(ADAPT_INDOOR, 1.0, sky)
	_adapt = lerpf(_adapt, to, 1.0 - exp(-delta / ADAPT_SECONDS))
	if absf(env.tonemap_exposure - EXPOSURE * _adapt) > 0.002:
		env.tonemap_exposure = EXPOSURE * _adapt


func _exit_tree() -> void:
	bounce.stop()


func _process(delta: float) -> void:
	var eye := get_viewport().get_camera_3d()
	if eye != null:
		var at := eye.global_position
		disc.global_position = at + Daylight.toward_sun(time) * DISC_DISTANCE
		lift_to(at.y - Terrain.height_at(at.x, at.z))
		adapt(bounce.sky_at(at), delta)
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
	var overhead: Color = l.zenith.lerp(l.horizon, 0.3)
	RenderingServer.global_shader_parameter_set("sky_overhead", Vector3(overhead.r, overhead.g, overhead.b))
