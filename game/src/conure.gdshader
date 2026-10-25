shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx, shadows_disabled;

#include "res://src/ground.gdshaderinc"
#include "res://src/bounce.gdshaderinc"

varying vec4 given;

instance uniform float floor_height = 0.0;
// A row of `palette`; row 0 is iridescent, its feathers coloured here. See Conure.PLUMAGES.
instance uniform int plumage = 0;
// Each part's rigid motion this frame from Conure.pose: a rotation quaternion and a shift after it. The body's shift
// carries the breathing scale in w and the feet's how far into flight the bird is.
instance uniform vec4 turn_body = vec4(0.0, 0.0, 0.0, 1.0);
instance uniform vec4 shift_body = vec4(0.0, 0.0, 0.0, 1.0);
instance uniform vec4 turn_head = vec4(0.0, 0.0, 0.0, 1.0);
instance uniform vec3 shift_head = vec3(0.0);
instance uniform vec4 turn_wing_l = vec4(0.0, 0.0, 0.0, 1.0);
instance uniform vec3 shift_wing_l = vec3(0.0);
instance uniform vec4 turn_wing_r = vec4(0.0, 0.0, 0.0, 1.0);
instance uniform vec3 shift_wing_r = vec3(0.0);
instance uniform vec4 turn_tail = vec4(0.0, 0.0, 0.0, 1.0);
instance uniform vec3 shift_tail = vec3(0.0);
instance uniform vec4 turn_feet = vec4(0.0, 0.0, 0.0, 1.0);
instance uniform vec4 shift_feet = vec4(0.0);
uniform sampler2D palette : filter_nearest;
const int PATCHES = 9;
const int BILL = 8;

// The perched body's frame: X across, L along the body (up and forward), D out of the back. Matches conure.gd.
const vec3 X = vec3(1.0, 0.0, 0.0);
const vec3 L = vec3(0.0, 0.8192, -0.5736);
const vec3 D = vec3(0.0, 0.5736, 0.8192);
const vec3 BODY = vec3(0.0, 0.062, 0.012);

const vec3 BLUE = vec3(0.04, 0.2, 0.72);
const vec3 TEAL = vec3(0.02, 0.42, 0.52);
const vec3 GREEN = vec3(0.16, 0.56, 0.08);

varying vec3 tint;

vec3 rotated(vec4 q, vec3 v) {
	return v + 2.0 * cross(q.xyz, cross(q.xyz, v) + q.w * v);
}

void vertex() {
	int area = COLOR.a > 0.75 ? int(COLOR.b * float(PATCHES) + 0.5) : BILL;
	tint = texelFetch(palette, ivec2(area, plumage), 0).rgb;
	int part = int(UV2.x + 0.5);
	float fly = shift_feet.w;
	vec4 turn = turn_body;
	vec3 shift = shift_body.xyz;
	if (part == 5) {
		VERTEX = mix(VERTEX, BODY - L * 0.03, fly * 0.7);
		turn = turn_feet;
		shift = shift_feet.xyz;
	} else {
		VERTEX = BODY + (VERTEX - BODY) * shift_body.w;
	}
	if (part == 1) {
		turn = turn_head;
		shift = shift_head;
	} else if (part == 2 || part == 3) {
		// Flight draws the wing out along the body before it beats.
		vec3 shoulder = BODY + L * 0.03 + D * 0.012 + X * (part == 2 ? -0.026 : 0.026);
		VERTEX += L * dot(VERTEX - shoulder, L) * fly * 0.9;
		turn = part == 2 ? turn_wing_l : turn_wing_r;
		shift = part == 2 ? shift_wing_l : shift_wing_r;
	} else if (part == 4) {
		turn = turn_tail;
		shift = shift_tail;
	}
	VERTEX = rotated(turn, VERTEX) + shift;
	NORMAL = rotated(turn, NORMAL);
	given = given_over((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, normalize(mat3(MODEL_MATRIX) * NORMAL), floor_height);
}

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float plume = step(0.75, COLOR.a);
	float fluff = COLOR.g * 2.0 - 1.0;
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
