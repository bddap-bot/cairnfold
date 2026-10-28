shader_type spatial;
render_mode diffuse_lambert_wrap, shadows_disabled;
#include "res://src/ground.gdshaderinc"
#include "res://src/bounce.gdshaderinc"
#include "res://src/turn.gdshaderinc"

// INSTANCE_CUSTOM: x how many bounds it has made, so its feet keep pace with the ground or bark it covers, y how far it
// has grown in, z how far it bounds rather than keeps still, w how far it sits up on its haunches to nibble.
varying vec4 given;

void vertex() {
	int part = int(UV2.x + 0.5);
	float c = INSTANCE_CUSTOM.x * TAU;
	float gait = INSTANCE_CUSTOM.z;
	float sit = INSTANCE_CUSTOM.w;
	float still = 1.0 - gait;
	float t = TIME + INSTANCE_CUSTOM.x * 0.37;
	if (part == 2) {
		float flick = pow(max(sin(t * 0.9), 0.0), 12.0);
		turn(VERTEX, NORMAL, vec3(0.0, 0.05, 0.075), rot(vec3(0.0, 0.0, 1.0), still * (0.12 * sin(t * 1.3) + 0.25 * flick * sin(t * 30.0))));
		turn(VERTEX, NORMAL, vec3(0.0, 0.05, 0.075), rot(vec3(1.0, 0.0, 0.0), gait * (0.9 + 0.25 * sin(c))));
	} else if (part == 1) {
		turn(VERTEX, NORMAL, vec3(0.0, 0.075, -0.04), rot(vec3(0.0, 1.0, 0.0), still * 0.45 * sin(t * 0.6) * (1.0 - sit)));
		VERTEX.y += sit * 0.003 * sin(t * 15.0);
	} else if (part == 3) {
		VERTEX.z += gait * 0.03 * cos(c);
		VERTEX.y += gait * 0.008 * max(-sin(c), 0.0);
	} else if (part == 4) {
		VERTEX.z -= gait * 0.03 * cos(c);
		VERTEX.y += gait * 0.008 * max(sin(c), 0.0);
	}
	if (part != 3) {
		turn(VERTEX, NORMAL, vec3(0.0, 0.02, 0.05), rot(vec3(1.0, 0.0, 0.0), sit * 1.05));
	}
	turn(VERTEX, NORMAL, vec3(0.0, 0.03, 0.0), rot(vec3(1.0, 0.0, 0.0), gait * 0.18 * sin(c)));
	VERTEX.y += gait * 0.02 * max(sin(c + 0.5), 0.0);
	VERTEX *= INSTANCE_CUSTOM.y;
	given = given_at((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, normalize(mat3(MODEL_MATRIX) * NORMAL));
}

void fragment() {
	bool eye = COLOR.r < 0.1;
	ALBEDO = pow(COLOR.rgb, vec3(2.2));
	ROUGHNESS = eye ? 0.2 : 0.8;
	SPECULAR = eye ? 0.6 : 0.2;
	AO = given.a;
	EMISSION = ALBEDO * given.rgb;
}
