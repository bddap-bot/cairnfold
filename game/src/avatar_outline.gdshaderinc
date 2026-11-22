#include "res://src/sculpture.gdshaderinc"
#include "res://src/flat_light.gdshaderinc"

// unity/materials.gd outline_layer: each atlas texel's colour, and in alpha its share of `width`. Read nearest: where
// the layer is narrower than the atlas its cells are a few texels wide, and a blended neighbour would change a width.
uniform sampler2D outline : source_color, filter_nearest, repeat_disable;
uniform float width;
uniform vec4 atlas = vec4(1.0, 1.0, 0.0, 0.0);
uniform sampler2D picture : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 colour : source_color = vec4(1.0);
uniform sampler2D light_index : hint_default_black, filter_nearest, repeat_disable;
uniform sampler2D lighting : hint_default_black, filter_nearest, repeat_disable;
uniform bool lit_by_menu = false;
const int POST_ROW = 2;

varying vec3 flat_light;
varying float brightness;

void vertex() {
	float share = textureLod(outline, UV * atlas.xy + atlas.zw, 0.0).a;
	// No width draws no hull, as in lilToon: a material swapped in without an outline would otherwise show back faces.
	VERTEX = share > 0.0 ? VERTEX + normalize(NORMAL) * share * width : vec3(intBitsToFloat(0x7fc00000));
	vec3 at = NODE_POSITION_WORLD + vec3(0.0, 1.0, 0.0);
	vec3 key;
	float spare;
	flat_light = lit_flat(given_over(at, vec3(0.0), ground_at(at.xz)), 1.0, 1.0, CAMERA_VISIBLE_LAYERS == mirror_mask, MODEL_MATRIX, NORMAL, key, spare);
	brightness = 1.0;
	if (lit_by_menu) {
		ivec2 size = textureSize(lighting, 0);
		int column = min(int(round(textureLod(light_index, UV * atlas.xy + atlas.zw, 0.0).r * 255.0)), size.x - 1);
		vec4 post = texelFetch(lighting, ivec2(column, POST_ROW), 0);
		flat_light = max(flat_light + post.r, vec3(0.0));
		brightness = max(1.0 - post.g, 0.0);
	}
}

void fragment() {
	vec2 uv = UV * atlas.xy + atlas.zw;
	ALBEDO = SCULPTED ? SCULPTURE : texture(outline, uv).rgb;
#ifdef CUT
	ALPHA = texture(picture, uv).a * colour.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
#endif
	ROUGHNESS = 1.0;
	AO = 0.0;
	ALBEDO *= brightness;
	EMISSION = ALBEDO * flat_light;
}
