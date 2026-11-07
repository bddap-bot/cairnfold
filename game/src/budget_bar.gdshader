shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;
uniform float fill = 0.0;
uniform float pending = 0.0;
uniform float over = 0.0;
uniform vec2 size = vec2(0.036, 0.0065);
const vec3 TRACK = vec3(0.16, 0.14, 0.12);
const vec3 CALM = vec3(0.52, 0.74, 0.42);
const vec3 NEAR = vec3(0.95, 0.68, 0.28);
const vec3 GHOST = vec3(0.98, 0.95, 0.86);
const vec3 NO = vec3(0.92, 0.3, 0.26);
void fragment() {
	vec2 p = (UV - 0.5) * size;
	float r = size.y * 0.5;
	vec2 q = abs(p) - vec2(size.x * 0.5 - r, 0.0);
	float d = length(max(q, 0.0)) - r;
	if (d > 0.0) {
		discard;
	}
	float x = UV.x;
	float inset = step(d, -size.y * 0.18);
	vec3 c = TRACK;
	float shown = clamp(fill, 0.0, 1.0);
	if (inset > 0.5 && x < shown) {
		c = mix(CALM, NEAR, smoothstep(0.7, 1.0, shown));
	} else if (inset > 0.5 && x < clamp(fill + pending, 0.0, 1.0)) {
		c = GHOST;
	}
	if (over > 0.5) {
		c = mix(c, NO, 0.65 + 0.35 * sin(TIME * 12.0));
	}
	ALBEDO = c;
}
