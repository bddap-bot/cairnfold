shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;

#include "res://src/sculpture.gdshaderinc"
#include "res://src/given.gdshaderinc"
#include "res://src/palette.gdshaderinc"

// A lilypad (Pads). INSTANCE_CUSTOM: x how far it has opened out, y its own phase.
void vertex() {
	VERTEX *= INSTANCE_CUSTOM.x;
	float rock = TIME * 0.8 + INSTANCE_CUSTOM.y;
	VERTEX.y += (VERTEX.x * sin(rock) + VERTEX.z * cos(rock * 0.7)) * 0.03 * (1.0 - season_winter);
	GIVE_HERE;
}

void fragment() {
	// UV.x is 0 at the stalk and 1 at the rim, UV.y once round (Pads.leaf).
	float vein = smoothstep(0.8, 1.0, abs(sin(UV.y * 28.0))) * smoothstep(0.1, 0.5, UV.x);
	vec3 leaf = COLOR.rgb * (1.0 + 0.25 * smoothstep(0.7, 1.0, UV.x) - 0.2 * vein);
	ALBEDO = SCULPTED ? SCULPTURE : mix(leaf, SNOW, season_winter * (0.7 + 0.25 * smoothstep(0.3, 1.0, UV.x)));
	ROUGHNESS = 0.55;
	TAKE_GIVEN;
}
