shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;

#include "res://src/ground.gdshaderinc"

uniform sampler2D detail : filter_linear_mipmap, repeat_enable;
uniform vec3 meadow_dry : source_color = vec3(0.56, 0.62, 0.22);
uniform vec3 meadow_lush : source_color = vec3(0.22, 0.46, 0.12);
uniform vec3 earth : source_color = vec3(0.45, 0.38, 0.27);
uniform vec3 rock : source_color = vec3(0.58, 0.56, 0.52);

varying vec3 world_pos;
varying float steep;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y = ground_at(world_pos.xz);
	world_pos.y = VERTEX.y;
	NORMAL = ground_normal(world_pos.xz);
	steep = 1.0 - NORMAL.y;
}

void fragment() {
	float d = texture(detail, world_pos.xz * 0.07).r;
	float fine = texture(detail, world_pos.xz * 0.45).r;
	vec3 grass = mix(meadow_dry, meadow_lush, clamp(COLOR.r + (d - 0.5) * 0.8, 0.0, 1.0));
	grass *= 0.85 + fine * 0.3;
	float s = steep + (fine - 0.5) * 0.06;
	vec3 c = mix(grass, earth, smoothstep(0.2, 0.32, s));
	vec3 stone = rock * (0.8 + texture(detail, world_pos.xz * 0.9 + world_pos.y * 0.3).r * 0.35);
	ALBEDO = mix(c, stone, smoothstep(0.36, 0.48, s));
	ROUGHNESS = 1.0;
}
