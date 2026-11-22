shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap;

#include "res://src/sculpture.gdshaderinc"
#include "res://src/given.gdshaderinc"

void vertex() {
	float phase = TIME * 3.4 + dot(MODEL_MATRIX[3].xz, vec2(0.7, 0.4));
	float k = VERTEX.x;
	VERTEX.z += sin(phase - k * 5.5) * k * 0.14;
	VERTEX.y += sin(phase * 0.6 - k * 3.0) * k * 0.04 - k * k * 0.05;
	NORMAL = normalize(vec3(0.14 * (5.5 * k * cos(phase - k * 5.5) - sin(phase - k * 5.5)), 0.0, 1.0));
	GIVE_HERE;
}

void fragment() {
	ALBEDO = SCULPTED ? SCULPTURE : COLOR.rgb * (0.85 + 0.15 * sin(UV.x * 20.0));
	ROUGHNESS = 0.9;
	SPECULAR = 0.1;
	TAKE_GIVEN;
}
