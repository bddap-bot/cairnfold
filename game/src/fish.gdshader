shader_type spatial;
render_mode blend_mix, depth_draw_never, diffuse_lambert_wrap, specular_disabled, shadows_disabled, cull_disabled;

// Drawn after the pond's surface, which would hide them in deep water: the water's tint over them stands in
// for it. INSTANCE_CUSTOM: x its own seed, y its speed over a cruise's.
uniform vec3 back : source_color = vec3(0.32, 0.3, 0.26);
uniform vec3 water : source_color = vec3(0.16, 0.42, 0.5);

varying float top;

void vertex() {
	float along = UV.y;
	float pace = INSTANCE_CUSTOM.y;
	float beat = TIME * (5.0 + 7.0 * pace) + INSTANCE_CUSTOM.x;
	VERTEX.x += sin(beat - along * 3.0) * 0.035 * (0.2 + 0.8 * along * along) * (0.6 + 0.4 * min(pace, 2.0));
	top = smoothstep(0.0, 0.02, VERTEX.y);
}

void fragment() {
	float patch = smoothstep(0.1, 0.3, sin(UV.y * 11.0 + COLOR.g * 23.0) + 0.6 * sin(UV.y * 5.0 + COLOR.b * 17.0));
	vec3 skin = pow(COLOR.rgb, vec3(2.2));
	vec3 c = mix(mix(skin, vec3(0.9, 0.85, 0.75), 0.4), skin, top);
	c = mix(c, vec3(0.92, 0.88, 0.8), top * patch * 0.45 * (1.0 - UV.x));
	ALBEDO = mix(c, water, 0.18);
	ALPHA = 0.88;
}
