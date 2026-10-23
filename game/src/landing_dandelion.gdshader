shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Dandelion seeds lifting off a ring on the ground one after another and drifting up on the breeze.
#include "res://src/landing.gdshaderinc"
#include "res://src/billboard.gdshaderinc"

const float RADIUS = 0.42;
const float LIFE = 2.6;
const float RAYS = 11.0;

varying float fade;

void vertex() {
	vec3 c = MODEL_MATRIX[3].xyz;
	float k = length(MODEL_MATRIX[0].xyz);
	float i = float(INSTANCE_ID);
	float n = float(count);
	float t = fract(clock / LIFE + i / n * 3.0);
	float a = TAU * (i + 0.4 * hash(i)) / n + 0.6 * t;
	float r = RADIUS * k * (1.0 + 0.35 * t);
	float h = k * (0.07 + 0.75 * t * t + 0.2 * t);
	vec3 at = c + vec3(cos(a) * r, h, sin(a) * r);
	at.x += 0.05 * k * t * sin(clock * 2.0 + i * 2.3);
	fade = smoothstep(0.0, 0.08, t) * (1.0 - smoothstep(0.55, 1.0, t)) * smoothstep(0.0, 0.3, clock - 0.01 * i);
	MODELVIEW_MATRIX = billboard(VIEW_MATRIX, INV_VIEW_MATRIX, at, 0.15 * k);
}

void fragment() {
	vec2 q = UV - vec2(0.5, 0.38);
	float r = length(q);
	float th = atan(q.x, -q.y);
	float arc = abs(fract(th * RAYS / TAU) - 0.5) * TAU / RAYS * r;
	float ray = smoothstep(0.022, 0.006, arc) * step(r, 0.34) * step(abs(th), 2.45);
	float fuzz = 0.3 * smoothstep(0.36, 0.12, r) * step(abs(th), 2.45);
	float stalk = smoothstep(0.018, 0.008, abs(q.x)) * step(0.0, q.y) * step(q.y, 0.36);
	float seed = smoothstep(0.05, 0.03, length((q - vec2(0.0, 0.42)) * vec2(1.0, 0.45)));
	float puff = max(max(ray, fuzz), max(stalk, seed));
	ALBEDO = mix(vec3(1.0, 0.99, 0.95), vec3(0.45, 0.33, 0.2), seed);
	ALPHA = puff * fade * 0.95;
}
