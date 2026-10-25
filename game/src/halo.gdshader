shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// The glow a lantern hangs in the air: a soft disc turned to the eye, in its glow colour (COLOR.rgb), wider and stronger
// (COLOR.a, half a lit lantern's) the brighter it burns.

#include "res://src/billboard.gdshaderinc"

void vertex() {
	MODELVIEW_MATRIX = billboard(VIEW_MATRIX, INV_VIEW_MATRIX, MODEL_MATRIX[3].xyz, length(MODEL_MATRIX[0].xyz));
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float f = max(1.0 - d, 0.0);
	ALBEDO = pow(COLOR.rgb, vec3(2.2)) * COLOR.a * 2.0 * f * f * 0.55;
}
