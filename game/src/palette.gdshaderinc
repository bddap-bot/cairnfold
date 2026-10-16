// The season's colours (Palette.globals).
// rgb the season's colour for plants of average brightness, a how far plants turn to it.
global uniform vec4 season_meadow;
global uniform vec4 season_foliage;
global uniform float season_bloom;

// Turns a plant colour toward the season's, keeping some of its own light and shade.
vec3 seasoned(vec3 c, vec4 season) {
	float luma = dot(c, vec3(0.3, 0.55, 0.15));
	return mix(c, season.rgb * clamp(luma / 0.35, 0.75, 1.3), season.a);
}
