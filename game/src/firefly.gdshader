shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// INSTANCE_CUSTOM: x the clock time the firefly came, or went if negative; y its own seed.
uniform float clock = 0.0;
uniform float dusk = 0.0;
uniform float fade;
uniform vec3 tint : source_color = vec3(0.78, 1.0, 0.35);

varying float glow;

void vertex() {
	float s = INSTANCE_CUSTOM.y;
	float t = TIME + s;
	vec3 drift = vec3(sin(t * 0.31 + s) + 0.5 * sin(t * 0.73 + s * 2.1), 0.5 * sin(t * 0.47 + s * 3.7), cos(t * 0.27 + s * 1.3) + 0.5 * sin(t * 0.61 + s * 0.7)) * 0.35;
	float born = INSTANCE_CUSTOM.x;
	float here = born > 0.0 ? clamp((clock - born) / fade, 0.0, 1.0) : clamp(1.0 - (clock + born) / fade, 0.0, 1.0);
	// A slow flash every few seconds, each firefly on its own beat, with a faint glow between.
	float period = 1.8 + fract(s * 0.37) * 2.2;
	float beat = fract(t / period);
	float flash = smoothstep(0.0, 0.15, beat) * (1.0 - smoothstep(0.15, 0.55, beat));
	glow = (0.25 + flash) * here * dusk;
	float scale = length(MODEL_MATRIX[0].xyz) * (0.7 + 0.5 * flash);
	vec3 at = MODEL_MATRIX[3].xyz + drift;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * scale, INV_VIEW_MATRIX[1] * scale, INV_VIEW_MATRIX[2] * scale, vec4(at, 1.0));
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float core = smoothstep(0.14, 0.04, d);
	float halo = pow(max(1.0 - d, 0.0), 2.5) * 0.45;
	ALBEDO = tint * (core * 2.5 + halo) * glow;
}
