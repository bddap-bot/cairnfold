shader_type spatial;
render_mode cull_disabled;

#include "res://src/palette.gdshaderinc"

uniform vec3 albedo : source_color;

void fragment() {
	ALBEDO = albedo * tint_plaster;
	ROUGHNESS = 0.95;
}
