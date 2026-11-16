// Water's depth per ground grid point: negative on a pond's shore, Terrain.DRY elsewhere. Depth, not level, so it
// filters smoothly into the dry ground around a pond. Include after ground.gdshaderinc, whose grid it shares.
global uniform sampler2D water_depth : filter_linear, repeat_disable;
const float DROWNS = 0.02;
const float DRY = -0.6;

float water_depth_at(vec2 xz) {
	return textureLod(water_depth, grid_uv(xz), 0.0).r;
}

float planted_water(float planted, float depth) {
	return planted * step(DROWNS, depth);
}

bool drowned(vec2 xz) {
	return water_depth_at(xz) > DROWNS;
}

float bank(float depth) {
	return smoothstep(DRY + 0.35, DRY + 0.52, depth);
}

vec3 caustic(sampler2D noise, vec2 xz) {
	vec2 uv = xz * 0.35;
	float a = texture(noise, uv + TIME * vec2(0.021, 0.013)).r;
	float b = texture(noise, uv * 1.37 - TIME * vec2(0.017, 0.024)).r;
	return vec3(0.85, 0.95, 0.8) * smoothstep(0.045, 0.0, abs(a - b));
}

// Read per vertex: each corner of a fragment's cell lies a step along an axis from one of its vertices, so 0 means
// its bilinear depth read blends only DRY.
float pond_near(vec2 xz) {
	vec2 t = grid_uv(xz);
	vec2 e = vec2(1.0 / ground_grid.z, 0.0);
	float deepest = max(max(textureLod(water_depth, t, 0.0).r, textureLod(water_depth, t + e, 0.0).r),
		max(textureLod(water_depth, t - e, 0.0).r, max(textureLod(water_depth, t + e.yx, 0.0).r, textureLod(water_depth, t - e.yx, 0.0).r)));
	return deepest > DRY + 0.05 ? 1.0 : 0.0;
}
