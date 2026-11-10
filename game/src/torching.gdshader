shader_type spatial;

#include "res://src/ground.gdshaderinc"
#include "res://src/bounce.gdshaderinc"
#include "res://src/detail.gdshaderinc"

// Raw like the stones' instance colours, as plaster is.
uniform vec3 albedo;
// Its build's plaster swatch over the first (Palette.tint).
instance uniform vec3 tint = vec3(1.0);
instance uniform vec3 backing_tint = vec3(1.0);

varying vec3 world_pos;
varying vec3 world_nrm;
#include "res://src/interior.gdshaderinc"
varying vec3 bounce_at;
varying vec3 lamp_at;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float ground = ground_at(world_pos.xz);
	ROOM_HERE;
	// The probes beside it stand among the tiles; the floor's see what the room does through its doors. A gable's
	// outer backing shows where its courses stop short of the apex, so it reads the air outside as their stones do.
	bool outside = COLOR.r > 0.5 && !within_walls(world_pos.xz + world_nrm.xz * 0.5);
	bounce_at = outside ? bounce_over(world_pos, world_nrm, ground) : bounce_on_ground(room_read(room_row, world_pos, world_nrm, world_pos, ROOM_TORCHING_REACH).xz);
	lamp_at = lamp_over(world_pos, world_nrm, ground);
}

void fragment() {
	vec3 p = world_pos * 1.7;
	vec3 n = abs((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float grain = COLOR.r > 0.5 ? (n.x > n.z ? texture(detail, p.yz).r : texture(detail, p.xy).r) : texture(detail, p.xz).r;
	ALBEDO = albedo * mix(tint, backing_tint, COLOR.r) * (0.78 + grain * 0.45);
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
	vec4 bounce = texture(bounce_volume, bounce_at);
	EMISSION = ALBEDO * given_back(bounce_at, lamp_at, bounce);
	TAKE_ROOM(bounce.a);
}
