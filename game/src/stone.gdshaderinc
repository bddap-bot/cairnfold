#include "res://src/bounce.gdshaderinc"
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
varying vec3 bounce_at;
varying vec3 lamp_at;
// Lamps supplies the same strength to the opening's spill and its glass (colour alpha 0, Wall.pack).
uniform float window_glow;
#ifdef ROOF_TIMBER
instance uniform vec3 timber_color = vec3(1.0);
#endif
varying float pane;
varying flat int style;
// A styled boulder's tone within its style, its own from where it stands.
varying flat float tone;

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
	// A piece's ends turn by INSTANCE_CUSTOM.zw about its local y: a wall panel's each cut along the bisector with its
	// neighbour, an arch's wedge on lines through the arch's centre; its z faces' normals turn with each end, so a
	// curved run of panels or a ring of wedges closes and shades round.
	#ifdef ROOF_TIMBER
	float turn = 0.0;
#else
	float turn = VERTEX.x < 0.0 ? INSTANCE_CUSTOM.z : INSTANCE_CUSTOM.w;
#endif
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (turn != 0.0) {
		vec3 axis = normalize(MODEL_MATRIX[1].xyz);
		vec3 run = MODEL_MATRIX[0].xyz;
		VERTEX.x += VERTEX.z * length(MODEL_MATRIX[2].xyz) * tan(turn) / length(run - axis * dot(run, axis));
		if (abs(NORMAL.z) > 0.5) {
			vec3 n = normalize(MODEL_MATRIX[2].xyz) * sign(NORMAL.z);
			world_nrm = n * cos(turn) + cross(axis, n) * sin(turn);
			NORMAL = transpose(mat3(MODEL_MATRIX)) * world_nrm;
		}
	}
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
#endif
	surface_pos = miniature ? VERTEX : world_pos;
	bounce_at = bounce_coord(world_pos, world_nrm);
	lamp_at = lamp_coord(world_pos, world_nrm);
	pane = COLOR.a < 0.5 ? textureLod(lamp_volume, lamp_coord(world_pos, -world_nrm), 0.0).r : 0.0;
#ifdef ROOF_TIMBER
	COLOR = vec4(timber_color, 1.0);
	occlusion = 0.85;
	material = 5.0;
#else
	occlusion = INSTANCE_CUSTOM.x;
	material = INSTANCE_CUSTOM.y;
#endif
	style = stone_style;
	tone = 0.35 + 0.3 * fract(sin(dot(MODEL_MATRIX[3].xz, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec4 bounce = texture(bounce_volume, bounce_at);
	if (abs(material - 4.0) < 0.5) {
		ALBEDO = COLOR.rgb * occlusion * plaster_surface(detail, world_pos, world_nrm, world_pos.y - ground_at(world_pos.xz));
	} else {
		vec3 p = surface_pos * 1.7;
		vec3 an = abs(world_nrm);
		float tri = texture(detail, p.yz).r * an.x + texture(detail, p.xz).r * an.y + texture(detail, p.xy).r * an.z;
		vec3 base = COLOR.rgb * (0.78 + tri * 0.45);
		// Moss takes stone out under the sky: a floor under its roof and woodwork (Palette.Element WOOD, TIMBER) stay bare.
		float wood = step(abs(material - 3.0), 0.5) + step(abs(material - 5.0), 0.5);
		float patch = texture(detail, surface_pos.xz * 0.3).r;
		float mossy = smoothstep(0.55, 0.9, world_nrm.y) * smoothstep(0.45, 0.7, patch) * smoothstep(0.35, 0.7, bounce.a) * (1.0 - wood);
		if (style >= 0) {
			// The styles' tones are linear where stone's own colours are not, so they come back to stone's before its
			// paint tints them (Boulders: the swatch over the one stone is laid in) and its shade darkens them.
			base = pow(stone_rock(style, tone, moss, patch, tri), vec3(1.0 / 2.2)) * COLOR.rgb;
		}
		ALBEDO = mix(base, moss, mossy * 0.8) * occlusion;
	}
	ROUGHNESS = 0.92;
	SPECULAR = 0.25;
	AO = bounce.a;
	EMISSION = ALBEDO * given_back(bounce_at, lamp_at, bounce) + pane * lamp_light * window_glow;
}
