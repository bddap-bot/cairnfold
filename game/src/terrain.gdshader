shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;

#include "res://src/ground.gdshaderinc"
#include "res://src/water.gdshaderinc"
#include "res://src/palette.gdshaderinc"
#include "res://src/bounce.gdshaderinc"
#include "res://src/meadow.gdshaderinc"
#include "res://src/stone_ground.gdshaderinc"
#include "res://src/flora_lod.gdshaderinc"

// The meadow's colour maths runs at half precision: the Quest 2 is bound by ground fragments and its GPU runs
// mediump at twice the rate. Positions and texture coordinates stay highp, 160 m wide at millimetres, and the stone
// path keeps full precision for its divide by a cover that can be tiny.
uniform sampler2D detail : filter_linear_mipmap, repeat_enable;
// Set from Meadow.GROUND.
uniform mediump vec3 earth : source_color;
uniform mediump vec3 trodden : source_color = vec3(0.52, 0.45, 0.33);
uniform mediump vec3 bed : source_color = vec3(0.50, 0.44, 0.32);
// The grass past its clumps' reach (FloraCover): a clump at each vertex as half the factor it makes of the meadow's
// colour, over its presence in alpha, painted in as the clumps there sink away.
global uniform sampler2D flora_grass : filter_nearest, repeat_disable;
uniform bool far_grass = true;
// A camera seeing this layer (Quality.FULL_LAYER) draws every clump whole, so the ground paints none.
uniform uint full_layer;

varying highp vec2 world_xz;
varying mediump float steep;
// What the builds give back and the sky seen, read per vertex: the volumes hold a probe a grid cell, as the vertices
// lie, and the Quest 2 is bound by ground fragments.
varying mediump vec3 given;
varying mediump float sky_seen;
varying mediump vec3 meadow_lush;
varying mediump vec3 meadow_dry;
// 1 where a pond reaches within a grid step: only there does a fragment read the water's depth.
varying mediump float pond;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y = ground_at(world_pos.xz);
	world_pos.y = VERTEX.y;
	world_xz = world_pos.xz;
	if (ground_humps[0].w != 0.0 || ground_humps[1].w != 0.0) {
		NORMAL = ground_normal(world_pos.xz);
	} else {
		NORMAL = ground_point_normal(world_pos.xz);
	}
	steep = 1.0 - NORMAL.y;
	vec3 bounce_at = bounce_on_ground(world_pos.xz);
	vec4 bounce = textureLod(bounce_volume, bounce_at, 0.0);
	given = given_back(bounce_at, bounce_at, bounce);
	sky_seen = bounce.a;
	pond = pond_near(world_pos.xz);
	float dist = distance(world_pos, CAMERA_POSITION_WORLD);
	bool painted = far_grass && (CAMERA_VISIBLE_LAYERS & full_layer) == 0u;
	// The share of clumps sunk away here (grass.gdshader's `gone`): all but the survivors over the LOD band, then they.
	float sunk = painted ? (1.0 - survivors) * smoothstep(lod_begin, lod_begin + lod_band, dist) + survivors * smoothstep(draw_reach * survivors_from - sink, draw_reach, dist) : 0.0;
	vec4 clump = textureLod(flora_grass, ((world_pos.xz - ground_grid.x) / ground_grid.y + 0.5) / ground_grid.z, 0.0);
	vec3 tuft = 1.0 + (2.0 * clump.rgb - clump.a) * sunk;
	meadow_lush = blade_color(blade_top(0.0, 0.5), canopy) * tuft;
	meadow_dry = blade_color(blade_top(1.0, 0.5), canopy) * tuft;
}

void fragment() {
	mediump float d = texture(detail, world_xz * 0.07).r;
	mediump float fine = texture(detail, world_xz * 0.45).r;
	// COLOR.r is the grass's own dryness here; the noise breaks it into patches finer than the blades' clumps show.
	mediump vec3 meadow = mix(meadow_lush, meadow_dry, patched(clamp(COLOR.r + (d - 0.5) * 0.8, 0.0, 1.0)));
	mediump vec3 grass = meadow * (0.85 + fine * 0.3);
	mediump float s = steep + (fine - 0.5) * 0.06;
	mediump vec3 c = mix(grass, earth, smoothstep(0.2, 0.32, s));
	vec2 cover = ground_cover(world_xz);
	// Stone ground is one material however it came: painted, or a slope too steep to hold soil.
	float stony = max(cover.g, smoothstep(0.36, 0.48, s));
	// Painted slabs line a pond's bed and banks; a slope's own rock goes under the sand like any ground.
	float paved = 0.0;
	if (stony > 0.0) {
		float grit = texture(detail, world_xz * 3.7).r;
		int style = min(ground_style(world_xz, (vec2(fine, grit) - 0.5) * vec2(3.0, 2.5)), STONE_ROOM - 1);
		float laid;
		vec2 slope;
		c = stone_ground(style, world_xz, stony, c, earth, meadow, d, fine, grit, laid, slope);
		NORMAL = normalize(mix(NORMAL, stone_normal(NORMAL, VIEW_MATRIX[0].xyz, VIEW_MATRIX[2].xyz, slope), laid));
		paved = laid * min(cover.g / stony, 1.0);
	}
	if (pond > 0.0) {
		float under = water_depth_at(world_xz);
		// Only near a pond is the depth worth smoothing; elsewhere it is the dry floor, far below any bank.
		if (under > -0.5) {
			under = grid_smooth(water_depth, world_xz);
		}
		mediump float shore = bank(under + (d - 0.5) * 0.12 + (fine - 0.5) * 0.06);
		if (shore > 0.0) {
			mediump float pebble = texture(detail, world_xz * 2.3).r;
			mediump float soaked = mix(1.0, 0.75, smoothstep(-0.1, 0.0, under));
			c = mix(c, mix(bed * (0.7 + pebble * 0.6), c, paved) * soaked, shore);
			c += caustic(detail, world_xz) * 0.35 * smoothstep(0.05, 0.3, under);
		}
	}
	ALBEDO = mix(c, trodden * (0.85 + fine * 0.3), smoothstep(0.1, 0.7, cover.r * (1.0 - cover.g) + (d - 0.5) * 0.3));
	ROUGHNESS = 1.0;
	AO = sky_seen;
	EMISSION = ALBEDO * given;
}
