shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;

// A disc of stone ground in small, as the ground shades it (stone_ground.gdshaderinc): `span` metres of style `style`
// across, fraying toward its rim into meadow as scattered stones.

#include "res://src/ground.gdshaderinc"
#include "res://src/bounce.gdshaderinc"
#include "res://src/stone_ground.gdshaderinc"

uniform sampler2D detail : filter_linear_mipmap, repeat_enable;
uniform int style;
uniform float span = 2.0;
uniform vec3 earth : source_color;
uniform vec3 meadow : source_color;

varying vec4 given;

void vertex() {
	given = given_at((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, normalize(mat3(MODEL_MATRIX) * NORMAL));
}

void fragment() {
	vec2 at = UV - 0.5;
	float r = length(at) * 2.0;
	if (r > 1.0) {
		discard;
	}
	vec2 xz = at * span;
	float d = texture(detail, xz * 0.07).r;
	float fine = texture(detail, xz * 0.45).r;
	float grit = texture(detail, xz * 3.7).r;
	float laid;
	vec2 slope;
	ALBEDO = stone_ground(style, xz, 1.0 - smoothstep(0.5, 1.0, r), meadow, earth, meadow, d, fine, grit, laid, slope);
	vec3 x = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz);
	vec3 z = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	NORMAL = normalize(mix(NORMAL, stone_normal(NORMAL, x, z, slope), laid));
	ROUGHNESS = 1.0;
	AO = given.a;
	EMISSION = ALBEDO * given.rgb;
}
