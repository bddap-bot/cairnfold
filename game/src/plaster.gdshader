shader_type spatial;
render_mode diffuse_lambert_wrap;

#include "res://src/ground.gdshaderinc"
#include "res://src/bounce.gdshaderinc"

// Raw like the stones' instance colours, so a gable matches the wall it continues.
uniform vec3 albedo;
// Its build's plaster swatch over the first (Palette.tint).
instance uniform vec3 tint = vec3(1.0);
uniform sampler2D detail : filter_linear_mipmap, repeat_enable;

varying vec3 world_pos;
varying vec3 bounce_at;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	bounce_at = bounce_coord(world_pos, n);
}

void fragment() {
	// The plaster panels' grain (stone.gdshaderinc) on a vertical face, so a gable reads as the wall below it.
	vec3 p = world_pos * 1.7;
	vec3 n = abs((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float grain = n.x > n.z ? texture(detail, p.yz).r : texture(detail, p.xy).r;
	ALBEDO = albedo * tint * (0.78 + grain * 0.45);
	ROUGHNESS = 0.92;
	SPECULAR = 0.25;
	vec4 bounce = texture(bounce_volume, bounce_at);
	AO = bounce.a;
	EMISSION = ALBEDO * given_back(bounce_at, bounce);
}
