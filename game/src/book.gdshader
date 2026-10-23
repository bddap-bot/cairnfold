shader_type spatial;
render_mode diffuse_lambert_wrap;

// The picture book's binding and the edges of its pages. A cover (`kind` 0) is cloth over board, worn pale at its
// corners and edges, the front stamped in foil with a nest of three eggs in a ring of leaves; a block of pages
// (`kind` 1) shows leaf lines on its sides and a painted fore-edge. `size` is the box's size in metres.

#include "res://src/ground.gdshaderinc"
#include "res://src/bounce.gdshaderinc"
#include "res://src/book.gdshaderinc"

uniform int kind = 0;
uniform vec3 size = vec3(0.16, 0.003, 0.16);
uniform bool front = false;
// The front's top face baked (Book): albedo with metal in alpha, and roughness.
uniform bool baked = false;
uniform sampler2D cover_paint : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D cover_rough : filter_linear_mipmap, repeat_disable;
// For a block of pages: which way its fore-edge faces, +1 the right block's, -1 the left's.
uniform float fore_side = 1.0;
uniform vec3 cloth;
uniform vec3 leather;
uniform vec3 paper : source_color;
// The bow of the leaf lying on it, and that leaf's width, its spine at the block's middle less half of it.
uniform float gutter_bow = 0.0;
uniform float leaf_width = 0.15;
uniform vec3 edge_paint : source_color = vec3(0.86, 0.6, 0.32);

varying vec3 local;
varying vec3 local_n;
varying vec4 given;

void vertex() {
	if (VERTEX.y > 0.0) {
		VERTEX.y += gutter_rise(leaf_width * 0.5 + fore_side * VERTEX.x * size.x, leaf_width, gutter_bow) / size.y;
	}
	local = VERTEX;
	local_n = NORMAL;
	given = given_at((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, normalize(mat3(MODEL_MATRIX) * NORMAL));
}

void fragment() {
	vec3 n = normalize(local_n);
	if (kind == 0) {
		float rough;
		float metal;
		vec3 c;
		if (baked && n.y > 0.5) {
			vec2 uv = local.xz / size.xz + 0.5;
			vec4 paint = texture(cover_paint, uv);
			c = paint.rgb;
			metal = paint.a;
			rough = texture(cover_rough, uv).r;
		} else {
			c = cover(local, n, size, front, cloth, leather, rough, metal);
		}
		ALBEDO = c;
		METALLIC = metal;
		ROUGHNESS = rough;
	} else {
		vec3 lp = local * size;
		float lines = 0.5 + 0.5 * sin(lp.y / 0.00042 * TAU);
		vec3 c = paper * (0.9 + 0.1 * lines);
		float fore = smoothstep(0.6, 0.9, n.x * fore_side) + smoothstep(0.6, 0.9, abs(n.z));
		float deckle = noise(vec2(lp.z * 300.0 + lp.x * 300.0, lp.y * 2000.0));
		fore *= step(0.25, deckle) * 0.4 + 0.6;
		vec2 at = vec2(lp.z + lp.x, lp.y) * vec2(180.0, 900.0);
		c = mix(c, edge_paint * (0.85 + 0.25 * noise(at)), clamp(fore, 0.0, 1.0) * (0.75 + 0.25 * noise(at * 0.3)));
		ALBEDO = c;
		ROUGHNESS = 0.95;
	}
	SPECULAR = 0.2;
	AO = given.a;
	EMISSION = ALBEDO * given.rgb;
}
