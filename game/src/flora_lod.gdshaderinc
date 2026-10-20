// A plant's near mesh and what stands in for it far off share these transitions: a flower's and its far patch's
// reach, and the grass's LOD band, survivors and sink (grass.gdshader), which the ground paints the grass by.
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
