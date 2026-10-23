shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;

// The stone disc (stone_disc.gdshaderinc) under the garden's light.

#include "res://src/ground.gdshaderinc"
#include "res://src/bounce.gdshaderinc"
#include "res://src/stone_ground.gdshaderinc"
#include "res://src/stone_disc.gdshaderinc"

varying vec4 given;

void vertex() {
	given = given_at((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, normalize(mat3(MODEL_MATRIX) * NORMAL));
}

void fragment() {
	float laid;
	vec2 slope;
	ALBEDO = stone_disc(UV, laid, slope);
	vec3 x = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz);
	vec3 z = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	NORMAL = normalize(mix(NORMAL, stone_normal(NORMAL, x, z, slope), laid));
	ROUGHNESS = 1.0;
	AO = given.a;
	EMISSION = ALBEDO * given.rgb;
}
