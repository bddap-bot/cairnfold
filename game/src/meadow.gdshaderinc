// Set from Meadow.GRASS; the ground shares them where no blades are drawn.
uniform vec3 root_color : source_color;
uniform vec3 tip_lush : source_color;
uniform vec3 tip_dry : source_color;
uniform vec3 cool_clump : source_color;
uniform vec3 warm_clump : source_color;
uniform float root_shade = 0.55;
// Where on a blade, root to tip, the ground takes its colour.
uniform float canopy;
// Steep, so dryness lies in soft-edged patches of three tones; two ramps, since the ground runs it per fragment.
const float PATCH_SLOPE = 6.67;

float patched(float dry) {
	return dot(clamp(dry * PATCH_SLOPE + vec2(0.5 - 0.25 * PATCH_SLOPE, 0.5 - 0.75 * PATCH_SLOPE), 0.0, 1.0), vec2(0.5));
}

vec3 blade_top(float dry, float tint) {
	return seasoned(mix(tip_lush, tip_dry, patched(dry)) * mix(cool_clump, warm_clump, tint), season_meadow);
}

vec3 blade_color(vec3 top, float t) {
	return mix(seasoned(root_color, season_meadow), top, t) * mix(root_shade, 1.0, smoothstep(0.0, 0.7, t));
}
