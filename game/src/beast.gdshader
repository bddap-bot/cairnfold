shader_type spatial;
render_mode diffuse_lambert_wrap, shadows_disabled;

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = COLOR.r < 0.1 ? 0.3 : 0.9;
	SPECULAR = COLOR.r < 0.1 ? 0.6 : 0.2;
	RIM = 0.25;
	RIM_TINT = 0.6;
}
