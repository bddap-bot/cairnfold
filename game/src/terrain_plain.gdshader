shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;

// For ground with no stone or pond (Meadow.plain): either's code costs every fragment registers even where unused.
#define PLAIN
#include "res://src/terrain.gdshaderinc"
