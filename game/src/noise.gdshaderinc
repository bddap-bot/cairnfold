// Multiplies and adds alone, no sine: the Quest 2 pays dearly for a full-precision sine a fragment, and a sine hash
// breaks up at the mobile renderer's lower precisions.
highp float hash(highp vec2 p) {
	highp vec3 q = fract(p.xyx * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
