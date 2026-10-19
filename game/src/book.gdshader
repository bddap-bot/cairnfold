shader_type spatial;
render_mode diffuse_lambert_wrap;

// The picture book's binding and the edges of its pages. A cover (`kind` 0) is cloth over board, worn pale at its
// corners and edges, the front stamped in foil with a nest of three eggs in a ring of leaves; a block of pages
// (`kind` 1) shows leaf lines on its sides and a painted fore-edge. `size` is the box's size in metres.

#include "res://src/ground.gdshaderinc"
#include "res://src/bounce.gdshaderinc"

uniform int kind = 0;
uniform vec3 size = vec3(0.16, 0.003, 0.16);
uniform bool front = false;
// For a block of pages: which way its fore-edge faces, +1 the right block's, -1 the left's.
uniform float fore_side = 1.0;
uniform vec3 cloth : source_color = vec3(0.27, 0.42, 0.33);
uniform vec3 leather : source_color = vec3(0.36, 0.21, 0.12);
uniform vec3 foil : source_color = vec3(0.86, 0.71, 0.44);
uniform vec3 egg : source_color = vec3(0.72, 0.84, 0.86);
uniform vec3 paper : source_color = vec3(0.96, 0.9, 0.77);
uniform vec3 edge_paint : source_color = vec3(0.86, 0.6, 0.32);

varying vec3 local;
varying vec3 local_n;
varying vec4 given;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
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

void vertex() {
	local = VERTEX;
	local_n = NORMAL;
	given = given_at((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, normalize(mat3(MODEL_MATRIX) * NORMAL));
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

void fragment() {
	vec3 h = size * 0.5;
	vec3 n = normalize(local_n);
	if (kind == 0) {
		vec2 xz = local.xz;
		vec2 to_edge = h.xz - abs(xz);
		float corner = length(max(vec2(0.013) - to_edge, vec2(0.0))) / 0.013;
		float edge = 1.0 - smoothstep(0.0, 0.0025, min(to_edge.x, to_edge.y));
		float grain = noise(xz * vec2(2600.0, 300.0)) * 0.5 + noise(xz * vec2(300.0, 2600.0)) * 0.5;
		float mottle = noise(xz * 90.0 + float(front) * 7.0);
		vec3 c = cloth * (0.86 + 0.14 * grain) * (0.92 + 0.12 * mottle);
		float worn = clamp(edge * 0.8 + (1.0 - abs(n.y)) * 0.35 + smoothstep(0.7, 0.95, noise(xz * 160.0)) * 0.3, 0.0, 1.0) * (0.45 + 0.55 * noise(xz * 700.0));
		c = mix(c, mix(cloth, vec3(0.78, 0.74, 0.62), 0.45), worn * 0.7);
		float spine = 1.0 - smoothstep(0.022, 0.024, local.x + h.x + (noise(xz * 400.0) - 0.5) * 0.001);
		vec2 out_ = vec2(h.x - local.x, h.z - abs(local.z));
		vec2 o = max(out_, vec2(0.0));
		float cap_d = pow(pow(o.x, 1.6) + pow(o.y, 1.6), 1.0 / 1.6);
		float cap = 1.0 - smoothstep(0.019, 0.0205, cap_d + (noise(xz * 400.0) - 0.5) * 0.0012);
		float hide = max(spine, cap);
		float scuff = smoothstep(0.55, 0.8, noise(xz * 520.0)) * (edge + 0.3);
		vec3 hidec = leather * (0.8 + 0.3 * noise(xz * 260.0)) * mix(1.0, 1.5, clamp(scuff, 0.0, 1.0));
		c = mix(c, hidec, hide);
		float metal = 0.0;
		ROUGHNESS = mix(mix(0.85, 0.95, worn), 0.55, hide);
		if (front && n.y > 0.5) {
			vec2 p = vec2(local.x - 0.004, local.z) / size.x;
			float eggs;
			float s = stamp(p, eggs) * (0.8 + 0.2 * noise(p * 300.0));
			c = mix(c, egg * (0.9 + 0.1 * noise(p * 200.0)), eggs * 0.9);
			c = mix(c, foil, s);
			metal = s * 0.7;
			ROUGHNESS = mix(ROUGHNESS, 0.38, s);
			float bands = 1.0 - smoothstep(0.0006, 0.0012, abs(abs(local.z) - h.z + 0.014));
			c = mix(c, foil, bands * spine);
			float rule = 1.0 - smoothstep(0.0004, 0.0009, abs(local.x + h.x - 0.026));
			c = mix(c, foil, rule * (1.0 - cap) * 0.8);
		}
		ALBEDO = c;
		METALLIC = metal;
	} else {
		vec3 lp = local * size;
		float lines = 0.5 + 0.5 * sin(lp.y / 0.00042 * TAU);
		vec3 c = paper * (0.9 + 0.1 * lines);
		float fore = smoothstep(0.6, 0.9, n.x * fore_side) + smoothstep(0.6, 0.9, abs(n.z));
		float deckle = noise(vec2(lp.z * 300.0 + lp.x * 300.0, lp.y * 2000.0));
		fore *= step(0.25, deckle) * 0.4 + 0.6;
		vec2 at = vec2(lp.z + lp.x, lp.y) * vec2(180.0, 900.0);
		c = mix(c, edge_paint * (0.85 + 0.25 * noise(at)), clamp(fore, 0.0, 1.0) * (0.75 + 0.25 * noise(at * 0.3)));
		ALBEDO = c;
		ROUGHNESS = 0.95;
	}
	SPECULAR = 0.2;
	AO = given.a;
	EMISSION = ALBEDO * given.rgb;
}
