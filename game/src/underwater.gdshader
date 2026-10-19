shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

// Motes, bubbles and shafts of sunlight about an eye under water (Underwater). Each is held still in the world and
// wrapped into a box about the head, fading out toward the box's edge, so none follows the head and none pops.
uniform float level;
uniform float reach;
uniform vec3 ray;
uniform vec3 sun;
uniform vec3 ambient;

const float SHAFT_LENGTH = 2.5;

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
		float size = kind > 0.25 ? 0.008 + COLOR.b * 0.012 : 0.005 + COLOR.b * 0.006;
		shown = (1.0 - smoothstep(0.6, 1.0, length(off) / reach)) * smoothstep(0.15, 0.4, length(p - eye));
		p += (INV_VIEW_MATRIX[0].xyz * corner.x + INV_VIEW_MATRIX[1].xyz * corner.y) * size;
	} else {
		float wide = reach * 1.5;
		vec2 off = mod(VERTEX.xz * 1.5 + TIME * vec2(0.04, 0.025) - head.xz + wide, 2.0 * wide) - wide;
		vec3 top = vec3(head.x + off.x, level, head.z + off.y);
		vec3 side = normalize(cross(ray, top - eye));
		p = top + ray * along * SHAFT_LENGTH + side * corner.x * (0.2 + COLOR.b * 0.4);
		shown = (1.0 - smoothstep(0.55, 1.0, length(off) / wide)) * smoothstep(0.4, 1.2, length(off))
			* (0.55 + 0.45 * sin(TIME * 0.35 + phase));
	}
	y = p.y;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(p, 1.0);
}

void fragment() {
	float r = length(corner);
	vec3 c;
	float a;
	if (kind < 0.25) {
		c = ambient * 2.5 + sun * 0.08;
		a = smoothstep(1.0, 0.1, r) * 0.8;
	} else if (kind < 0.75) {
		c = ambient * 3.0 + sun * 0.25;
		a = smoothstep(1.0, 0.8, r) * smoothstep(0.4, 0.85, r) * 0.7 + smoothstep(0.35, 0.0, length(corner - vec2(-0.35, 0.35))) * 0.6;
	} else {
		c = sun * vec3(0.75, 0.95, 0.9);
		a = pow(1.0 - abs(corner.x), 2.0) * pow(1.0 - along, 1.5) * smoothstep(0.0, 0.08, along) * 0.45;
	}
	ALBEDO = c;
	ALPHA = a * shown * smoothstep(0.0, 0.05, level - y);
}
