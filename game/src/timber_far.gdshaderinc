// No per-fragment reads: past the near distance a beam is a few pixels wide, its detail averages to the colour it
// scales (0.78 + 0.45 x its mean of 0.5), and its bounce light varies too little across it.
#include "res://src/sculpture.gdshaderinc"
#include "res://src/ground.gdshaderinc"
#include "res://src/bounce.gdshaderinc"
#include "res://src/piece.gdshaderinc"

varying float occlusion;
varying vec4 given;
varying vec3 world_pos;
varying vec3 world_nrm;
#include "res://src/interior.gdshaderinc"

void vertex() {
	mat4 piece = PIECE_MATRIX;
	if (piece_cut(piece, CAMERA_POSITION_WORLD)) {
		VERTEX = vec3(0.0);
	} else {
		world_pos = laid_point((piece * vec4(VERTEX, 1.0)).xyz);
		world_nrm = laid_dir(normalize(mat3(piece) * NORMAL));
		occlusion = PIECE_CUSTOM.x;
		ROOM_HERE;
		float ground = ground_at(world_pos.xz);
		given = given_read(volume_coord(room_read(room_row, read_over(world_pos, world_nrm), world_nrm, laid_point(piece[3].xyz), 0.0), ground), lamp_over(world_pos, world_nrm, ground));
#ifdef BAKED
		VERTEX = world_pos;
		NORMAL = world_nrm;
#endif
	}
}

void fragment() {
	ALBEDO = SCULPTED ? SCULPTURE : COLOR.rgb * occlusion;
	ROUGHNESS = 0.92;
	SPECULAR = 0.25;
	EMISSION = ALBEDO * given.rgb;
	TAKE_ROOM(given.a);
}
