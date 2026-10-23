shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;

#include "res://src/ground.gdshaderinc"
#include "res://src/water.gdshaderinc"
#include "res://src/palette.gdshaderinc"
#include "res://src/bounce.gdshaderinc"
#include "res://src/meadow.gdshaderinc"
#include "res://src/stone_ground.gdshaderinc"
#include "res://src/flora_lod.gdshaderinc"
#include "res://src/detail.gdshaderinc"
#include "res://src/noise.gdshaderinc"

// The meadow's colour maths runs at half precision: the Quest 2 is bound by ground fragments and its GPU runs
// mediump at twice the rate. Positions and texture coordinates stay highp, 160 m wide at millimetres, and the stone
// path keeps full precision for its divide by a cover that can be tiny.
// Set from Meadow.GROUND.
uniform mediump vec3 earth : source_color;
uniform mediump vec3 trodden : source_color = vec3(0.52, 0.45, 0.33);
uniform mediump vec3 bed : source_color = vec3(0.50, 0.44, 0.32);
uniform mediump vec3 cliff_light : source_color = vec3(0.80, 0.74, 0.63);
uniform mediump vec3 cliff_dark : source_color = vec3(0.34, 0.32, 0.30);
// Terrain.ROCK: the steepness over which rock rises.
uniform mediump vec2 rock_steep;
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
	vec2 rim = clamp(world_pos.xz, ground_grid.x, -ground_grid.x);
	vec2 out_to = world_pos.xz - rim;
	if (dot(out_to, out_to) > 0.0) {
		// The bank's foot (Terrain.BANK_FOOT) stays where the mesh lays it; it slopes up to the edge as it stands now.
		vec2 slope = out_to * (ground_at(rim) - VERTEX.y) / dot(out_to, out_to);
		NORMAL = normalize(vec3(slope.x, 1.0, slope.y));
	} else {
		VERTEX.y = ground_at(world_pos.xz);
		if (ground_humps[0].w != 0.0 || ground_humps[1].w != 0.0) {
			NORMAL = ground_normal(world_pos.xz);
		} else {
			NORMAL = ground_point_normal(world_pos.xz);
		}
	}
	world_pos.y = VERTEX.y;
	world_xz = world_pos.xz;
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
	vec4 clump = textureLod(flora_grass, grid_uv(world_pos.xz), 0.0);
	vec3 tuft = 1.0 + (2.0 * clump.rgb - clump.a) * sunk;
	meadow_lush = blade_color(blade_top(0.0, 0.5), canopy) * tuft;
	meadow_dry = blade_color(blade_top(1.0, 0.5), canopy) * tuft;
}

// Bedded rock on a face too steep to hold soil, as `rock` (0 to 1) reaches over `under`: beds about half a metre
// thick in units of a few metres, pale and dark by turns, undulating with `d`. Each bed's top is a lit ledge over the
// shadowed undercut of the one above; joints cut a unit into tall blocks and stain dark down from its lips. `tilt` leans
// the face's normal up on a ledge, down under one. Joints and bed lines fade as they thin under a pixel, so far off
// the units carry it.
vec3 cliff(highp vec3 p, float along, float rock, vec3 under, vec3 green, float d, float fine, out float laid, out float tilt) {
	highp float y = p.y + (d - 0.5) * 1.2;
	highp float b = y / 0.55;
	highp float layer = floor(b);
	float f = float(b - layer);
	highp float unit = floor(y / 2.6);
	float bv = float(hash(vec2(layer, 3.0)));
	// Golden-ratio steps keep neighbouring units apart in tone, where a hash of neighbours can bunch.
	float uv = float(fract(unit * 0.618034 + 0.3));
	highp float u = mix(p.x, p.z, along) + (fine - 0.5) * 0.25;
	highp float ju = u / (1.4 + uv * 1.6) + uv * 5.3 + step(0.6, bv) * 0.5;
	highp float col = floor(ju);
	float jf = float(ju - col);
	float vb = float(hash(vec2(layer, col)));
	float thin_u = fwidth(float(ju));
	float thin_b = thin_u * 3.0;
	float joint = (1.0 - smoothstep(0.0, 0.04 + thin_u, min(jf, 1.0 - jf))) * (1.0 - smoothstep(0.1, 0.35, thin_u));
	float prominent = smoothstep(0.3, 0.6, bv);
	float lip = smoothstep(0.75, 0.95, f) * prominent;
	float undercut = (1.0 - smoothstep(0.0, 0.22, f)) * mix(0.3, 1.0, prominent) * (1.0 - smoothstep(0.15, 0.5, thin_b) * 0.6);
	float stain = texture(detail, vec2(float(u) * 0.3, float(y) * 0.02)).r;
	float streak = smoothstep(0.5, 0.75, stain + (1.0 - smoothstep(0.0, 0.25, min(jf, 1.0 - jf))) * 0.25);
	float tone = clamp(mix(0.15, 0.85, uv) + (vb - 0.5) * 0.3 + (fine - 0.5) * 0.4, 0.0, 1.0);
	vec3 face = mix(cliff_dark, cliff_light, tone);
	face *= 1.0 - streak * 0.4 * (1.0 - lip);
	face = mix(face, cliff_light * 1.1, lip * 0.55);
	face *= 1.0 - undercut * 0.55 - joint * 0.5;
	face = mix(face, green * 0.6, lip * smoothstep(0.45, 0.65, d + (vb - 0.5) * 0.5));
	tilt = lip * 0.9 - undercut * 0.8;
	float threshold = 0.1 + vb * 0.6;
	laid = smoothstep(threshold - 0.05, threshold + 0.05, rock + (d - 0.5) * 0.25);
	return mix(under, face, laid);
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
	float rocky = smoothstep(rock_steep.x, rock_steep.y, s);
	// Painted slabs line a pond's bed and banks; a slope's own rock goes under the sand like any ground.
	float paved = 0.0;
	if (cover.g > 0.0) {
		float grit = texture(detail, world_xz * 3.7).r;
		int style = min(ground_style(world_xz, (vec2(fine, grit) - 0.5) * vec2(3.0, 2.5)), STONE_ROOM - 1);
		vec2 slope;
		c = stone_ground(style, world_xz, cover.g, c, earth, meadow, d, fine, grit, paved, slope);
		NORMAL = normalize(mix(NORMAL, stone_normal(NORMAL, VIEW_MATRIX[0].xyz, VIEW_MATRIX[2].xyz, slope), paved));
	}
	if (rocky > 0.0) {
		float laid;
		float tilt;
		// Rebuilt here rather than carried as varyings: the Quest 2 is bound by ground fragments, and every varying costs
		// every one of them. `along` is 0 where the face looks along x, 1 along z, so its joints count along the other.
		vec3 n = mat3(INV_VIEW_MATRIX) * NORMAL;
		float along = smoothstep(-0.2, 0.2, abs(n.x) - abs(n.z));
		c = cliff((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, along, rocky, c, meadow, d, fine, laid, tilt);
		NORMAL = normalize(NORMAL + VIEW_MATRIX[1].xyz * tilt * laid);
		paved *= 1.0 - laid;
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
