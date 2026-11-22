shader_type spatial;
render_mode cull_disabled;

#include "res://src/sculpture.gdshaderinc"
#include "res://src/given.gdshaderinc"
#include "res://src/palette.gdshaderinc"

uniform vec3 backlight : source_color = vec3(0.2, 0.3, 0.06);
// Past it leaves would be specks costing a full leaf each.
uniform float reach;
// Quality.FULL_LAYER.
uniform uint full_layer;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float shown = 1.0;
	if ((CAMERA_VISIBLE_LAYERS & full_layer) == 0u) {
		shown = 1.0 - smoothstep(max(reach - 15.0, reach * 0.5), reach, distance(origin, CAMERA_POSITION_WORLD));
	}
	VERTEX *= shown;
	// The ground height under its wall (IvyLayout.bake).
	float foot = COLOR.a;
	COLOR = vec4(seasoned(COLOR.rgb, season_foliage), 1.0);
	given = vec4(0.0);
	if (shown > 0.0) {
		given = given_over(origin, normalize(mat3(MODEL_MATRIX) * vec3(0.0, 0.0, 1.0)), foot);
	}
}

void fragment() {
	ALBEDO = SCULPTED ? SCULPTURE : COLOR.rgb;
	ROUGHNESS = 0.75;
	BACKLIGHT = SCULPTED ? vec3(0.0) : seasoned(backlight, season_foliage);
	TAKE_GIVEN;
}
