shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

// A soft ring that always faces the eye: a press's pulse (`fill` 1) or a held button's timer, its arc filled to `fill`
// clockwise from the top over a faint track.
uniform vec4 colour : source_color = vec4(1.0, 0.86, 0.5, 1.0);
uniform float radius = 0.02;
uniform float width = 0.0035;
uniform float fill = 1.0;
uniform float track = 0.0;
uniform float alpha = 1.0;
uniform float half_size = 0.06;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0 * half_size;
	float r = length(p);
	float band = 1.0 - smoothstep(width * 0.35, width, abs(r - radius));
	float turn = fract(atan(p.x, -p.y) / TAU + 1.0);
	float lit = turn <= fill ? 1.0 : track;
	ALBEDO = colour.rgb;
	ALPHA = band * lit * alpha * colour.a;
}
