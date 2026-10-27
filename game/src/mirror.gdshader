shader_type spatial;
render_mode unshaded;

// The glass is a unit disc on its mesh's xz plane. Each eye's reflected camera frames the glass's rectangle, so its
// view maps onto the glass by the glass's own coordinates, turned left for right as a mirror turns them.
uniform sampler2D left_eye : source_color, filter_linear, repeat_disable;
uniform sampler2D right_eye : source_color, filter_linear, repeat_disable;

varying vec2 on_glass;

void vertex() {
	on_glass = vec2(1.0 - VERTEX.x, 1.0 + VERTEX.z) * 0.5;
}

void fragment() {
	ALBEDO = VIEW_INDEX == VIEW_RIGHT ? texture(right_eye, on_glass).rgb : texture(left_eye, on_glass).rgb;
}
