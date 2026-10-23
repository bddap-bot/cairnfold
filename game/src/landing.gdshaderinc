// What every destination halo shares: its pieces stand about the node's origin at the node's scale.
uniform float clock = 0.0;
uniform int count = 1;
// The height the halo stands at and its scale, for pieces that are not placed by it.
uniform float base = 0.0;
uniform float size = 1.0;

float hash(float n) {
	return fract(sin(n * 12.9898 + 4.1414) * 43758.5453);
}

// A quad's x along `right` and its y up, `w` wide and `h` tall, its centre at `at`.
mat4 upright(mat4 view, vec3 eye, vec3 at, float w, float h) {
	vec3 f = eye - at;
	f.y = 0.0;
	f = length(f) > 1e-4 ? normalize(f) : vec3(0.0, 0.0, 1.0);
	vec3 r = normalize(cross(vec3(0.0, 1.0, 0.0), f));
	return view * mat4(vec4(r * w, 0.0), vec4(0.0, h, 0.0, 0.0), vec4(f, 0.0), vec4(at, 1.0));
}

// A quad laid flat on the ground, `w` across, its centre at `at`.
mat4 flat_on_ground(mat4 view, vec3 at, float w) {
	return view * mat4(vec4(w, 0.0, 0.0, 0.0), vec4(0.0, 0.0, -w, 0.0), vec4(0.0, 1.0, 0.0, 0.0), vec4(at, 1.0));
}

// 0 to 1 with a little overshoot, as a thing springs up.
float spring(float t) {
	t = clamp(t, 0.0, 1.0);
	return t + 0.35 * sin(t * PI);
}
