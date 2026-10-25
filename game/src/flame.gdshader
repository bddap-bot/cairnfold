shader_type spatial;
render_mode unshaded, cull_disabled;

// A lantern's flame in its colour (COLOR, its Palette.Element.LANTERN swatch, as the wheel shows it).

void vertex() {
	float lift = 0.9 + 0.1 * sin(TIME * 7.0) * sin(TIME * 11.0);
	VERTEX.y = (VERTEX.y + 0.5) * lift - 0.5;
	VERTEX.xz *= 1.0 - max(VERTEX.y, 0.0) * 0.7;
}

void fragment() {
	ALBEDO = pow(COLOR.rgb, vec3(2.2)) * (0.96 + 0.04 * sin(TIME * 7.0) * sin(TIME * 11.0));
}
