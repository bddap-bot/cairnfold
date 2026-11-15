// GIVE_HERE follows the last write to VERTEX and NORMAL, both in model space. TAKE_GIVEN follows ALBEDO and is two
// statements, so it needs braces under an if.
#include "res://src/ground.gdshaderinc"
#include "res://src/bounce.gdshaderinc"

varying vec4 given;

#define GIVE_HERE given = given_at((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, normalize(mat3(MODEL_MATRIX) * NORMAL))
#define TAKE_GIVEN AO = given.a; EMISSION = ALBEDO * given.rgb
