shader_type spatial;
render_mode world_vertex_coords, cull_disabled;
#include "res://src/ground.gdshaderinc"
#include "res://src/water.gdshaderinc"
#include "res://src/bounce.gdshaderinc"

varying float wet;
varying vec3 bounce_at;
varying vec3 lamp_at;
varying vec2 patch;

void vertex() {
	wet = planted_water(1.0, water_depth_at(INSTANCE_CUSTOM.zw));
	patch = VERTEX.xz;
	float mound = VERTEX.y - MODEL_MATRIX[3].y;
	VERTEX.y = ground_at(VERTEX.xz) + 0.012 + mound * mix(1.0, 0.35, wet);
	VERTEX.xz += wet * mound * 0.5 * vec2(sin(TIME * 1.4 + patch.x * 5.0), cos(TIME * 1.1 + patch.y * 4.0));
	NORMAL = ground_normal(VERTEX.xz);
	bounce_at = bounce_coord(VERTEX, NORMAL);
	lamp_at = lamp_coord(VERTEX, NORMAL);
}

void fragment() {
	float grain = sin(patch.x * 180.0 + sin(patch.y * 120.0)) * sin(patch.y * 163.0);
	ALBEDO = mix(COLOR.rgb, vec3(0.12, 0.32, 0.09), wet) * (0.9 + 0.12 * grain);
	ROUGHNESS = mix(1.0, 0.75, wet);
	vec4 bounce = texture(bounce_volume, bounce_at);
	AO = bounce.a;
	EMISSION = ALBEDO * given_back(bounce_at, lamp_at, bounce);
}
