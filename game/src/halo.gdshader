shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// COLOR.a: half the square root of the lamp's strength (fittings.gd).

#include "res://src/billboard.gdshaderinc"

void vertex() {
	MODELVIEW_MATRIX = billboard(VIEW_MATRIX, INV_VIEW_MATRIX, MODEL_MATRIX[3].xyz, length(MODEL_MATRIX[0].xyz));
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float f = max(1.0 - d, 0.0);
	ALBEDO = pow(COLOR.rgb, vec3(2.2)) * COLOR.a * 2.0 * f * f * 0.55;
}
