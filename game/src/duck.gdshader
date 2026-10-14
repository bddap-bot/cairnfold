shader_type spatial;
render_mode diffuse_lambert_wrap, shadows_disabled;

// x idle, y paddle, z waddle, w fly: weights scale each motion so blends stay continuous.
instance uniform vec4 mode = vec4(1.0, 0.0, 0.0, 0.0);
instance uniform float phase = 0.0;
// Steps per second relative to a grown duck's, so short legs keep their feet planted.
instance uniform float pace = 1.0;

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

void vertex() {
	int part = int(UV2.x + 0.5);
	float t = TIME + phase;
	float idle = mode.x, paddle = mode.y, waddle = mode.z, fly = mode.w;
	float c = t * TAU * 1.5 * pace;
	bool foot = part == 4 || part == 5;
	float side = part == 4 ? -1.0 : 1.0;

	// Idle: breathe, look around with a curious tilt, now and then ruffle the wings and wag.
	float burst = pow(max(sin(t * 0.8 + 1.3), 0.0), 30.0);
	if (!foot) {
		VERTEX.xz *= 1.0 + idle * 0.012 * sin(t * 2.4);
	}
	if (part == 1) {
		vec3 neck = vec3(0.0, 0.22, -0.09);
		float yaw = idle * (0.5 * sin(t * 0.55) + 0.2 * sin(t * 1.7 + 0.4));
		float tilt = idle * 0.28 * smoothstep(0.3, 0.9, sin(t * 0.37 + 2.0));
		float nod = paddle * 0.06 * sin(t * 2.2) + waddle * 0.12 * sin(2.0 * c);
		turn(VERTEX, NORMAL, vec3(0.0, 0.345, -0.13), rot(vec3(0.0, 0.0, 1.0), tilt));
		turn(VERTEX, NORMAL, neck, rot(vec3(0.0, 1.0, 0.0), yaw) * rot(vec3(1.0, 0.0, 0.0), nod));
	}
	if (part == 2 || part == 3) {
		float s = part == 2 ? -1.0 : 1.0;
		float lift = idle * burst * 0.9 * (0.6 + 0.4 * sin(t * 30.0));
		float flap = fly * (0.5 + 0.9 * sin(t * TAU * 3.5));
		turn(VERTEX, NORMAL, vec3(s * 0.08, 0.24, -0.04), rot(vec3(0.0, 0.0, 1.0), s * (lift + flap)));
	}
	if (part == 6) {
		float wag = idle * burst * 0.5 * sin(t * 28.0) + paddle * 0.15 * sin(t * 3.1) + waddle * 0.25 * sin(c);
		turn(VERTEX, NORMAL, vec3(0.0, 0.22, 0.14), rot(vec3(0.0, 1.0, 0.0), wag));
	}

	// Paddle: the body floats lower and bobs; the legs kick under it in turn.
	if (foot) {
		float kick = paddle * 0.7 * sin(t * TAU * 1.1 + (side < 0.0 ? 0.0 : PI));
		turn(VERTEX, NORMAL, vec3(side * 0.05, 0.09, 0.0), rot(vec3(1.0, 0.0, 0.0), kick + paddle * 0.5 - fly * 1.3));
	}
	VERTEX.y += paddle * (-0.07 + 0.006 * sin(t * 2.0));

	// Waddle: each step rolls the body over the planted foot while the other swings forward.
	if (foot) {
		float swing = side < 0.0 ? sin(c) : -sin(c);
		VERTEX.y += waddle * max(swing, 0.0) * 0.03;
		VERTEX.z += waddle * cos(c) * (side < 0.0 ? 1.0 : -1.0) * 0.035;
	} else {
		VERTEX.y += waddle * 0.012 * abs(cos(c));
		turn(VERTEX, NORMAL, vec3(0.0), rot(vec3(0.0, 0.0, 1.0), waddle * 0.13 * sin(c)) * rot(vec3(0.0, 1.0, 0.0), waddle * 0.08 * sin(c)));
	}
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = COLOR.r < 0.1 ? 0.25 : 0.75;
	SPECULAR = COLOR.r < 0.1 ? 0.6 : 0.3;
}
