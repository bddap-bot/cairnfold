shader_type spatial;

#include "res://src/ground.gdshaderinc"
#include "res://src/bounce.gdshaderinc"
#include "res://src/detail.gdshaderinc"

// Raw like the stones' instance colours, as plaster is.
uniform vec3 albedo;
// Its build's plaster swatch over the first (Palette.tint).
instance uniform vec3 tint = vec3(1.0);

varying vec3 world_pos;
varying vec3 bounce_at;
varying vec3 lamp_at;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// The probes beside it stand among the tiles; the floor's see what the room does through its doors.
	bounce_at = bounce_on_ground(world_pos.xz);
	lamp_at = lamp_over(world_pos, normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz), ground_at(world_pos.xz));
}

void fragment() {
	ALBEDO = albedo * tint * (0.78 + texture(detail, world_pos.xz * 1.7).r * 0.45);
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
	vec4 bounce = texture(bounce_volume, bounce_at);
	AO = bounce.a;
	EMISSION = ALBEDO * given_back(bounce_at, lamp_at, bounce);
}
