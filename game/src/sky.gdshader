shader_type sky;
uniform vec3 zenith : source_color = vec3(0.30, 0.52, 0.85);
uniform vec3 horizon : source_color = vec3(0.86, 0.88, 0.84);
uniform vec3 ground_tint : source_color = vec3(0.55, 0.60, 0.45);
uniform vec3 sun_glow : source_color = vec3(1.0, 0.82, 0.55);
uniform sampler2D clouds : filter_linear_mipmap, repeat_enable;
uniform float cloud_cover = 0.48;
uniform vec3 cloud_light : source_color = vec3(1.0);
// The light does not drive the sky (Look), and the discs are drawn apart from it.
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform vec3 moon_glow : source_color = vec3(0.0);
uniform float stars = 0.0;

vec3 star_field(vec3 d) {
	vec3 s = d * 150.0;
	vec3 cell = floor(s);
	float h = fract(sin(dot(cell, vec3(127.1, 311.7, 74.7))) * 43758.5453);
	vec3 at = vec3(fract(h * 17.0), fract(h * 131.0), fract(h * 1031.0)) * 0.5 + 0.25;
	float lit = smoothstep(0.975, 1.0, h);
	vec3 tint = mix(vec3(0.72, 0.82, 1.0), vec3(1.0, 0.88, 0.72), fract(h * 43.0));
	return tint * lit * (1.0 - smoothstep(0.0, 0.32, length(fract(s) - at))) * (0.4 + 0.6 * fract(h * 7.0));
}

// Cells about a pixel and a half wide in the headset, so the dither stays on the sky, unaliased, as the head turns.
float grain(vec3 d) {
	uvec3 v = uvec3(ivec3(floor(d * 900.0)) + 2048);
	v = v * 1664525u + 1013904223u;
	v.x += v.y * v.z;
	v.y += v.z * v.x;
	v.z += v.x * v.y;
	v ^= v >> 16u;
	v.x += v.y * v.z;
	return float(v.x >> 8u) / 16777216.0 - 0.5;
}

void sky() {
	vec3 d = EYEDIR;
	float up = clamp(d.y, 0.0, 1.0);
	vec3 col = mix(horizon, zenith, pow(up, 0.55));
	if (d.y < 0.0) {
		col = mix(horizon, ground_tint * cloud_light, clamp(-d.y * 3.0, 0.0, 1.0));
	}
	float sd = max(dot(d, sun_dir), 0.0);
	col += sun_glow * (pow(sd, 6.0) * 0.25 + pow(sd, 64.0) * 0.6);
	float md = max(dot(d, moon_dir), 0.0);
	col += moon_glow * (pow(md, 6.0) * 0.06 + pow(md, 80.0) * 0.12);
	if (d.y > 0.0) {
		if (stars > 0.0) {
			col += stars * star_field(d) * smoothstep(0.02, 0.25, d.y) * (1.0 - pow(md, 12.0));
		}
		vec2 uv = d.xz / (d.y + 0.12) * 0.18;
		float c = texture(clouds, uv).r * 0.7 + texture(clouds, uv * 2.7 + 0.3).r * 0.3;
		float a = smoothstep(cloud_cover, cloud_cover + 0.22, c) * smoothstep(0.0, 0.18, d.y);
		vec3 lit = mix(vec3(0.95, 0.93, 0.9), vec3(1.0, 0.92, 0.78), pow(sd, 3.0)) + moon_glow * pow(md, 4.0) * 0.8;
		vec3 shade = mix(vec3(0.72, 0.76, 0.84), lit, smoothstep(cloud_cover, cloud_cover + 0.5, c));
		col = mix(col, shade * cloud_light, a * 0.9);
	}
	// The night sky fills a few codes of the 10-bit scene buffer, so its moon glow bands into rings undithered.
	COLOR = col + grain(d) * 0.002;
}
