// The ground's heights (Terrain.install): grid origin, step and points per side in ground_grid, and the
// hump a stroke is pulling (Terrain.set_hump), sampled on the grid points as Terrain.height_at does.
global uniform sampler2D ground_height : filter_linear, repeat_disable;
global uniform vec3 ground_grid;
global uniform vec4 ground_hump;

float bell(float t) {
	float s = max(1.0 - t * t, 0.0);
	return s * s * s;
}

float hump_at(vec2 p) {
	return ground_hump.w * bell(length(p - ground_hump.xy) / ground_hump.z);
}

float ground_at(vec2 xz) {
	vec2 g = (xz - ground_grid.x) / ground_grid.y;
	float h = textureLod(ground_height, (g + 0.5) / ground_grid.z, 0.0).r;
	if (ground_hump.w != 0.0) {
		vec2 c = clamp(floor(g), 0.0, ground_grid.z - 2.0);
		vec2 f = clamp(g - c, 0.0, 1.0);
		vec2 p = ground_grid.x + c * ground_grid.y;
		float s = ground_grid.y;
		h += mix(mix(hump_at(p), hump_at(p + vec2(s, 0.0)), f.x), mix(hump_at(p + vec2(0.0, s)), hump_at(p + vec2(s, s)), f.x), f.y);
	}
	return h;
}

vec3 ground_normal(vec2 xz) {
	float e = ground_grid.y;
	float dx = ground_at(xz + vec2(e, 0.0)) - ground_at(xz - vec2(e, 0.0));
	float dz = ground_at(xz + vec2(0.0, e)) - ground_at(xz - vec2(0.0, e));
	return normalize(vec3(-dx, 2.0 * e, -dz));
}
