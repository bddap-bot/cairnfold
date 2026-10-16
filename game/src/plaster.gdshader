shader_type spatial;
render_mode cull_disabled;

#include "res://src/ground.gdshaderinc"
#include "res://src/bounce.gdshaderinc"

uniform vec3 albedo : source_color;
// Its build's plaster swatch over the first (Palette.tint).
instance uniform vec3 tint = vec3(1.0);

varying vec3 bounce_at;

void vertex() {
	bounce_at = bounce_coord((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz));
}

void fragment() {
	ALBEDO = albedo * tint;
	ROUGHNESS = 0.95;
	vec4 bounce = texture(bounce_volume, bounce_at);
	AO = bounce.a;
	EMISSION = ALBEDO * given_back(bounce_at, bounce);
}
