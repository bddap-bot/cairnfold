shader_type spatial;
#include "res://src/given.gdshaderinc"
uniform vec4 paint_colour : source_color = vec4(0.3, 0.3, 0.8, 1.0);
uniform float load : hint_range(0.0, 1.0) = 0.0;
varying float from_tip;
void vertex() {
	GIVE_HERE;
	from_tip = (0.013 - VERTEX.y) / 0.026;
}
void fragment() {
	float painted = (1.0 - smoothstep(load - 0.025, load, from_tip)) * step(0.01, load);
	ALBEDO = mix(vec3(0.69, 0.57, 0.34), paint_colour.rgb, painted);
	EMISSION = ALBEDO * given.rgb;
	ROUGHNESS = mix(0.9, mix(0.85, 0.22, load), painted);
}
