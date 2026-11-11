shader_type spatial;
render_mode diffuse_lambert_wrap, shadows_disabled;
#include "res://src/given.gdshaderinc"
#include "res://src/turn.gdshaderinc"

// INSTANCE_CUSTOM: x its clock, y how far it has grown in, z how far it flies, its wings out and beating, or below 0 how
// far through a hoot it is, perched; w how far its head turns from the way it faces, left positive.

const int PART_BODY = 0;
const int PART_HEAD = 1;
const int PART_WING_L = 2;
const int PART_WING_R = 3;
const int PART_FEET = 4;
const int PART_EYES = 5;

void vertex() {
	int part = int(UV2.x + 0.5);
	float t = INSTANCE_CUSTOM.x;
	float fly = max(INSTANCE_CUSTOM.z, 0.0);
	float hoot = max(-INSTANCE_CUSTOM.z, 0.0);
	if (part == PART_EYES) {
		float blink = smoothstep(0.93, 0.96, fract(t * 0.19)) * (1.0 - smoothstep(0.985, 1.0, fract(t * 0.19)));
		VERTEX.y = 0.257 + (VERTEX.y - 0.257) * (1.0 - 0.9 * blink);
	}
	if (part == PART_HEAD || part == PART_EYES) {
		vec3 neck = vec3(0.0, 0.2, 0.0);
		turn(VERTEX, NORMAL, neck, rot(vec3(1.0, 0.0, 0.0), 0.9 * fly + 0.18 * hoot));
		turn(VERTEX, NORMAL, neck, rot(vec3(0.0, 1.0, 0.0), INSTANCE_CUSTOM.w + 0.06 * sin(t * 0.8)));
		VERTEX.y -= 0.01 * hoot;
	} else if (part == PART_WING_L || part == PART_WING_R) {
		float side = part == PART_WING_L ? -1.0 : 1.0;
		vec3 shoulder = vec3(side * 0.06, 0.2, 0.0);
		VERTEX.y = shoulder.y + (VERTEX.y - shoulder.y) * (1.0 + 0.9 * fly);
		VERTEX.z = mix(VERTEX.z, VERTEX.z * 0.6, fly);
		float beat = fly * (1.45 + 0.55 * sin(t * 6.5));
		turn(VERTEX, NORMAL, shoulder, rot(vec3(0.0, 0.0, 1.0), side * -beat));
	} else if (part == PART_FEET) {
		VERTEX.z += fly * 0.04;
		VERTEX.y += fly * 0.02;
	} else if (part == PART_BODY) {
		VERTEX.xz *= 1.0 + 0.012 * sin(t * 1.7) + 0.05 * hoot * smoothstep(0.12, 0.17, VERTEX.y) * step(VERTEX.z, 0.0);
	}
	VERTEX *= INSTANCE_CUSTOM.y;
	GIVE_HERE;
}

void fragment() {
	bool eye = COLOR.r < 0.1;
	ALBEDO = pow(COLOR.rgb, vec3(2.2));
	ROUGHNESS = eye ? 0.15 : 0.85;
	SPECULAR = eye ? 0.7 : 0.15;
	TAKE_GIVEN;
}
