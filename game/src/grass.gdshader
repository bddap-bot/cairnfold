shader_type spatial;
render_mode world_vertex_coords, cull_disabled, diffuse_lambert_wrap, specular_disabled;

#include "res://src/ground.gdshaderinc"
#include "res://src/water.gdshaderinc"
#include "res://src/palette.gdshaderinc"
#include "res://src/bounce.gdshaderinc"
#include "res://src/wind.gdshaderinc"
#include "res://src/meadow.gdshaderinc"

uniform float backlight = 1.0;
uniform float gust_brighten = 0.22;
uniform float far_begin = 8.0;
uniform float far_end = 20.0;
#include "res://src/flora_lod.gdshaderinc"
// Survivors spread wider and stand taller across that band, holding the meadow's cover with a quarter of its clumps.
uniform vec2 survivor_scale = vec2(2.0, 1.25);
// A camera seeing this layer (Quality.FULL_LAYER) draws every clump whole at every distance.
uniform uint full_layer;
// The warmest-tinted clumps, this share of them, stand out as accents: taller, their tips a fresher green.
uniform float accent_share = 0.05;
uniform float accent_height = 1.6;
uniform vec3 accent_tip : source_color = vec3(0.62, 0.82, 0.22);
uniform float hand_radius = 0.35;
uniform vec3 hand_left;
uniform vec3 hand_right;
// Placed grass (Flora's painted and ghost pools) rooted under a pond grows as pondweed: tall ribbons reaching this share of
// the way to the surface, leaning in a slow current and darkening toward blue-green with depth. The meadow's own drowns.
instance uniform float planted = 0.0;
uniform float weed_reach = 0.7;
uniform float weed_stretch = 2.5;
uniform float weed_narrow = 0.5;
uniform float weed_keep = 0.25;
uniform float current_period = 6.0;
uniform float current_sway = 0.06;
uniform vec3 weed_root : source_color = vec3(0.09, 0.16, 0.06);
uniform vec3 weed_tip : source_color = vec3(0.36, 0.52, 0.14);
uniform vec3 weed_deep : source_color = vec3(0.10, 0.30, 0.24);

varying float tip;
varying vec3 top;
varying float gust;
varying float far;
// Bounce and lantern light at the blade's root, read once a vertex: grass is the most overdrawn thing drawn.
varying vec4 given;
varying float weed;

vec3 parted(vec3 v, vec3 root, vec3 hand) {
	vec2 away = v.xz - hand.xz;
	float above = hand.y - root.y;
	float reach = (1.0 - smoothstep(0.0, hand_radius, length(away))) * step(-0.05, above) * (1.0 - smoothstep(0.05, 0.45, above));
	vec2 dir = normalize(away + 1e-4);
	return vec3(dir.x, -0.8, dir.y) * reach * hand_radius;
}

void vertex() {
	tip = UV.y;
	float depth = water_depth_at(INSTANCE_CUSTOM.zw);
	weed = planted * step(0.02, depth);
	float accent = step(1.0 - accent_share, INSTANCE_CUSTOM.y);
	top = mix(blade_top(INSTANCE_CUSTOM.x, INSTANCE_CUSTOM.y), seasoned(accent_tip, season_meadow), accent);
	top = mix(top, mix(weed_tip, weed_deep, smoothstep(0.1, 1.2, depth)) * mix(0.8, 1.2, INSTANCE_CUSTOM.y), weed);
	float ground = ground_at(INSTANCE_CUSTOM.zw);
	VERTEX.y += ground;
	vec3 root = MODEL_MATRIX[3].xyz + vec3(0.0, ground, 0.0);
	float size = length(MODEL_MATRIX[1].xyz);
	vec3 at = bounce_on_ground(root.xz);
	vec4 bounce = textureLod(bounce_volume, at, 0.0);
	given = vec4(given_back(at, at, bounce), bounce.a);
	float worn = max(bare(root.xz), bank(depth) * (1.0 - weed));
	// An unscaled clump's blades stand about 0.2 m.
	float stretch = mix(1.0, clamp(depth * weed_reach / (0.2 * size), 1.0, weed_stretch), weed);
	float wide = (1.0 - worn * 0.5) * mix(1.0, weed_narrow, weed);
	VERTEX = root + (VERTEX - root) * vec3(wide, (1.0 - worn) * mix(1.0, accent_height, accent) * stretch, wide);
	float dist = distance(root, CAMERA_POSITION_WORLD);
	bool full = (CAMERA_VISIBLE_LAYERS & full_layer) != 0u;
	float lod = full ? 0.0 : smoothstep(lod_begin, lod_begin + lod_band, dist);
	VERTEX = mix(VERTEX + mat3(MODEL_MATRIX) * vec3(CUSTOM0.x, 0.0, CUSTOM0.y) * lod, root, lod * CUSTOM0.z);
	float rank = COLOR.a;
	vec2 grown = mix(vec2(1.0), survivor_scale, lod * step(rank, survivors));
	VERTEX = root + (VERTEX - root) * grown.xyx;

	gust = wind_gust(root.xz) * (1.0 - weed);
	// The current's swell runs up a ribbon, its tip a little behind its middle.
	float swell = TIME * TAU / current_period + dot(root.xz, vec2(0.9, 0.6)) - tip * 1.6;
	vec3 current = (vec3(wind_dir.x, 0.0, wind_dir.y) * (0.4 + 0.6 * sin(swell)) + vec3(-wind_dir.y, 0.0, wind_dir.x) * 0.5 * sin(swell * 0.61 + 1.3)) * current_sway * stretch;
	vec3 push = mix(wind_push(root.xz, gust), current, weed);
	VERTEX = bent(VERTEX, (push + parted(VERTEX, root, hand_left) + parted(VERTEX, root, hand_right)) * size, tip);

	far = smoothstep(far_begin, far_end, dist);
	if (!full) {
		VERTEX = mix(VERTEX, root, flora_fade(dist, grass_end(rank), sink));
	}
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.35 + 0.5 * far));
	if (depth > 0.02 && (weed == 0.0 || rank >= weed_keep)) {
		VERTEX = vec3(INSTANCE_CUSTOM.z, ground, INSTANCE_CUSTOM.w);
	}
}

void fragment() {
	// Far blades converge on their mid-tone so sub-pixel slivers do not flicker in a headset.
	float t = mix(tip, 0.6, far);
	ALBEDO = mix(blade_color(top, t), mix(weed_root, top, t), weed) * COLOR.rgb * (1.0 + gust_brighten * gust * t * (1.0 - far));
	// Back faces arrive with the normal flipped, which would turn the up-bent normal downward and shade them dark.
	vec3 up = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	NORMAL -= 2.0 * min(dot(NORMAL, up), 0.0) * up;
	ROUGHNESS = 0.9;
	BACKLIGHT = top * backlight * t * (1.0 - 0.5 * far) * (1.0 - weed);
	AO = given.a;
	EMISSION = ALBEDO * given.rgb;
}
