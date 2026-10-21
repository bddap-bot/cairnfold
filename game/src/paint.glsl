#[compute]
#version 450

// One canvas's paint (Canvas, Brushwork). `wet` holds pigment still in the water (rgb, optical density) and the water
// itself (a); `dry` the pigment laid into the paper (rgb) and the height of oil standing on it (a); `paper` the
// paper's tooth (r). A tick is two flow steps, wet A to B and B back to A, so A is always the canvas as it stands.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// Read-only neighbours use texture fetches; storage-image reads are costly on the Quest 2.
layout(set = 0, binding = 0) uniform sampler2D wet_in;
layout(rgba16f, set = 0, binding = 1) uniform restrict image2D wet_out;
layout(rgba16f, set = 0, binding = 2) uniform restrict image2D dry;
layout(rgba8, set = 0, binding = 3) uniform restrict image2D paper;
layout(set = 0, binding = 6) uniform sampler2D paper_in;

struct Dab {
	vec4 a; // x, y, radius, pressure
	vec4 b; // heading, load, dryness, flat angle
};
layout(std430, set = 0, binding = 4) restrict readonly buffer Dabs { Dab dabs[]; };
// Per tile, the first tick it is wet and the tick it is dry again.
layout(std430, set = 0, binding = 5) restrict readonly buffer Tiles { ivec2 tiles[]; };

layout(push_constant, std430) uniform Params {
	ivec2 origin;
	ivec2 size;
	int mode;
	int first;
	int count;
	int brush;
	vec4 colour; // optical density, and the paint's strength
	vec4 more; // medium, unused, tick, 1 on a tick's second step
} pc;

const int PAPER = 0;
const int DAB = 1;
const int FLOW = 2;
const int WATER = 0;
const int OIL = 1;
const int CHARCOAL = 2;
const int SMEAR = 3;
const int FLAT = 2;
const int TILE = 64;
const int TILES_X = 24;

const float WET = 0.004;
// Water flows to a neighbour by this share of the difference in level; into dry paper only past the paper's tooth.
const float FLOW_RATE = 0.2;
const float EDGE = 0.4;
const float TOOTH_HOLD = 0.35;
// A tilted canvas: very wet paint runs down.
const float GRAVITY = 0.09;
const float RUNS = 0.55;
// Water dries by a little every step and a share of what is there, a share far larger at a wash's edge. Since a
// share never empties a texel the edge stays put as the wash dries, fed from inside: the rim where pigment piles up.
const float EVAPORATE = 0.0004;
const float EVAPORATE_SHARE = 0.003;
const float EDGE_SHARE = 0.03;
// Pigment settles out of the water a little every step, more into the paper's pits (granulation), and the rest as
// the water thins.
const float SETTLE = 0.002;
const float GRANULATE = 0.7;
const float THIN = 0.02;
// How far in from a wash's edge it dries faster, in texels.
const int EDGE_REACH = 4;
const float LIFT = 0.25;

float hash(vec2 p) {
	p = fract(p * vec2(443.897, 441.423));
	p += dot(p, p.yx + 19.19);
	return fract((p.x + p.y) * p.x);
}

vec2 slope(vec2 i) {
	float a = hash(i) * 6.2831853;
	return vec2(cos(a), sin(a));
}

// Gradient noise, 0..1, each octave turned off the grid so no axis shows through.
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(slope(i), f);
	float b = dot(slope(i + vec2(1, 0)), f - vec2(1, 0));
	float c = dot(slope(i + vec2(0, 1)), f - vec2(0, 1));
	float d = dot(slope(i + vec2(1, 1)), f - vec2(1, 1));
	return clamp(mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 0.75 + 0.5, 0.0, 1.0);
}

float octave(vec2 p, float scale, float turn) {
	float c = cos(turn);
	float s = sin(turn);
	return noise(mat2(vec2(c, s), vec2(-s, c)) * p / scale + turn * 37.0);
}

ivec2 canvas_size() {
	return imageSize(dry);
}

bool inside(ivec2 p) {
	ivec2 s = canvas_size();
	return p.x >= 0 && p.y >= 0 && p.x < s.x && p.y < s.y;
}

