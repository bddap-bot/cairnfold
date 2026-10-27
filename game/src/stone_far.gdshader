shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;
#define GIVEN_PER_VERTEX
#define BAKED
#include "res://src/ground.gdshaderinc"
#include "res://src/stone_ground.gdshaderinc"
#include "res://src/stone.gdshaderinc"
