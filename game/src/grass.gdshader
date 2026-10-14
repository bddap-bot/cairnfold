shader_type spatial;
render_mode world_vertex_coords, cull_disabled, diffuse_lambert_wrap, specular_disabled;

#include "res://src/ground.gdshaderinc"

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
uniform float hand_radius = 0.35;
uniform vec3 hand_left;
uniform vec3 hand_right;

varying float tip;
varying float dryness;
varying float tint;
varying float gust;
varying float far;

vec3 parted(vec3 v, vec3 root, vec3 hand) {
	vec2 away = v.xz - hand.xz;
	float above = hand.y - root.y;
	float reach = (1.0 - smoothstep(0.0, hand_radius, length(away))) * step(-0.05, above) * (1.0 - smoothstep(0.05, 0.45, above));
	vec2 dir = normalize(away + 1e-4);
	return vec3(dir.x, -0.8, dir.y) * reach * hand_radius;
}

void vertex() {
	tip = UV.y;
	dryness = INSTANCE_CUSTOM.x;
	tint = INSTANCE_CUSTOM.y;
	float ground = ground_at(INSTANCE_CUSTOM.zw);
	VERTEX.y += ground;
	vec3 root = MODEL_MATRIX[3].xyz + vec3(0.0, ground, 0.0);
	float size = length(MODEL_MATRIX[1].xyz);

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

	far = smoothstep(far_begin, far_end, distance(root, CAMERA_POSITION_WORLD));
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.35 + 0.5 * far));
}

void fragment() {
	// Far blades converge on their mid-tone so sub-pixel slivers do not flicker in a headset.
	float t = mix(tip, 0.6, far * 0.7);
	vec3 top = mix(tip_lush, tip_dry, dryness) * mix(cool_clump, warm_clump, tint);
	vec3 c = mix(root_color, top, t) * mix(root_shade, 1.0, smoothstep(0.0, 0.7, t));
	ALBEDO = c * COLOR.rgb * (1.0 + gust_brighten * gust * t * (1.0 - far));
	// Back faces arrive with the normal flipped, which would turn the up-bent normal downward and shade them dark.
	vec3 up = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	NORMAL -= 2.0 * min(dot(NORMAL, up), 0.0) * up;
	ROUGHNESS = 0.9;
	BACKLIGHT = top * backlight * t * (1.0 - 0.5 * far);
}
