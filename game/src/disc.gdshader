shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// The sun's or the moon's disc and its glow, turned to the eye: drawn apart from the sky so turning the sky
// moves it every frame without restarting the sky's radiance update.

uniform vec3 tint : source_color = vec3(1.0, 0.95, 0.85);
uniform float radius = 0.28;
// 0 for the sun's hot disc and tight corona; 1 for the moon's soft, mottled face in a wide halo.
uniform float moon = 0.0;

#include "res://src/billboard.gdshaderinc"

void vertex() {
	MODELVIEW_MATRIX = billboard(VIEW_MATRIX, INV_VIEW_MATRIX, MODEL_MATRIX[3].xyz, length(MODEL_MATRIX[0].xyz));
}

float blot(vec2 p, vec2 at, float r) {
	return smoothstep(r, r * 0.25, length(p - at));
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float d = length(p);
	float disc = smoothstep(radius, radius * mix(0.8, 0.94, moon), d);
	if (moon < 0.5) {
		float corona = pow(max(1.0 - d, 0.0), 3.0) * 0.5;
		ALBEDO = tint * (disc * 8.0 + corona);
	} else {
		vec2 f = p / radius;
		float seas = blot(f, vec2(-0.30, -0.18), 0.40) * 0.7 + blot(f, vec2(-0.05, -0.36), 0.26) * 0.6
			+ blot(f, vec2(0.24, -0.26), 0.28) * 0.65 + blot(f, vec2(0.08, 0.08), 0.22) * 0.55
			+ blot(f, vec2(-0.40, 0.24), 0.24) * 0.5 + blot(f, vec2(0.40, 0.10), 0.16) * 0.4
			+ blot(f, vec2(0.18, 0.46), 0.10) * 0.35 + blot(f, vec2(-0.12, 0.58), 0.08) * 0.3;
		float limb = sqrt(max(1.0 - dot(f, f), 0.0));
		vec3 face = mix(vec3(1.0, 0.93, 0.80), vec3(0.50, 0.55, 0.66), min(seas, 1.0) * 0.75) * mix(0.78, 1.0, limb);
		float halo = exp(-d * 5.5) * 0.55 + exp(-d * 16.0) * 0.25;
		ALBEDO = tint * halo * (1.0 - disc) + face * dot(tint, vec3(0.3, 0.5, 0.2)) * disc * 1.6;
	}
}
