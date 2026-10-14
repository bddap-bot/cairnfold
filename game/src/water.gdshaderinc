// Pond surface heights (Water), one texel per ground grid point; NONE far below the ground where there is no pond.
// Include after ground.gdshaderinc, whose grid it shares.
global uniform sampler2D water_level : filter_linear, repeat_disable;

float water_at(vec2 xz) {
	vec2 g = (xz - ground_grid.x) / ground_grid.y;
	return textureLod(water_level, (g + 0.5) / ground_grid.z, 0.0).r;
}

bool drowned(vec2 xz, float ground) {
	return water_at(xz) > ground + 0.02;
}
