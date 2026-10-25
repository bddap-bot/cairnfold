shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, diffuse_lambert_wrap, specular_disabled;

// A puff of chimney smoke (Smoke): COLOR.a is how far through its rise it starts, and it rises, drifts downwind, swells
// and fades over and over, lit as the hour and the lanterns near it light everything else.

#include "res://src/billboard.gdshaderinc"
#include "res://src/ground.gdshaderinc"
#include "res://src/bounce.gdshaderinc"
#include "res://src/wind.gdshaderinc"

uniform float rise;
uniform float drift;
const float SECONDS = 7.0;
varying float fade;
varying vec3 given;

void vertex() {
	float t = fract(TIME / SECONDS + COLOR.a);
	vec3 at = MODEL_MATRIX[3].xyz + vec3(0.0, t * rise, 0.0) + vec3(wind_dir.x, 0.0, wind_dir.y) * t * t * drift;
	MODELVIEW_MATRIX = billboard(VIEW_MATRIX, INV_VIEW_MATRIX, at, mix(0.3, 1.3, sqrt(t)));
	fade = smoothstep(0.0, 0.1, t) * (1.0 - smoothstep(0.35, 1.0, t));
	given = given_at(at, vec3(0.0, 1.0, 0.0)).rgb;
}

void fragment() {
	vec2 p = UV - 0.5;
	float d = length(p) * 2.0;
	float wisp = 0.8 + 0.2 * sin(atan(p.y, p.x) * 3.0 + d * 6.0);
	ALBEDO = vec3(0.86, 0.85, 0.83);
	ALPHA = fade * 0.6 * pow(max(1.0 - d * wisp, 0.0), 1.2);
	ROUGHNESS = 1.0;
	EMISSION = ALBEDO * given;
}
