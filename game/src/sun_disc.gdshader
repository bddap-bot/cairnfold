shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// The sun's disc and its tight corona, turned to the eye: drawn apart from the sky so dragging the sun
// moves it every frame without restarting the sky's radiance update.

uniform vec3 tint : source_color = vec3(1.0, 0.95, 0.85);
uniform float radius = 0.28;

#include "res://src/billboard.gdshaderinc"

void vertex() {
	MODELVIEW_MATRIX = billboard(VIEW_MATRIX, INV_VIEW_MATRIX, MODEL_MATRIX[3].xyz, length(MODEL_MATRIX[0].xyz));
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float disc = smoothstep(radius, radius * 0.8, d);
	float corona = pow(max(1.0 - d, 0.0), 3.0) * 0.5;
	ALBEDO = tint * (disc * 8.0 + corona);
}
