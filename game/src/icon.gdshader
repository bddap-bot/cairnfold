shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

// The icon look (icon.gdshaderinc) of a plain material: its colour, picture and, where they count, vertex colours.

#include "res://src/icon.gdshaderinc"

uniform vec4 colour : source_color = vec4(1.0);
uniform bool use_vertex = false;
uniform sampler2D picture : source_color, hint_default_white, filter_linear_mipmap;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);

void fragment() {
	vec3 c = colour.rgb * texture(picture, UV * uv_scale + uv_offset).rgb;
	ALBEDO = icon_look(use_vertex ? c * COLOR.rgb : c, NORMAL);
}
