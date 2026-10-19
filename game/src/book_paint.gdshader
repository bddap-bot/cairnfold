shader_type canvas_item;
render_mode blend_disabled;

// The picture book's fixed paint, which Book bakes once so the book in the hand reads textures rather than painting
// every pixel each frame. `part` 0 is a page's face (`face_seed`, `face_drawn`, `back_face` putting the spine on its
// right): warm paper, a deckled window with an inked frame and painted sprigs, or with no picture an endpaper of little
// leaves. The face is affine in what its window shows, so the bake keeps it as paint + weight * picture: rgb the paint
// (sRGB), alpha the weight. Part 1 is the paper's grain, which the window's painted backdrop reads. Parts 2 and 3 are
// the front cover's top (`board` its size): its albedo (sRGB) with metal in alpha, then its roughness.

#include "res://src/book.gdshaderinc"

uniform float face_seed = 0.0;
uniform bool face_drawn = false;
uniform bool back_face = false;
uniform int part = 0;
uniform vec3 board = vec3(0.155, 0.0042, 0.16);

vec3 encoded(vec3 c) {
	c = clamp(c, 0.0, 1.0);
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}

float fbm(vec2 p) {
	return noise(p) * 0.55 + noise(p * 2.1 + 3.1) * 0.3 + noise(p * 4.3 + 7.7) * 0.15;
}

float box(vec2 p, vec2 c, vec2 h) {
	vec2 d = abs(p - c) - h;
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
}

// A sprig of painted leaves from `root` along `dir`, with a flower at its tip.
vec4 sprig(vec2 p, vec2 root, float dir, float seed, vec3 bloom) {
	if (length(p - root) > 0.15) {
		return vec4(0.0);
	}
	float paint = 0.0;
	vec2 along = vec2(cos(dir), sin(dir));
	vec2 off = p - root;
	float t = clamp(dot(off, along), 0.0, 0.11);
	float bow = sin(t / 0.11 * 3.1) * 0.012;
	vec2 normal = vec2(-along.y, along.x);
	float stem = abs(dot(off, normal) - bow);
	paint = max(paint, (1.0 - smoothstep(0.0008, 0.0018, stem)) * step(dot(off, along), 0.11) * step(0.0, dot(off, along)));
	for (int i = 0; i < 5; i++) {
		float s = 0.02 + float(i) * 0.02;
		float side = (i % 2 == 0) ? 1.0 : -1.0;
		vec2 c = root + along * s + normal * (sin(s / 0.11 * 3.1) * 0.012 + side * 0.009);
		float e = ellipse(p, c, vec2(0.011, 0.0048) * (1.0 - float(i) * 0.08), dir + side * 0.7);
		paint = max(paint, 1.0 - smoothstep(-0.25, 0.1, e));
	}
	vec2 tip = root + along * 0.118;
	float petals = 0.0;
	for (int i = 0; i < 5; i++) {
		float a = float(i) / 5.0 * TAU + seed;
		petals = max(petals, 1.0 - smoothstep(-0.2, 0.15, ellipse(p, tip + vec2(cos(a), sin(a)) * 0.0055, vec2(0.0055, 0.0035), a)));
	}
	float heart = 1.0 - smoothstep(0.0015, 0.0028, length(p - tip));
	vec3 c = mix(srgb_to_linear(LEAF), bloom, petals);
	c = mix(c, vec3(0.95, 0.78, 0.35), heart);
	return vec4(c, max(paint, max(petals, heart)));
}

