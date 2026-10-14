shader_type spatial;
render_mode world_vertex_coords, cull_disabled, diffuse_lambert_wrap, specular_disabled;

#include "res://src/ground.gdshaderinc"
#include "res://src/water.gdshaderinc"
#include "res://src/palette.gdshaderinc"
#include "res://src/bounce.gdshaderinc"

uniform vec3 root_color : source_color = vec3(0.10, 0.24, 0.06);
uniform vec3 tip_lush : source_color = vec3(0.45, 0.68, 0.18);
uniform vec3 tip_dry : source_color = vec3(0.80, 0.78, 0.34);
uniform vec3 cool_clump : source_color = vec3(0.82, 0.96, 0.90);
uniform vec3 warm_clump : source_color = vec3(1.10, 1.02, 0.82);
uniform float root_shade = 0.55;
uniform float backlight = 1.0;
uniform vec2 wind_dir = vec2(0.8, 0.6);
uniform float wind_strength = 0.07;
uniform float gust_wavelength = 7.0;
uniform float gust_speed = 1.4;
uniform float gust_brighten = 0.22;
uniform float far_begin = 10.0;
uniform float far_end = 30.0;
// Blades shrink into the ground over the last stretch before `draw_reach`, past which Flora draws no meadow grass.
uniform float draw_reach;
uniform float draw_fade = 8.0;
// From lod_begin out, over lod_band, a clump draws fewer, wider blades (Meshes.grass_clump): far blades are slivers
// whose cost is their count, not their pixels.
uniform float lod_begin = 8.0;
uniform float lod_band = 4.0;
uniform float hand_radius = 0.35;
uniform vec3 hand_left;
uniform vec3 hand_right;

varying float tip;
varying vec3 top;
varying float gust;
varying float far;
varying vec3 bounce_at;

vec3 parted(vec3 v, vec3 root, vec3 hand) {
	vec2 away = v.xz - hand.xz;
	float above = hand.y - root.y;
	float reach = (1.0 - smoothstep(0.0, hand_radius, length(away))) * step(-0.05, above) * (1.0 - smoothstep(0.05, 0.45, above));
	vec2 dir = normalize(away + 1e-4);
	return vec3(dir.x, -0.8, dir.y) * reach * hand_radius;
}

void vertex() {
	tip = UV.y;
	top = seasoned(mix(tip_lush, tip_dry, INSTANCE_CUSTOM.x) * mix(cool_clump, warm_clump, INSTANCE_CUSTOM.y), season_meadow);
	float ground = ground_at(INSTANCE_CUSTOM.zw);
	VERTEX.y += ground;
	vec3 root = MODEL_MATRIX[3].xyz + vec3(0.0, ground, 0.0);
	float size = length(MODEL_MATRIX[1].xyz);
	bounce_at = bounce_on_ground(root.xz);
	float worn = bare(root.xz);
	VERTEX = root + (VERTEX - root) * vec3(1.0 - worn * 0.5, 1.0 - worn, 1.0 - worn * 0.5);
	float dist = distance(root, CAMERA_POSITION_WORLD);
	float lod = smoothstep(lod_begin, lod_begin + lod_band, dist);
	VERTEX = mix(VERTEX + mat3(MODEL_MATRIX) * vec3(CUSTOM0.x, 0.0, CUSTOM0.y) * lod, root, lod * CUSTOM0.z);

	// Gusts are bands travelling downwind; a slower cross-wind wave keeps them from reading as stripes.
	float along = sin(dot(root.xz, wind_dir) * (TAU / gust_wavelength) - TIME * gust_speed) * 0.5 + 0.5;
	float across = sin(dot(root.xz, vec2(-wind_dir.y, wind_dir.x)) * 0.13 + TIME * 0.21) * 0.5 + 0.5;
	gust = along * along * (0.35 + 0.65 * across);
	float flutter = 0.15 * sin(TIME * 3.1 + root.x * 1.7 + root.z * 2.3);
	vec3 bend = vec3(wind_dir.x, 0.0, wind_dir.y) * wind_strength * (0.3 + 1.3 * gust + flutter);
	bend += parted(VERTEX, root, hand_left) + parted(VERTEX, root, hand_right);
	bend *= size * tip * tip;
	VERTEX += bend;
	VERTEX.y -= length(bend.xz) * 0.6 * tip;

	far = smoothstep(far_begin, far_end, dist);
	VERTEX = mix(VERTEX, root, smoothstep(draw_reach - draw_fade, draw_reach, dist));
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.35 + 0.5 * far));
	if (drowned(INSTANCE_CUSTOM.zw, ground)) {
		VERTEX = vec3(INSTANCE_CUSTOM.z, ground, INSTANCE_CUSTOM.w);
	}
}

void fragment() {
	// Far blades converge on their mid-tone so sub-pixel slivers do not flicker in a headset.
	float t = mix(tip, 0.6, far * 0.7);
	vec3 c = mix(seasoned(root_color, season_meadow), top, t) * mix(root_shade, 1.0, smoothstep(0.0, 0.7, t));
	ALBEDO = c * COLOR.rgb * (1.0 + gust_brighten * gust * t * (1.0 - far));
	// Back faces arrive with the normal flipped, which would turn the up-bent normal downward and shade them dark.
	vec3 up = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	NORMAL -= 2.0 * min(dot(NORMAL, up), 0.0) * up;
	ROUGHNESS = 0.9;
	BACKLIGHT = top * backlight * t * (1.0 - 0.5 * far);
	vec4 bounce = texture(bounce_volume, bounce_at);
	AO = bounce.a;
	EMISSION = ALBEDO * bounce.rgb * bounce_light;
}
