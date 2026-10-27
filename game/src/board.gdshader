shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

#include "res://src/ground.gdshaderinc"
#include "res://src/bounce.gdshaderinc"
#include "res://src/paint.gdshaderinc"

uniform sampler2D wet : filter_linear, repeat_disable;
uniform sampler2D dry : filter_linear, repeat_disable;
uniform sampler2D paper : filter_linear, repeat_disable;
uniform sampler2D relief : filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec2 metres;
uniform vec2 board;
uniform float open;
uniform vec2 thumb;
uniform float thumb_clear;

varying vec4 given;

void vertex() {
	given = given_at((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, normalize(mat3(MODEL_MATRIX) * NORMAL));
}

void fragment() {
	vec4 w = texture(wet, UV);
	vec4 d = texture(dry, UV);
	vec2 tooth = texture(paper, UV).rg;
	vec2 at = (UV - 0.5) * metres;
	float inside = (1.0 - smoothstep(open - 0.01, open, length(at / (board * 0.5)))) * smoothstep(thumb_clear, thumb_clear + 0.002, distance(at, thumb));
	ALPHA = smoothstep(0.02, 0.35, d.a) * inside;
	ALBEDO = canvas_colour(w, d, tooth);
	vec3 mean_normal = texture(relief, UV).rgb * 2.0 - 1.0;
	NORMAL_MAP = normalize(mean_normal) * 0.5 + 0.5;
	float oil = smoothstep(0.02, 0.2, d.a);
	ROUGHNESS = paint_filtered_roughness(paint_roughness(oil, canvas_damp(w)), mean_normal);
	SPECULAR = paint_specular(oil, canvas_damp(w));
	EMISSION = ALBEDO * given.rgb;
}