vec2 grain(ivec2 p) {
	return texelFetch(paper_in, p, 0).rg;
}

ivec2 tile(ivec2 p) {
	return tiles[(p.y / TILE) * TILES_X + p.x / TILE];
}

bool wet_tile(ivec2 p, int tick) {
	ivec2 t = tile(p);
	return tick >= t.x && tick < t.y;
}

// The paper's grain (r), fine pits pigment settles into, and its tooth (g), the broader lumps a wash's edge stops on.
void make_paper(ivec2 p) {
	vec2 q = vec2(p);
	float grain = 0.6 * octave(q, 2.3, 0.5) + 0.4 * octave(q, 1.2, 1.7);
	float tooth = 0.55 * octave(q, 18.0, 0.9) + 0.3 * octave(q, 6.5, 2.3) + 0.15 * octave(q, 2.8, 4.1);
	imageStore(paper, p, vec4(clamp((grain - 0.5) * 1.6 + 0.5, 0.0, 1.0), clamp((tooth - 0.5) * 1.8 + 0.5, 0.0, 1.0), 0.0, 1.0));
}

// How much of a dab reaches texel `q`: a soft disc for round brushes and the stick, a blunt flat oval for the flat,
// its edge ragged with the paper and the bristles.
float footprint(Dab d, vec2 q, float h) {
	vec2 rel = q - d.a.xy;
	float r = d.a.z;
	float dist;
	if (int(pc.more.x) == CHARCOAL) {
		float c = cos(d.b.w);
		float s = sin(d.b.w);
		vec2 l = vec2(dot(rel, vec2(c, s)), dot(rel, vec2(-s, c)));
		dist = length(l / vec2(r, d.b.x));
	} else if (pc.brush == FLAT) {
		float c = cos(d.b.w);
		float s = sin(d.b.w);
		vec2 l = vec2(dot(rel, vec2(c, s)), dot(rel, vec2(-s, c))) / vec2(r, r * 0.28);
		dist = pow(pow(abs(l.x), 4.0) + pow(abs(l.y), 4.0), 0.25);
	} else {
		dist = length(rel) / r;
	}
	float rag = pc.more.x == float(OIL) ? 0.08 : 0.25;
	dist += (h - 0.5) * rag;
	float soft = pc.more.x == float(OIL) ? 0.65 : 0.85;
	return 1.0 - smoothstep(soft, 1.0, dist);
}

// Streaks a brush's bristles drag along its heading.
float bristles(Dab d, vec2 q) {
	vec2 rel = q - d.a.xy;
	vec2 across = vec2(-sin(d.b.x), cos(d.b.x));
	float k = dot(rel, across) / max(d.a.z, 1.0);
	float n = noise(vec2(k * 7.0 + d.a.z, 3.7)) * 0.65 + noise(vec2(k * 19.0, 9.1)) * 0.35;
	return n;
}

float feathers(Dab d, vec2 q) {
	vec2 v = (q - d.a.xy) / d.a.z;
	v.x *= 0.7;
	float fringe = 0.06 * sin(v.y * 37.0) * sin(v.x * 29.0);
	return (1.0 - smoothstep(0.55, 1.0, length(v) + fringe)) * d.a.w;
}

void smear(ivec2 p) {
	vec4 here = texelFetch(wet_in, p, 0);
	vec4 change = vec4(0.0);
	ivec2 extent = textureSize(wet_in, 0);
	// Each outgoing transfer has an equal incoming transfer at its destination: no pigment is created.
	for (int i = pc.first; i < pc.first + pc.count; i++) {
		Dab d = dabs[i];
		float f = feathers(d, vec2(p) + 0.5);
		if (f <= 0.0) continue;
		ivec2 offset = ivec2(round(vec2(cos(d.b.x), sin(d.b.x)) * 12.0));
		ivec2 source = p - offset;
		ivec2 destination = p + offset;
		float amount = 0.6 / float(pc.count);
		if (all(greaterThanEqual(source, ivec2(0))) && all(lessThan(source, extent))) {
			change += texelFetch(wet_in, source, 0) * min(f, feathers(d, vec2(source) + 0.5)) * amount;
		}
		if (all(greaterThanEqual(destination, ivec2(0))) && all(lessThan(destination, extent))) {
			change -= here * min(f, feathers(d, vec2(destination) + 0.5)) * amount;
		}
	}
	imageStore(wet_out, p, here + change);
}

