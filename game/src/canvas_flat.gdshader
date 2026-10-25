shader_type canvas_item;
render_mode unshaded, blend_disabled;

#include "res://src/paint.gdshaderinc"

// A canvas flat and unlit, one texel to a pixel: its colour sRGB-encoded as an image file holds it, or with `height`
// its height over the highest it can stand as a 16-bit number, the high byte in red and the low in green. Each channel is rounded to its
// 8-bit step here: past the fragment Godot's 2D pipeline carries a colour at half precision, a twentieth of a step off,
// which would round a value near a step's boundary to the next.

uniform sampler2D wet : filter_nearest, repeat_disable;
uniform sampler2D dry : filter_nearest, repeat_disable;
uniform sampler2D paper : filter_nearest, repeat_disable;
uniform bool height;

vec3 srgb(vec3 c) {
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

void fragment() {
	ivec2 at = ivec2(UV * vec2(textureSize(wet, 0)));
	vec4 d = texelFetch(dry, at, 0);
	vec2 tooth = texelFetch(paper, at, 0).rg;
	if (height) {
		float v = round(clamp(canvas_height(d, tooth) / (impasto + grain), 0.0, 1.0) * 65535.0);
		float high = floor(v / 256.0);
		COLOR = vec4(high / 255.0, (v - high * 256.0) / 255.0, 0.0, 1.0);
	} else {
		COLOR = vec4(round(srgb(clamp(canvas_colour(texelFetch(wet, at, 0), d, tooth), 0.0, 1.0)) * 255.0) / 255.0, 1.0);
	}
}
