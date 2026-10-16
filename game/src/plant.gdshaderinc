#include "res://src/ground.gdshaderinc"
#include "res://src/water.gdshaderinc"
#include "res://src/palette.gdshaderinc"
#include "res://src/bounce.gdshaderinc"

uniform vec3 albedo : source_color = vec3(1.0);
uniform float roughness = 1.0;
#ifdef BACKLIT
uniform vec3 backlight : source_color = vec3(0.0);
#endif

#ifdef FLOWER
// Flowers shrink to their roots over the last draw_fade before draw_reach, so the edge Flora culls at shows no pop.
uniform float draw_reach = 1000.0;
uniform float draw_fade = 4.0;
// Heads seen edge-on from afar are sub-pixel specks that 4x MSAA cannot hold still, so over this band they take
// the stalk's green.
uniform float head_fade_begin = 10.0;
uniform float head_fade_end = 30.0;
// Stalk length to the head in an unscaled flower (Meshes.FLOWER_HEIGHT).
uniform float stem;
#endif

varying vec3 bounce_at;
#ifdef FLOWER
varying float far_head;
#endif

void vertex() {
	float ground = ground_at(INSTANCE_CUSTOM.zw);
	VERTEX.y += ground;
#ifdef PARTED
	vec3 root = MODEL_MATRIX[3].xyz + vec3(0.0, ground, 0.0);
	VERTEX = mix(root, VERTEX, 1.0 - bare(root.xz));
#endif
#ifdef FLOWER
	if (INSTANCE_CUSTOM.r >= season_bloom) {
		VERTEX = root;
	}
	float size = length(MODEL_MATRIX[1].xyz);
	VERTEX = bent(VERTEX, wind_push(root.xz, wind_gust(root.xz)) * size * STALK_GIVE, clamp((VERTEX.y - root.y) / (size * stem), 0.0, 1.0));
	float dist = distance(root, CAMERA_POSITION_WORLD);
	far_head = smoothstep(head_fade_begin, head_fade_end, dist);
	VERTEX = mix(VERTEX, root, smoothstep(draw_reach - draw_fade, draw_reach, dist));
#endif
	bounce_at = bounce_coord(VERTEX, NORMAL);
	if (drowned(INSTANCE_CUSTOM.zw, ground)) {
		VERTEX = vec3(INSTANCE_CUSTOM.z, ground, INSTANCE_CUSTOM.w);
	}
#ifdef BACKLIT
	COLOR.rgb = seasoned(albedo * COLOR.rgb, season_foliage);
#endif
}

#ifdef FLOWER
uniform vec3 stalk : source_color;
uniform vec3 eye : source_color;
#endif

void fragment() {
#ifdef FLOWER
	vec3 head = mix(albedo * COLOR.rgb, eye, smoothstep(0.55, 0.9, UV.y));
	ALBEDO = mix(stalk, mix(head, stalk, far_head), UV.x);
#elif defined(BACKLIT)
	ALBEDO = COLOR.rgb;
#else
	ALBEDO = albedo * COLOR.rgb;
#endif
	ROUGHNESS = roughness;
	vec4 bounce = texture(bounce_volume, bounce_at);
	AO = bounce.a;
	EMISSION = ALBEDO * given_back(bounce_at, bounce);
#ifdef BACKLIT
	BACKLIGHT = seasoned(backlight, season_foliage);
#endif
}
