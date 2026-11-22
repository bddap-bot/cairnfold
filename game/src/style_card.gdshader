shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

// Rows map linear rgb to rgb (PhotoStyle.TONES).
uniform mat3 tone;
uniform bool strokes;
uniform bool white;

void fragment() {
	vec2 at = UV;
	if (strokes) {
		at = floor(at * vec2(8.0, 6.0)) / vec2(8.0, 6.0);
	}
	float ground = smoothstep(0.52, 0.56, at.y);
	float sun = 1.0 - smoothstep(0.08, 0.1, distance(at, vec2(0.72, 0.25)));
	vec3 sky = white ? vec3(0.62, 0.72, 0.85) : vec3(0.3, 0.5, 0.85);
	vec3 meadow = white ? vec3(0.75) : vec3(0.18, 0.45, 0.1);
	vec3 c = mix(mix(sky, vec3(1.0, 0.92, 0.6), sun), meadow * (0.7 + 0.3 * at.y), ground);
	ALBEDO = c * tone;
}
