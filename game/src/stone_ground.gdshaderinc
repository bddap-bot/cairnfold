// Indexed by StoneStyles style. stone_patterns layer per style: r height, g the stone's value, ba its face normal.
// stone_look: x tile in metres, y moss, z grassed share of joints, w boulder roughness.
#define STONE_ROOM 8
uniform sampler2DArray stone_patterns : filter_linear_mipmap, repeat_enable;
uniform vec4 stone_look[STONE_ROOM];
uniform vec3 stone_light[STONE_ROOM];
uniform vec3 stone_dark[STONE_ROOM];

// d, fine, grit: noise at three scales.
vec3 stone_face(int style, vec4 p, vec3 green, float d, float fine, float grit) {
	float h = p.r;
	float v = p.g;
	float warm = (fract(v * 7.3) - 0.5) * 0.14;
	vec3 face = mix(stone_dark[style], stone_light[style], v) * vec3(1.0 + warm, 1.0, 1.0 - warm);
	face *= mix(0.5, 1.0, smoothstep(0.0, 0.6, h)) * (0.8 + fine * 0.4) * (0.85 + grit * 0.3);
	face = mix(face, vec3(0.66, 0.65, 0.52), smoothstep(0.65, 0.9, grit) * smoothstep(0.5, 0.9, h) * 0.12);
	return mix(face, green * 0.55, stone_look[style].y * smoothstep(0.35, 0.75, (1.0 - h) * 0.5 + d * 0.45 + (grit - 0.5) * 0.4));
}

// `stony` in 0..1. `laid` is the share showing stone face; `slope` that face's tilt, x and z per metre up.
vec3 stone_ground(int style, vec2 xz, float stony, vec3 under, vec3 soil, vec3 green, float d, float fine, float grit, out float laid, out vec2 slope) {
	vec4 look = stone_look[style];
	vec4 p = texture(stone_patterns, vec3(xz / look.x, float(style)));
	float h = p.r;
	float v = p.g;
	vec2 n = p.ba * 2.0 - 1.0;
	slope = n / sqrt(max(1.0 - dot(n, n), 0.04));
	vec3 face = stone_face(style, p, green, d, fine, grit);
	// Lowest-valued stones drop first, so the edge frays into scattered stones instead of ending in a line.
	float threshold = 0.12 + v * 0.7;
	laid = smoothstep(threshold - 0.04, threshold + 0.04, stony + (d - 0.5) * 0.25 + (fine - 0.5) * 0.15) * smoothstep(0.02, 0.12, h);
	vec3 fill = mix(soil * 0.6, green * 0.7, look.z * smoothstep(0.35, 0.65, d + (fine - 0.5) * 0.6));
	vec3 joint = mix(under, fill, smoothstep(0.4, 0.95, stony));
	return mix(joint, face, laid);
}

// n, x and z in one space; x and z are the pattern's axes.
vec3 stone_normal(vec3 n, vec3 x, vec3 z, vec2 slope) {
	return normalize(n + x * slope.x + z * slope.y);
}

// `v` in 0..1.
vec3 stone_rock(int style, float v, vec3 green, float d, float fine) {
	return stone_face(style, vec4(mix(0.3, 1.0, fine), clamp(v + (d - 0.5) * 0.3, 0.0, 1.0), 0.5, 0.5), green, d, fine, fine);
}
