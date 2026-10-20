#include "res://src/ground.gdshaderinc"
#include "res://src/water.gdshaderinc"
#include "res://src/palette.gdshaderinc"
#include "res://src/bounce.gdshaderinc"

uniform vec3 albedo : source_color = vec3(1.0);
uniform float roughness = 1.0;
#ifdef BACKLIT
uniform vec3 backlight : source_color = vec3(0.0);
// A crown blob gives to the wind this much of what a grass blade of its height above the ground would, all of it
// moving as one, so the crown sways rather than ripples.
const float CROWN_GIVE = 0.12;
// How far a blob's normals lean out from its trunk, so the faces between a crown's blobs light as its outside does
// and the crown shades as one mass.
const float CROWN_ROUND = 0.8;
// The tint a blob's underside takes, so the shade under a crown reads cool.
const vec3 CROWN_SHADE = vec3(0.8, 0.92, 1.15);
#endif

#ifdef FLOWER
// Flowers shrink to their roots over the last draw_fade before draw_reach, so the edge Flora culls at shows no pop.
uniform float draw_reach = 1000.0;
uniform float draw_fade = 4.0;
// A camera seeing this layer (Quality.FULL_LAYER) draws flowers at every distance.
uniform uint full_layer;
// Heads seen edge-on from afar are sub-pixel specks that 4x MSAA cannot hold still, so over this band they take
// the stalk's green.
uniform float head_fade_begin = 10.0;
uniform float head_fade_end = 30.0;
// Stalk length to the head in an unscaled flower (Meshes.FLOWER_HEIGHT).
uniform float stem;
// Placed flowers (Flora's painted and ghost pools) rooted under a pond grow as water plants; the meadow's own drown.
// Past lily_depth a lily: its head opens into a pad lily_pad times as wide, floating at the surface with its bloom
// raised in the middle, on a stem from the bed. Shallower, an iris standing emergent_height out of the water, its
// stalk widened at the foot into sword leaves.
instance uniform float planted = 0.0;
uniform float lily_depth = 0.35;
uniform float lily_pad = 2.6;
uniform float lily_drift = 0.04;
uniform float emergent_height = 0.3;
uniform float leaf_widen = 5.0;
uniform vec3 pad_green : source_color = vec3(0.16, 0.36, 0.1);
#endif

varying vec3 bounce_at;
varying vec3 lamp_at;
#ifdef FLOWER
varying float far_head;
varying float lily;
#endif

void vertex() {
	float ground = ground_at(INSTANCE_CUSTOM.zw);
	VERTEX.y += ground;
#ifdef BACKLIT
	vec2 out_of_crown = VERTEX.xz - INSTANCE_CUSTOM.zw;
	NORMAL = normalize(NORMAL + CROWN_ROUND * vec3(out_of_crown.x, 0.0, out_of_crown.y) / max(length(out_of_crown), 0.3));
	VERTEX += wind_push(INSTANCE_CUSTOM.zw, wind_gust(INSTANCE_CUSTOM.zw)) * CROWN_GIVE * max(MODEL_MATRIX[3].y, 0.0);
#endif
#ifdef PARTED
	vec3 root = MODEL_MATRIX[3].xyz + vec3(0.0, ground, 0.0);
	float depth = water_depth_at(root.xz);
	float wet = 0.0;
#ifdef FLOWER
	wet = planted * step(0.02, depth);
#endif
	VERTEX = mix(root, VERTEX, 1.0 - max(bare(root.xz), bank(depth) * (1.0 - wet)));
#endif
#ifdef FLOWER
	if (INSTANCE_CUSTOM.r >= season_bloom) {
		VERTEX = root;
	}
	float size = length(MODEL_MATRIX[1].xyz);
	float up = clamp((VERTEX.y - root.y) / (size * stem), 0.0, 1.0);
	lily = wet * step(lily_depth, depth);
	vec3 off = VERTEX - root;
	// Head vertices (UV.x 1) lie within a small disc about the stalk's top; the eye is UV.y 1.
	vec2 pad = off.xz * mix(1.0, lily_pad * mix(1.0, 1.8, step(length(off.xz), 0.045 * size)), UV.x);
	off.xz = mix(off.xz, mix(off.xz * mix(leaf_widen, 1.0, up), pad, lily), wet * mix(1.0 - UV.x, 1.0, lily));
	// The surface stands 2 cm over the root (FloraLayout.brush); a pad floats just on it.
	float head = mix(size * stem, mix(depth + emergent_height, depth + 0.03, lily), wet);
	off.y = mix(off.y, off.y - size * stem + head, up * wet) + lily * UV.x * UV.y * 0.03 * size;
	VERTEX = root + off;
	vec3 drift = vec3(wind_dir.x, 0.0, wind_dir.y) * sin(TIME * 0.9 + dot(root.xz, vec2(1.3, 0.7))) * lily_drift;
	VERTEX = mix(bent(VERTEX, wind_push(root.xz, wind_gust(root.xz)) * size * STALK_GIVE, up), VERTEX + drift * up, lily);
	float dist = distance(root, CAMERA_POSITION_WORLD);
	far_head = smoothstep(head_fade_begin, head_fade_end, dist);
	if ((CAMERA_VISIBLE_LAYERS & full_layer) == 0u) {
		VERTEX = mix(VERTEX, root, smoothstep(draw_reach - draw_fade, draw_reach, dist));
	}
#endif
	bounce_at = bounce_coord(VERTEX, NORMAL);
	lamp_at = lamp_coord(VERTEX, NORMAL);
#ifdef PARTED
	if (depth > 0.02 && wet == 0.0) {
#else
	if (drowned(INSTANCE_CUSTOM.zw)) {
#endif
		VERTEX = vec3(INSTANCE_CUSTOM.z, ground, INSTANCE_CUSTOM.w);
	}
#ifdef BACKLIT
	COLOR.rgb = seasoned(albedo * COLOR.rgb, season_foliage) * mix(vec3(1.0), CROWN_SHADE, smoothstep(0.2, -0.8, NORMAL.y));
#endif
}

#ifdef FLOWER
uniform vec3 stalk : source_color;
uniform vec3 eye : source_color;
#endif

void fragment() {
#ifdef FLOWER
	vec3 bloom = mix(albedo * COLOR.rgb, pad_green, lily * (1.0 - smoothstep(0.45, 0.6, UV.y)));
	vec3 head = mix(bloom, eye, smoothstep(0.55 + 0.3 * lily, 0.9 + 0.08 * lily, UV.y));
	ALBEDO = mix(stalk, mix(head, stalk, far_head), UV.x);
#elif defined(BACKLIT)
	ALBEDO = COLOR.rgb;
#else
	ALBEDO = albedo * COLOR.rgb;
#endif
	ROUGHNESS = roughness;
	vec4 bounce = texture(bounce_volume, bounce_at);
	AO = bounce.a;
	EMISSION = ALBEDO * given_back(bounce_at, lamp_at, bounce);
#ifdef BACKLIT
	BACKLIGHT = seasoned(backlight, season_foliage);
#endif
}
