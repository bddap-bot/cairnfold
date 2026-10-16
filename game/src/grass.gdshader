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
// Past `draw_reach` Flora draws no meadow grass.
uniform float draw_reach;
// Set from Flora's GRASS_ constants, which say what each does.
uniform float lod_begin;
uniform float lod_band;
uniform float survivors;
uniform float survivors_from;
// Each clump sinks into the ground over this distance, at a distance set by its rank.
uniform float sink = 1.5;
// Survivors spread wider and stand taller across that band, holding the meadow's cover with a quarter of its clumps.
uniform vec2 survivor_scale = vec2(2.0, 1.25);
// A camera seeing this layer (Quality.FULL_LAYER) draws every clump whole at every distance.
uniform uint full_layer;
uniform float hand_radius = 0.35;
uniform vec3 hand_left;
uniform vec3 hand_right;

varying float tip;
varying vec3 top;
varying float gust;
varying float far;
// Bounce and lantern light at the blade's root, read once a vertex: grass is the most overdrawn thing drawn.
varying vec4 given;

vec3 parted(vec3 v, vec3 root, vec3 hand) {
	vec2 away = v.xz - hand.xz;
	float above = hand.y - root.y;
	float reach = (1.0 - smoothstep(0.0, hand_radius, length(away))) * step(-0.05, above) * (1.0 - smoothstep(0.05, 0.45, above));
	vec2 dir = normalize(away + 1e-4);
	return vec3(dir.x, -0.8, dir.y) * reach * hand_radius;
}

void vertex() {
	tip = UV.y;
	top = blade_top(INSTANCE_CUSTOM.x, INSTANCE_CUSTOM.y);
	float ground = ground_at(INSTANCE_CUSTOM.zw);
	VERTEX.y += ground;
	vec3 root = MODEL_MATRIX[3].xyz + vec3(0.0, ground, 0.0);
	float size = length(MODEL_MATRIX[1].xyz);
	vec3 at = bounce_on_ground(root.xz);
	vec4 bounce = textureLod(bounce_volume, at, 0.0);
	given = vec4(given_back(at, at, bounce), bounce.a);
	float worn = max(bare(root.xz), bank(water_depth_at(root.xz)));
	VERTEX = root + (VERTEX - root) * vec3(1.0 - worn * 0.5, 1.0 - worn, 1.0 - worn * 0.5);
	float dist = distance(root, CAMERA_POSITION_WORLD);
	bool full = (CAMERA_VISIBLE_LAYERS & full_layer) != 0u;
	float lod = full ? 0.0 : smoothstep(lod_begin, lod_begin + lod_band, dist);
	VERTEX = mix(VERTEX + mat3(MODEL_MATRIX) * vec3(CUSTOM0.x, 0.0, CUSTOM0.y) * lod, root, lod * CUSTOM0.z);
	float rank = COLOR.a;
	vec2 grown = mix(vec2(1.0), survivor_scale, lod * step(rank, survivors));
	VERTEX = root + (VERTEX - root) * grown.xyx;

	gust = wind_gust(root.xz);
	VERTEX = bent(VERTEX, (wind_push(root.xz, gust) + parted(VERTEX, root, hand_left) + parted(VERTEX, root, hand_right)) * size, tip);

	far = smoothstep(far_begin, far_end, dist);
	if (!full) {
		float gone = rank < survivors
			? mix(draw_reach, draw_reach * survivors_from, rank / survivors)
			: mix(lod_begin + lod_band, lod_begin + sink, (rank - survivors) / (1.0 - survivors));
		VERTEX = mix(VERTEX, root, smoothstep(gone - sink, gone, dist));
	}
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.35 + 0.5 * far));
	if (drowned(INSTANCE_CUSTOM.zw)) {
		VERTEX = vec3(INSTANCE_CUSTOM.z, ground, INSTANCE_CUSTOM.w);
	}
}

void fragment() {
	// Far blades converge on their mid-tone so sub-pixel slivers do not flicker in a headset.
	float t = mix(tip, 0.6, far);
	ALBEDO = blade_color(top, t) * COLOR.rgb * (1.0 + gust_brighten * gust * t * (1.0 - far));
	// Back faces arrive with the normal flipped, which would turn the up-bent normal downward and shade them dark.
	vec3 up = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	NORMAL -= 2.0 * min(dot(NORMAL, up), 0.0) * up;
	ROUGHNESS = 0.9;
	BACKLIGHT = top * backlight * t * (1.0 - 0.5 * far);
	AO = given.a;
	EMISSION = ALBEDO * given.rgb;
}
