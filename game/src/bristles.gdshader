shader_type spatial;
uniform vec4 paint_colour : source_color = vec4(0.3, 0.3, 0.8, 1.0);
uniform float load : hint_range(0.0, 1.0) = 0.0;
varying float along;
void vertex() {
	along = (VERTEX.y + 0.013) / 0.026;
}
void fragment() {
	float painted = (1.0 - smoothstep(load - 0.025, load, along)) * step(0.01, load);
	ALBEDO = mix(vec3(0.69, 0.57, 0.34), paint_colour.rgb, painted);
	ROUGHNESS = mix(0.9, mix(0.85, 0.22, load), painted);
}
