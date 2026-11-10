// What a thing small or dense enough to be lit once a vertex takes from the baked volumes where it stands. GIVE_HERE
// follows the last write to VERTEX and NORMAL, both in model space; a shader that knows its ground height or lights
// itself otherwise assigns `given` instead. TAKE_GIVEN follows ALBEDO and is two statements, so it needs braces under
// an if.
#include "res://src/ground.gdshaderinc"
#include "res://src/bounce.gdshaderinc"

varying vec4 given;

#define GIVE_HERE given = given_at((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, normalize(mat3(MODEL_MATRIX) * NORMAL))
#define TAKE_GIVEN AO = given.a; EMISSION = ALBEDO * given.rgb
