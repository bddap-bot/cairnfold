shader_type spatial;
render_mode cull_disabled;

#include "res://src/ground.gdshaderinc"
#include "res://src/bounce.gdshaderinc"
#include "res://src/palette.gdshaderinc"

uniform vec3 backlight : source_color = vec3(0.2, 0.3, 0.06);
// Leaves shrink away over the last 15 m before this distance, or its far half when it is nearer: past it they would be
// specks costing a full leaf each.
uniform float reach;
// A camera seeing this layer (Quality.FULL_LAYER) draws every leaf.
uniform uint full_layer;

varying vec4 given;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float shown = 1.0;
	if ((CAMERA_VISIBLE_LAYERS & full_layer) == 0u) {
		shown = 1.0 - smoothstep(max(reach - 15.0, reach * 0.5), reach, distance(origin, CAMERA_POSITION_WORLD));
	}
	VERTEX *= shown;
	// A sprig's colour carries the ground height under its wall (IvyLayout.bake) in its alpha.
	float foot = COLOR.a;
	COLOR = vec4(seasoned(COLOR.rgb, season_foliage), 1.0);
	given = vec4(0.0);
	if (shown > 0.0) {
		given = given_over(origin, normalize(mat3(MODEL_MATRIX) * vec3(0.0, 0.0, 1.0)), foot);
	}
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.75;
	BACKLIGHT = seasoned(backlight, season_foliage);
	AO = given.a;
	EMISSION = ALBEDO * given.rgb;
}
