// A piece's frame and custom data (occlusion, material code, end turns): its instance's in a MultiMesh, or with BAKED,
// carried on each vertex of a chunk baked into one mesh (Masonry.bake) as the rows of its world frame.
#ifdef BAKED
#define PIECE_MATRIX transpose(mat4(CUSTOM0, CUSTOM1, CUSTOM2, vec4(0.0, 0.0, 0.0, 1.0)))
#define PIECE_CUSTOM CUSTOM3
#else
#define PIECE_MATRIX MODEL_MATRIX
#define PIECE_CUSTOM INSTANCE_CUSTOM
#endif
