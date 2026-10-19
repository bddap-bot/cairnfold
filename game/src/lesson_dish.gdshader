shader_type spatial;
render_mode diffuse_lambert_wrap, cull_disabled;

// The patch of meadow a page's picture shows, fraying into the paper at its rim, raised into a hill of
// `hill_height` at `hill_at` (local x, z) for the page that teaches shaping the ground.

uniform vec3 root_color : source_color;
uniform vec3 tip_lush : source_color;
uniform vec3 tip_dry : source_color;
uniform vec3 earth : source_color;
uniform vec2 hill_at = vec2(0.0);
uniform float hill_height = 0.0;
uniform float hill_radius = 0.6;
uniform float radius = 1.4;

varying vec2 flat_at;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float hill(vec2 p) {
	float d = length(p - hill_at) / hill_radius;
	return hill_height * exp(-d * d * 2.2);
}

void vertex() {
	flat_at = VERTEX.xz;
	VERTEX.y += hill(VERTEX.xz);
	float e = 0.02;
	vec3 dx = vec3(2.0 * e, hill(VERTEX.xz + vec2(e, 0)) - hill(VERTEX.xz - vec2(e, 0)), 0.0);
	vec3 dz = vec3(0.0, hill(VERTEX.xz + vec2(0, e)) - hill(VERTEX.xz - vec2(0, e)), 2.0 * e);
	NORMAL = normalize(cross(dz, dx));
}

void fragment() {
	vec2 p = flat_at;
	float r = length(p) / radius;
	float fray = r + (noise(p * 7.0) - 0.5) * 0.22 + (noise(p * 23.0) - 0.5) * 0.08;
	if (fray > 0.96) {
		discard;
	}
	float n = noise(p * 3.0) * 0.6 + noise(p * 11.0) * 0.4;
	vec3 grass = mix(mix(root_color, tip_lush, 0.55), tip_lush, n * 0.6);
	grass = mix(grass, tip_dry, smoothstep(0.55, 0.9, noise(p * 2.0 + 5.0)) * 0.35);
	vec3 c = mix(grass, earth, smoothstep(0.8, 0.95, fray) * 0.6);
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
