shader_type spatial;
render_mode diffuse_lambert_wrap, shadows_disabled;
#include "res://src/ground.gdshaderinc"
#include "res://src/bounce.gdshaderinc"
#include "res://src/turn.gdshaderinc"

// INSTANCE_CUSTOM: x its clock, y how far it has grown in, z how far it flies, its wings out and beating, or below 0 how
// far through a hoot it is, perched; w how far its head turns from the way it faces, left positive.
varying vec4 given;

void vertex() {
	int part = int(UV2.x + 0.5);
	float t = INSTANCE_CUSTOM.x;
	float fly = max(INSTANCE_CUSTOM.z, 0.0);
	float hoot = max(-INSTANCE_CUSTOM.z, 0.0);
	if (part == 5) {
		float blink = smoothstep(0.93, 0.96, fract(t * 0.19)) * (1.0 - smoothstep(0.985, 1.0, fract(t * 0.19)));
		VERTEX.y = 0.257 + (VERTEX.y - 0.257) * (1.0 - 0.9 * blink);
	}
	if (part == 1 || part == 5) {
		vec3 neck = vec3(0.0, 0.2, 0.0);
		turn(VERTEX, NORMAL, neck, rot(vec3(1.0, 0.0, 0.0), 0.9 * fly + 0.18 * hoot));
		turn(VERTEX, NORMAL, neck, rot(vec3(0.0, 1.0, 0.0), INSTANCE_CUSTOM.w + 0.06 * sin(t * 0.8)));
		VERTEX.y -= 0.01 * hoot;
	} else if (part == 2 || part == 3) {
		float side = part == 2 ? -1.0 : 1.0;
		vec3 shoulder = vec3(side * 0.06, 0.2, 0.0);
		VERTEX.y = shoulder.y + (VERTEX.y - shoulder.y) * (1.0 + 0.9 * fly);
		VERTEX.z = mix(VERTEX.z, VERTEX.z * 0.6, fly);
		float beat = fly * (1.45 + 0.55 * sin(t * 6.5));
		turn(VERTEX, NORMAL, shoulder, rot(vec3(0.0, 0.0, 1.0), side * -beat));
	} else if (part == 4) {
		VERTEX.z += fly * 0.04;
		VERTEX.y += fly * 0.02;
	} else if (part == 0) {
		VERTEX.xz *= 1.0 + 0.012 * sin(t * 1.7) + 0.05 * hoot * smoothstep(0.12, 0.17, VERTEX.y) * step(VERTEX.z, 0.0);
	}
	VERTEX *= INSTANCE_CUSTOM.y;
	given = given_at((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, normalize(mat3(MODEL_MATRIX) * NORMAL));
}

void fragment() {
	bool eye = COLOR.r < 0.1;
	ALBEDO = pow(COLOR.rgb, vec3(2.2));
	ROUGHNESS = eye ? 0.15 : 0.85;
	SPECULAR = eye ? 0.7 : 0.15;
	AO = given.a;
	EMISSION = ALBEDO * given.rgb;
}
