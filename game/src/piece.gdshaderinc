// A piece's frame and custom data (occlusion, material code, end turns): its instance's in a MultiMesh, or with BAKED,
// carried on each vertex of a chunk baked into one mesh (Masonry.bake) as the rows of its world frame.
#ifdef BAKED
#define PIECE_MATRIX transpose(mat4(CUSTOM0, CUSTOM1, CUSTOM2, vec4(0.0, 0.0, 0.0, 1.0)))
#define PIECE_CUSTOM CUSTOM3
#else
#define PIECE_MATRIX MODEL_MATRIX
#define PIECE_CUSTOM INSTANCE_CUSTOM
#endif

// The distances from the eye, [x, y), of the pieces an instance draws; the rest collapse to a point. A chunk near the eye
// draws its near and its far instance, each the pieces on its side of the near distance (Masonry._ranges). A baked far
// chunk is drawn only past it whole, and leaves the test out: read on every vertex of a chunk, it cost the Quest 2's
// view of a hamlet from the air 0.3 ms.
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
