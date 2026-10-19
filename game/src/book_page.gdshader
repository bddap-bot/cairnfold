shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap;

// A leaf of the picture book, hinged at the spine (x 0) and `width` wide: turned `angle` (0 on the right, PI on the
// left), its free edge lagging as paper does by `bend`. Each face is an illustrated page: warm paper, a picture
// (`*_picture`, a live LessonScene) inked over a painted backdrop in a deckled window with an inked frame and sprigs,
// or, with no picture, an endpaper of little leaves. `wash_*` is the picture's sky, `horizon_*` where its horizon
// lies, `fade` its loop's fade.

#include "res://src/ground.gdshaderinc"
#include "res://src/bounce.gdshaderinc"

uniform float width = 0.15;
uniform float angle = 0.0;
uniform float bend = 0.0;
// How high a resting leaf bows up out of the gutter, as a bound page does.
uniform float gutter_bow = 0.0;
uniform sampler2D front_picture : source_color, filter_linear, repeat_disable;
uniform sampler2D back_picture : source_color, filter_linear, repeat_disable;
uniform bool front_drawn = false;
uniform bool back_drawn = false;
uniform vec3 front_wash : source_color = vec3(0.8, 0.86, 0.86);
uniform vec3 back_wash : source_color = vec3(0.8, 0.86, 0.86);
uniform float front_horizon = 0.5;
uniform float back_horizon = 0.5;
uniform float front_fade = 0.0;
uniform float back_fade = 0.0;
uniform float front_seed = 0.0;
uniform float back_seed = 1.0;
uniform vec3 paper : source_color = vec3(0.97, 0.91, 0.78);
uniform vec3 ink : source_color = vec3(0.33, 0.3, 0.24);
uniform vec3 leaf : source_color = vec3(0.47, 0.6, 0.41);

varying vec4 given;

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

float fbm(vec2 p) {
	return noise(p) * 0.55 + noise(p * 2.1 + 3.1) * 0.3 + noise(p * 4.3 + 7.7) * 0.15;
}

float ellipse(vec2 p, vec2 c, vec2 r, float a) {
	p -= c;
	p = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * p;
	return length(p / r) - 1.0;
}

float box(vec2 p, vec2 c, vec2 h) {
	vec2 d = abs(p - c) - h;
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
}

