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
	// The probes beside it stand among the tiles; the floor's see what the room does through its doors.
	bounce_at = bounce_on_ground(world_pos.xz);
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	lamp_at = lamp_over(world_pos, world_nrm, ground_at(world_pos.xz));
	room_row = room_row_at(world_pos);
	room_in = room_in_at(room_row, world_pos, world_nrm);
}

void fragment() {
	vec3 p = world_pos * 1.7;
	vec3 n = abs((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float grain = COLOR.r > 0.5 ? (n.x > n.z ? texture(detail, p.yz).r : texture(detail, p.xy).r) : texture(detail, p.xz).r;
	ALBEDO = albedo * mix(tint, backing_tint, COLOR.r) * (0.78 + grain * 0.45);
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
	vec4 bounce = texture(bounce_volume, bounce_at);
	float sun_share = interior_light(world_pos, world_nrm, room_row, room_in);
	vec2 ao = interior_ao(sun_share, bounce.a);
	AO = ao.x;
	AO_LIGHT_AFFECT = ao.y;
	EMISSION = ALBEDO * given_back(bounce_at, lamp_at, bounce);
	EMISSION += ALBEDO * interior_ambient(sun_share, bounce.a, world_nrm);
}
