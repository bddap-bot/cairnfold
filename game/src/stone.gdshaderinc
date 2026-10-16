#include "res://src/palette.gdshaderinc"
#include "res://src/bounce.gdshaderinc"

uniform sampler2D detail : filter_linear_mipmap, repeat_enable;
uniform vec3 moss : source_color = vec3(0.30, 0.42, 0.14);

varying vec3 world_pos;
varying vec3 world_nrm;
varying float occlusion;
varying vec3 tint;
varying vec3 bounce_at;

void vertex() {
#ifdef RIDES_GROUND
	// Sheared onto the ground's plane under the stone's centre, so it lies along a slope however the ground was shaped.
	vec2 c = MODEL_MATRIX[3].xz;
	vec3 n = ground_normal(c);
	vec2 slope = n.xz / n.y;
	VERTEX.y += ground_at(c) - dot(slope, VERTEX.xz - c);
	NORMAL = normalize(vec3(NORMAL.x + slope.x * NORMAL.y, NORMAL.y, NORMAL.z + slope.y * NORMAL.y));
	world_pos = VERTEX;
	world_nrm = NORMAL;
#else
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
#endif
	bounce_at = bounce_coord(world_pos, world_nrm);
	occlusion = INSTANCE_CUSTOM.x;
	tint = material_tint(INSTANCE_CUSTOM.y);
}

void fragment() {
	vec3 p = world_pos * 1.7;
	vec3 an = abs(world_nrm);
	float tri = texture(detail, p.yz).r * an.x + texture(detail, p.xz).r * an.y + texture(detail, p.xy).r * an.z;
	vec3 base = COLOR.rgb * tint * (0.78 + tri * 0.45);
	float mossy = smoothstep(0.55, 0.9, world_nrm.y) * smoothstep(0.45, 0.7, texture(detail, world_pos.xz * 0.3).r);
	ALBEDO = mix(base, moss, mossy * 0.8) * occlusion;
	ROUGHNESS = 0.92;
	SPECULAR = 0.25;
	vec4 bounce = texture(bounce_volume, bounce_at);
	AO = bounce.a;
	EMISSION = ALBEDO * given_back(bounce_at, bounce);
}
