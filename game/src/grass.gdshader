shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;

uniform vec3 root_color : source_color = vec3(0.12, 0.30, 0.07);
uniform vec3 tip_lush : source_color = vec3(0.45, 0.68, 0.18);
uniform vec3 tip_dry : source_color = vec3(0.78, 0.78, 0.32);
uniform float wind_strength = 0.12;

varying float tip;
varying float dryness;

void vertex() {
	tip = UV.y;
	dryness = INSTANCE_CUSTOM.x;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = sin(TIME * 1.3 + w.x * 0.35 + w.z * 0.22) + 0.4 * sin(TIME * 2.9 + w.z * 0.9);
	VERTEX.x += sway * wind_strength * tip * tip;
	VERTEX.z += sway * wind_strength * 0.5 * tip * tip;
	NORMAL = mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.6);
}

void fragment() {
	vec3 top = mix(tip_lush, tip_dry, dryness);
	ALBEDO = mix(root_color, top, tip) * COLOR.rgb;
	ROUGHNESS = 0.9;
	BACKLIGHT = vec3(0.35, 0.45, 0.1) * tip;
}