void lay(ivec2 p) {
	if (int(pc.more.x) == SMEAR) {
		smear(p);
		return;
	}
	vec2 q = vec2(p) + 0.5;
	vec4 w = imageLoad(wet_out, p);
	vec4 laid = imageLoad(dry, p);
	vec2 paper_here = grain(p);
	float fine = paper_here.x;
	float lump = paper_here.y;
	int medium = int(pc.more.x);
	vec3 density = pc.colour.rgb;
	float strength = pc.colour.a;
	bool touched = false;
	for (int i = pc.first; i < pc.first + pc.count; i++) {
		Dab d = dabs[i];
		vec2 rel = q - d.a.xy;
		float reach = d.a.z * 1.4 + 2.0;
		if (abs(rel.x) > reach || abs(rel.y) > reach) {
			continue;
		}
		float f = footprint(d, q, medium == CHARCOAL ? fine : lump);
		if (f <= 0.0) {
			continue;
		}
		touched = true;
		float pressure = d.a.w;
		float load = d.b.y;
		float dryness = d.b.z;
		if (medium == WATER) {
			// A skimming or nearly dry brush leaves the paper's hollows white.
			float skim = smoothstep(dryness - 0.3, dryness, mix(lump, fine, 0.6) + 0.2);
			float water = f * skim * load * (0.12 + 0.3 * sqrt(pressure));
			float added = min(water, max(1.0 - w.a, 0.0));
			vec3 paint = density * strength;
			w.a += added;
			w.rgb += paint * added;
			// The brush and the puddle under it trade pigment, so going over a wet wash evens it toward the brush's
			// mix instead of piling colour on: a clean wet brush thins it.
			w.rgb = mix(w.rgb, paint * w.a, clamp(water * 0.5, 0.0, 1.0));
			// A wet brush with little colour on it lifts what lies there.
			if (laid.a < 0.01) {
				vec3 lifted = laid.rgb * f * LIFT * pressure * load * max(0.0, 1.0 - strength * 4.0);
				laid.rgb -= lifted;
				w.rgb += lifted;
			}
		} else if (medium == OIL) {
			float streak = bristles(d, q);
			float body = clamp(load * 1.6, 0.0, 1.0);
			float cover = f * body * smoothstep(dryness * 0.9, dryness * 0.9 + 0.3, lump * 0.4 + fine * 0.2 + streak * 0.6);
			cover = clamp(cover, 0.0, 1.0);
			laid.rgb += w.rgb * cover;
			w *= 1.0 - cover;
			vec3 paint = mix(density, laid.rgb, 0.4 * (1.0 - load) * f);
			laid.rgb = mix(laid.rgb, paint, cover);
			float height = (0.35 + 0.65 * pressure) * load * (0.55 + 0.45 * streak);
			laid.a = mix(laid.a, max(laid.a * 0.6, height), cover);
		} else {
			// Charcoal catches on the paper's peaks, its tooth as much as its grain so the grain reads at arm's length.
			// Pressing harder reaches lower but never into the deepest pits: a hard line closed into a smooth band
			// reads as a wash. Each pass darkens what it catches less than the one before.
			float bite = 0.86 - pressure * 0.44;
			float take = f * load * smoothstep(bite - 0.04, bite + 0.04, fine * 0.5 + lump * 0.5) * (0.12 + 0.2 * pressure);
			laid.rgb += density * take * exp(-laid.g * 0.6);
		}
	}
	if (touched) {
		imageStore(wet_out, p, w);
		imageStore(dry, p, laid);
	}
}

