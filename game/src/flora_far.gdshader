shader_type spatial;
render_mode skip_vertex_transform, cull_disabled, diffuse_lambert_wrap, specular_disabled;

#include "res://src/ground.gdshaderinc"
#include "res://src/water.gdshaderinc"
#include "res://src/palette.gdshaderinc"
#include "res://src/meadow.gdshaderinc"
#include "res://src/bounce.gdshaderinc"
#include "res://src/flora_lod.gdshaderinc"

uniform bool flower = false;
uniform float stem;
uniform float patch_scale = 1.41421356;
varying vec3 tint;
varying vec4 given;

void vertex() {
	float ground = ground_at(INSTANCE_CUSTOM.zw);
	vec3 root = MODEL_MATRIX[3].xyz + vec3(0.0, ground, 0.0);
	float size = length(MODEL_MATRIX[1].xyz);
	float dist = distance(root, CAMERA_POSITION_WORLD);
	float fade = flora_fade(dist, flower ? draw_reach : grass_end(COLOR.a), flower ? draw_fade : sink);
	float cover = 1.0 - max(bare(root.xz), bank(water_depth_at(root.xz)));
	// Water plants retain their own mesh and depth-dependent silhouette. Land patches never float above ponds.
	if (drowned(INSTANCE_CUSTOM.zw) || (flower && INSTANCE_CUSTOM.r >= season_bloom)) {
		cover = 0.0;
	}
	float width = flower ? mix(0.13, 0.22, smoothstep(18.0, 50.0, dist)) : 0.5;
	vec3 centre = root + vec3(0.0, (flower ? stem : 0.1) * size * cover, 0.0);
	// Use the plant's own facing to keep distant blooms from forming identical upright markers.
	vec2 turn = MODEL_MATRIX[0].xz / max(length(MODEL_MATRIX[0].xz), 0.001);
	vec2 petal = vec2(turn.x * VERTEX.x - turn.y * VERTEX.y, turn.y * VERTEX.x + turn.x * VERTEX.y);
	vec3 world = centre + (INV_VIEW_MATRIX[0].xyz * petal.x + INV_VIEW_MATRIX[1].xyz * petal.y) * width * patch_scale * size * sqrt(fade) * cover;
	if (!flower) {
		vec3 patch = mat3(MODEL_MATRIX) * vec3(VERTEX.x, 0.0, VERTEX.y) * width * patch_scale * sqrt(fade) * cover;
		world = root + patch;
		world.y = ground_at(world.xz) + 0.03;
	}
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	tint = (flower ? COLOR.rgb : blade_color(blade_top(INSTANCE_CUSTOM.x, INSTANCE_CUSTOM.y), 0.6) * COLOR.rgb);
	vec3 at = bounce_on_ground(root.xz);
	vec4 bounce = textureLod(bounce_volume, at, 0.0);
	given = vec4(given_back(at, at, bounce), bounce.a);
}

void fragment() {
	NORMAL = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	ALBEDO = tint;
	ROUGHNESS = 0.9;
	AO = given.a;
	EMISSION = ALBEDO * given.rgb;
}
