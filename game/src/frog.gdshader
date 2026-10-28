shader_type spatial;
render_mode diffuse_lambert_wrap, shadows_disabled;
#include "res://src/ground.gdshaderinc"
#include "res://src/bounce.gdshaderinc"

// INSTANCE_CUSTOM: x its clock, y how far it has grown in, z how far its hind legs reach out behind (a hop, a kick),
// w how far its throat swells (a croak).
varying vec4 given;

void vertex() {
	int part = int(UV2.x + 0.5);
	float t = INSTANCE_CUSTOM.x;
	float legs = INSTANCE_CUSTOM.z;
	if (part == 3 || part == 4) {
		float reach = smoothstep(-0.01, 0.04, VERTEX.z) * 0.6 + 0.4;
		VERTEX.z += legs * 0.055 * reach;
		VERTEX.y -= legs * 0.012 * reach;
		VERTEX.x *= 1.0 - legs * 0.25;
	} else if (part == 2) {
		VERTEX += (VERTEX - vec3(0.0, 0.034, -0.044)) * INSTANCE_CUSTOM.w * 1.1;
	} else if (part == 0) {
		VERTEX.xy *= 1.0 + 0.025 * sin(t * 2.2);
	}
	if (part == 1 || part == 2) {
		VERTEX.y += legs * 0.006;
	}
	VERTEX *= INSTANCE_CUSTOM.y;
	given = given_at((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, normalize(mat3(MODEL_MATRIX) * NORMAL));
}

void fragment() {
	bool eye = COLOR.r < 0.1;
	ALBEDO = pow(COLOR.rgb, vec3(2.2));
	ROUGHNESS = eye ? 0.2 : 0.55;
	SPECULAR = eye ? 0.6 : 0.25;
	AO = given.a;
	EMISSION = ALBEDO * given.rgb;
}
