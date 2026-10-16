shader_type spatial;
render_mode cull_disabled;

#include "res://src/ground.gdshaderinc"
#include "res://src/palette.gdshaderinc"
#include "res://src/bounce.gdshaderinc"

uniform vec3 albedo : source_color;

varying vec3 bounce_at;

void vertex() {
	bounce_at = bounce_coord((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz));
}

void fragment() {
	ALBEDO = albedo * tint_plaster;
	ROUGHNESS = 0.95;
	vec4 bounce = texture(bounce_volume, bounce_at);
	AO = bounce.a;
	EMISSION = ALBEDO * given_back(bounce_at, bounce);
}
