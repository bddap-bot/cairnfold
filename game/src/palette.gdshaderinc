// rgb: the colour for plants of average brightness; a: how far plants turn to it.
global uniform vec4 season_meadow;
global uniform vec4 season_foliage;
global uniform float season_bloom;

vec3 seasoned(vec3 c, vec4 season) {
	float luma = dot(c, vec3(0.3, 0.55, 0.15));
	return mix(c, season.rgb * clamp(luma / 0.35, 0.75, 1.3), season.a);
}

// 1 in a season whose ponds freeze, snow lies and broadleaved trees stand bare, else 0.
global uniform float season_winter;
const vec3 SNOW = vec3(0.93, 0.95, 0.98);
const vec3 ICE = vec3(0.62, 0.77, 0.84);
const vec3 FROST = vec3(0.88, 0.93, 0.96);

// How much of a surface snow covers, 0 to 1: it lies on what faces up (`up`, its normal's rise) under the open sky
// (`sky`, the share of it over the surface: what the ground sees of it past the builds around, and none of it for a
// build's face inside a room), its edge broken by `drift`, a noise from 0 to 1.
float snow_cover(float up, float sky, float drift) {
	return season_winter * smoothstep(0.35, 0.7, up + (drift - 0.5) * 0.3) * smoothstep(0.35, 0.7, sky);
}
