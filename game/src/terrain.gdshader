shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;

#include "res://src/ground.gdshaderinc"
#include "res://src/water.gdshaderinc"

uniform sampler2D detail : filter_linear_mipmap, repeat_enable;
uniform vec3 meadow_dry : source_color = vec3(0.56, 0.62, 0.22);
uniform vec3 meadow_lush : source_color = vec3(0.22, 0.46, 0.12);
uniform vec3 earth : source_color = vec3(0.45, 0.38, 0.27);
uniform vec3 rock : source_color = vec3(0.58, 0.56, 0.52);
uniform vec3 trodden : source_color = vec3(0.52, 0.45, 0.33);
uniform vec3 bed : source_color = vec3(0.50, 0.44, 0.32);

varying vec3 world_pos;
varying float steep;
varying float under;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y = ground_at(world_pos.xz);
	world_pos.y = VERTEX.y;
	NORMAL = ground_normal(world_pos.xz);
	steep = 1.0 - NORMAL.y;
	under = water_at(world_pos.xz) - VERTEX.y;
}

void fragment() {
	float d = texture(detail, world_pos.xz * 0.07).r;
	float fine = texture(detail, world_pos.xz * 0.45).r;
	vec3 grass = mix(meadow_dry, meadow_lush, clamp(COLOR.r + (d - 0.5) * 0.8, 0.0, 1.0));
	grass *= 0.85 + fine * 0.3;
	float s = steep + (fine - 0.5) * 0.06;
	vec3 c = mix(grass, earth, smoothstep(0.2, 0.32, s));
	vec3 stone = rock * (0.8 + texture(detail, world_pos.xz * 0.9 + world_pos.y * 0.3).r * 0.35);
	c = mix(c, stone, smoothstep(0.36, 0.48, s));
	if (under > -0.25) {
		float pebble = texture(detail, world_pos.xz * 2.3).r;
		c = mix(c, bed * (0.7 + pebble * 0.6) * mix(1.0, 0.75, smoothstep(-0.1, 0.0, under)), smoothstep(-0.25, -0.08, under));
		vec2 uv = world_pos.xz * 0.35;
		float a = texture(detail, uv + TIME * vec2(0.021, 0.013)).r;
		float b = texture(detail, uv * 1.37 - TIME * vec2(0.017, 0.024)).r;
		c += vec3(0.85, 0.95, 0.8) * smoothstep(0.045, 0.0, abs(a - b)) * 0.35 * smoothstep(0.05, 0.3, under);
	}
	ALBEDO = mix(c, trodden * (0.85 + fine * 0.3), smoothstep(0.1, 0.7, path_cover(world_pos.xz) + (d - 0.5) * 0.3));
	ROUGHNESS = 1.0;
}
