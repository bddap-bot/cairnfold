shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;

#include "res://src/ground.gdshaderinc"
#include "res://src/bounce.gdshaderinc"
#include "res://src/plaster.gdshaderinc"
#include "res://src/detail.gdshaderinc"

// Raw like the stones' instance colours, so a gable matches the wall it continues.
uniform vec3 albedo;
// Its build's plaster swatch over the first (Palette.tint).
instance uniform vec3 tint = vec3(1.0);

// Probes up among a roof's tiles cannot tell a house's inside from its outside, so a gable reads the air a metre
// before it, no higher than LOW over the ground.
const float LOW = 1.5;

varying vec3 world_pos;
varying vec3 world_nrm;
#include "res://src/interior.gdshaderinc"
varying vec3 bounce_at;
varying vec3 lamp_at;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	world_nrm = n;
	room_row = room_row_at(world_pos);
	room_in = room_in_at(room_row, world_pos, n);
	vec3 q = world_pos + n;
	float ground = ground_at(q.xz);
	bounce_at = vec3((q.xz - bounce_grid.x) / bounce_grid.y, min(q.y - ground, LOW) / bounce_grid.z);
	lamp_at = volume_coord(q, ground);
}

void fragment() {
	ALBEDO = albedo * tint * plaster_surface(detail, world_pos, world_nrm, world_pos.y - ground_at(world_pos.xz));
	ROUGHNESS = 0.92;
	SPECULAR = 0.25;
	vec4 bounce = texture(bounce_volume, bounce_at);
	float sun_share = interior_light(world_pos, world_nrm, room_row, room_in);
	vec2 ao = interior_ao(sun_share, bounce.a);
	AO = ao.x;
	AO_LIGHT_AFFECT = ao.y;
	EMISSION = ALBEDO * given_back(bounce_at, lamp_at, bounce);
	EMISSION += ALBEDO * interior_ambient(sun_share, bounce.a, world_nrm);
}
