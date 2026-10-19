shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx, shadows_disabled;

#include "res://src/ground.gdshaderinc"
#include "res://src/bounce.gdshaderinc"

varying vec4 given;

// x looking about, y preening, z pecking, w flight: weights scale each motion so blends stay continuous.
instance uniform vec4 mode = vec4(1.0, 0.0, 0.0, 0.0);
instance uniform float phase = 0.0;
// A row of `palette`; row 0 is iridescent, its feathers coloured here. See Conure.PLUMAGES.
instance uniform int plumage = 0;
// Where the head is held to look at something, in the bird's own space: yaw, pitch, and how far it holds there
// rather than looking about.
instance uniform vec3 gaze = vec3(0.0);
uniform sampler2D palette : filter_nearest;
const int PATCHES = 9;
const int BILL = 8;

// The perched body's frame: X across, L along the body (up and forward), D out of the back. Matches conure.gd.
const vec3 X = vec3(1.0, 0.0, 0.0);
const vec3 L = vec3(0.0, 0.8192, -0.5736);
const vec3 D = vec3(0.0, 0.5736, 0.8192);
const vec3 BODY = vec3(0.0, 0.062, 0.012);
const vec3 NECK = vec3(0.0, 0.098, -0.012);

const vec3 BLUE = vec3(0.04, 0.2, 0.72);
const vec3 TEAL = vec3(0.02, 0.42, 0.52);
const vec3 GREEN = vec3(0.16, 0.56, 0.08);

varying vec3 rest;
varying vec3 tint;

mat3 rot(vec3 axis, float a) {
	axis = normalize(axis);
	float s = sin(a), c = cos(a), oc = 1.0 - c;
	return mat3(
		vec3(oc * axis.x * axis.x + c, oc * axis.x * axis.y + axis.z * s, oc * axis.z * axis.x - axis.y * s),
		vec3(oc * axis.x * axis.y - axis.z * s, oc * axis.y * axis.y + c, oc * axis.y * axis.z + axis.x * s),
		vec3(oc * axis.z * axis.x + axis.y * s, oc * axis.y * axis.z - axis.x * s, oc * axis.z * axis.z + c));
}

void turn(inout vec3 v, inout vec3 n, vec3 pivot, mat3 m) {
	v = m * (v - pivot) + pivot;
	n = m * n;
}

float hash(float n) {
	return fract(sin(n * 127.1 + 311.7) * 43758.547) * 2.0 - 1.0;
}

// A held value that snaps to a new random one now and then, as a bird's head moves in quick turns.
float snap(float t, float rate, float seed) {
	float k = floor(t * rate);
	return mix(hash(k + seed), hash(k + 1.0 + seed), smoothstep(0.0, 0.18, fract(t * rate)));
}

