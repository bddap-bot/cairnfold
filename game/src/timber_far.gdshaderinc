// Far timbers: the stone shader's light without its per-fragment reads. Beyond the near distance a beam is a few
// pixels wide, its detail texture averages to the colour it scales (0.78 + 0.45 x its mean of 0.5), and its bounce
// light varies too little across it to read per fragment.
#include "res://src/ground.gdshaderinc"
#include "res://src/bounce.gdshaderinc"
#include "res://src/piece.gdshaderinc"

varying float occlusion;
varying vec4 given;

void vertex() {
	mat4 piece = PIECE_MATRIX;
	vec3 world_pos = (piece * vec4(VERTEX, 1.0)).xyz;
	vec3 world_nrm = normalize(mat3(piece) * NORMAL);
	occlusion = PIECE_CUSTOM.x;
	given = given_at(world_pos, world_nrm);
#ifdef BAKED
	VERTEX = world_pos;
	NORMAL = world_nrm;
#endif
}

void fragment() {
	ALBEDO = COLOR.rgb * occlusion;
	ROUGHNESS = 0.92;
	SPECULAR = 0.25;
	AO = given.a;
	EMISSION = ALBEDO * given.rgb;
}
