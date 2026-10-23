shader_type spatial;
render_mode unshaded, shadows_disabled, fog_disabled;

// The stone disc (stone_disc.gdshaderinc) in the icon look (icon.gdshaderinc).

#include "res://src/ground.gdshaderinc"
#include "res://src/stone_ground.gdshaderinc"
#include "res://src/stone_disc.gdshaderinc"
#include "res://src/icon.gdshaderinc"

void fragment() {
	float laid;
	vec2 slope;
	vec3 c = stone_disc(UV, laid, slope);
	vec3 x = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz);
	vec3 z = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	ALBEDO = icon_look(c, normalize(mix(NORMAL, stone_normal(NORMAL, x, z, slope), laid)));
}
