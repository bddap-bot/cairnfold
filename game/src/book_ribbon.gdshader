shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap;

// The book's ribbon bookmark, hanging from between its pages and swaying; while the book is shut it glows softly,
// asking to be pulled. VERTEX.z runs down the ribbon from where it leaves the pages.

#include "res://src/ground.gdshaderinc"
#include "res://src/bounce.gdshaderinc"

uniform float glow = 0.0;
uniform vec3 colour : source_color = vec3(0.55, 0.08, 0.16);

varying vec4 given;

void vertex() {
	float v = clamp(VERTEX.z / 0.07, 0.0, 1.0);
	float sway = sin(TIME * 1.9 + v * 2.6) * 0.012 * v * v + sin(TIME * 3.1 + v * 5.0) * 0.003 * v;
	VERTEX.x += sway;
	VERTEX.y -= v * v * 0.02;
	given = given_at((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, normalize(mat3(MODEL_MATRIX) * NORMAL));
}

void fragment() {
	float notch = UV.y > 0.93 ? step(abs(UV.x - 0.5) * 2.0, (UV.y - 0.93) / 0.07) : 0.0;
	if (notch > 0.5) {
		discard;
	}
	float sheen = 0.7 + 0.3 * pow(abs(sin(UV.x * 3.14159)), 0.5) + 0.12 * sin(UV.y * 60.0 + UV.x * 9.0);
	ALBEDO = colour * sheen;
	ROUGHNESS = 0.28;
	SPECULAR = 0.65;
	ANISOTROPY = 0.6;
	float pulse = 0.55 + 0.45 * sin(TIME * 2.4);
	AO = given.a;
	EMISSION = ALBEDO * given.rgb + mix(colour, vec3(1.0, 0.7, 0.35), 0.35) * glow * pulse * 0.75;
}
