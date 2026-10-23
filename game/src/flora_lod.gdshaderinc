// A plant's near mesh and what stands in for it far off share these transitions: a flower's and its far patch's
// reach, and the grass's LOD band, survivors and sink (grass.gdshader), which the ground paints the grass by.
uniform float draw_reach = 18.0;
uniform float draw_fade = 4.0;
// Set from Flora's GRASS_ constants, which say what each does.
uniform float lod_begin;
uniform float lod_band;
uniform float survivors;
uniform float survivors_from;
// Each clump sinks into the ground over this distance, at a distance set by its rank.
uniform float sink = 1.5;

float flora_fade(float dist, float end, float band) {
	return smoothstep(end - band, end, dist);
}
