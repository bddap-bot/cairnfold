shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;

#include "res://src/ground.gdshaderinc"
#include "res://src/bounce.gdshaderinc"
#include "res://src/detail.gdshaderinc"

// Its build's thatch swatch over the first (Palette.tint).
instance uniform vec3 tint = vec3(1.0);
uniform vec3 moss : source_color = vec3(0.30, 0.42, 0.14);

varying vec3 world_pos;
varying vec3 world_nrm;
varying vec3 fall;
varying vec3 bounce_at;
varying vec3 lamp_at;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	fall = normalize((MODEL_MATRIX * vec4(TANGENT, 0.0)).xyz);
	float ground = ground_at(world_pos.xz);
	bounce_at = bounce_over(world_pos, world_nrm, ground);
	lamp_at = lamp_over(world_pos, world_nrm, ground);
}

void fragment() {
	// The detail noise stretched along the way the straw runs (the vertex's tangent) reads as reed.
	vec3 across = normalize(cross(world_nrm, fall));
	vec2 uv = vec2(dot(world_pos, across) * 4.0, dot(world_pos, fall) * 0.35);
	float straw = texture(detail, uv).r * 0.65 + texture(detail, uv * vec2(2.7, 1.3) + 0.37).r * 0.35;
	vec3 base = COLOR.rgb * tint * (0.62 + straw * 0.7);
	// COLOR.a is how weathered the roof is: moss gathers on its gentler, upward faces.
	float mossy = smoothstep(0.55, 0.9, world_nrm.y) * smoothstep(0.5, 0.75, texture(detail, world_pos.xz * 0.3).r) * COLOR.a;
	ALBEDO = mix(base, moss * (0.62 + straw * 0.7), mossy * 0.35);
	ROUGHNESS = 0.95;
	SPECULAR = 0.15;
	vec4 bounce = texture(bounce_volume, bounce_at);
	AO = bounce.a;
	EMISSION = ALBEDO * given_back(bounce_at, lamp_at, bounce);
}
