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
