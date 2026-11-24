// PIECE_CUSTOM: occlusion, material code, end turns. BAKED (Masonry.bake) carries the world frame's rows per vertex.
#ifdef BAKED
#define PIECE_MATRIX transpose(mat4(CUSTOM0, CUSTOM1, CUSTOM2, vec4(0.0, 0.0, 0.0, 1.0)))
#define PIECE_CUSTOM CUSTOM3
#else
#define PIECE_MATRIX MODEL_MATRIX
#define PIECE_CUSTOM INSTANCE_CUSTOM
#endif

// A build in hand is drawn carried (Wall.carry) but keeps the light of where it was laid: what it reads of the garden's
// light (rooms, bounce, lamps, ground) it reads there. `carried`: the carry's offset (xyz) and turn about up (w).
#ifdef BAKED
vec3 laid_dir(vec3 d) {
	return d;
}
#else
instance uniform vec4 carried = vec4(0.0);

vec3 laid_dir(vec3 d) {
	float c = cos(carried.w);
	float s = sin(carried.w);
	return vec3(c * d.x - s * d.z, d.y, s * d.x + c * d.z);
}
#endif

vec3 laid_point(vec3 p) {
#ifdef BAKED
	return p;
#else
	return laid_dir(p - carried.xyz);
#endif
}

// piece_range: eye distances [x, y) an instance draws (Masonry._ranges); the rest collapse to a point. A baked far
// chunk is drawn only wholly past the near distance, so skips the test, which cost the Quest 2 0.3 ms over a hamlet.
#ifdef BAKED
bool piece_cut(mat4 piece, vec3 eye) {
	return false;
}
#else
instance uniform vec2 piece_range = vec2(0.0, 1e30);

bool piece_cut(mat4 piece, vec3 eye) {
	float d = distance(piece[3].xyz, eye);
	return d < piece_range.x || d >= piece_range.y;
}
#endif
