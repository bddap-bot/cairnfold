#include "res://src/sculpture.gdshaderinc"
#include "res://src/bounce.gdshaderinc"
#include "res://src/roof_shadow.gdshaderinc"
#include "res://src/piece.gdshaderinc"
#include "res://src/plaster.gdshaderinc"
#include "res://src/detail.gdshaderinc"
#include "res://src/palette.gdshaderinc"

uniform vec3 moss : source_color = vec3(0.30, 0.42, 0.14);
// StoneStyles index, or -1 for stone in its own colour.
instance uniform int stone_style = -1;
// Full-size surface detail while its lighting stays in the garden.
instance uniform bool miniature = false;
// Piece frame, where its shadow's box (Wall.kinds) spans -0.5 to 0.5.
varying vec3 local_pos;

varying vec3 world_nrm;
#include "res://src/interior.gdshaderinc"
varying float occlusion;
varying float material;
#ifdef GIVEN_PER_VERTEX
varying vec4 given;
#else
varying vec3 bounce_at;
varying vec3 lamp_at;
#endif
// Lamps gives the opening's spill and its glass (COLOR.a 0, Stones.glazed) the same strength.
uniform float window_glow;
global uniform float window_night;
// WallLayout.GLASS: dark by day, the glass's COLOR being its night glow.
uniform vec3 glass_colour;
varying float glass;
#ifdef ROOF_TIMBER
instance uniform vec3 timber_color = vec3(1.0);
#endif
varying vec3 pane;
varying flat int style;
varying flat float tone;
varying flat vec3 box_sun;
// In metres: less than a wall's thickness, so a grazing sun does not throw a point past what stands before it.
const float FACE_REACH = 0.5;
// Palette.code's Element values.
const float ELEMENT_MEADOW = 0.0;
const float ELEMENT_ROOF = 2.0;
const float ELEMENT_WOOD = 3.0;
const float ELEMENT_PLASTER = 4.0;
const float ELEMENT_TIMBER = 5.0;
const float ELEMENT_GLOW = 7.0;

void vertex() {
	mat4 piece = PIECE_MATRIX;
	if (piece_cut(piece, CAMERA_POSITION_WORLD)) {
		VERTEX = vec3(0.0);
	} else {
		// So a curved run of panels or a ring of wedges closes and shades round.
#ifdef ROOF_TIMBER
		float turn = 0.0;
#else
		float turn = VERTEX.x < 0.0 ? PIECE_CUSTOM.z : PIECE_CUSTOM.w;
#endif
		world_nrm = normalize((piece * vec4(NORMAL, 0.0)).xyz);
		if (turn != 0.0) {
			vec3 axis = normalize(piece[1].xyz);
			vec3 run = piece[0].xyz;
			VERTEX.x += VERTEX.z * length(piece[2].xyz) * tan(turn) / length(run - axis * dot(run, axis));
			if (abs(NORMAL.z) > 0.5) {
				vec3 n = normalize(piece[2].xyz) * sign(NORMAL.z);
				world_nrm = n * cos(turn) + cross(axis, n) * sin(turn);
				NORMAL = transpose(mat3(piece)) * world_nrm;
			}
		}
		local_pos = VERTEX;
		vec3 world_pos = laid_point((piece * vec4(VERTEX, 1.0)).xyz);
		world_nrm = laid_dir(world_nrm);
		ROOM_HERE;
#ifdef ROOF_TIMBER
		occlusion = 0.85;
		material = ELEMENT_TIMBER;
#else
		occlusion = PIECE_CUSTOM.x;
		material = PIECE_CUSTOM.y;
#endif
		box_sun = vec3(0.0);
#if !defined(BAKED) && !defined(ROOF_TIMBER)
		// A far chunk's stones stand on their flat faces, a roof's ceiling is no piece, and a boulder casts its own shape.
		if (stone_style < 0 && abs(material - ELEMENT_ROOF) >= 0.5) {
			box_sun = inverse(mat3(piece)) * sun_toward;
		}
#endif
		float ground = ground_at(world_pos.xz);
		// A tile lies on the roof over the room it is no part of, however low it reaches.
		bool cover = abs(material - ELEMENT_ROOF) < 0.5;
		vec3 q = cover ? read_over_cover(world_pos, world_nrm) : read_over(world_pos, world_nrm);
		vec3 lowest = laid_point(piece[3].xyz) - vec3(0.0, 0.5 * (abs(piece[0].y) + abs(piece[1].y) + abs(piece[2].y)), 0.0);
#ifdef ROOF_TIMBER
		float reach = 0.0;
#else
		float reach = cover ? 0.0 : ROOM_STONE_REACH;
#endif
		vec3 at = volume_coord(room_read(room_row, q, world_nrm, cover ? q : lowest, reach), ground);
#ifdef GIVEN_PER_VERTEX
		given = given_read(at, lamp_over(world_pos, world_nrm, ground));
#else
		bounce_at = at;
		lamp_at = lamp_over(world_pos, world_nrm, ground);
#endif
		glass = COLOR.a < 0.5 ? 1.0 : 0.0;
		pane = glass > 0.5 ? textureLod(lamp_volume, lamp_over(world_pos, -world_nrm, ground), 0.0).rgb : vec3(0.0);
#ifdef ROOF_TIMBER
		COLOR = vec4(timber_color, 1.0);
#endif
		// COLOR.a, read here as the glass mark, carries on to the fragment how much snow lies on the piece, worked out a
		// vertex at a time: the Quest 2 pays for every instruction a stone's fragment adds. A frame stretched unevenly
		// leans a normal it carries as is, so the face's own normal takes its inverse transpose. Snow fills a roof's
		// laps, so the lip of a tile takes some too.
		COLOR.a = 0.0;
		if (season_winter > 0.0) {
			float up = normalize(transpose(inverse(mat3(piece))) * NORMAL).y;
			up = mix(up, up * 0.5 + 0.5, step(abs(material - ELEMENT_ROOF), 0.5));
			COLOR.a = snow_cover(up, 1.0 - room_in, 0.5) * (1.0 - glass);
		}
		style = stone_style;
		tone = 0.35 + 0.3 * fract(sin(dot(laid_point(piece[3].xyz).xz, vec2(12.9898, 78.233))) * 43758.5453);
#ifdef BAKED
		VERTEX = world_pos;
		NORMAL = world_nrm;
#endif
	}
}

