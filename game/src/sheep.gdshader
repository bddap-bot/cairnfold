shader_type spatial;
render_mode diffuse_lambert_wrap, shadows_disabled;

// x idle, y graze, z walk, w lie: weights scale each motion so blends stay continuous.
instance uniform vec4 mode = vec4(1.0, 0.0, 0.0, 0.0);
instance uniform float phase = 0.0;
// The legs' cycle angle, advanced on the CPU by the ground walked so hooves stay planted at any pace.
instance uniform float gait = 0.0;
instance uniform vec3 wool = vec3(1.0);

varying float fleece;

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
	float idle = mode.x, graze = mode.y, walk = mode.z, lie = mode.w;
	bool leg = part >= 4 && part <= 7;
	bool ear = part == 2 || part == 3;
	// Wool is the only cream colour; the eyes' shine is pure white.
	fleece = step(0.5, COLOR.r) * step(COLOR.b, 0.9);

	if (part == 0 || part == 9) {
		VERTEX.x *= 1.0 + 0.018 * sin(t * 1.7) * (1.0 - walk) + lie * 0.06;
		VERTEX.y -= graze * 0.05 * smoothstep(0.0, -0.4, VERTEX.z);
	}

	if (ear) {
		float side = part == 2 ? -1.0 : 1.0;
		float burst = pow(max(sin(t * 0.7 + side * 1.9), 0.0), 40.0);
		float flick = burst * 0.8 * sin(t * 38.0) + walk * 0.12 * sin(2.0 * gait);
		turn(VERTEX, NORMAL, vec3(side * 0.06, 0.73, -0.43), rot(vec3(0.0, 0.0, 1.0), side * flick) * rot(vec3(1.0, 0.0, 0.0), burst * 0.4));
	}

	// The head turns about the top of the neck; a grazing head drops to the grass and nibbles. The neck's wool
	// follows it more the further forward it lies, so the fleece stretches rather than tears.
	float follow = part == 1 || ear ? 1.0 : part == 9 ? clamp((-VERTEX.z - 0.24) / 0.2, 0.0, 1.0) : 0.0;
	if (follow > 0.0) {
		float look = idle * (0.5 * sin(t * 0.43) + 0.2 * sin(t * 1.3 + 1.0)) + lie * 0.45 * sin(t * 0.31) + graze * 0.2 * sin(t * 0.5);
		float tilt = idle * 0.18 * smoothstep(0.4, 0.95, sin(t * 0.29 + 2.0));
		float nibble = graze * 0.08 * sin(t * 9.0) * smoothstep(0.0, 0.6, sin(t * 0.8));
		float pitch = -graze * 1.3 + nibble + walk * 0.05 * sin(2.0 * gait) + lie * 0.1;
		vec3 v = VERTEX, n = NORMAL;
		turn(v, n, vec3(0.0, 0.58, -0.3), rot(vec3(0.0, 1.0, 0.0), look) * rot(vec3(1.0, 0.0, 0.0), pitch) * rot(vec3(0.0, 0.0, 1.0), tilt));
		v += graze * vec3(0.0, -0.18, -0.02);
		VERTEX = mix(VERTEX, v, follow);
		NORMAL = normalize(mix(NORMAL, n, follow));
	}

	if (part == 8) {
		float wag = idle * 0.35 * pow(max(sin(t * 0.5 + 0.7), 0.0), 30.0) * sin(t * 24.0) + walk * 0.2 * sin(2.0 * gait);
		turn(VERTEX, NORMAL, vec3(0.0, 0.52, 0.36), rot(vec3(0.0, 1.0, 0.0), wag));
	}

	// Walk: diagonal legs swing together, a lifted hoof on the forward swing; lie folds them under the body.
	if (leg) {
		bool front = part == 4 || part == 5;
		vec3 hip = vec3(part == 4 || part == 6 ? -0.12 : 0.12, 0.32, front ? -0.17 : 0.22);
		float g = gait + (part == 4 || part == 7 ? 0.0 : PI);
		float lift = walk * max(cos(g), 0.0);
		VERTEX.y += lift * 0.06 * clamp(1.0 - VERTEX.y / 0.32, 0.0, 1.0);
		VERTEX = hip + (VERTEX - hip) * vec3(1.0, 1.0 - 0.35 * lie, 1.0);
		turn(VERTEX, NORMAL, hip, rot(vec3(1.0, 0.0, 0.0), walk * 0.42 * sin(g) + lie * (front ? -1.5 : 1.5)));
	} else {
		VERTEX.y += walk * 0.018 * cos(2.0 * gait);
	}
	VERTEX.y -= lie * 0.2;
}

void fragment() {
	ALBEDO = COLOR.rgb * mix(vec3(1.0), wool, fleece);
	ROUGHNESS = COLOR.r < 0.1 ? 0.25 : 0.9;
	SPECULAR = COLOR.r < 0.1 ? 0.6 : 0.2;
}
