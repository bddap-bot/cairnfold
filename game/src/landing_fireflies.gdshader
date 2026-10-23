shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Fireflies that spill out from the centre and circle where the player will land.
#include "res://src/landing.gdshaderinc"
#include "res://src/billboard.gdshaderinc"

const float RADIUS = 0.42;
const vec3 GLOW = vec3(1.0, 0.82, 0.38);

varying float glow;

void vertex() {
	vec3 c = MODEL_MATRIX[3].xyz;
	float k = length(MODEL_MATRIX[0].xyz);
	float i = float(INSTANCE_ID);
	float out_ = smoothstep(0.0, 0.5, clock - 0.02 * i);
	float s = hash(i);
	float a = TAU * i / float(count) + clock * (0.45 + 0.2 * s) * (mod(i, 2.0) * 2.0 - 1.0);
	float r = RADIUS * k * (0.8 + 0.4 * hash(i + 5.0)) * out_;
	float h = k * (0.08 + 0.3 * hash(i + 9.0) + 0.06 * sin(clock * 2.3 + i * 1.7));
	float beat = fract(clock / (1.1 + 0.9 * s) + s);
	float flash = smoothstep(0.0, 0.12, beat) * (1.0 - smoothstep(0.12, 0.6, beat));
	glow = (0.55 + flash) * out_;
	MODELVIEW_MATRIX = billboard(VIEW_MATRIX, INV_VIEW_MATRIX, c + vec3(cos(a) * r, h, sin(a) * r), k * (0.2 + 0.06 * flash));
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float core = smoothstep(0.22, 0.08, d);
	float f = max(1.0 - d, 0.0);
	ALBEDO = (GLOW * f * f * f * f * 0.8 + vec3(1.0, 0.97, 0.8) * core * 1.6) * glow;
}