void fragment() {
	// Taken from the view rather than carried, a Quest 2 having no room for its varying (tests/test_varyings.gd).
	vec3 world_pos = laid_point((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	if (abs(material - ELEMENT_ROOF) < 0.5) {
		LIGHT_VERTEX += (VIEW_MATRIX * vec4(sun_toward * ROOF_PULL, 0.0)).xyz;
	}
	// The shadow is a plain box, so a point on a sunward face reads it where its ray crosses that face's plane: leaving
	// by another side would land in a joint, under the neighbouring box.
	vec3 side = abs(local_pos);
	vec3 face = side.x >= max(side.y, side.z) ? vec3(sign(local_pos.x), 0.0, 0.0) : side.y >= side.z ? vec3(0.0, sign(local_pos.y), 0.0) : vec3(0.0, 0.0, sign(local_pos.z));
	float toward = dot(face, box_sun);
	if (toward > 0.0) {
		float lift = min(max(0.5 - dot(face, local_pos), 0.0) / toward, FACE_REACH);
		LIGHT_VERTEX += (VIEW_MATRIX * vec4(sun_toward * lift, 0.0)).xyz;
	}
#ifdef GIVEN_PER_VERTEX
	vec4 bounce = given;
#else
	vec4 bounce = texture(bounce_volume, bounce_at);
#endif
	float drift = 0.5;
	if (abs(material - ELEMENT_PLASTER) < 0.5) {
		ALBEDO = SCULPTED ? SCULPTURE : COLOR.rgb * occlusion * plaster_surface(detail, world_pos, world_nrm, world_pos.y - ground_at(world_pos.xz));
	} else {
		vec3 surface_pos = miniature ? local_pos : world_pos;
		vec3 p = surface_pos * 1.7;
		vec3 an = abs(world_nrm);
		float tri = texture(detail, p.yz).r * an.x + texture(detail, p.xz).r * an.y + texture(detail, p.xy).r * an.z;
		vec3 base = COLOR.rgb * (0.78 + tri * 0.45);
		// Unpainted parts (ELEMENT_MEADOW: iron, curtains, flowers) stay bare.
		float wood = step(abs(material - ELEMENT_WOOD), 0.5) + step(abs(material - ELEMENT_TIMBER), 0.5) + step(material, ELEMENT_MEADOW + 0.5) + step(abs(material - ELEMENT_GLOW), 0.5);
		float patch = texture(detail, surface_pos.xz * 0.3).r;
		drift = patch;
		float mossy = smoothstep(0.55, 0.9, world_nrm.y) * smoothstep(0.45, 0.7, patch) * smoothstep(0.35, 0.7, bounce.a) * (1.0 - wood);
		if (style >= 0) {
			// The styles' tones are linear, stone's own colours not, so they convert before COLOR tints them (Boulders).
			base = pow(stone_rock(style, tone, moss, patch, mix(0.5, tri, stone_look[style].w)), vec3(1.0 / 2.2)) * COLOR.rgb;
			float m = stone_look[style].y;
			mossy = smoothstep(0.9 - m, 1.0 - m * 0.6, world_nrm.y) * smoothstep(0.5 - m * 0.6, 0.6, patch) * smoothstep(0.35, 0.7, bounce.a) * min(m * 2.0, 1.0);
		}
		ALBEDO = SCULPTED ? SCULPTURE : mix(mix(base, moss, mossy * 0.8), glass_colour, glass) * occlusion;
	}
	float snowy = 0.0;
	if (COLOR.a > 0.0) {
		// The amount a vertex carries blends down a rounded stone's face; the face's own slope keeps it on the top.
		float face_up = mix(smoothstep(0.3, 0.6, world_nrm.y), 1.0, step(abs(material - ELEMENT_ROOF), 0.5));
		snowy = clamp(COLOR.a * (0.7 + 0.6 * drift) * face_up, 0.0, 1.0);
		ALBEDO = mix(ALBEDO, SNOW, snowy);
	}
	ROUGHNESS = style >= 0 ? stone_look[style].w : 0.92;
	SPECULAR = 0.25;
#ifdef GIVEN_PER_VERTEX
	EMISSION = ALBEDO * given.rgb + pane * lamp_light * window_glow + glass * COLOR.rgb * window_night;
#else
	EMISSION = ALBEDO * given_back(lamp_at, bounce) + pane * lamp_light * window_glow + glass * COLOR.rgb * window_night;
#endif
	TAKE_ROOM(bounce.a);
	// Snow lies under the open sky, whatever the builds around hide of it from the probe the face reads (thatch too).
	if (snowy > 0.0) {
		EMISSION += ALBEDO * snowy * (1.0 - bounce.a) * sky_ambient * mix(sky_horizon, sky_zenith, 0.8);
	}
}
