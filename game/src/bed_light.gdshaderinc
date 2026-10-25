// One surface opening per world-space cell, shared by the light ribbon and its footprint on the bed.
global uniform vec3 water_ray;
const float DAPPLE_CELL = 1.5;

vec2 dapple_seed(vec2 cell) {
	return fract(sin(vec2(dot(cell, vec2(127.1, 311.7)), dot(cell, vec2(269.5, 183.3)))) * 43758.5453);
}

vec2 dapple_center(vec2 cell) {
	return (cell + 0.3 + dapple_seed(cell) * 0.4) * DAPPLE_CELL;
}

float dapple_radius(vec2 cell) {
	return 0.16 + dapple_seed(cell).x * 0.22;
}

float dapple_strength(vec2 cell) {
	return 0.55 + 0.45 * sin(TIME * 0.35 + dapple_seed(cell).y * 6.2832);
}

float bed_light(vec2 xz, float depth) {
	vec2 surface = xz - water_ray.xz * depth / -water_ray.y;
	vec2 cell = floor(surface / DAPPLE_CELL);
	float r = length(surface - dapple_center(cell)) / dapple_radius(cell);
	return pow(max(0.0, 1.0 - r), 1.5) * dapple_strength(cell);
}
