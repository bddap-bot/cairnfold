#[vertex]
#version 450

layout(location = 0) out vec2 uv;

void main() {
	uv = vec2((gl_VertexIndex << 1) & 2, gl_VertexIndex & 2);
	gl_Position = vec4(uv * 2.0 - 1.0, 0.0, 1.0);
}

#[fragment]
#version 450

layout(location = 0) in vec2 uv;
layout(location = 0) out vec4 colour;
layout(set = 0, binding = 0) uniform sampler2D seen;
// A pipeline of its own lays daubs, so the eyes' Kuwahara pass carries none of their registers.
layout(constant_id = 0) const bool DAUBS = false;

// The scene's colour is held as the square root of its light (scripts/engine.patch, scene_encode).
vec3 light(vec2 at) {
	vec3 c = texture(seen, at).rgb;
	return c * c;
}

// `tone` rows map linear rgb to rgb; `brush`: Kuwahara's reach in texels (x, y), samples a side (z), the lift (w); 1
// to copy; `daubs`: their width in texels (x) and where this view's corner lies in the picture, in texels (y, z).
layout(push_constant, std430) uniform Style {
	vec4 r;
	vec4 g;
	vec4 b;
	vec4 brush;
	vec4 daubs;
} style;

// Kuwahara's four quadrants, each sampled on a fixed grid whatever the reach, so a photo's strokes cost what a
// preview's do a pixel. The quadrants blend by how evenly each is lit, the evenest all but alone, rather than the
// evenest taken outright, whose hard switches drew blocks and streaks along edges.
vec3 kuwahara() {
	int n = int(style.brush.z);
	vec2 stride = style.brush.xy / float(n);
	vec3 blended = vec3(0.0);
	float weights = 0.0;
	for (int q = 0; q < 4; q++) {
		vec2 dir = vec2((q & 1) == 0 ? -1.0 : 1.0, (q & 2) == 0 ? -1.0 : 1.0);
		vec3 sum = vec3(0.0);
		vec3 squares = vec3(0.0);
		for (int y = 0; y <= n; y++) {
			for (int x = 0; x <= n; x++) {
				vec3 c = light(uv + dir * stride * vec2(x, y));
				sum += c;
				squares += c * c;
			}
		}
		float count = float((n + 1) * (n + 1));
		vec3 mean = sum / count;
		vec3 spread = max(squares / count - mean * mean, vec3(0.0));
		float v = spread.r + spread.g + spread.b;
		float w = 1.0 / pow(1e-5 + v, 4.0);
		blended += mean * w;
		weights += w;
	}
	return blended / weights;
}

uint mixed(ivec2 p, uint salt) {
	uint h = uint(p.x) * 0x8da6b343u ^ uint(p.y) * 0xd8163841u ^ salt * 0xcb1ab31fu;
	h ^= h >> 15;
	h *= 0x2c1b3c6du;
	h ^= h >> 12;
	h *= 0x297a2d39u;
	return h ^ (h >> 15);
}

vec4 chance(ivec2 p, uint salt) {
	uint h = mixed(p, salt);
	return vec4(h & 255u, (h >> 8) & 255u, (h >> 16) & 255u, h >> 24) / 255.0;
}

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// One daub to each cell of a grid a daub wide. A pixel shows, of the daubs over it, the one whose paint lies nearest
// the view there, so a daub stops at an edge rather than painting over it. A daub reaches into the cells around its
// own, so a pixel looks through the four cells on a side nearest it.
vec3 daubs() {
	vec2 size = vec2(textureSize(seen, 0));
	float w = style.daubs.x;
	vec2 at = uv * size + style.daubs.yz;
	vec2 cell = at / w;
	ivec2 first = ivec2(floor(cell)) - 2 + ivec2(greaterThanEqual(fract(cell), vec2(0.5)));
	vec2 lit = normalize(vec2(-0.6, -0.8));
	vec3 here = light(uv);
	float best = 1e9;
	vec3 colour = vec3(0.0);
	float shade = 1.0;
	for (int y = 0; y < 4; y++) {
		for (int x = 0; x < 4; x++) {
			ivec2 q = first + ivec2(x, y);
			vec4 c = chance(q, 1u);
			vec4 d = chance(q, 2u);
			vec2 centre = (vec2(q) + 0.5 + (c.xy - 0.5) * 0.7) * w;
			vec2 tap = (centre - style.daubs.yz) / size;
			vec2 o = 0.15 * w / size;
			vec3 xp = light(tap + vec2(o.x, 0.0));
			vec3 xm = light(tap - vec2(o.x, 0.0));
			vec3 yp = light(tap + vec2(0.0, o.y));
			vec3 ym = light(tap - vec2(0.0, o.y));
			vec2 slope = vec2(luma(xp) - luma(xm), luma(yp) - luma(ym));
			float slant = 0.7 + 0.6 * c.z;
			vec2 free = vec2(cos(slant), -sin(slant));
			vec2 along = length(slope) > 1e-6 ? normalize(vec2(-slope.y, slope.x)) : free;
			along = dot(along, free) < 0.0 ? -along : along;
			along = normalize(mix(free, along, smoothstep(0.01, 0.06, length(slope) / (luma(xp + xm + yp + ym) * 0.25 + 0.02))));
			vec2 across = vec2(-along.y, along.x);
			vec2 off = at - centre;
			float u = dot(off, along) / (w * (1.0 + 0.5 * c.w));
			float v = dot(off, across) / (w * 0.55);
			float e = u * u + v * v;
			vec3 paint = (xp + xm + yp + ym) * 0.25;
			vec3 gap = abs(sqrt(paint) - sqrt(here));
			float miss = e < 1.0 ? gap.r + gap.g + gap.b + 0.02 * d.x : 1e3 + e;
			if (miss < best) {
				best = miss;
				colour = paint;
				float vv = clamp(v, -1.0, 1.0);
				float ridge = 1.0 - 0.16 * vv * dot(across, lit);
				float bristle = 1.0 + 0.06 * sin(vv * 2.0 * 3.14159 + d.y * 6.2832);
				float tip = 1.0 - 0.08 * smoothstep(0.55, 1.0, abs(clamp(u, -1.0, 1.0)));
				shade = ridge * bristle * tip;
			}
		}
	}
	return colour * shade * shade;
}

void main() {
	vec3 c = DAUBS ? daubs() : style.brush.z > 0.0 ? kuwahara() : light(uv);
	vec3 toned = max(vec3(dot(style.r.rgb, c), dot(style.g.rgb, c), dot(style.b.rgb, c)), vec3(0.0));
	float lift = style.brush.w;
	if (lift > 0.0) {
		toned = toned * (1.0 + lift) / (toned + lift);
	}
	colour = vec4(sqrt(toned), texture(seen, uv).a);
}
