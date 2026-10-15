// The meadow's grass colours, shared by the blades and by the ground that stands in for them where none are drawn;
// set from Meadow.GRASS.
uniform vec3 root_color : source_color;
uniform vec3 tip_lush : source_color;
uniform vec3 tip_dry : source_color;
uniform vec3 cool_clump : source_color;
uniform vec3 warm_clump : source_color;
uniform float root_shade = 0.55;

// A blade's tip colour from how dry it is (FloraLayout.dryness) and its clump's tint, both 0..1.
vec3 blade_top(float dry, float tint) {
	return seasoned(mix(tip_lush, tip_dry, dry) * mix(cool_clump, warm_clump, tint), season_meadow);
}

// The colour `t` of the way from a blade's root to its tip.
vec3 blade_color(vec3 top, float t) {
	return mix(seasoned(root_color, season_meadow), top, t) * mix(root_shade, 1.0, smoothstep(0.0, 0.7, t));
}
