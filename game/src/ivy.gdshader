shader_type spatial;
render_mode cull_disabled;

uniform vec3 backlight : source_color = vec3(0.2, 0.3, 0.06);
// Leaves shrink away over this range of distances: past it they would be specks costing a full leaf each.
uniform float far_begin = 20.0;
uniform float far_end = 35.0;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	VERTEX *= 1.0 - smoothstep(far_begin, far_end, distance(origin, CAMERA_POSITION_WORLD));
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.75;
	BACKLIGHT = backlight;
}
