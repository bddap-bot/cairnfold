// How deep pond water (Water) stands over each ground grid point, one texel per point: negative on a pond's shore,
// DRY everywhere else. Depth rather than level, so it filters smoothly into the dry ground around a pond.
// Include after ground.gdshaderinc, whose grid it shares.
global uniform sampler2D water_depth : filter_linear, repeat_disable;

float water_depth_at(vec2 xz) {
	vec2 g = (xz - ground_grid.x) / ground_grid.y;
	return textureLod(water_depth, (g + 0.5) / ground_grid.z, 0.0).r;
}

bool drowned(vec2 xz) {
	return water_depth_at(xz) > 0.02;
}

// 1 on the bare bank and bed of a pond at this depth, 0 on meadow.
float bank(float depth) {
	return smoothstep(-0.25, -0.08, depth);
}

// Sunlight the waves overhead focus into bright lines, where two drifting noises cross.
vec3 caustic(sampler2D noise, vec2 xz) {
	vec2 uv = xz * 0.35;
	float a = texture(noise, uv + TIME * vec2(0.021, 0.013)).r;
	float b = texture(noise, uv * 1.37 - TIME * vec2(0.017, 0.024)).r;
	return vec3(0.85, 0.95, 0.8) * smoothstep(0.045, 0.0, abs(a - b));
}
