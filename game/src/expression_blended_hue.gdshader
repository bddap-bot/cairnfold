shader_type spatial;
render_mode diffuse_lambert, specular_disabled, vertex_lighting, cull_back;

#define BLENDED
#define DECAL_HUE
#include "res://src/expression.gdshaderinc"
