shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;
#include "res://src/ground.gdshaderinc"
#include "res://src/bounce.gdshaderinc"
varying vec4 given;
void vertex() {
	float phase = INSTANCE_CUSTOM.x;
	if (UV2.x > 0.5 && UV2.x < 1.5) {
		VERTEX.x *= 1.0 + 0.07 * sin(phase * 3.0 + VERTEX.z * 150.0);
	} else if (UV2.x > 1.5) {
		VERTEX.x += 0.003 * sin(phase * 1.4) * smoothstep(0.025, 0.065, VERTEX.y);
	}
	VERTEX *= INSTANCE_CUSTOM.y;
	given = given_at((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, normalize(mat3(MODEL_MATRIX) * NORMAL));
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.65;
	AO = given.a;
	EMISSION = ALBEDO * given.rgb;
}
