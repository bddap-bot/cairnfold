shader_type spatial;
render_mode cull_disabled;

#include "res://src/palette.gdshaderinc"

uniform vec3 backlight : source_color = vec3(0.2, 0.3, 0.06);
// Leaves shrink away over the last 15 m before this distance, or its far half when it is nearer: past it they would be
// specks costing a full leaf each.
uniform float reach;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	VERTEX *= 1.0 - smoothstep(max(reach - 15.0, reach * 0.5), reach, distance(origin, CAMERA_POSITION_WORLD));
	COLOR.rgb = seasoned(COLOR.rgb, season_foliage);
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.75;
	BACKLIGHT = seasoned(backlight, season_foliage);
}
