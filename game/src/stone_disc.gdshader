shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;

// The stone disc (stone_disc.gdshaderinc) under the garden's light.

#include "res://src/given.gdshaderinc"
#include "res://src/stone_ground.gdshaderinc"
#include "res://src/stone_disc.gdshaderinc"

void vertex() {
	GIVE_HERE;
}

void fragment() {
	float laid;
	vec2 slope;
	ALBEDO = stone_disc(UV, laid, slope);
	vec3 x = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz);
	vec3 z = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	NORMAL = normalize(mix(NORMAL, stone_normal(NORMAL, x, z, slope), laid));
	ROUGHNESS = 1.0;
	TAKE_GIVEN;
}
