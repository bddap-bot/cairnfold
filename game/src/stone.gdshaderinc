#include "res://src/bounce.gdshaderinc"
#include "res://src/roof_shadow.gdshaderinc"
#include "res://src/piece.gdshaderinc"
#include "res://src/plaster.gdshaderinc"
#include "res://src/detail.gdshaderinc"

uniform vec3 moss : source_color = vec3(0.30, 0.42, 0.14);
// A boulder's style (StoneStyles, stone_ground.gdshaderinc), or -1 for stone in its own colour.
instance uniform int stone_style = -1;
// A wheel boulder keeps full-size surface detail while its lighting stays in the garden.
instance uniform bool miniature = false;
varying vec3 surface_pos;

varying vec3 world_pos;
varying vec3 world_nrm;
varying float occlusion;
varying float material;
#ifdef GIVEN_PER_VERTEX
// Bounce's given_at, read once a vertex: Stones.small_material.
varying vec4 given;
#else
varying vec3 bounce_at;
varying vec3 lamp_at;
#endif
// Lamps supplies the same strength to the opening's spill and its glass (colour alpha 0, Stones.glazed).
uniform float window_glow;
// How strongly a room's glass glows at night in its colour (Look, Daylight.lit), on top of the lamps' light behind it.
global uniform float window_night;
// Glass by day (WallLayout.GLASS): dark, its own colour being the glow it shines at night.
uniform vec3 glass_colour;
varying float glass;
#ifdef ROOF_TIMBER
instance uniform vec3 timber_color = vec3(1.0);
#endif
varying vec3 pane;
varying flat int style;
// A styled boulder's tone within its style, its own from where it stands.
varying flat float tone;

void vertex() {
	mat4 piece = PIECE_MATRIX;
	// A piece's ends turn by its custom data's zw about its local y: a wall panel's each cut along the bisector with its
	// neighbour, an arch's wedge on lines through the arch's centre; its z faces' normals turn with each end, so a
	// curved run of panels or a ring of wedges closes and shades round.
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
	world_pos = (piece * vec4(VERTEX, 1.0)).xyz;
	surface_pos = miniature ? VERTEX : world_pos;
#ifdef ROOF_TIMBER
	occlusion = 0.85;
	material = 5.0;
#else
	occlusion = PIECE_CUSTOM.x;
	material = PIECE_CUSTOM.y;
#endif
	float ground = ground_at(world_pos.xz);
	// Palette.Element ROOF: the covering.
	vec3 at = abs(material - 2.0) < 0.5 ? bounce_over_cover(world_pos, world_nrm, ground) : bounce_over(world_pos, world_nrm, ground);
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
	style = stone_style;
	tone = 0.35 + 0.3 * fract(sin(dot(piece[3].xz, vec2(12.9898, 78.233))) * 43758.5453);
#ifdef BAKED
	VERTEX = world_pos;
	NORMAL = world_nrm;
#endif
}

void fragment() {
	if (abs(material - 2.0) < 0.5) {
		LIGHT_VERTEX += (VIEW_MATRIX * vec4(sun_toward * ROOF_PULL, 0.0)).xyz;
	}
#ifdef GIVEN_PER_VERTEX
	vec4 bounce = given;
#else
	vec4 bounce = texture(bounce_volume, bounce_at);
#endif
	if (abs(material - 4.0) < 0.5) {
		ALBEDO = COLOR.rgb * occlusion * plaster_surface(detail, world_pos, world_nrm, world_pos.y - ground_at(world_pos.xz));
	} else {
		vec3 p = surface_pos * 1.7;
		vec3 an = abs(world_nrm);
		float tri = texture(detail, p.yz).r * an.x + texture(detail, p.xz).r * an.y + texture(detail, p.xy).r * an.z;
		vec3 base = COLOR.rgb * (0.78 + tri * 0.45);
		// Moss takes stone out under the sky: a floor under its roof, woodwork (Palette.Element WOOD, TIMBER), glass (GLOW)
		// and parts with no paint (iron, curtains, flowers) stay bare.
		float wood = step(abs(material - 3.0), 0.5) + step(abs(material - 5.0), 0.5) + step(material, 0.5) + step(abs(material - 7.0), 0.5);
		float patch = texture(detail, surface_pos.xz * 0.3).r;
		float mossy = smoothstep(0.55, 0.9, world_nrm.y) * smoothstep(0.45, 0.7, patch) * smoothstep(0.35, 0.7, bounce.a) * (1.0 - wood);
		if (style >= 0) {
			// The styles' tones are linear where stone's own colours are not, so they come back to stone's before its
			// paint tints them (Boulders: the swatch over the one stone is laid in) and its shade darkens them.
			base = pow(stone_rock(style, tone, moss, patch, mix(0.5, tri, stone_look[style].w)), vec3(1.0 / 2.2)) * COLOR.rgb;
			// A style's moss caps its boulders as far down their flanks as it grows thick: none on a river cobble.
			float m = stone_look[style].y;
			mossy = smoothstep(0.9 - m, 1.0 - m * 0.6, world_nrm.y) * smoothstep(0.5 - m * 0.6, 0.6, patch) * smoothstep(0.35, 0.7, bounce.a) * min(m * 2.0, 1.0);
		}
		ALBEDO = mix(mix(base, moss, mossy * 0.8), glass_colour, glass) * occlusion;
	}
	ROUGHNESS = style >= 0 ? stone_look[style].w : 0.92;
	SPECULAR = 0.25;
	AO = bounce.a;
#ifdef GIVEN_PER_VERTEX
	EMISSION = ALBEDO * given.rgb + pane * lamp_light * window_glow + glass * COLOR.rgb * window_night;
#else
	EMISSION = ALBEDO * given_back(bounce_at, lamp_at, bounce) + pane * lamp_light * window_glow + glass * COLOR.rgb * window_night;
#endif
}
