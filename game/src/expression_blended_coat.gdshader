shader_type spatial;
render_mode diffuse_lambert, specular_disabled, vertex_lighting, cull_back;

#define BLENDED
#define CLEAR_COAT
#include "res://src/expression.gdshaderinc"
