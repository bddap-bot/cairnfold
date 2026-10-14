shader_type sky;
uniform vec3 zenith : source_color = vec3(0.30, 0.52, 0.85);
uniform vec3 horizon : source_color = vec3(0.86, 0.88, 0.84);
uniform vec3 ground_tint : source_color = vec3(0.55, 0.60, 0.45);
uniform vec3 sun_glow : source_color = vec3(1.0, 0.82, 0.55);
uniform sampler2D clouds : filter_linear_mipmap, repeat_enable;
uniform float cloud_cover = 0.48;
uniform vec3 cloud_light : source_color = vec3(1.0);
// Toward the sun; the light does not drive the sky (Look), and the disc is drawn apart from it.
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);

void sky() {
	vec3 d = EYEDIR;
	float up = clamp(d.y, 0.0, 1.0);
	vec3 col = mix(horizon, zenith, pow(up, 0.55));
	if (d.y < 0.0) {
		col = mix(horizon, ground_tint * cloud_light, clamp(-d.y * 3.0, 0.0, 1.0));
	}
	float sd = max(dot(d, sun_dir), 0.0);
	col += sun_glow * (pow(sd, 6.0) * 0.25 + pow(sd, 64.0) * 0.6);
	if (d.y > 0.0) {
		vec2 uv = d.xz / (d.y + 0.12) * 0.18;
		float c = texture(clouds, uv).r * 0.7 + texture(clouds, uv * 2.7 + 0.3).r * 0.3;
		float a = smoothstep(cloud_cover, cloud_cover + 0.22, c) * smoothstep(0.0, 0.18, d.y);
		vec3 lit = mix(vec3(0.95, 0.93, 0.9), vec3(1.0, 0.92, 0.78), pow(sd, 3.0));
		vec3 shade = mix(vec3(0.72, 0.76, 0.84), lit, smoothstep(cloud_cover, cloud_cover + 0.5, c));
		col = mix(col, shade * cloud_light, a * 0.9);
	}
	COLOR = col;
}