vec3 page(vec2 p, bool drawn, vec3 picture, float seed, float spine_dist) {
	float grain = noise(p * 140.0 + seed) * 0.7 + noise(p * 300.0 + seed) * 0.3;
	vec3 c = srgb_to_linear(PAPER) * (0.95 + 0.06 * grain);
	c *= mix(0.5, 1.0, smoothstep(0.0, 0.2, spine_dist)) * mix(0.85, 1.0, smoothstep(0.0, 0.06, spine_dist));
	float edge_dist = min(min(p.x, 1.0 - p.x), min(p.y, 1.0 - p.y));
	c *= mix(0.86, 1.0, smoothstep(0.0, 0.025 + 0.01 * noise(p * 40.0), edge_dist));
	if (!drawn) {
		vec2 cell = p * 7.0;
		vec2 id = floor(cell);
		vec2 f = fract(cell) - 0.5;
		float a = hash(id + seed) * TAU;
		float l = 1.0 - smoothstep(-0.2, 0.15, ellipse(f, vec2(0.0), vec2(0.28, 0.12), a));
		float dot_ = 1.0 - smoothstep(0.04, 0.07, length(fract(cell + 0.5) - 0.5));
		c = mix(c, srgb_to_linear(LEAF) * 0.9, l * 0.85);
		c = mix(c, vec3(0.82, 0.48, 0.42), dot_ * 0.8);
		return c;
	}
	float wob = (fbm(p * 26.0 + seed * 3.0) - 0.5) * 0.026 + (noise(p * 120.0 + seed) - 0.5) * 0.006;
	float d = box(p, WINDOW_CENTRE, WINDOW_HALF - 0.02) - 0.02 + wob;
	float inside = 1.0 - smoothstep(-0.002, 0.002, d);
	vec3 pic = picture * (0.96 + 0.07 * grain);
	float pool = smoothstep(-0.018, 0.0, d) * inside;
	pic *= 1.0 - pool * 0.18;
	c = mix(c, pic, inside);
	float shade = smoothstep(0.03, 0.0, d - 0.004) * (1.0 - inside);
	c *= 1.0 - shade * 0.22;
	float frame_d = d - 0.02 + (noise(p * 60.0 + seed) - 0.5) * 0.003;
	float line = 1.0 - smoothstep(0.0012, 0.0028, abs(frame_d));
	line *= 0.7 + 0.3 * noise(p * 90.0);
	c = mix(c, srgb_to_linear(INK), line * 0.85);
	float rim = 1.0 - smoothstep(0.0, 0.004, abs(d + 0.001));
	c = mix(c, mix(srgb_to_linear(INK), srgb_to_linear(LEAF), 0.4), rim * 0.55);
	vec3 bloom = mix(vec3(0.93, 0.6, 0.66), vec3(0.98, 0.84, 0.45), hash(vec2(seed, 2.0)));
	vec4 s1 = sprig(p, vec2(0.035, 0.95), -0.8 + seed * 0.1, seed, bloom);
	vec4 s2 = sprig(p, vec2(0.975, 0.045), 2.3, seed + 1.0, mix(bloom, vec3(0.7, 0.75, 0.95), 0.5));
	vec4 s3 = sprig(p, vec2(0.66, 0.955), 3.2, seed + 2.0, bloom);
	c = mix(c, s1.rgb, s1.a * 0.85);
	c = mix(c, s2.rgb, s2.a * 0.85);
	c = mix(c, s3.rgb, s3.a * 0.7);
	return c;
}

void fragment() {
	float spine_dist = back_face ? 1.0 - UV.x : UV.x;
	if (part == 0) {
		vec3 paint = page(UV, face_drawn, vec3(0.0), face_seed, spine_dist);
		COLOR = vec4(encoded(paint), face_drawn ? page(UV, face_drawn, vec3(1.0), face_seed, spine_dist).r - paint.r : 0.0);
	} else if (part == 1) {
		COLOR = vec4(noise(UV * 140.0 + face_seed) * 0.7 + noise(UV * 300.0 + face_seed) * 0.3, 0.0, 0.0, 1.0);
	} else {
		float rough;
		float metal;
		vec3 c = cover(vec3(UV.x - 0.5, 0.0, UV.y - 0.5) * board, vec3(0.0, 1.0, 0.0), board, true, rough, metal);
		COLOR = part == 2 ? vec4(encoded(c), metal) : vec4(rough, 0.0, 0.0, 1.0);
	}
}
