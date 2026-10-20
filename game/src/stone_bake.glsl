#[compute]
#version 450

// The painted stone ground's patterns (StoneStyles), one layer a style, each tiling its square: r the height, 0 in a
// joint to 1 on a stone's crown; g the stone's own value; b and a its face's normal, x and z, 0.5 for level.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba8, set = 0, binding = 0) uniform restrict writeonly image2DArray patterns;

layout(push_constant, std430) uniform Params {
	ivec4 shape; // kind, stones across, courses down, layer
	vec4 cut; // jitter, warp, joint in metres, dome
	vec4 face; // grain, relief in metres, tile in metres, elongation
} p;

const int CELLS = 0;
const int PEBBLES = 1;
const int COURSES = 2;

uvec3 pcg3d(uvec3 v) {
	v = v * 1664525u + 1013904223u;
	v.x += v.y * v.z;
	v.y += v.z * v.x;
	v.z += v.x * v.y;
	v ^= v >> 16u;
	v.x += v.y * v.z;
	v.y += v.z * v.x;
	v.z += v.x * v.y;
	return v;
}

// `c` wrapped into 0..period: GLSL leaves % of a negative int undefined, and drivers differ.
ivec2 wrap(ivec2 c, int period) {
	return ivec2(mod(vec2(c), float(period)));
}

vec3 rand3(ivec2 c, int period, int salt) {
	uvec2 w = uvec2(wrap(c, period));
	return vec3(pcg3d(uvec3(w, uint(salt + p.shape.w * 101)))) / 4294967295.0;
}

// Value noise with `period` lattice cells across the tile, so it tiles.
float noise(vec2 uv, int period, int salt) {
	vec2 x = uv * float(period);
	ivec2 i = ivec2(floor(x));
	vec2 f = fract(x);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = rand3(i, period, salt).x;
	float b = rand3(i + ivec2(1, 0), period, salt).x;
	float c = rand3(i + ivec2(0, 1), period, salt).x;
	float d = rand3(i + ivec2(1, 1), period, salt).x;
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 uv, int period, int salt) {
	float sum = 0.0;
	float amp = 0.5;
	for (int k = 0; k < 4; k++) {
		sum += noise(uv, period, salt + k) * amp;
		period *= 2;
		amp *= 0.5;
	}
	return sum / 0.9375;
}

// Irregular stones: the distance in metres to the nearest joint (the bisector to the next stone's centre), how far
// from its own centre in stones, and its value.
vec3 cells(vec2 uv) {
	int n = p.shape.y;
	vec2 q = uv * float(n) + p.cut.y * (vec2(fbm(uv, 4, 11), fbm(uv, 4, 23)) - 0.5) * 2.0;
	ivec2 g = ivec2(floor(q));
	vec2 near = vec2(0.0);
	ivec2 home = g;
	float best = 1e9;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			ivec2 c = g + ivec2(x, y);
			vec2 at = vec2(c) + 0.5 + (rand3(c, n, 3).xy - 0.5) * p.cut.x;
			float d = dot(q - at, q - at);
			if (d < best) {
				best = d;
				near = at;
				home = c;
			}
		}
	}
	// A soft minimum over the joints, so a stone's corners round off as worn stone's do.
	float edge = 0.0;
	for (int y = -2; y <= 2; y++) {
		for (int x = -2; x <= 2; x++) {
			ivec2 c = home + ivec2(x, y);
			if (c == home) {
				continue;
			}
			vec2 at = vec2(c) + 0.5 + (rand3(c, n, 3).xy - 0.5) * p.cut.x;
			edge += exp(-max(dot((near + at) * 0.5 - q, normalize(at - near)), 0.0) / 0.04);
		}
	}
	return vec3(max(-0.04 * log(edge), 0.0) * p.face.z / float(n), sqrt(best), rand3(home, n, 5).x);
}

// Rounded pebbles, each its own ellipse turned its own way; the highest dome wins where two touch.
vec2 pebbles(vec2 uv) {
	int n = p.shape.y;
	vec2 q = uv * float(n);
	ivec2 g = ivec2(floor(q));
	vec2 out_h = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			ivec2 c = g + ivec2(x, y);
			vec3 r = rand3(c, n, 3);
			vec3 s = rand3(c, n, 7);
			vec2 at = vec2(c) + 0.5 + (r.xy - 0.5) * p.cut.x;
			float a = r.z * 6.2831853;
			vec2 l = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * (q - at);
			l.x /= mix(1.0, p.face.w, s.y);
			float e = length(l) / (0.34 + 0.1 * s.x);
			float h = sqrt(max(1.0 - e * e, 0.0)) * (0.75 + 0.25 * s.x);
			if (h > out_h.x) {
				out_h = vec2(h, s.z);
			}
		}
	}
	return out_h;
}

// Cut blocks in courses, each course's joints shifted half a block from the last and a little more at random; an even
// number of courses, so the tile repeats.
vec3 courses(vec2 uv) {
	int n = p.shape.y;
	int rows = p.shape.z;
	float y = uv.y * float(rows);
	int row = wrap(ivec2(int(floor(y))), rows).x;
	float shift = float(row % 2) * 0.5 + (rand3(ivec2(0, row), rows, 13).x - 0.5) * p.cut.x;
	float x = uv.x * float(n) + shift;
	int col = int(floor(x));
	vec2 f = vec2(fract(x), fract(y));
	float edge = min(min(f.x, 1.0 - f.x) * p.face.z / float(n), min(f.y, 1.0 - f.y) * p.face.z / float(rows));
	return vec3(edge, 0.0, rand3(ivec2(wrap(ivec2(col), n).x, row), n * rows, 5).x);
}

vec2 height(vec2 uv) {
	float grain = (fbm(uv, 16, 31) - 0.5) * p.face.x;
	if (p.shape.x == PEBBLES) {
		vec2 h = pebbles(uv);
		return vec2(clamp(h.x + grain * h.x, 0.0, 1.0), h.y);
	}
	vec3 c = p.shape.x == COURSES ? courses(uv) : cells(uv);
	float gap = p.cut.z * 0.15;
	float h = smoothstep(gap, gap + p.cut.z, c.x) * (1.0 - p.cut.w * c.y * c.y);
	return vec2(clamp(h + grain * smoothstep(0.0, 0.3, h), 0.0, 1.0), c.z);
}

void main() {
	ivec2 size = imageSize(patterns).xy;
	ivec2 t = ivec2(gl_GlobalInvocationID.xy);
	if (any(greaterThanEqual(t, size))) {
		return;
	}
	vec2 uv = (vec2(t) + 0.5) / vec2(size);
	vec2 e = 1.0 / vec2(size);
	vec2 h = height(uv);
	float metres = 2.0 * p.face.z / float(size.x);
	float gx = (height(uv + vec2(e.x, 0.0)).x - height(uv - vec2(e.x, 0.0)).x) * p.face.y / metres;
	float gz = (height(uv + vec2(0.0, e.y)).x - height(uv - vec2(0.0, e.y)).x) * p.face.y / metres;
	vec3 n = normalize(vec3(-gx, 1.0, -gz));
	imageStore(patterns, ivec3(t, p.shape.w), vec4(h.x, h.y, n.x * 0.5 + 0.5, n.z * 0.5 + 0.5));
}
