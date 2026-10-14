#include "res://src/ground.gdshaderinc"

uniform vec3 albedo : source_color = vec3(1.0);
uniform float roughness = 1.0;
#ifdef BACKLIT
uniform vec3 backlight : source_color = vec3(0.0);
#endif

void vertex() {
	VERTEX.y += ground_at(INSTANCE_CUSTOM.zw);
}

void fragment() {
	ALBEDO = albedo * COLOR.rgb;
	ROUGHNESS = roughness;
#ifdef BACKLIT
	BACKLIGHT = backlight;
#endif
}
