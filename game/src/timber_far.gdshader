shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;

// Far timbers: the stone shader's light without its per-fragment reads. Beyond the near distance a beam is a few
// pixels wide, its detail texture averages to the colour it scales (0.78 + 0.45 x its mean of 0.5), and its bounce
// light varies too little across it to read per fragment.
#include "res://src/ground.gdshaderinc"
#include "res://src/bounce.gdshaderinc"

varying float occlusion;
varying vec4 given;

void vertex() {
	occlusion = INSTANCE_CUSTOM.x;
	given = given_at((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, normalize(mat3(MODEL_MATRIX) * NORMAL));
}

void fragment() {
	ALBEDO = COLOR.rgb * occlusion;
	ROUGHNESS = 0.92;
	SPECULAR = 0.25;
	AO = given.a;
	EMISSION = ALBEDO * given.rgb;
}
