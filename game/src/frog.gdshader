shader_type spatial;
render_mode diffuse_lambert_wrap, shadows_disabled;
#include "res://src/given.gdshaderinc"

// INSTANCE_CUSTOM: x its clock, y how far it has grown in, z how far its hind legs reach out behind (a hop, a kick),
// w how far its throat swells (a croak).

const int PART_BODY = 0;
const int PART_HEAD = 1;
const int PART_THROAT = 2;
const int PART_HIND_L = 3;
const int PART_HIND_R = 4;

void vertex() {
	int part = int(UV2.x + 0.5);
	float t = INSTANCE_CUSTOM.x;
	float legs = INSTANCE_CUSTOM.z;
	if (part == PART_HIND_L || part == PART_HIND_R) {
		float reach = smoothstep(-0.01, 0.04, VERTEX.z) * 0.6 + 0.4;
		VERTEX.z += legs * 0.055 * reach;
		VERTEX.y -= legs * 0.012 * reach;
		VERTEX.x *= 1.0 - legs * 0.25;
	} else if (part == PART_THROAT) {
		VERTEX += (VERTEX - vec3(0.0, 0.034, -0.044)) * INSTANCE_CUSTOM.w * 1.1;
	} else if (part == PART_BODY) {
		VERTEX.xy *= 1.0 + 0.025 * sin(t * 2.2);
	}
	if (part == PART_HEAD || part == PART_THROAT) {
		VERTEX.y += legs * 0.006;
	}
	VERTEX *= INSTANCE_CUSTOM.y;
	GIVE_HERE;
}

void fragment() {
	bool eye = COLOR.r < 0.1;
	ALBEDO = pow(COLOR.rgb, vec3(2.2));
	ROUGHNESS = eye ? 0.2 : 0.55;
	SPECULAR = eye ? 0.6 : 0.25;
	TAKE_GIVEN;
}
