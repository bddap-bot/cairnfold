shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;

#include "res://src/ground.gdshaderinc"
#include "res://src/water.gdshaderinc"
#include "res://src/palette.gdshaderinc"
#include "res://src/bounce.gdshaderinc"
#include "res://src/meadow.gdshaderinc"

uniform sampler2D detail : filter_linear_mipmap, repeat_enable;
uniform sampler2D flagstones : filter_linear_mipmap, repeat_enable;
uniform float flagstone_scale = 0.17;
// Set from Meadow.GROUND, which the stone tool's icon shares.
uniform vec3 earth : source_color;
uniform vec3 rock : source_color;
// Where on a blade, root to tip, the meadow's ground takes its colour: the tone far blades converge on.
uniform float canopy = 0.6;
uniform vec3 trodden : source_color = vec3(0.52, 0.45, 0.33);
uniform vec3 bed : source_color = vec3(0.50, 0.44, 0.32);

varying vec3 world_pos;
varying float steep;
varying vec3 bounce_at;
varying vec3 meadow_lush;
varying vec3 meadow_dry;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y = ground_at(world_pos.xz);
	world_pos.y = VERTEX.y;
	NORMAL = ground_normal(world_pos.xz);
	// Per vertex: the height grid's texels are these vertices, and the Quest 2 is bound by ground fragments.
	steep = ground_humps[0].w != 0.0 || ground_humps[1].w != 0.0 ? 1.0 - NORMAL.y : ground_steepness(world_pos.xz);
	bounce_at = bounce_on_ground(world_pos.xz);
	meadow_lush = blade_color(blade_top(0.0, 0.5), canopy);
	meadow_dry = blade_color(blade_top(1.0, 0.5), canopy);
}

void fragment() {
	float d = texture(detail, world_pos.xz * 0.07).r;
	float fine = texture(detail, world_pos.xz * 0.45).r;
	// COLOR.r is the grass's own dryness here; the noise breaks it into patches finer than the blades' clumps show.
	vec3 meadow = mix(meadow_lush, meadow_dry, patched(clamp(COLOR.r + (d - 0.5) * 0.8, 0.0, 1.0)));
	vec3 grass = meadow * (0.85 + fine * 0.3);
	float s = steep + (fine - 0.5) * 0.06;
	vec3 c = mix(grass, earth, smoothstep(0.2, 0.32, s));
	vec2 cover = ground_cover(world_pos.xz);
	// Stone ground is one material however it came: painted, or a slope too steep to hold soil.
	float stony = max(cover.g, smoothstep(0.36, 0.48, s));
	// Painted slabs line a pond's bed and banks; a slope's own rock goes under the sand like any ground.
	float paved = 0.0;
	if (stony > 0.0) {
		vec2 slab = texture(flagstones, world_pos.xz * flagstone_scale + world_pos.y * 0.05).rg;
		vec3 face = rock * (0.8 + slab.g * 0.28) * (0.88 + fine * 0.24) * mix(0.8, 1.04, smoothstep(0.03, 0.25, slab.r));
		// Toward its edge stone ground loses whole slabs, the lowest-valued first, so it frays into the
		// meadow as scattered stones over earthy joints instead of ending in a line.
		float threshold = 0.12 + slab.g * 0.7;
		float laid = smoothstep(threshold - 0.04, threshold + 0.04, stony + (d - 0.5) * 0.25 + (fine - 0.5) * 0.15) * smoothstep(0.02, 0.06, slab.r);
		vec3 joint = mix(c, mix(earth, meadow, 0.35) * 0.8, smoothstep(0.4, 0.95, stony));
		c = mix(joint, face, laid);
		paved = laid * min(cover.g / stony, 1.0);
	}
	float under = water_depth_at(world_pos.xz);
	// Only near a pond is the depth worth smoothing; elsewhere it is the dry floor, far below any bank.
	if (under > -0.5) {
		under = grid_smooth(water_depth, world_pos.xz);
	}
	float shore = bank(under + (d - 0.5) * 0.12 + (fine - 0.5) * 0.06);
	if (shore > 0.0) {
		float pebble = texture(detail, world_pos.xz * 2.3).r;
		float soaked = mix(1.0, 0.75, smoothstep(-0.1, 0.0, under));
		c = mix(c, mix(bed * (0.7 + pebble * 0.6), c, paved) * soaked, shore);
		c += caustic(detail, world_pos.xz) * 0.35 * smoothstep(0.05, 0.3, under);
	}
	ALBEDO = mix(c, trodden * (0.85 + fine * 0.3), smoothstep(0.1, 0.7, cover.r * (1.0 - cover.g) + (d - 0.5) * 0.3));
	ROUGHNESS = 1.0;
	vec4 bounce = texture(bounce_volume, bounce_at);
	AO = bounce.a;
	EMISSION = ALBEDO * given_back(bounce_at, bounce_at, bounce);
}
