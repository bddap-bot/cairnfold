shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// A soft shaft of sunlight falling on where the player will land, motes drifting in it and a pool of light below.
#include "res://src/landing.gdshaderinc"
#include "res://src/billboard.gdshaderinc"

const float WIDE = 0.9;
const float TALL = 4.0;
const vec3 SUN = vec3(1.0, 0.93, 0.72);

varying float piece;
varying float fade;

void vertex() {
	vec3 c = MODEL_MATRIX[3].xyz;
	float k = length(MODEL_MATRIX[0].xyz);
	float i = float(INSTANCE_ID);
	fade = smoothstep(0.0, 0.5, clock);
	if (INSTANCE_ID == 0) {
		piece = 0.0;
		MODELVIEW_MATRIX = upright(VIEW_MATRIX, INV_VIEW_MATRIX[3].xyz, c + vec3(0.0, 0.5 * TALL * k, 0.0), WIDE * k, TALL * k);
	} else if (INSTANCE_ID == 1) {
		piece = 1.0;
		MODELVIEW_MATRIX = flat_on_ground(VIEW_MATRIX, c + vec3(0.0, 0.05 * k, 0.0), 1.4 * k);
	} else {
		piece = 2.0;
		float t = fract(clock * 0.12 + hash(i));
		float a = TAU * hash(i + 3.0) + clock * 0.3;
		float r = 0.3 * k * hash(i + 5.0);
		vec3 at = c + vec3(cos(a) * r, k * (0.2 + 2.6 * t), sin(a) * r);
		fade *= smoothstep(0.0, 0.15, t) * (1.0 - smoothstep(0.7, 1.0, t)) * (0.6 + 0.4 * sin(clock * 3.0 + i));
		MODELVIEW_MATRIX = billboard(VIEW_MATRIX, INV_VIEW_MATRIX, at, 0.05 * k);
	}
}

void fragment() {
	vec2 p = UV - 0.5;
	vec3 col;
	if (piece < 0.5) {
		float across = pow(max(1.0 - abs(p.x) * 2.0, 0.0), 1.6);
		float down = smoothstep(-0.5, 0.45, p.y) * (1.0 - smoothstep(0.42, 0.5, p.y));
		float rays = 0.85 + 0.15 * sin(p.x * 22.0 + clock * 0.7) * sin(p.x * 9.0 - clock * 0.4);
		col = SUN * across * down * rays * 0.42;
	} else if (piece < 1.5) {
		float d = length(p) * 2.0;
		col = SUN * pow(max(1.0 - d, 0.0), 1.5) * 0.45;
	} else {
		float d = length(p) * 2.0;
		col = SUN * pow(max(1.0 - d, 0.0), 2.0) * 1.6;
	}
	ALBEDO = col * fade;
}
