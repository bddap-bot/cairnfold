// One wind field for every plant that sways: a function of ground position and TIME only, so a flower moves with
// the grass around it and no machine needs another's wind.
uniform vec2 wind_dir = vec2(0.8, 0.6);
uniform float wind_strength = 0.07;
uniform float gust_wavelength = 7.0;
uniform float gust_speed = 1.4;
// A flower's stalk, carrying its head, gives to the wind a little less than a grass blade of its height.
const float STALK_GIVE = 0.8;

// Gusts are bands travelling downwind; a slower cross-wind wave keeps them from reading as stripes.
float wind_gust(vec2 at) {
	float along = sin(dot(at, wind_dir) * (TAU / gust_wavelength) - TIME * gust_speed) * 0.5 + 0.5;
	float across = sin(dot(at, vec2(-wind_dir.y, wind_dir.x)) * 0.13 + TIME * 0.21) * 0.5 + 0.5;
	return along * along * (0.35 + 0.65 * across);
}

// How far the wind at `at` pushes the tip of a plant of unit height scale.
vec3 wind_push(vec2 at, float gust) {
	float flutter = 0.15 * sin(TIME * 3.1 + at.x * 1.7 + at.y * 2.3);
	return vec3(wind_dir.x, 0.0, wind_dir.y) * wind_strength * (0.3 + 1.3 * gust + flutter);
}

// `v` bent by `push` at the tip, `tip` running 0 at the root to 1 there; it sinks as it leans, so it keeps its length.
vec3 bent(vec3 v, vec3 push, float tip) {
	vec3 b = push * tip * tip;
	return v + b - vec3(0.0, length(b.xz) * 0.6 * tip, 0.0);
}
