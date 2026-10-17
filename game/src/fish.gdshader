shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled, shadows_disabled, cull_disabled;

// INSTANCE_CUSTOM: x its own seed, y its speed over a cruise's.
uniform vec3 back : source_color = vec3(0.32, 0.3, 0.26);

varying float top;

void vertex() {
	float along = UV.y;
	float pace = INSTANCE_CUSTOM.y;
	float beat = TIME * (5.0 + 7.0 * pace) + INSTANCE_CUSTOM.x;
	float sway = sin(beat - along * 3.0) * 0.022 * (0.2 + 0.8 * along * along) * (0.6 + 0.4 * min(pace, 2.0));
	VERTEX.x += sway;
	top = smoothstep(0.0, 0.02, VERTEX.y);
}

void fragment() {
	float spot = step(0.55, fract(sin(dot(floor(UV.y * 4.0) + COLOR.r * 7.0, 12.9898)) * 43758.5453));
	vec3 belly = mix(COLOR.rgb, vec3(0.98, 0.94, 0.86), 0.35);
	vec3 c = mix(belly, COLOR.rgb, top);
	c = mix(c, back, top * spot * 0.35 * (1.0 - UV.x));
	ALBEDO = c;
	ROUGHNESS = 0.6;
}
