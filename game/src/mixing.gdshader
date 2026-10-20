shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

#include "res://src/ground.gdshaderinc"
#include "res://src/bounce.gdshaderinc"

// An oil palette's mixing field as Mixing leaves it: each channel's linear reflectance stored as its square root, the
// amount of paint in alpha. A thin film still shows the board through it; a heap is opaque and glossy.

uniform sampler2D field : filter_linear, repeat_disable;

varying vec4 given;

void vertex() {
	given = given_at((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, normalize(mat3(MODEL_MATRIX) * NORMAL));
}

void fragment() {
	vec4 t = texture(field, UV);
	ALBEDO = t.rgb * t.rgb;
	ALPHA = smoothstep(0.0, 0.15, t.a);
	ROUGHNESS = 0.22;
	SPECULAR = 0.6;
	EMISSION = ALBEDO * given.rgb;
}
