// The picture book's paint, shared by its shaders and the bake (book_paint.gdshader, Book): the paper, ink and cover
// colours (sRGB), where a page's picture window sits in the page's coordinates (x from the spine, y down the page),
// and a cover's stamp; the cover's cloth and leather are Book's (CLOTH, LEATHER), which the wheel's icon draws too.
const vec3 PAPER = vec3(0.97, 0.91, 0.78);
const vec3 INK = vec3(0.33, 0.3, 0.24);
const vec3 LEAF = vec3(0.47, 0.6, 0.41);
const vec3 FOIL = vec3(0.86, 0.71, 0.44);
const vec3 EGG = vec3(0.72, 0.84, 0.86);
const vec2 WINDOW_CENTRE = vec2(0.5, 0.48);
const vec2 WINDOW_HALF = vec2(0.44, 0.41);

vec2 window_uv(vec2 p) {
	return (p - (WINDOW_CENTRE - WINDOW_HALF)) / (2.0 * WINDOW_HALF);
}

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

// Sine-free, so it stays smooth at the mobile renderer's precision.
float hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float ellipse(vec2 p, vec2 c, vec2 r, float a) {
	p -= c;
	p = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * p;
	return length(p / r) - 1.0;
}

// The stamp on the front, in units of the cover's width from its centre, y down the cover.
float stamp(vec2 p, out float eggs) {
	float r = length(p);
	float ring = 1.0 - smoothstep(0.006, 0.011, abs(r - 0.31));
	float leaves = 0.0;
	for (int i = 0; i < 14; i++) {
		float a = float(i) / 14.0 * TAU + 0.12;
		vec2 c = vec2(cos(a), sin(a)) * 0.31;
		float side = (i % 2 == 0) ? 1.0 : -1.0;
		leaves = max(leaves, 1.0 - smoothstep(-0.05, 0.05, ellipse(p, c + vec2(-sin(a), cos(a)) * 0.0 + vec2(cos(a), sin(a)) * 0.035 * side, vec2(0.042, 0.016), a + 1.2 * side) * 4.0));
	}
	vec2 q = p - vec2(0.0, 0.06);
	float bowl = ellipse(q, vec2(0.0), vec2(0.19, 0.095), 0.0);
	float nest = (1.0 - smoothstep(-0.02, 0.02, bowl)) * step(-0.02, q.y);
	float twigs = 0.55 + 0.45 * sin((q.x * 1.3 + q.y * 3.5) * 120.0 + noise(q * 60.0) * 3.0);
	nest *= mix(1.0, twigs, 0.7);
	float rim = 1.0 - smoothstep(0.004, 0.009, abs(bowl));
	eggs = 0.0;
	float outline = 0.0;
	for (int i = 0; i < 3; i++) {
		vec2 c = vec2(float(i - 1) * 0.075, 0.03 - (i == 1 ? 0.03 : 0.0));
		float e = ellipse(p, c, vec2(0.043, 0.055), float(i - 1) * 0.3);
		eggs = max(eggs, 1.0 - smoothstep(-0.03, 0.03, e * 3.0));
		outline = max(outline, 1.0 - smoothstep(0.02, 0.06, abs(e)));
	}
	return max(max(ring, leaves), max(max(nest, rim) * (1.0 - eggs), outline * eggs));
}

// A cover's cloth over board at `local` on the face with normal `n`, `size` the board: leather at the spine and
// corners, worn pale at its edges, the front's top stamped in foil. Linear albedo, with its roughness and metal.
vec3 cover(vec3 local, vec3 n, vec3 size, bool front, vec3 cloth, vec3 leather, out float rough, out float metal) {
	vec3 h = size * 0.5;
	vec2 xz = local.xz;
	vec2 to_edge = h.xz - abs(xz);
	float corner = length(max(vec2(0.013) - to_edge, vec2(0.0))) / 0.013;
	float edge = 1.0 - smoothstep(0.0, 0.0025, min(to_edge.x, to_edge.y));
	float grain = noise(xz * vec2(2600.0, 300.0)) * 0.5 + noise(xz * vec2(300.0, 2600.0)) * 0.5;
	float mottle = noise(xz * 90.0 + float(front) * 7.0);
	vec3 c = srgb_to_linear(cloth) * (0.86 + 0.14 * grain) * (0.92 + 0.12 * mottle);
	float worn = clamp(edge * 0.8 + (1.0 - abs(n.y)) * 0.35 + smoothstep(0.7, 0.95, noise(xz * 160.0)) * 0.3, 0.0, 1.0) * (0.45 + 0.55 * noise(xz * 700.0));
	c = mix(c, mix(srgb_to_linear(cloth), vec3(0.78, 0.74, 0.62), 0.45), worn * 0.7);
	float spine = 1.0 - smoothstep(0.022, 0.024, local.x + h.x + (noise(xz * 400.0) - 0.5) * 0.001);
	vec2 out_ = vec2(h.x - local.x, h.z - abs(local.z));
	vec2 o = max(out_, vec2(0.0));
	float cap_d = pow(pow(o.x, 1.6) + pow(o.y, 1.6), 1.0 / 1.6);
	float cap = 1.0 - smoothstep(0.019, 0.0205, cap_d + (noise(xz * 400.0) - 0.5) * 0.0012);
	float hide = max(spine, cap);
	float scuff = smoothstep(0.55, 0.8, noise(xz * 520.0)) * (edge + 0.3);
	vec3 hidec = srgb_to_linear(leather) * (0.8 + 0.3 * noise(xz * 260.0)) * mix(1.0, 1.5, clamp(scuff, 0.0, 1.0));
	c = mix(c, hidec, hide);
	metal = 0.0;
	rough = mix(mix(0.85, 0.95, worn), 0.55, hide);
	if (front && n.y > 0.5) {
		vec2 p = vec2(local.x - 0.004, local.z) / size.x;
		float eggs;
		float s = stamp(p, eggs) * (0.8 + 0.2 * noise(p * 300.0));
		c = mix(c, srgb_to_linear(EGG) * (0.9 + 0.1 * noise(p * 200.0)), eggs * 0.9);
		c = mix(c, srgb_to_linear(FOIL), s);
		metal = s * 0.7;
		rough = mix(rough, 0.38, s);
		float bands = 1.0 - smoothstep(0.0006, 0.0012, abs(abs(local.z) - h.z + 0.014));
		c = mix(c, srgb_to_linear(FOIL), bands * spine);
		float rule = 1.0 - smoothstep(0.0004, 0.0009, abs(local.x + h.x - 0.026));
		c = mix(c, srgb_to_linear(FOIL), rule * (1.0 - cap) * 0.8);
	}
	return c;
}
