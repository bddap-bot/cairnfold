shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;

// The ground where no stone is laid and no pond reaches (Meadow.plain): the code for either costs every fragment
// registers even where it never runs.
#define PLAIN
#include "res://src/terrain.gdshaderinc"
