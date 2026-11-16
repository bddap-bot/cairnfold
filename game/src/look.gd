class_name Look
extends Node

## Each sky change restarts its radiance update, the ambient light's source, which takes frames: while turned the sky
## changes this often so each finishes, and the light and discs, which follow every frame, stay out of it.
const SKY_EVERY := 0.2
const DISC_DISTANCE := 2400.0
## Degrees from each disc's centre: `span` its quad's half-width, `radius` its radius.
const SUN_DISC := {"span": 6.5, "radius": 1.8}
const MOON_DISC := {"span": 9.0, "radius": 2.5}

# Splits by view depth change a fixed object's shade as the head turns, so one map covers the garden; its 21 cm texels
# lose small casters, so an engine splitting by distance from the eye (scripts/engine.patch) adds one in SHADOW_NEAR.
const SHADOW_REACH := 256.0
const SHADOW_NEAR := 10.0
const SPLIT_BY_DISTANCE := "rendering/lights_and_shadows/directional_shadow/split_by_distance"
const STANDING := 2.0
const FOG_BEGIN := 18.0
const FOG_END := 140.0
const AIR_FOG := {"fog_depth_curve": 1.6, "fog_density": 0.55, "fog_aerial_perspective": 0.8, "fog_sun_scatter": 0.35, "fog_sky_affect": 0.15}
const WATER_FOG := {"fog_depth_begin": 0.0, "fog_depth_end": 7.0, "fog_depth_curve": 0.6, "fog_density": 1.0, "fog_aerial_perspective": 0.0, "fog_sun_scatter": 0.0, "fog_sky_affect": 1.0}
const UNDER_FOG := Color(0.07, 0.25, 0.27)
## Water takes red first, then green: what reaches the eye through it keeps this much of each.
const UNDER_KEEPS := Color(0.55, 0.92, 1.0)
## Under a roof, seeing no sky (Bounce.sky_at), exposure rises this many times, most of it in ADAPT_SECONDS, so a
## house's inside reads once entered and its doorway glows.
const ADAPT_INDOOR := 1.8
const ADAPT_SECONDS := 0.7
## Under a sky darker than NIGHT_FLOOR exposure rises with the dark, up to NIGHT_MOST times, so builds read before
## dawn; the night's keys (Daylight.KEYS) stay as they are.
const NIGHT_FLOOR := 0.12
const NIGHT_MOST := 4.0

static var _absorb: GradientTexture1D

var sun: DirectionalLight3D
## The sun as a photo sees it (Quality.FULL_LAYER); turned with `sun` as its child, lit as it is.
var photo_sun: DirectionalLight3D
var env: Environment
var sky_mat: ShaderMaterial
var disc: MeshInstance3D
var moon_disc: MeshInstance3D
var bounce := Bounce.new()
var interior := Interior.new()
var terrain: Terrain
var _lift := -1.0
var time := -1.0
var _sky_time := -1.0
var _since_sky := INF
var _adapt := 1.0
var _exposure := 1.0
var under := false


static func build(parent: Node, ground: Terrain) -> Look:
	var look := Look.new()
	look.terrain = ground
	look.bounce.terrain = ground
	parent.add_child(look)
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://src/sky.gdshader")
	var clouds := FastNoiseLite.new()
	clouds.seed = 21
	clouds.noise_type = FastNoiseLite.TYPE_PERLIN
	clouds.frequency = 0.012
	clouds.fractal_octaves = 5
	clouds.fractal_gain = 0.55
	sky_mat.set_shader_parameter("clouds", Meshes.noise_texture(clouds, 512))
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
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_energy = 1.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.04
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	if ProjectSettings.get_setting(SPLIT_BY_DISTANCE, false):
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_split_1 = SHADOW_NEAR / SHADOW_REACH
		sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = SHADOW_REACH
	sun.directional_shadow_fade_start = 1.0
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	parent.add_child(sun)
	look.sun = sun
	look.photo_sun = sun.duplicate()
	sun.layers = Quality.LADDER_LAYER
	look.photo_sun.layers = Quality.FULL_LAYER
	look.photo_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	look.photo_sun.directional_shadow_blend_splits = true
	sun.add_child(look.photo_sun)
	look.env = env
	look._set_fog(AIR_FOG)
	look.sky_mat = sky_mat
	look.disc = _disc(SUN_DISC, 0.0)
	look.moon_disc = _disc(MOON_DISC, 1.0)
	look.add_child(look.disc)
	look.add_child(look.moon_disc)
	for m in Mountains.build():
		look.add_child(m)
	look.bounce.install()
	look.interior.install()
	var detail := FastNoiseLite.new()
	detail.seed = 3
	detail.frequency = 0.02
	detail.fractal_octaves = 4
	RenderingServer.global_shader_parameter_set(&"detail", Meshes.noise_texture(detail, 256))
	look.lift_to(0.0)
	look.set_time(Daylight.DEFAULT)
	look._paint_sky()
	return look