// Water a texel at `wi` gives its neighbour at `wj`, of tooth `hj`, lying `dir` from it this step. Both texels work
// it out from the same values, so water and pigment are only ever moved, never made.
float give(float wi, float wj, float hj, ivec2 dir) {
	if (wi < WET) {
		return 0.0;
	}
	if (wj < WET && wi < EDGE + hj * TOOTH_HOLD) {
		return 0.0;
	}
	float level = wi - wj + GRAVITY * float(dir.y) * max(wi - RUNS, 0.0);
	return clamp(FLOW_RATE * level, 0.0, wi * 0.24);
}

bool damp(ivec2 q, int tick) {
	return inside(q) && wet_tile(q, tick) && texelFetch(wet_in, q, 0).a >= WET;
}

void flow(ivec2 p) {
	int tick = int(pc.more.z);
	if (!wet_tile(p, tick)) {
		return;
	}
	vec4 c = texelFetch(wet_in, p, 0);
	// Wet tiles include a margin for future flow. Empty texels with no wet neighbour cannot change this step.
	if (all(equal(c, vec4(0.0)))) {
		ivec2 hi = canvas_size() - 1;
		vec4 neighbours = vec4(texelFetch(wet_in, min(p + ivec2(1, 0), hi), 0).a,
			texelFetch(wet_in, max(p - ivec2(1, 0), ivec2(0)), 0).a,
			texelFetch(wet_in, min(p + ivec2(0, 1), hi), 0).a,
			texelFetch(wet_in, max(p - ivec2(0, 1), ivec2(0)), 0).a);
		if (all(lessThan(neighbours, vec4(WET)))) {
			imageStore(wet_out, p, vec4(0.0));
			return;
		}
	}
	vec2 paper_here = grain(p);
	float wc = c.a;
	vec3 conc = c.rgb / max(wc, 1e-4);
	float w_new = wc;
	vec3 p_new = c.rgb;
	const ivec2 sides[4] = ivec2[](ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1));
	float edge = 0.0;
	for (int k = 0; k < 4; k++) {
		ivec2 q = p + sides[k];
		if (!damp(p + sides[k] * EDGE_REACH, tick)) {
			edge += 0.15;
		}
		if (!inside(q) || !wet_tile(q, tick)) {
			edge += 0.1;
			continue;
		}
		vec4 n = texelFetch(wet_in, q, 0);
		if (n.a < WET) {
			edge += 0.1;
		}
		float out_w = give(wc, n.a, grain(q).y, sides[k]);
		float in_w = give(n.a, wc, paper_here.y, -sides[k]);
		w_new += in_w - out_w;
		p_new += in_w * n.rgb / max(n.a, 1e-4) - out_w * conc;
	}
	if (w_new > 0.0) {
		w_new = max(w_new * (1.0 - EVAPORATE_SHARE - EDGE_SHARE * edge * (1.0 - w_new)) - EVAPORATE, 0.0);
	}
	float settle = SETTLE * (1.0 + GRANULATE * (0.5 - paper_here.x)) + THIN * (1.0 - smoothstep(0.0, 0.1, w_new));
	// A tile's last tick lays whatever is still in the water, so a dry tile holds nothing wet.
	if (w_new < WET || (pc.more.w > 0.5 && tick == tile(p).y - 1)) {
		settle = 1.0;
		w_new = 0.0;
	}
	vec3 laid_now = max(p_new, vec3(0.0)) * clamp(settle, 0.0, 1.0);
	p_new = max(p_new - laid_now, vec3(0.0));
	if (any(greaterThan(laid_now, vec3(0.0)))) {
		vec4 laid = imageLoad(dry, p);
		imageStore(dry, p, vec4(min(laid.rgb + laid_now, vec3(8.0)), laid.a));
	}
	imageStore(wet_out, p, vec4(p_new, w_new));
}

void main() {
	ivec2 p = pc.origin + ivec2(gl_GlobalInvocationID.xy);
	if (any(greaterThanEqual(ivec2(gl_GlobalInvocationID.xy), pc.size)) || !inside(p)) {
		return;
	}
	if (pc.mode == PAPER) {
		make_paper(p);
	} else if (pc.mode == DAB) {
		lay(p);
	} else {
		flow(p);
	}
}
