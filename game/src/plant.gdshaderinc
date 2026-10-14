#include "res://src/ground.gdshaderinc"

uniform vec3 albedo : source_color = vec3(1.0);
uniform float roughness = 1.0;
#ifdef BACKLIT
uniform vec3 backlight : source_color = vec3(0.0);
#endif

void vertex() {
	float ground = ground_at(INSTANCE_CUSTOM.zw);
	VERTEX.y += ground;
#ifdef PARTED
	vec3 root = MODEL_MATRIX[3].xyz + vec3(0.0, ground, 0.0);
	VERTEX = mix(root, VERTEX, 1.0 - path_cover(root.xz));
#endif
}

void fragment() {
	ALBEDO = albedo * COLOR.rgb;
	ROUGHNESS = roughness;
#ifdef BACKLIT
	BACKLIGHT = backlight;
#endif
}
