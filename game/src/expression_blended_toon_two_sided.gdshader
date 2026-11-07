shader_type spatial;
render_mode diffuse_lambert, specular_disabled, vertex_lighting, cull_disabled;

#define BLENDED
#define TOON
#include "res://src/expression.gdshaderinc"
