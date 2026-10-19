// The ground's heights (Terrain.install): grid origin, step and points per side in ground_grid, and the
// humps strokes are pulling (Terrain.set_hump), one per hand in the first two columns of ground_humps,
// sampled on the grid points as Terrain.height_at does.
global uniform sampler2D ground_height : filter_linear, repeat_disable;
global uniform vec3 ground_grid;
global uniform mat4 ground_humps;
// What the ground is made of (Ground): red trodden earth, green stone, neither meadow.
global uniform sampler2D ground_mask : filter_linear, repeat_disable;

float bell(float t) {
	float s = max(1.0 - t * t, 0.0);
	return s * s * s;
}

float hump_at(vec4 hump, vec2 p) {
	return hump.w * bell(length(p - hump.xy) / hump.z);
}

float ground_at(vec2 xz) {
	vec2 g = (xz - ground_grid.x) / ground_grid.y;
	vec4 t = textureLod(ground_height, (g + 0.5) / ground_grid.z, 0.0);
	float h = t.r + t.b;
	for (int k = 0; k < 2; k++) {
		vec4 hump = ground_humps[k];
		if (hump.w != 0.0) {
			vec2 c = clamp(floor(g), 0.0, ground_grid.z - 2.0);
			vec2 f = clamp(g - c, 0.0, 1.0);
			vec2 p = ground_grid.x + c * ground_grid.y;
			float s = ground_grid.y;
			h += mix(mix(hump_at(hump, p), hump_at(hump, p + vec2(s, 0.0)), f.x), mix(hump_at(hump, p + vec2(0.0, s)), hump_at(hump, p + vec2(s, s)), f.x), f.y);
		}
	}
	return h;
}

// A one-texel-per-grid-point texture as a cubic B-spline through the neighbourhood of `xz`, in four filtered
// taps, of red plus blue: ground_height's blue holds what rounding red to half precision left, and a texture
// without blue reads 0 there. Bilinear contours kink at every grid line, so a small hollow's waterline drawn from them is a polygon.
float grid_smooth(sampler2D t, vec2 xz) {
	vec2 g = (xz - ground_grid.x) / ground_grid.y;
	vec2 i = floor(g);
	vec2 f = g - i;
	vec2 w0 = (1.0 - f) * (1.0 - f) * (1.0 - f) / 6.0;
	vec2 w1 = (4.0 - 6.0 * f * f + 3.0 * f * f * f) / 6.0;
	vec2 w3 = f * f * f / 6.0;
	vec2 s0 = w0 + w1;
	vec2 s1 = 1.0 - s0;
	vec2 t0 = (i - 0.5 + w1 / s0) / ground_grid.z;
	vec2 t1 = (i + 1.5 + w3 / s1) / ground_grid.z;
	return s0.y * (s0.x * dot(textureLod(t, t0, 0.0).rb, vec2(1.0)) + s1.x * dot(textureLod(t, vec2(t1.x, t0.y), 0.0).rb, vec2(1.0)))
		+ s1.y * (s0.x * dot(textureLod(t, vec2(t0.x, t1.y), 0.0).rb, vec2(1.0)) + s1.x * dot(textureLod(t, t1, 0.0).rb, vec2(1.0)));
}

vec2 ground_cover(vec2 xz) {
	return textureLod(ground_mask, (xz - ground_grid.x) / (ground_grid.y * (ground_grid.z - 1.0)), 0.0).rg;
}

// How bare of plants the ground is, as Ground.bare reads it: 1 on earth or stone.
float bare(vec2 xz) {
	vec2 c = ground_cover(xz);
	return min(c.r + c.g, 1.0);
}

vec3 ground_normal(vec2 xz) {
	float e = ground_grid.y;
	float dx = ground_at(xz + vec2(e, 0.0)) - ground_at(xz - vec2(e, 0.0));
	float dz = ground_at(xz + vec2(0.0, e)) - ground_at(xz - vec2(0.0, e));
	return normalize(vec3(-dx, 2.0 * e, -dz));
}

// 1 - the ground normal's y, bilinear between grid points: a fragment's own, not its triangle's. Live humps are
// not in the texture.
float ground_steepness(vec2 xz) {
	vec2 g = (xz - ground_grid.x) / ground_grid.y;
	return textureLod(ground_height, (g + 0.5) / ground_grid.z, 0.0).g;
}
