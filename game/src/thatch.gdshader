shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;

#include "res://src/sculpture.gdshaderinc"
#include "res://src/ground.gdshaderinc"
#include "res://src/bounce.gdshaderinc"
#include "res://src/roof_shadow.gdshaderinc"
#include "res://src/detail.gdshaderinc"
#include "res://src/palette.gdshaderinc"

// Its build's thatch swatch over the first (Palette.tint).
instance uniform vec3 tint = vec3(1.0);
uniform vec3 moss : source_color = vec3(0.30, 0.42, 0.14);

varying vec3 world_pos;
varying vec3 world_nrm;
#include "res://src/interior.gdshaderinc"
varying vec3 fall;
varying vec3 bounce_at;
varying vec3 lamp_at;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	ROOM_HERE;
	fall = normalize((MODEL_MATRIX * vec4(TANGENT, 0.0)).xyz);
	float ground = ground_at(world_pos.xz);
	bounce_at = volume_coord(room_read(room_row, read_over_cover(world_pos, world_nrm), world_nrm, world_pos, 0.0), ground);
	lamp_at = lamp_over(world_pos, world_nrm, ground);
}

void fragment() {
	LIGHT_VERTEX += (VIEW_MATRIX * vec4(sun_toward * ROOF_PULL, 0.0)).xyz;
	vec3 across = normalize(cross(world_nrm, fall));
	vec2 uv = vec2(dot(world_pos, across) * 4.0, dot(world_pos, fall) * 0.35);
	float straw = texture(detail, uv).r * 0.65 + texture(detail, uv * vec2(2.7, 1.3) + 0.37).r * 0.35;
	vec3 base = COLOR.rgb * tint * (0.62 + straw * 0.7);
	// COLOR.a: how weathered the roof is.
	float mossy = smoothstep(0.55, 0.9, world_nrm.y) * smoothstep(0.5, 0.75, texture(detail, world_pos.xz * 0.3).r) * COLOR.a;
	ALBEDO = SCULPTED ? SCULPTURE : mix(base, moss * (0.62 + straw * 0.7), mossy * 0.35);
	float snowy = 0.0;
	if (season_winter > 0.0) {
		snowy = snow_cover(world_nrm.y, 1.0 - room_in, straw);
		ALBEDO = mix(ALBEDO, SNOW, snowy);
	}
	ROUGHNESS = 0.95;
	SPECULAR = 0.15;
	vec4 bounce = texture(bounce_volume, bounce_at);
	EMISSION = ALBEDO * given_back(lamp_at, bounce);
	TAKE_ROOM(bounce.a);
	EMISSION += ALBEDO * snowy * (1.0 - bounce.a) * sky_ambient * mix(sky_horizon, sky_zenith, 0.8);
}
