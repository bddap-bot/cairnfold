shader_type spatial;
render_mode diffuse_lambert_wrap, shadows_disabled;

#include "res://src/ground.gdshaderinc"
#include "res://src/bounce.gdshaderinc"

varying vec4 given;

void vertex() {
	given = given_at((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, normalize(mat3(MODEL_MATRIX) * NORMAL));
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = COLOR.r < 0.1 ? 0.3 : 0.9;
	SPECULAR = COLOR.r < 0.1 ? 0.6 : 0.2;
	RIM = 0.25;
	RIM_TINT = 0.6;
	AO = given.a;
	EMISSION = ALBEDO * given.rgb;
}
