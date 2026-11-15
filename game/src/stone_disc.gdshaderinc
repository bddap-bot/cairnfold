// `span` is in metres. Include after stone_ground.gdshaderinc.
#include "res://src/detail.gdshaderinc"
uniform int style;
uniform float span = 2.0;
uniform vec3 earth : source_color;
uniform vec3 meadow : source_color;

// `uv` runs 0 to 1 across the disc.
vec3 stone_disc(vec2 uv, out float laid, out vec2 slope) {
	vec2 at = uv - 0.5;
	float r = length(at) * 2.0;
	vec2 xz = at * span;
	float d = texture(detail, xz * 0.07).r;
	float fine = texture(detail, xz * 0.45).r;
	float grit = texture(detail, xz * 3.7).r;
	return stone_ground(style, xz, 1.0 - smoothstep(0.5, 1.0, r), meadow, earth, meadow, d, fine, grit, laid, slope);
}
