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
// Meshes.BLOB_LUMP: how far a blob's surface strays from its sphere, in blob radii.
uniform float crown_lump;
// The tint a blob's underside takes, so the shade under a crown reads cool.
const vec3 CROWN_SHADE = vec3(0.8, 0.92, 1.15);
#endif

#ifdef FLOWER
// Flowers shrink to their roots over the last draw_fade before draw_reach, so the edge Flora culls at shows no pop.
#include "res://src/flora_lod.gdshaderinc"
// A camera seeing this layer (Quality.FULL_LAYER) draws flowers at every distance.
uniform uint full_layer;
// Aquatic heads retain their existing edge-on fade; land petals hand their colour to the far patch.
uniform float head_fade_begin = 10.0;
uniform float head_fade_end = 30.0;
// Stalk length to the head in an unscaled flower (Meshes.FLOWER_HEIGHT).
uniform float stem;
// Placed flowers (Flora's painted and ghost pools) rooted under a pond grow as water plants; the meadow's own drown.
// Past lily_depth a lily: its head opens into a pad lily_pad times as wide, floating at the surface with its bloom
// raised in the middle, on a stem from the bed. Shallower, an iris: its sword leaves (Meshes.flower) open from the bed,
// full width from just under the surface up to leaf_rise over it, and its bloom cups upward emergent_height over the
// water, iris_bloom times as wide, both in flower sizes.
instance uniform float planted = 0.0;
uniform float water_reach = 60.0;
uniform float lily_depth = 0.35;
uniform float lily_pad = 2.6;
uniform float lily_drift = 0.04;
uniform float emergent_height = 0.5;
uniform float leaf_rise = 0.4;
uniform float iris_bloom = 1.5;
uniform float bloom_cup = 0.9;
// Meshes.LEAF_SHOULDER: the leaves' lower shoulders, stood just under the surface; their tips' heights are in stems.
uniform float leaf_shoulder;
uniform vec3 pad_green : source_color = vec3(0.16, 0.36, 0.1);

// The water plant a flower rooted `depth` under a pond grows as: 0 none, 1 an iris, 2 a lily.
float water_form(float placed, float depth) {
	return planted_water(placed, depth) + placed * step(lily_depth, depth);
}
#endif

#ifdef BARK
varying float moss_coat;
varying vec2 bark_uv;
#endif
varying vec4 given;
#ifdef FLOWER
varying float far_head;
varying float lily;
#endif

void vertex() {
#ifdef BARK
	moss_coat = INSTANCE_CUSTOM.r;
	bark_uv = UV;
#endif
	float ground = ground_at(INSTANCE_CUSTOM.zw);
	VERTEX.y += ground;
#ifdef BACKLIT
	vec2 out_of_crown = VERTEX.xz - INSTANCE_CUSTOM.zw;
	NORMAL = normalize(NORMAL + CROWN_ROUND * vec3(out_of_crown.x, 0.0, out_of_crown.y) / max(length(out_of_crown), 0.3));
	VERTEX += wind_push(INSTANCE_CUSTOM.zw, wind_gust(INSTANCE_CUSTOM.zw)) * CROWN_GIVE * max(MODEL_MATRIX[3].y, 0.0);
	if (IN_SHADOW_PASS) {
		// A crown's coarse shadow blob (Flora.crown_shade) casts from a lump's depth behind its sunlit surface: its
		// lumps, which the drawn blobs do not share, lay no stripes across the crown's lit side, and moved along the
		// sun's rays, its shade on the ground keeps its shape.
		VERTEX -= INV_VIEW_MATRIX[2].xyz * crown_lump * length(MODEL_MATRIX[0].xyz);
	}
#endif
#ifdef PARTED
	vec3 root = MODEL_MATRIX[3].xyz + vec3(0.0, ground, 0.0);
	float depth = water_depth_at(root.xz);
	float wet = 0.0;
#ifdef FLOWER
	float form = water_form(planted, depth);
	wet = step(0.5, form);
#endif
	VERTEX = mix(root, VERTEX, 1.0 - max(bare(root.xz), bank(depth) * (1.0 - wet)));
#endif
#ifdef FLOWER
	if (INSTANCE_CUSTOM.r >= season_bloom) {
		VERTEX = root;
	}
	float size = length(MODEL_MATRIX[1].xyz);
	float up = clamp((VERTEX.y - root.y) / (size * stem), 0.0, 1.0);
	lily = step(1.5, form);
	float iris = wet - lily;
	float leaf = step(UV.y, -0.5);
	vec3 off = VERTEX - root;
	float rise = off.y / size;
	// Head vertices (UV.x 1) lie within a small disc about the stalk's top; the eye is UV.y 1.
	vec2 pad = off.xz * mix(1.0, lily_pad * mix(1.0, 1.8, step(length(off.xz), 0.045 * size)), UV.x);
	off.xz = mix(off.xz * mix(1.0, iris_bloom, iris * UV.x), pad, lily);
	// The surface stands 2 cm over the root (FloraLayout.brush); a pad floats just on it.
	float head = mix(size * stem, mix(depth + emergent_height * size, depth + 0.03, lily), wet);
	off.y = mix(off.y, off.y - size * stem + head, up * wet) + lily * UV.x * UV.y * 0.03 * size + iris * UV.x * length(off.xz) * bloom_cup;
	float leaf_y = rise < leaf_shoulder ? rise / leaf_shoulder * depth : depth + (rise - leaf_shoulder) / (stem - leaf_shoulder) * leaf_rise * size;
	off = mix(off, vec3(off.x, leaf_y, off.z) * iris, leaf);
	up = mix(up, clamp(off.y / head, 0.0, 1.0), leaf);
	VERTEX = root + off;
	vec3 drift = vec3(wind_dir.x, 0.0, wind_dir.y) * sin(TIME * 0.9 + dot(root.xz, vec2(1.3, 0.7))) * lily_drift;
	VERTEX = mix(bent(VERTEX, wind_push(root.xz, wind_gust(root.xz)) * size * STALK_GIVE, up), VERTEX + drift * up, lily);
	float dist = distance(root, CAMERA_POSITION_WORLD);
	far_head = wet * smoothstep(head_fade_begin, head_fade_end, dist);
	if ((CAMERA_VISIBLE_LAYERS & full_layer) == 0u) {
		VERTEX = mix(VERTEX, root, flora_fade(dist, mix(draw_reach, water_reach, wet), draw_fade));
	}
#endif
	given = given_over(VERTEX, NORMAL, ground);
#ifdef PARTED
	// The meadow's flowers drown; a tree or bush never stands in water (World._drown).
	if (depth > 0.02 && wet == 0.0) {
		VERTEX = vec3(INSTANCE_CUSTOM.z, ground, INSTANCE_CUSTOM.w);
	}
#endif
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
#ifdef BARK
	if (moss_coat > 0.0) {
		float patches = sin(bark_uv.x * 37.0 + sin(bark_uv.y * 28.0)) * sin(bark_uv.y * 49.0 + bark_uv.x * 16.0);
		float coat = moss_coat * smoothstep(-0.5, 0.3, patches + 0.7 - bark_uv.y * 0.6);
		ALBEDO = mix(ALBEDO, vec3(0.23, 0.37, 0.065) * (0.85 + 0.3 * patches), coat);
	}
#endif
	ROUGHNESS = roughness;
	AO = given.a;
	EMISSION = ALBEDO * given.rgb;
#ifdef BACKLIT
	BACKLIGHT = seasoned(backlight, season_foliage);
#endif
}
