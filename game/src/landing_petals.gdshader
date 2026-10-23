shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Blossom petals spiralling down and fluttering onto where the player will land, each touch sending out a ripple.
#include "res://src/landing.gdshaderinc"

const float RADIUS = 0.42;
const float FALL = 2.8;
const vec3 PINK = vec3(0.95, 0.38, 0.58);

varying float ground;
varying float fade;
varying float tint;

void vertex() {
	vec3 c = MODEL_MATRIX[3].xyz;
	float k = length(MODEL_MATRIX[0].xyz);
	float i = float(INSTANCE_ID);
	ground = INSTANCE_ID == 0 ? 1.0 : 0.0;
	tint = hash(i + 1.0);
	if (INSTANCE_ID == 0) {
		fade = fract(clock / 1.3);
		MODELVIEW_MATRIX = flat_on_ground(VIEW_MATRIX, c + vec3(0.0, 0.06 * k, 0.0), 2.0 * RADIUS * k * (0.7 + 0.8 * fade));
	} else {
		float n = float(count - 1);
		float t = fract(clock / FALL + i / n * 2.0);
		float a = TAU * i / n + 2.2 * t;
		float r = RADIUS * k * (1.35 - 0.35 * t);
		float h = k * (0.04 + 0.7 * (1.0 - t));
		fade = smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(0.85, 1.0, t)) * smoothstep(0.0, 0.3, clock - 0.02 * i);
		float spin = clock * (3.0 + 2.0 * tint) + i;
		vec3 x = vec3(cos(spin), 0.35 * sin(spin * 1.3), sin(spin));
		vec3 y = normalize(cross(vec3(sin(spin * 0.7), 1.0, cos(spin * 0.9)), x));
		float w = 0.11 * k;
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(x * w, 0.0), vec4(y * w * 1.3, 0.0), vec4(cross(x, y), 0.0), vec4(c + vec3(cos(a) * r, h, sin(a) * r), 1.0));
	}
}

void fragment() {
	if (ground > 0.5) {
		float d = length(UV - 0.5) * 2.0;
		float ring = smoothstep(0.08, 0.0, abs(d - 0.85));
		ALBEDO = mix(vec3(1.0), PINK, 0.4);
		ALPHA = ring * (1.0 - fade) * 0.7;
	} else {
		vec2 q = UV - vec2(0.5, 0.15);
		float half_w = 0.42 * sin(PI * clamp(q.y / 0.8, 0.0, 1.0)) * (1.0 - 0.25 * smoothstep(0.65, 0.8, q.y));
		float notch = smoothstep(0.06, 0.0, abs(q.x)) * smoothstep(0.68, 0.8, q.y);
		float a = smoothstep(0.02, 0.0, abs(q.x) - half_w) * (1.0 - notch);
		ALBEDO = mix(mix(PINK, vec3(1.0, 0.92, 0.95), tint * 0.6), vec3(0.95, 0.5, 0.65), smoothstep(0.35, 0.0, q.y));
		ALPHA = a * fade;
	}
}
