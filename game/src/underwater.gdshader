shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform float level;
uniform float reach;
uniform float bottom;
uniform vec3 sun;
uniform vec3 ambient;

#include "res://src/bed_light.gdshaderinc"

varying float kind;
varying vec2 corner;
varying float shown;
varying float along;
varying float y;

void vertex() {
	vec3 head = NODE_POSITION_WORLD;
	vec3 eye = INV_VIEW_MATRIX[3].xyz;
	float phase = COLOR.g * 6.2832;
	kind = COLOR.r;
	corner = UV * 2.0 - 1.0;
	along = UV.y;
	vec3 p;
	if (kind < 0.75) {
		vec3 drift = kind > 0.25
			? vec3(sin(TIME * 2.1 + phase) * 0.02, TIME * 0.32, cos(TIME * 1.7 + phase) * 0.02)
			: vec3(sin(TIME * 0.21 + phase), sin(TIME * 0.13 + phase * 1.7), cos(TIME * 0.17 + phase)) * 0.2 + vec3(0.03, -0.006, 0.02) * TIME;
		vec3 off = mod(VERTEX + drift - head + reach, 2.0 * reach) - reach;
		p = head + off;
		float size = kind > 0.25 ? 0.012 + COLOR.b * 0.02 : 0.012 + COLOR.b * 0.012;
		shown = (1.0 - smoothstep(0.6, 1.0, length(off) / reach)) * smoothstep(0.5, 1.0, length(p - eye));
		p += (INV_VIEW_MATRIX[0].xyz * corner.x + INV_VIEW_MATRIX[1].xyz * corner.y) * size;
	} else {
		vec2 surface_eye = head.xz - water_ray.xz * (level - head.y) / -water_ray.y;
		vec2 cell = floor(surface_eye / DAPPLE_CELL) + VERTEX.xz;
		vec3 top = vec3(dapple_center(cell).x, level, dapple_center(cell).y);
		vec3 side = normalize(cross(water_ray, top - eye));
		float span = max(0.0, level - bottom) / -water_ray.y;
		p = top + water_ray * along * span + side * corner.x * dapple_radius(cell);
		shown = (1.0 - smoothstep(2.0, 3.0, length(top.xz - surface_eye) / DAPPLE_CELL))
			* smoothstep(0.8, 1.8, length(top + water_ray * span * 0.5 - eye)) * dapple_strength(cell);
	}
	y = p.y;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(p, 1.0);
}

void fragment() {
	float r = length(corner);
	vec3 c;
	float a;
	if (kind < 0.25) {
		c = ambient * 5.0 + sun * 0.3;
		a = smoothstep(1.0, 0.1, r) * 0.8;
	} else if (kind < 0.75) {
		c = ambient * 3.0 + sun * 0.25;
		a = smoothstep(1.0, 0.8, r) * smoothstep(0.4, 0.85, r) * 0.7 + smoothstep(0.35, 0.0, length(corner - vec2(-0.35, 0.35))) * 0.6;
	} else {
		c = (ambient * 5.0 + sun * 0.6) * vec3(0.85, 1.0, 0.95);
		a = pow(1.0 - abs(corner.x), 1.5) * mix(0.6, 0.25, along) * smoothstep(0.0, 0.03, along);
	}
	ALBEDO = c;
	ALPHA = a * shown * smoothstep(0.0, 0.05, level - y);
}
