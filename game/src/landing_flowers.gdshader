shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

// A ring of little flowers on stems that bloom one after another round it.
#include "res://src/landing.gdshaderinc"

const float RADIUS = 0.42;
const float WIDE = 0.19;
const vec3 PETALS[4] = vec3[](vec3(1.0, 0.97, 0.92), vec3(1.0, 0.42, 0.6), vec3(1.0, 0.8, 0.15), vec3(0.6, 0.46, 1.0));

varying vec3 petal;
varying float open;

void vertex() {
	vec3 c = MODEL_MATRIX[3].xyz;
	float k = length(MODEL_MATRIX[0].xyz);
	float i = float(INSTANCE_ID);
	float n = float(count);
	float a = TAU * (i + 0.3 * hash(i)) / n;
	float r = RADIUS * k * (0.92 + 0.16 * hash(i + 7.0));
	float bloom = spring((clock - 0.035 * i) / 0.3);
	float h = WIDE * k * (0.85 + 0.35 * hash(i + 3.0)) * bloom;
	open = bloom;
	petal = PETALS[int(mod(i, 4.0))];
	vec3 at = c + vec3(cos(a) * r, h, sin(a) * r);
	at.x += 0.012 * k * sin(clock * 1.7 + i);
	MODELVIEW_MATRIX = upright(VIEW_MATRIX, INV_VIEW_MATRIX[3].xyz, at, h, 2.0 * h);
}

void fragment() {
	vec2 q = vec2(UV.x - 0.5, (UV.y - 0.25) * 2.0);
	float r = length(q);
	float th = atan(q.y, q.x) + 0.6 * open;
	float edge = 0.27 + 0.2 * pow(abs(cos(2.5 * th)), 0.7);
	bool head = r < edge * open;
	bool stem = UV.y > 0.25 && abs(UV.x - 0.5 + 0.03 * (UV.y - 0.25)) < 0.035;
	if (!head && !stem) {
		discard;
	}
	vec3 col = vec3(0.16, 0.4, 0.1);
	if (head) {
		col = mix(petal * 0.82, petal, smoothstep(0.08, 0.3, r));
		col = mix(col, vec3(1.0, 0.72, 0.2), smoothstep(0.12, 0.09, r));
	}
	ALBEDO = col;
}
