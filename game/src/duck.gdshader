shader_type spatial;
render_mode diffuse_lambert_wrap, shadows_disabled;

#include "res://src/sculpture.gdshaderinc"
#include "res://src/given.gdshaderinc"
#include "res://src/turn.gdshaderinc"

// x idle, y paddle, z waddle, w fly: weights scale each motion so blends stay continuous.
instance uniform vec4 mode = vec4(1.0, 0.0, 0.0, 0.0);
instance uniform float phase = 0.0;
// Fraction of a step cycle, advanced by ground walked so the feet keep pace at any speed.
instance uniform float stride = 0.0;
instance uniform float peck = 0.0;
uniform float swing;

const int PART_HEAD = 1;
const int PART_WING_L = 2;
const int PART_WING_R = 3;
const int PART_FOOT_L = 4;
const int PART_FOOT_R = 5;
const int PART_TAIL = 6;

void vertex() {
	int part = int(UV2.x + 0.5);
	float t = TIME + phase;
	float idle = mode.x, paddle = mode.y, waddle = mode.z, fly = mode.w;
	float c = stride * TAU;
	bool foot = part == PART_FOOT_L || part == PART_FOOT_R;
	float side = part == PART_FOOT_L ? -1.0 : 1.0;

	float burst = pow(max(sin(t * 0.8 + 1.3), 0.0), 30.0);
	if (!foot) {
		VERTEX.xz *= 1.0 + idle * 0.012 * sin(t * 2.4);
	}
	if (part == PART_HEAD) {
		vec3 neck = vec3(0.0, 0.22, -0.09);
		float yaw = idle * (0.5 * sin(t * 0.55) + 0.2 * sin(t * 1.7 + 0.4));
		float tilt = idle * 0.28 * smoothstep(0.3, 0.9, sin(t * 0.37 + 2.0));
		float nod = paddle * 0.06 * sin(t * 2.2) + waddle * 0.12 * sin(2.0 * c) - peck * (0.35 + 0.75 * pow(max(sin(t * 5.5), 0.0), 3.0));
		turn(VERTEX, NORMAL, vec3(0.0, 0.345, -0.13), rot(vec3(0.0, 0.0, 1.0), tilt));
		turn(VERTEX, NORMAL, neck, rot(vec3(0.0, 1.0, 0.0), yaw) * rot(vec3(1.0, 0.0, 0.0), nod));
	}
	if (part == PART_WING_L || part == PART_WING_R) {
		float s = part == PART_WING_L ? -1.0 : 1.0;
		float lift = idle * burst * 0.9 * (0.6 + 0.4 * sin(t * 30.0));
		float flap = fly * (0.5 + 0.9 * sin(t * TAU * 3.5));
		turn(VERTEX, NORMAL, vec3(s * 0.08, 0.24, -0.04), rot(vec3(0.0, 0.0, 1.0), s * (lift + flap)));
	}
	if (part == PART_TAIL) {
		float wag = idle * burst * 0.5 * sin(t * 28.0) + paddle * 0.15 * sin(t * 3.1) + waddle * 0.25 * sin(c);
		turn(VERTEX, NORMAL, vec3(0.0, 0.22, 0.14), rot(vec3(0.0, 1.0, 0.0), wag));
	}

	if (foot) {
		float kick = paddle * 0.7 * sin(t * TAU * 1.1 + (side < 0.0 ? 0.0 : PI));
		turn(VERTEX, NORMAL, vec3(side * 0.05, 0.09, 0.0), rot(vec3(1.0, 0.0, 0.0), kick + paddle * 0.5 - fly * 1.3));
	}
	VERTEX.y += paddle * (-0.07 + 0.006 * sin(t * 2.0));

	if (foot) {
		float rise = side < 0.0 ? sin(c) : -sin(c);
		VERTEX.y += waddle * max(rise, 0.0) * 0.03;
		VERTEX.z += waddle * cos(c) * (side < 0.0 ? 1.0 : -1.0) * swing;
	} else {
		VERTEX.y += waddle * 0.012 * abs(cos(c));
		turn(VERTEX, NORMAL, vec3(0.0), rot(vec3(0.0, 0.0, 1.0), waddle * 0.13 * sin(c)) * rot(vec3(0.0, 1.0, 0.0), waddle * 0.08 * sin(c)));
	}
	GIVE_HERE;
}

void fragment() {
	ALBEDO = SCULPTED ? SCULPTURE : COLOR.rgb;
	ROUGHNESS = COLOR.r < 0.1 ? 0.25 : 0.75;
	SPECULAR = COLOR.r < 0.1 ? 0.6 : 0.3;
	TAKE_GIVEN;
}
