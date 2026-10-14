// The glade's colours (Palette.globals): each built material's tint, and the season's.
global uniform vec3 tint_stone;
global uniform vec3 tint_roof;
global uniform vec3 tint_wood;
global uniform vec3 tint_plaster;
// rgb the season's colour for plants of average brightness, a how far plants turn to it.
global uniform vec4 season_meadow;
global uniform vec4 season_foliage;
global uniform float season_bloom;

vec3 material_tint(float code) {
	int c = int(code + 0.5);
	return c == 1 ? tint_stone : c == 2 ? tint_roof : c == 3 ? tint_wood : c == 4 ? tint_plaster : vec3(1.0);
}

// Turns a plant colour toward the season's, keeping some of its own light and shade.
vec3 seasoned(vec3 c, vec4 season) {
	float luma = dot(c, vec3(0.3, 0.55, 0.15));
	return mix(c, season.rgb * clamp(luma / 0.35, 0.75, 1.3), season.a);
}
