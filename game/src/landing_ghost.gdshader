shader_type spatial;
render_mode unshaded, blend_mix, depth_prepass_alpha, cull_back, shadows_disabled, fog_disabled;

// The player's own avatar as a ghost standing where they will: a glowing rim, a faint body and slow bands of light
// rising through it, drawn up from the feet as it appears.
#include "res://src/landing.gdshaderinc"

const vec3 GLOW = vec3(0.62, 0.86, 1.0);

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float up = (world.y - base) / size;
	if (up > clock * 4.0) {
		discard;
	}
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.0);
	float band = 0.8 + 0.2 * sin(up * 30.0 - clock * 5.0);
	float edge = smoothstep(0.15, 0.0, clock * 4.0 - up);
	ALBEDO = mix(GLOW, vec3(1.0), rim + edge) * band;
	ALPHA = clamp(0.3 + 0.6 * rim + edge, 0.0, 1.0);
}
