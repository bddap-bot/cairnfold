// Stone in its styles (StoneStyles), painted ground laid in its pattern and each boulder one stone of it: a pattern
// layer a style, r height, g each stone's value, b and a its face's normal; per style its tile in metres, moss, and how
// much of its joints is meadow; its stones' tones.
#define STONE_ROOM 8
uniform sampler2DArray stone_patterns : filter_linear_mipmap, repeat_enable;
uniform vec4 stone_look[STONE_ROOM];
uniform vec3 stone_light[STONE_ROOM];
uniform vec3 stone_dark[STONE_ROOM];

// The face of a stone of `style` whose pattern texel is `p`, its moss `green`; d, fine and grit are noise at three
// scales. Painted ground and a boulder share it, so one style reads as one stone on both.
vec3 stone_face(int style, vec4 p, vec3 green, float d, float fine, float grit) {
	float h = p.r;
	float v = p.g;
	float warm = (fract(v * 7.3) - 0.5) * 0.14;
	vec3 face = mix(stone_dark[style], stone_light[style], v) * vec3(1.0 + warm, 1.0, 1.0 - warm);
	// Soil-stained where a stone dips into its joint, grained over its face, flecked with lichen on its crown.
	face *= mix(0.5, 1.0, smoothstep(0.0, 0.6, h)) * (0.8 + fine * 0.4) * (0.85 + grit * 0.3);
	face = mix(face, vec3(0.66, 0.65, 0.52), smoothstep(0.65, 0.9, grit) * smoothstep(0.5, 0.9, h) * 0.12);
	return mix(face, green * 0.55, stone_look[style].y * smoothstep(0.35, 0.75, (1.0 - h) * 0.5 + d * 0.45 + (grit - 0.5) * 0.4));
}

// Stone of `style` laid over `under` as far as `stony` (0 to 1) reaches, its joints filled with `soil` and `green`;
// d, fine and grit are noise at three scales. `laid` is how much shows stone face and `slope` that face's tilt, x
// and z per metre up.
vec3 stone_ground(int style, vec2 xz, float stony, vec3 under, vec3 soil, vec3 green, float d, float fine, float grit, out float laid, out vec2 slope) {
	vec4 look = stone_look[style];
	vec4 p = texture(stone_patterns, vec3(xz / look.x, float(style)));
	float h = p.r;
	float v = p.g;
	vec2 n = p.ba * 2.0 - 1.0;
	slope = n / sqrt(max(1.0 - dot(n, n), 0.04));
	vec3 face = stone_face(style, p, green, d, fine, grit);
	// Toward its edge stone ground loses whole stones, the lowest-valued first, so it frays into the meadow as
	// scattered stones over earthy joints instead of ending in a line.
	float threshold = 0.12 + v * 0.7;
	laid = smoothstep(threshold - 0.04, threshold + 0.04, stony + (d - 0.5) * 0.25 + (fine - 0.5) * 0.15) * smoothstep(0.02, 0.12, h);
	// Joints are shaded soil, grassed in patches.
	vec3 fill = mix(soil * 0.6, green * 0.7, look.z * smoothstep(0.35, 0.65, d + (fine - 0.5) * 0.6));
	vec3 joint = mix(under, fill, smoothstep(0.4, 0.95, stony));
	return mix(joint, face, laid);
}

// A surface's normal `n` tilted by `slope` along its pattern's axes `x` and `z`, all in one space.
vec3 stone_normal(vec3 n, vec3 x, vec3 z, vec2 slope) {
	return normalize(n + x * slope.x + z * slope.y);
}

// A boulder of `style` at world point `at` facing world normal `n`, as one stone of it: the style's tones at `v` (0 to
// 1, the boulder's own), darkening into its pits where `fine` is low, with its lichen and moss, and cracked along its
// pattern's joints, cast along the axis it most faces (one read; worn edges hide the seams), where its style is laid
// in joints (stone_look w); d and fine are noise, coarse and fine.
vec3 stone_rock(int style, vec3 at, vec3 n, float v, vec3 green, float d, float fine) {
	vec4 look = stone_look[style];
	vec3 face = stone_face(style, vec4(mix(0.3, 1.0, fine), clamp(v + (d - 0.5) * 0.3, 0.0, 1.0), 0.5, 0.5), green, d, fine, fine);
	if (look.w == 0.0) {
		return face;
	}
	vec3 a = abs(n);
	vec2 uv = a.y >= max(a.x, a.z) ? at.xz : a.x >= a.z ? at.zy : at.xy;
	float h = texture(stone_patterns, vec3(uv / look.x, float(style))).r;
	return face * mix(0.5, 1.0, smoothstep(0.0, 0.035, h) * look.w);
}
