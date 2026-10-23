shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Two glowing bare footprints, left then right, stepping in where the player will stand, facing where they face.
#include "res://src/landing.gdshaderinc"

const vec3 GLOW = vec3(1.0, 0.8, 0.42);
const float LONG = 0.6;

varying float side;
varying float glow;

void vertex() {
	vec3 c = MODEL_MATRIX[3].xyz;
	mat3 b = mat3(MODEL_MATRIX);
	float k = length(b[0]);
	side = INSTANCE_ID == 0 ? -1.0 : 1.0;
	float step_in = smoothstep(0.0, 0.2, clock - 0.25 * float(INSTANCE_ID));
	glow = step_in * (0.8 + 0.2 * sin(clock * 3.0));
	vec3 at = c + b * vec3(0.2 * side, 0.12, -0.06 * side);
	vec3 x = b[0] * 0.9;
	vec3 y = -b[2];
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(x * 0.5, 0.0), vec4(y * LONG, 0.0), vec4(normalize(b[1]), 0.0), vec4(at, 1.0));
}

void fragment() {
	vec2 q = vec2((UV.x - 0.5) * side, 0.5 - UV.y);
	float sole = length((q - vec2(0.0, 0.05)) * vec2(2.6, 1.25)) - 0.26;
	float heel = length((q - vec2(0.02, -0.28)) * vec2(3.0, 2.4)) - 0.25;
	float ball = min(sole, heel);
	float toes = 1.0;
	for (int t = 0; t < 5; t++) {
		float ft = float(t);
		vec2 at = vec2(-0.2 + 0.1 * ft, 0.36 - 0.02 * abs(ft - 1.0) * abs(ft - 1.0));
		toes = min(toes, length(q - at) - (0.06 - 0.008 * ft));
	}
	float d = min(ball, toes * 3.0);
	float a = smoothstep(0.03, -0.01, d);
	float halo = 0.35 * smoothstep(0.25, 0.0, d);
	ALBEDO = GLOW * (a + halo) * glow;
}
