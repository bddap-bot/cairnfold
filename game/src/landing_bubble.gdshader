shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// A soap bubble where the player's head will be, wobbling, its film running with colour, little bubbles rising to it
// from the ground.
#include "res://src/landing.gdshaderinc"
#include "res://src/billboard.gdshaderinc"

const float EYE = 1.65;
const float RADIUS = 0.26;

varying float big;
varying float fade;
varying float seed;

void vertex() {
	vec3 c = MODEL_MATRIX[3].xyz;
	float k = length(MODEL_MATRIX[0].xyz);
	float i = float(INSTANCE_ID);
	seed = hash(i);
	big = INSTANCE_ID == 0 ? 1.0 : 0.0;
	float grow = spring(clock / 0.4);
	if (INSTANCE_ID == 0) {
		fade = 1.0;
		vec3 at = c + vec3(0.0, EYE * k + 0.03 * k * sin(clock * 1.7), 0.0);
		float w = 2.0 * RADIUS * k * grow;
		mat4 m = billboard(VIEW_MATRIX, INV_VIEW_MATRIX, at, w);
		m[0] *= 1.0 + 0.04 * sin(clock * 3.1);
		m[1] *= 1.0 - 0.04 * sin(clock * 3.1);
		MODELVIEW_MATRIX = m;
	} else {
		float t = fract(clock * 0.35 + seed);
		float a = TAU * hash(i + 2.0);
		vec3 at = c + vec3(cos(a) * 0.15 * k * (1.0 - t), k * EYE * t, sin(a) * 0.15 * k * (1.0 - t));
		at.x += 0.03 * k * sin(clock * 4.0 + i);
		fade = smoothstep(0.0, 0.1, t) * (1.0 - smoothstep(0.85, 1.0, t)) * smoothstep(0.0, 0.3, clock);
		MODELVIEW_MATRIX = billboard(VIEW_MATRIX, INV_VIEW_MATRIX, at, k * (0.05 + 0.04 * seed));
	}
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float d = length(p);
	if (d > 1.0) {
		discard;
	}
	float film = d * d * 1.4 + 0.25 * sin(p.x * 3.0 + clock * 0.9 + seed * 6.0) + 0.2 * p.y + clock * 0.05;
	vec3 sheen = 0.55 + 0.45 * cos(TAU * (film + vec3(0.0, 0.33, 0.67)));
	float rim = smoothstep(0.55, 1.0, d) * (1.0 - smoothstep(0.96, 1.0, d) * 0.5);
	float spot = smoothstep(0.22, 0.05, length(p - vec2(-0.38, -0.4)));
	float spot2 = smoothstep(0.1, 0.02, length(p - vec2(0.42, 0.45))) * 0.6;
	ALBEDO = mix(sheen, vec3(1.0), max(spot, spot2));
	ALPHA = clamp(0.08 + rim * 0.85 + spot + spot2, 0.0, 1.0) * fade;
}
