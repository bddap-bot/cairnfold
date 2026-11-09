shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform;

#include "res://src/particle.gdshaderinc"

varying vec4 particle_color;

void vertex() {
	particle_color = COLOR;
	particle_vertex(VERTEX, NORMAL, particle_color, MODEL_MATRIX, INSTANCE_CUSTOM, VIEW_MATRIX, INV_VIEW_MATRIX, PROJECTION_MATRIX);
}

void fragment() {
	vec4 c = particle_fragment(particle_color, UV);
	if (c.a < cutoff) {
		discard;
	}
	ALBEDO = c.rgb;
}
