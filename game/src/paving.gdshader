shader_type spatial;
render_mode world_vertex_coords, diffuse_lambert_wrap;

// A paving stone's height counts from the ground under its centre, so reshaping the ground relays no stone.
#define RIDES_GROUND
#include "res://src/ground.gdshaderinc"
#include "res://src/stone.gdshaderinc"
