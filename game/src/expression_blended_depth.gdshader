shader_type spatial;
render_mode diffuse_lambert, specular_disabled, vertex_lighting, cull_back, depth_draw_always;

#define BLENDED
#include "res://src/expression.gdshaderinc"