static func _disc(size: Dictionary, moon: float) -> MeshInstance3D:
	var quad := QuadMesh.new()
	var half := DISC_DISTANCE * tan(deg_to_rad(size.span))
	quad.size = Vector2.ONE * 2.0 * half
	var disc_mi := MeshInstance3D.new()
	disc_mi.mesh = quad
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://src/disc.gdshader")
	mat.set_shader_parameter("moon", moon)
	mat.set_shader_parameter("radius", size.radius / size.span)
	disc_mi.material_override = mat
	disc_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The quad turns to the eye in its shader, so its bounds must hold it facing any way.
	disc_mi.custom_aabb = AABB(-Vector3.ONE * half * sqrt(2.0), Vector3.ONE * half * 2.0 * sqrt(2.0))
	return disc_mi


func set_time(t: float) -> void:
	t = fposmod(t, 1.0)
	if t == time:
		return
	time = t
	var l := Daylight.light(t)
	var toward := Daylight.toward_light(t)
	sun.basis = Basis.looking_at(-toward)
	for light in [sun, photo_sun]:
		light.light_color = l.sun
		light.light_energy = l.energy
	disc.material_override.set_shader_parameter("tint", l.sun if toward == Daylight.toward_sun(t) else Color.BLACK)
	moon_disc.material_override.set_shader_parameter("tint", l.moon)
	env.ambient_light_energy = l.ambient
	RenderingServer.global_shader_parameter_set(&"window_night", Daylight.lit(t) * Lamps.NIGHT_GLOW)
	env.adjustment_saturation = l.saturation
	_exposure = l.exposure * night_adapted(l)
	_grade()
	_tint_fog(l)
	RenderingServer.global_shader_parameter_set(&"sun_toward", toward)
	RenderingServer.global_shader_parameter_set(&"sun_light", linear(l.sun) * l.energy)
	RenderingServer.global_shader_parameter_set(&"sky_zenith", linear(l.zenith))
	RenderingServer.global_shader_parameter_set(&"sky_horizon", linear(l.horizon))
	RenderingServer.global_shader_parameter_set(&"sky_haze", linear(l.fog))
	RenderingServer.global_shader_parameter_set(&"sky_ambient", l.ambient)
	bounce.set_sun(toward, l.sun * l.energy)
	interior.to_light = toward


## A colour as shaders that light themselves read it, as a source_color uniform would take it.
static func linear(c: Color) -> Vector3:
	var l := c.srgb_to_linear()
	return Vector3(l.r, l.g, l.b)


static func night_adapted(l: Dictionary) -> float:
	var sky: Color = l.horizon
	return clampf(NIGHT_FLOOR / maxf(sky.get_luminance(), 1e-4), 1.0, NIGHT_MOST)


static func fog_at_height(lift: float) -> Dictionary:
	var up := maxf(lift - STANDING, 0.0)
	return {
		"fog_depth_begin": FOG_BEGIN + up * 2.2,
		"fog_depth_end": FOG_END + up * 2.5,
	}


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
	_tint_fog(Daylight.light(time))


func _tint_fog(l: Dictionary) -> void:
	env.fog_light_color = UNDER_FOG * under_light(l) if under else l.fog


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


func adapt(sky: float, delta: float) -> void:
	var to := lerpf(ADAPT_INDOOR, 1.0, sky)
	_adapt = lerpf(_adapt, to, 1.0 - exp(-delta / ADAPT_SECONDS))
	if absf(env.tonemap_exposure - _exposure * _adapt) > 0.002:
		_grade()


## Sets the view's exposure, and hands it and the saturation to what undoes them (icon.gdshader).
func _grade() -> void:
	env.tonemap_exposure = _exposure * _adapt
	RenderingServer.global_shader_parameter_set("view_grade", Vector2(env.tonemap_exposure, env.adjustment_saturation))


func _exit_tree() -> void:
	bounce.stop()
	interior.stop()


func _process(delta: float) -> void:
	var eye := get_viewport().get_camera_3d()
	if eye != null:
		var at := eye.global_position
		disc.global_position = at + Daylight.toward_sun(time) * DISC_DISTANCE
		moon_disc.global_position = at + Daylight.toward_moon(time) * DISC_DISTANCE
		lift_to(at.y - terrain.shown_at(at.x, at.z))
		adapt(bounce.sky_at(at), delta)
	bounce.update()
	interior.update()
	_since_sky += delta
	if _sky_time != time and _since_sky >= SKY_EVERY:
		_paint_sky()


func _paint_sky() -> void:
	_sky_time = time
	_since_sky = 0.0
	var l := Daylight.light(time)
	sky_mat.set_shader_parameter("sun_dir", Daylight.toward_sun(time))
	sky_mat.set_shader_parameter("moon_dir", Daylight.toward_moon(time))
	sky_mat.set_shader_parameter("zenith", l.zenith)
	sky_mat.set_shader_parameter("horizon", l.horizon)
	sky_mat.set_shader_parameter("sun_glow", l.glow)
	sky_mat.set_shader_parameter("cloud_light", l.clouds)
	sky_mat.set_shader_parameter("moon_glow", l.moon)
	sky_mat.set_shader_parameter("stars", l.stars)
	var overhead: Color = l.zenith.lerp(l.horizon, 0.3)
	RenderingServer.global_shader_parameter_set("sky_overhead", Vector3(overhead.r, overhead.g, overhead.b))
