shader_type spatial;

#include "res://src/ground.gdshaderinc"
#include "res://src/bounce.gdshaderinc"
#include "res://src/paint.gdshaderinc"

// A canvas as paint.glsl leaves it, coloured as paint.gdshaderinc says: glossy where wet, oil standing up off it in
// ridges the light catches, charcoal and dry paper matte. The sheet is mounted on a board, so no light comes through
// it from behind.

uniform sampler2D wet : filter_linear, repeat_disable;
uniform sampler2D dry : filter_linear, repeat_disable;
uniform sampler2D paper : filter_linear, repeat_disable;
uniform vec2 metres;

varying vec4 given;

void vertex() {
	given = given_at((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, normalize(mat3(MODEL_MATRIX) * NORMAL));
}

void fragment() {
	vec4 w = texture(wet, UV);
	vec4 d = texture(dry, UV);
	vec2 tooth = texture(paper, UV).rg;
	float damp = canvas_damp(w);
	ALBEDO = canvas_colour(w, d, tooth);
	float height = canvas_height(d, tooth);
	NORMAL_MAP = paint_relief(height, UV, metres);
	float oil = smoothstep(0.02, 0.2, d.a);
	ROUGHNESS = paint_roughness(oil, damp);
	SPECULAR = paint_specular(oil, damp);
	AO = given.a;
	EMISSION = ALBEDO * given.rgb;
}
