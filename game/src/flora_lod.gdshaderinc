// The near mesh and its far patch use the same transition, including each grass clump's thinning rank.
uniform float draw_reach = 18.0;
uniform float draw_fade = 4.0;
uniform float lod_begin = 8.0;
uniform float lod_band = 4.0;
uniform float survivors = 0.25;
uniform float survivors_from = 0.5;
uniform float sink = 1.5;

float flora_fade(float dist, float end, float band) {
	return smoothstep(end - band, end, dist);
}

float grass_end(float rank) {
	return rank < survivors
		? mix(draw_reach, draw_reach * survivors_from, rank / survivors)
		: mix(lod_begin + lod_band, lod_begin + sink, (rank - survivors) / (1.0 - survivors));
}
