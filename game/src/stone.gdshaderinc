#include "res://src/bounce.gdshaderinc"
#include "res://src/water.gdshaderinc"

uniform sampler2D detail : filter_linear_mipmap, repeat_enable;
uniform vec3 moss : source_color = vec3(0.30, 0.42, 0.14);

varying vec3 world_pos;
varying vec3 world_nrm;
varying float occlusion;
varying vec3 bounce_at;
varying vec3 lamp_at;
// Lantern light a pane of glass (colour alpha 0, Wall.pack) shows from behind it, as bright as the lit stone and
// plaster it looks onto.
const float PANE_SHOWS = 0.6;
varying float pane;

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
	// A wall panel's ends turn by INSTANCE_CUSTOM.zw about the vertical: each end is cut along the bisector with its
	// neighbour, and its faces' normals turned to that bisector's, so a curved run of panels closes and shades round.
	float turn = VERTEX.x < 0.0 ? INSTANCE_CUSTOM.z : INSTANCE_CUSTOM.w;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (turn != 0.0) {
		VERTEX.x += VERTEX.z * length(MODEL_MATRIX[2].xyz) * tan(turn) / length(MODEL_MATRIX[0].xz);
		if (abs(NORMAL.z) > 0.5) {
			vec3 n = normalize(MODEL_MATRIX[2].xyz) * sign(NORMAL.z);
			world_nrm = vec3(n.x * cos(turn) + n.z * sin(turn), 0.0, n.z * cos(turn) - n.x * sin(turn));
			NORMAL = transpose(mat3(MODEL_MATRIX)) * world_nrm;
		}
	}
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
#endif
	bounce_at = bounce_coord(world_pos, world_nrm);
	lamp_at = lamp_coord(world_pos, world_nrm);
	pane = COLOR.a < 0.5 ? textureLod(lamp_volume, lamp_coord(world_pos, -world_nrm), 0.0).r : 0.0;
	occlusion = INSTANCE_CUSTOM.x;
}

void fragment() {
	vec3 p = world_pos * 1.7;
	vec3 an = abs(world_nrm);
	float tri = texture(detail, p.yz).r * an.x + texture(detail, p.xz).r * an.y + texture(detail, p.xy).r * an.z;
	vec3 base = COLOR.rgb * (0.78 + tri * 0.45);
	float mossy = smoothstep(0.55, 0.9, world_nrm.y) * smoothstep(0.45, 0.7, texture(detail, world_pos.xz * 0.3).r);
	ALBEDO = mix(base, moss, mossy * 0.8) * occlusion;
	ROUGHNESS = 0.92;
	SPECULAR = 0.25;
	vec4 bounce = texture(bounce_volume, bounce_at);
	AO = bounce.a;
	EMISSION = ALBEDO * given_back(bounce_at, lamp_at, bounce) + pane * lamp_light * PANE_SHOWS;
	// From above, the water's tint hides what the waves throw on sunken stone.
	if (eye_under > 0.0) {
		float wet = water_depth_at(world_pos.xz);
		EMISSION += caustic(detail, world_pos.xz) * 0.3 * step(0.02, wet) * smoothstep(0.0, 0.1, ground_at(world_pos.xz) + wet - world_pos.y);
	}
}
