shader_type spatial;
render_mode unshaded, cull_disabled;

void vertex() {
	float lift = 0.9 + 0.1 * sin(TIME * 7.0) * sin(TIME * 11.0);
	VERTEX.y = (VERTEX.y + 0.5) * lift - 0.5;
	VERTEX.xz *= 1.0 - max(VERTEX.y, 0.0) * 0.7;
}

void fragment() {
	ALBEDO = vec3(1.0, 0.8, 0.5);
	EMISSION = vec3(1.0, 0.68, 0.32) * 2.4 * (0.96 + 0.04 * sin(TIME * 7.0) * sin(TIME * 11.0));
}
