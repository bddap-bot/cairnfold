shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

#include "res://src/ground.gdshaderinc"
#include "res://src/bounce.gdshaderinc"
#include "res://src/noise.gdshaderinc"
#include "res://src/paint.gdshaderinc"

// An oil palette's mixing field as Mixing leaves it: each channel's linear reflectance stored as its square root, the
// amount of paint in alpha. A texel holding no paint holds no colour either, so colour is averaged over the texels around
// a point by the paint each holds, not filtered: paint keeps its colour to its edge instead of fading into the wood.

uniform sampler2D field : filter_nearest, repeat_disable;
uniform vec2 metres;

varying vec4 given;

void vertex() {
	given = given_at((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, normalize(mat3(MODEL_MATRIX) * NORMAL));
}

void fragment() {
	vec2 size = vec2(textureSize(field, 0));
	vec2 at = UV * size - 0.5;
	ivec2 base = ivec2(floor(at));
	vec2 f = fract(at);
	vec3 reflectance = vec3(0.0);
	float amount = 0.0;
	for (int i = 0; i < 4; i++) {
		ivec2 o = ivec2(i & 1, i >> 1);
		vec4 t = texelFetch(field, clamp(base + o, ivec2(0), ivec2(size) - 1), 0);
		float w = (o.x == 1 ? f.x : 1.0 - f.x) * (o.y == 1 ? f.y : 1.0 - f.y);
		reflectance += t.rgb * t.rgb * t.a * w;
		amount += t.a * w;
	}
	ALBEDO = SHEET * reflectance / max(amount, 1e-4);
	vec2 q = UV * metres * 350.0;
	float lumps = 0.6 * noise(q) + 0.4 * noise(q * 2.7 + 7.1);
	ALPHA = smoothstep(0.03, 0.08, amount + (lumps - 0.5) * 0.06);
	NORMAL_MAP = paint_relief(amount * impasto * (0.5 + 0.5 * lumps), UV, metres);
	float oil = smoothstep(0.02, 0.2, amount);
	ROUGHNESS = paint_roughness(oil, 0.0);
	SPECULAR = paint_specular(oil, 0.0);
	EMISSION = ALBEDO * given.rgb;
}
