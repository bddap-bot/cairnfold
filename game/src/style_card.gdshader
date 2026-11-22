shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform sampler2D lens : source_color, filter_linear;
// Rows map linear rgb to rgb (PhotoStyle.TONES).
uniform mat3 tone;
uniform bool strokes;
uniform bool white;

void fragment() {
	vec3 c = texture(lens, UV).rgb;
	if (strokes) {
		c = floor(c * 5.0 + 0.5) / 5.0;
	}
	if (white) {
		c = vec3(0.45 + 0.5 * dot(c, vec3(0.2126, 0.7152, 0.0722)));
	}
	ALBEDO = c * tone;
}
