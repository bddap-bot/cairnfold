shader_type spatial;
render_mode diffuse_lambert_wrap, shadows_disabled;
#include "res://src/sculpture.gdshaderinc"
#include "res://src/given.gdshaderinc"
#include "res://src/turn.gdshaderinc"

// INSTANCE_CUSTOM: x bounds made, so its feet keep pace with the ground or bark, y grown in, z bounding rather than
// still, w sitting up on its haunches to nibble.

const int PART_HEAD = 1;
const int PART_TAIL = 2;
const int PART_HIND = 3;
const int PART_FORE = 4;
const float SHOULDER = 0.045;
uniform float swing;

void vertex() {
	int part = int(UV2.x + 0.5);
	float c = INSTANCE_CUSTOM.x * TAU;
	float gait = INSTANCE_CUSTOM.z;
	float sit = INSTANCE_CUSTOM.w;
	float still = 1.0 - gait;
	float t = TIME + INSTANCE_CUSTOM.x * 0.37;
	if (part == PART_TAIL) {
		float flick = pow(max(sin(t * 0.9), 0.0), 12.0);
		turn(VERTEX, NORMAL, vec3(0.0, 0.05, 0.075), rot(vec3(0.0, 0.0, 1.0), still * (0.12 * sin(t * 1.3) + 0.25 * flick * sin(t * 30.0))));
		turn(VERTEX, NORMAL, vec3(0.0, 0.05, 0.075), rot(vec3(1.0, 0.0, 0.0), gait * (0.9 + 0.25 * sin(c))));
	} else if (part == PART_HEAD) {
		turn(VERTEX, NORMAL, vec3(0.0, 0.075, -0.04), rot(vec3(0.0, 1.0, 0.0), still * 0.45 * sin(t * 0.6) * (1.0 - sit)));
		VERTEX.y += sit * 0.003 * sin(t * 15.0);
	} else if (part == PART_HIND) {
		VERTEX.z += gait * swing * cos(c);
		VERTEX.y += gait * 0.008 * max(sin(c), 0.0);
	} else if (part == PART_FORE) {
		float reach = gait * clamp(1.0 - VERTEX.y / SHOULDER, 0.0, 1.0);
		VERTEX.z -= reach * swing * cos(c);
		VERTEX.y += reach * 0.008 * max(-sin(c), 0.0);
	}
	if (part != PART_HIND) {
		turn(VERTEX, NORMAL, vec3(0.0, 0.02, 0.05), rot(vec3(1.0, 0.0, 0.0), sit * 1.05));
	}
	turn(VERTEX, NORMAL, vec3(0.0, 0.03, 0.0), rot(vec3(1.0, 0.0, 0.0), gait * 0.18 * sin(c)));
	VERTEX.y += gait * 0.02 * max(sin(c + 0.5), 0.0);
	VERTEX *= INSTANCE_CUSTOM.y;
	GIVE_HERE;
}

void fragment() {
	bool eye = COLOR.r < 0.1;
	ALBEDO = SCULPTED ? SCULPTURE : pow(COLOR.rgb, vec3(2.2));
	ROUGHNESS = eye ? 0.2 : 0.8;
	SPECULAR = eye ? 0.6 : 0.2;
	TAKE_GIVEN;
}
