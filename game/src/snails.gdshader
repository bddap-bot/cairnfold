shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;
#include "res://src/given.gdshaderinc"
void vertex() {
	float phase = INSTANCE_CUSTOM.x;
	if (UV2.x > 0.5 && UV2.x < 1.5) {
		VERTEX.x *= 1.0 + 0.07 * sin(phase * 3.0 + VERTEX.z * 150.0);
	} else if (UV2.x > 1.5) {
		VERTEX.x += 0.003 * sin(phase * 1.4) * smoothstep(0.025, 0.065, VERTEX.y);
	}
	VERTEX *= INSTANCE_CUSTOM.y;
	GIVE_HERE;
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.65;
	TAKE_GIVEN;
}
