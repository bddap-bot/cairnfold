shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// The glow a lantern hangs in the air: a soft disc turned to the eye, keeping the instance's scale.

uniform vec3 tint : source_color = vec3(1.0, 0.62, 0.28);

void vertex() {
	float scale = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * scale, INV_VIEW_MATRIX[1] * scale, INV_VIEW_MATRIX[2] * scale, MODEL_MATRIX[3]);
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float f = max(1.0 - d, 0.0);
	ALBEDO = tint * f * f * 0.55;
}
