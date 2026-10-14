shader_type spatial;
render_mode cull_disabled, specular_disabled, diffuse_lambert_wrap;

// INSTANCE_CUSTOM: x the wingbeat's phase, y its swing and z the angle it swings about, in radians up from flat.
uniform vec3 body : source_color = vec3(0.16, 0.13, 0.12);

varying float edge;
varying float part;

void vertex() {
	edge = UV.x;
	part = UV.y;
	if (part < 1.5) {
		// Hindwings trail the forewings a little, as real ones do.
		float a = INSTANCE_CUSTOM.z + INSTANCE_CUSTOM.y * sin(INSTANCE_CUSTOM.x - part * 0.5);
		float side = sign(VERTEX.x);
		float r = abs(VERTEX.x);
		VERTEX.x = side * r * cos(a);
		VERTEX.y += r * sin(a);
		NORMAL = vec3(-side * sin(a), cos(a), 0.0);
	}
}

void fragment() {
	vec3 wing = COLOR.rgb * mix(0.7, 1.0, smoothstep(0.0, 0.35, edge)) * (part > 0.5 ? 0.88 : 1.0);
	wing = mix(wing, wing * 0.25, smoothstep(0.82, 0.94, edge));
	bool is_body = part > 1.5;
	ALBEDO = is_body ? body : wing;
	BACKLIGHT = is_body ? vec3(0.0) : wing * 0.6;
	ROUGHNESS = 0.9;
}
