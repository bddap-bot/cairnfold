shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;

uniform sampler2D detail : filter_linear_mipmap, repeat_enable;
uniform vec3 meadow_dry : source_color = vec3(0.56, 0.62, 0.22);
uniform vec3 meadow_lush : source_color = vec3(0.22, 0.46, 0.12);
uniform vec3 earth : source_color = vec3(0.45, 0.38, 0.27);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float d = texture(detail, world_pos.xz * 0.07).r;
	float fine = texture(detail, world_pos.xz * 0.45).r;
	vec3 grass = mix(meadow_dry, meadow_lush, clamp(COLOR.r + (d - 0.5) * 0.8, 0.0, 1.0));
	grass *= 0.85 + fine * 0.3;
	ALBEDO = mix(grass, earth, smoothstep(0.55, 0.9, COLOR.g + (fine - 0.5) * 0.3));
	ROUGHNESS = 1.0;
}
