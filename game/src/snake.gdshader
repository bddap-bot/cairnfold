shader_type spatial;
render_mode diffuse_lambert_wrap, shadows_disabled;
#include "res://src/ground.gdshaderinc"
#include "res://src/bounce.gdshaderinc"

// INSTANCE_CUSTOM: x how far it has slid, y how far it has grown in, z how hard it turns, left positive, w how far its
// tongue is out. The body lies along +Z behind the head; its waves are fixed to the ground it slides over, so each
// stretch of it follows the way the head went.
const float WAVE = 15.0;
const float SWAY = 0.03;

varying vec4 given;

void vertex() {
	int part = int(UV2.x + 0.5);
	float s = max(VERTEX.z, 0.0);
	float travel = INSTANCE_CUSTOM.x;
	float sway = SWAY * (0.35 + 0.65 * smoothstep(0.0, 0.2, s)) * (1.0 - 0.3 * smoothstep(0.5, 0.78, s));
	float head = sway * sin(WAVE * travel);
	VERTEX.x += sway * sin(WAVE * (travel - s)) - head * (1.0 - smoothstep(0.0, 0.12, s)) * 0.5;
	VERTEX.x -= INSTANCE_CUSTOM.z * 0.35 * s * s;
	VERTEX.y += 0.004 * (1.0 + sin(WAVE * (travel - s) * 2.0)) * smoothstep(0.05, 0.3, s);
	if (part == 1) {
		VERTEX.z += 0.016 * (1.0 - INSTANCE_CUSTOM.w);
		VERTEX.x += 0.0015 * sin(TIME * 40.0) * INSTANCE_CUSTOM.w;
	}
	VERTEX *= INSTANCE_CUSTOM.y;
	given = given_at((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, normalize(mat3(MODEL_MATRIX) * NORMAL));
}

void fragment() {
	bool eye = COLOR.r < 0.1;
	ALBEDO = pow(COLOR.rgb, vec3(2.2));
	ROUGHNESS = eye ? 0.2 : 0.45;
	SPECULAR = eye ? 0.6 : 0.35;
	AO = given.a;
	EMISSION = ALBEDO * given.rgb;
}