void vertex() {
	rest = VERTEX;
	int area = COLOR.a > 0.75 ? int(COLOR.b * float(PATCHES) + 0.5) : BILL;
	tint = texelFetch(palette, ivec2(area, plumage), 0).rgb;
	int part = int(UV2.x + 0.5);
	float t = TIME + phase;
	float idle = mode.x, preen = mode.y, peck = mode.z, fly = mode.w;
	bool wing = part == 2 || part == 3;
	float side = part == 2 ? -1.0 : 1.0;
	// Which shoulder a preening bird works at; it swings its head round to the other now and then.
	float shoulder_side = clamp(sin(t * 0.35 + 0.5) * 4.0, -1.0, 1.0);

	// Breathing, and now and then a fluff-up with a quick flick of both wings.
	float burst = pow(max(sin(t * 0.45 + 2.1), 0.0), 40.0);
	if (part != 5) {
		vec3 c = VERTEX - BODY;
		VERTEX = BODY + c * (1.0 + (idle + preen) * (0.014 * sin(t * 3.1) + 0.07 * burst));
	}

	if (part == 1) {
		float yaw = mix(idle * 1.1 * snap(t, 0.9, 3.0) + preen * 2.5 * shoulder_side, gaze.x, gaze.z);
		float cock = idle * 0.45 * snap(t, 0.7, 11.0) * (1.0 - 0.6 * gaze.z) + preen * 0.35 * sin(t * 9.0);
		float nod = mix(preen * (0.75 + 0.12 * sin(t * 14.0)) + peck * (0.25 + 0.9 * pow(max(sin(t * 4.2), 0.0), 6.0)) - fly * 0.4, -gaze.y, gaze.z);
		turn(VERTEX, NORMAL, NECK + vec3(0.0, 0.016, -0.012), rot(vec3(0.0, 0.0, 1.0), cock));
		turn(VERTEX, NORMAL, NECK, rot(vec3(0.0, 1.0, 0.0), yaw) * rot(X, -nod));
	}

	if (wing) {
		vec3 shoulder = BODY + L * 0.03 + D * 0.012 + X * side * 0.026;
		float flick = idle * burst * 0.5 * (0.6 + 0.4 * sin(t * 40.0));
		float lift = preen * 0.25 * max(side * shoulder_side, 0.0);
		float spread = fly * 1.45;
		float beat = fly * (0.25 + 1.0 * sin(t * TAU * 8.0));
		vec3 off = VERTEX - shoulder;
		float along = dot(off, -L);
		off += -L * along * fly * 0.9;
		VERTEX = shoulder + off;
		turn(VERTEX, NORMAL, shoulder, rot(L, -side * (beat + flick + lift)) * rot(D, side * spread));
	}

	if (part == 4) {
		vec3 rump = BODY - L * 0.036 + D * 0.014;
		float wag = idle * (0.08 * sin(t * 1.7) + 0.4 * burst * sin(t * 30.0)) + peck * 0.1 * sin(t * 4.2);
		float lift = fly * 0.9 + 0.12 * snap(t, 0.5, 23.0) * idle;
		turn(VERTEX, NORMAL, rump, rot(X, lift) * rot(D, wag));
	}

	if (part == 5) {
		VERTEX = mix(VERTEX, BODY - L * 0.03, fly * 0.7);
	}

	// Pecking leans the body forward over its feet; flight levels it out, bobbing with each beat.
	if (part != 5) {
		turn(VERTEX, NORMAL, vec3(0.0), rot(X, -peck * 0.55));
	}
	turn(VERTEX, NORMAL, BODY, rot(X, -fly * 0.96));
	VERTEX.y += fly * 0.006 * sin(t * TAU * 8.0 + 1.0);
	given = given_at((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, normalize(mat3(MODEL_MATRIX) * NORMAL));
}

float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n = i.x + i.y * 57.0 + i.z * 113.0;
	return mix(mix(mix(hash(n), hash(n + 1.0), f.x), mix(hash(n + 57.0), hash(n + 58.0), f.x), f.y),
		mix(mix(hash(n + 113.0), hash(n + 114.0), f.x), mix(hash(n + 170.0), hash(n + 171.0), f.x), f.y), f.z);
}

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float plume = step(0.75, COLOR.a);
	float fluff = noise(rest * 420.0) * 0.6 + noise(rest * 140.0) * 0.4;
	float rim = pow(1.0 - facing, 4.0);
	vec3 feather;
	if (plumage == 0) {
		float g = clamp(1.0 - smoothstep(0.3, 1.0, facing) + (COLOR.g - 0.5) + fluff * 0.08, 0.0, 1.0);
		vec3 hue = g < 0.5 ? mix(BLUE, TEAL, g * 2.0) : mix(TEAL, GREEN, g * 2.0 - 1.0);
		feather = hue * COLOR.r * (0.94 + 0.08 * fluff) + rim * 0.15 * GREEN;
	} else {
		feather = tint * COLOR.r * (0.94 + 0.08 * fluff) * (1.0 + rim * 0.3);
	}
	vec3 own = COLOR.a > 0.25 ? tint * COLOR.r : COLOR.rgb;
	ALBEDO = mix(own, feather, plume);
	ROUGHNESS = mix(COLOR.r < 0.1 ? 0.15 : 0.55, 0.85, plume);
	SPECULAR = mix(COLOR.r < 0.1 ? 0.8 : 0.35, 0.25, plume);
	BACKLIGHT = feather * 0.25 * plume;
	AO = given.a;
	EMISSION = ALBEDO * given.rgb;
}
