shader_type spatial;
render_mode cull_disabled;
#include "res://src/ground.gdshaderinc"
#include "res://src/bounce.gdshaderinc"
varying vec4 given;
uniform vec4 paint_colour : source_color = vec4(0.3, 0.3, 0.8, 1.0);
uniform bool stained = false;
void vertex() {
	given = given_at((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, normalize(mat3(MODEL_MATRIX) * NORMAL));
}
void fragment() {
	float weave = sin(UV.x * 320.0) * sin(UV.y * 160.0);
	float smear = (1.0 - smoothstep(0.14, 0.35, abs(UV.y - 0.5))) * (1.0 - smoothstep(0.3, 0.48, abs(UV.x - 0.5)));
	ALBEDO = mix(vec3(0.72, 0.66, 0.52), paint_colour.rgb, stained ? smear * 0.8 : 0.0) * (0.96 + 0.04 * weave);
	EMISSION = ALBEDO * given.rgb;
	ROUGHNESS = 0.95;
}