void vertex() {
	float x = VERTEX.x;
	float k = bend * sin(angle) / width;
	float a = angle - k * x;
	vec2 at = abs(k) < 1e-4 ? vec2(cos(angle), sin(angle)) * x : vec2(sin(angle) - sin(a), cos(a) - cos(angle)) / k;
	float rise = gutter_bow * sin(min(x / (width * 0.3), 1.0) * PI * 0.5) * (1.0 - 0.35 * smoothstep(0.3, 1.0, x / width));
	float slope = gutter_bow * cos(min(x / (width * 0.3), 1.0) * PI * 0.5) * PI * 0.5 / (width * 0.3) * step(x, width * 0.3);
	vec2 up_ = vec2(-sin(angle), cos(angle)) * (angle > PI * 0.5 ? -1.0 : 1.0);
	VERTEX = vec3(at.x + up_.x * rise, at.y + up_.y * rise + VERTEX.y, VERTEX.z);
	NORMAL = normalize(vec3(-sin(a), cos(a), 0.0) - vec3(cos(angle), sin(angle), 0.0) * slope);
	given = given_at((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, normalize(mat3(MODEL_MATRIX) * NORMAL));
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
	vec3 c = mix(leaf, bloom, petals);
	c = mix(c, vec3(0.95, 0.78, 0.35), heart);
	return vec4(c, max(paint, max(petals, heart)));
}

// The painted world behind a page's picture: a watercolour sky of the page's `wash` over the horizon at `horizon`
// (0 the picture's top, 1 its foot), soft clouds, two bands of far hills and a brushed meadow running to the
// picture's foot, which a camera looking down sees all of.
vec3 backdrop(vec2 uv, vec3 wash, float horizon, float seed, float grain) {
	float h = uv.y - horizon;
	float far = horizon - 0.07 - 0.05 * noise(vec2(uv.x * 2.5 + seed, 0.0)) + 0.025 * sin(uv.x * 5.0 + seed);
	vec3 c;
	if (uv.y < far + 0.01) {
		vec3 glow = vec3(1.0, 0.84, 0.56);
		c = mix(wash * vec3(0.78, 0.88, 1.0), mix(wash, glow, 0.75), smoothstep(-0.8, 0.0, h));
		float billow = noise(uv * vec2(3.2, 7.0) + vec2(seed * 2.3, 0.0));
		float cloud = smoothstep(0.52, 0.72, billow) * smoothstep(0.0, -0.18, h);
		c = mix(c, vec3(1.0, 0.97, 0.9) * mix(1.0, 0.93, smoothstep(0.66, 0.72, billow)), cloud * 0.75);
	} else {
		vec3 meadow = vec3(0.7, 0.8, 0.36);
		float patch_ = noise(uv * 6.0 + seed);
		c = mix(meadow * 0.9, meadow * 1.12 + vec3(0.04, 0.03, 0.0), noise(vec2(uv.x * 9.0, uv.y * 55.0) + seed));
		c = mix(c, vec3(0.9, 0.8, 0.46), smoothstep(0.5, 0.8, patch_) * 0.6);
		c = mix(c, paper, smoothstep(0.3, 0.12, patch_) * 0.5);
		c *= mix(0.82, 1.0, smoothstep(1.0, horizon + 0.1, uv.y));
		float near = horizon - 0.02 - 0.06 * noise(vec2(uv.x * 3.7 + seed * 1.3, 4.0));
		vec3 hills_far = vec3(0.66, 0.74, 0.74);
		vec3 hills_near = vec3(0.56, 0.7, 0.36);
		vec3 hills = mix(hills_far * (0.92 + 0.12 * grain), hills_far * 0.8, smoothstep(0.008, 0.0, abs(uv.y - far)) * 0.4);
		hills = mix(hills, hills_near * (0.92 + 0.14 * grain), smoothstep(near, near + 0.006, uv.y));
		hills = mix(hills, hills_near * 0.78, smoothstep(0.008, 0.0, abs(uv.y - near)) * 0.45);
		c = mix(hills, c, smoothstep(horizon + 0.02, horizon + 0.06, uv.y));
		if (uv.y < far + 0.006) {
			c = mix(wash, c, smoothstep(far, far + 0.006, uv.y));
		}
	}
	return max(mix(vec3(dot(c, vec3(0.3, 0.55, 0.15))), c, 1.8), vec3(0.0));
}

vec3 page(vec2 p, bool drawn, sampler2D picture, vec3 wash, float horizon, float fade, float seed, float spine_dist) {
	float grain = noise(p * 140.0 + seed) * 0.7 + noise(p * 300.0 + seed) * 0.3;
	vec3 c = paper * (0.95 + 0.06 * grain);
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
		c = mix(c, leaf * 0.9, l * 0.85);
		c = mix(c, vec3(0.82, 0.48, 0.42), dot_ * 0.8);
		return c;
	}
	vec2 centre = vec2(0.5, 0.48);
	vec2 half_ = vec2(0.44, 0.41);
	float wob = (fbm(p * 26.0 + seed * 3.0) - 0.5) * 0.026 + (noise(p * 120.0 + seed) - 0.5) * 0.006;
	float d = box(p, centre, half_ - 0.02) - 0.02 + wob;
	float inside = 1.0 - smoothstep(-0.002, 0.002, d);
	vec2 uv = (p - (centre - half_)) / (2.0 * half_);
	vec3 pic = c;
	if (inside > 0.0) {
		vec4 shot = texture(picture, clamp(uv, vec2(0.0), vec2(1.0)));
		float outline = clamp(fwidth(shot.a) * 1.8, 0.0, 1.0);
		vec3 ink_shot = max(mix(vec3(dot(shot.rgb, vec3(0.3, 0.55, 0.15))), shot.rgb, 1.7), vec3(0.0)) * 0.9;
		float shown = 1.0 - fade;
		float cover = shot.a * shown;
		pic = cover > 0.99 ? ink_shot : mix(backdrop(uv, wash, horizon, seed, grain), ink_shot, cover);
		pic = mix(pic, ink * 0.8, outline * 0.8 * shown);
		pic *= 0.96 + 0.07 * grain;
	}
	float pool = smoothstep(-0.018, 0.0, d) * inside;
	pic *= 1.0 - pool * 0.18;
	c = mix(c, pic, inside);
	float shade = smoothstep(0.03, 0.0, d - 0.004) * (1.0 - inside);
	c *= 1.0 - shade * 0.22;
	float frame_d = d - 0.02 + (noise(p * 60.0 + seed) - 0.5) * 0.003;
	float line = 1.0 - smoothstep(0.0012, 0.0028, abs(frame_d));
	line *= 0.7 + 0.3 * noise(p * 90.0);
	c = mix(c, ink, line * 0.85);
	float rim = 1.0 - smoothstep(0.0, 0.004, abs(d + 0.001));
	c = mix(c, mix(ink, leaf, 0.4), rim * 0.55);
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
	bool up = FRONT_FACING;
	vec2 p = up ? UV : vec2(1.0 - UV.x, UV.y);
	float spine_dist = UV.x;
	vec3 c = up ? page(p, front_drawn, front_picture, front_wash, front_horizon, front_fade, front_seed, spine_dist)
		: page(p, back_drawn, back_picture, back_wash, back_horizon, back_fade, back_seed, spine_dist);
	ALBEDO = c;
	ROUGHNESS = 0.92;
	SPECULAR = 0.15;
	AO = given.a;
	EMISSION = ALBEDO * given.rgb + ALBEDO * 0.08;
}
