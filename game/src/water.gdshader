shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;

#include "res://src/ground.gdshaderinc"

// Depth comes from the shared ground heights, not the depth buffer: on a tiled GPU reading the depth
// buffer back costs a full-frame resolve per eye.
uniform sampler2D waves : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D breakup : filter_linear_mipmap, repeat_enable;
uniform float level;
uniform float drop = 0.0;
uniform vec4 ripples[12];
uniform vec3 shallow : source_color = vec3(0.30, 0.68, 0.58);
uniform vec3 deep : source_color = vec3(0.03, 0.19, 0.29);
uniform vec3 foam_color : source_color = vec3(0.96, 0.98, 0.94);
uniform float wave_strength = 0.22;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 s = wp.xz;
	float depth = level - drop - ground_at(s);
	vec2 slope = (texture(waves, s * 0.21 + TIME * vec2(0.019, 0.011)).xy
		+ texture(waves, s * 0.33 - TIME * vec2(0.012, 0.021)).xy - 1.0) * wave_strength;
	for (int i = 0; i < 12; i++) {
		vec4 r = ripples[i];
		if (r.w > 0.0) {
			vec2 dv = s - r.xy;
			float d = length(dv) + 1e-4;
			float x = d - r.z * 0.42;
			slope += dv / d * cos(x * 26.0) * r.w * exp(-r.z * 1.3 - x * x * 14.0);
		}
	}
	vec3 n = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	float body = 1.0 - exp(-max(depth, 0.0) * 2.8);
	vec3 col = mix(shallow, deep, body);
	float alpha = mix(0.2, 0.93, body);

	float grain = texture(breakup, s * 0.6 + TIME * vec2(0.01, -0.008)).r;
	// The ground mesh is 1 m triangles while depth here is bilinear, so the surface fades out over the last
	// few centimetres and the foam line sits just inside where it meets the ground.
	float shore = smoothstep(0.03, 0.08, depth) * smoothstep(0.16, 0.09, depth + (grain - 0.5) * 0.05);
	float lines = smoothstep(0.86, 0.98, sin(depth * 48.0 - TIME * 1.2 + grain * 4.0) * 0.5 + 0.5) * smoothstep(0.3, 0.1, depth);
	float foam = clamp(max(shore * 0.8, lines * 0.55) * smoothstep(0.35, 0.65, grain + shore * 0.25), 0.0, 1.0);

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	alpha = mix(alpha, 0.95, fresnel * 0.7);
	col = mix(col, foam_color, foam);
	alpha = max(alpha, foam * 0.9) * smoothstep(0.0, 0.07, depth);

	ALBEDO = col;
	ALPHA = alpha;
	ROUGHNESS = mix(0.06, 0.6, foam);
	SPECULAR = 0.5;
}
