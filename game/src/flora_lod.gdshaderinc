uniform float draw_reach = 18.0;
uniform float draw_fade = 4.0;
// Set from Flora's GRASS_ constants, which say what each does.
uniform float lod_begin;
uniform float lod_band;
uniform float survivors;
uniform float survivors_from;
// The eye distance, in metres, over which a clump sinks, ending at a distance set by its rank.
uniform float sink = 1.5;

float flora_fade(float dist, float end, float band) {
	return smoothstep(end - band, end, dist);
}
