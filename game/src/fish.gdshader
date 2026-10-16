shader_type spatial;
render_mode blend_mix, depth_draw_never, diffuse_lambert_wrap, specular_disabled, shadows_disabled, cull_disabled;

#include "res://src/ground.gdshaderinc"
#include "res://src/water.gdshaderinc"
#include "res://src/bounce.gdshaderinc"

// Drawn after the pond's surface, which would hide them in deep water: the water's own tint over them stands in
// for it. INSTANCE_CUSTOM: x its own seed, y its speed over a cruise's, z how far it has faded in.
uniform vec3 shallow : source_color;
uniform vec3 deep : source_color;

varying float top;
varying float shown;
varying vec3 tint;
varying vec4 given;

void vertex() {
	float along = UV.y;
	float pace = INSTANCE_CUSTOM.y;
	float beat = TIME * (5.0 + 7.0 * pace) + INSTANCE_CUSTOM.x;
	VERTEX.x += sin(beat - along * 3.0) * 0.035 * (0.2 + 0.8 * along * along) * (0.6 + 0.4 * min(pace, 2.0));
	top = smoothstep(0.0, 0.02, VERTEX.y);
	shown = INSTANCE_CUSTOM.z;
	float body = 1.0 - exp(-max(water_depth_at(MODEL_MATRIX[3].xz), 0.0) * 2.8);
	tint = mix(shallow, deep, body);
	given = given_at((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, normalize(mat3(MODEL_MATRIX) * NORMAL));
}

void fragment() {
	float patch = smoothstep(0.1, 0.3, sin(UV.y * 11.0 + COLOR.g * 23.0) + 0.6 * sin(UV.y * 5.0 + COLOR.b * 17.0));
	vec3 skin = pow(COLOR.rgb, vec3(2.2));
	vec3 c = mix(mix(skin, vec3(0.9, 0.85, 0.75), 0.4), skin, top);
	c = mix(c, vec3(0.92, 0.88, 0.8), top * patch * 0.45 * (1.0 - UV.x));
	ALBEDO = mix(c, tint, 0.25);
	ALPHA = 0.88 * shown;
	AO = given.a;
	EMISSION = ALBEDO * given.rgb;
}
