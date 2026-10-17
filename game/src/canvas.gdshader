shader_type spatial;

// A canvas as paint.glsl leaves it: paper under the pigment laid and the pigment still in the water, darkened and
// glossy where wet, oil standing up off it in ridges the light catches, charcoal and dry paper matte. The sheet is
// mounted on a board, so no light comes through it from behind.

uniform sampler2D wet : filter_linear, repeat_disable;
uniform sampler2D dry : filter_linear, repeat_disable;
uniform sampler2D paper : filter_linear, repeat_disable;
uniform vec2 metres;

const vec3 SHEET = vec3(0.93, 0.91, 0.86);
const float IMPASTO = 0.0035;
const float GRAIN = 0.00025;

void fragment() {
	vec4 w = texture(wet, UV);
	vec4 d = texture(dry, UV);
	vec2 tooth = texture(paper, UV).rg;
	vec3 sheet = SHEET * (0.97 + 0.03 * tooth.x + 0.02 * tooth.y);
	vec3 col = sheet * exp(-(d.rgb + w.rgb));
	float damp = smoothstep(0.0, 0.25, w.a);
	ALBEDO = col * (1.0 - 0.12 * damp);
	vec2 px = 1.0 / vec2(textureSize(dry, 0));
	float hl = texture(dry, UV - vec2(px.x, 0)).a * IMPASTO + texture(paper, UV - vec2(px.x, 0)).r * GRAIN;
	float hr = texture(dry, UV + vec2(px.x, 0)).a * IMPASTO + texture(paper, UV + vec2(px.x, 0)).r * GRAIN;
	float hu = texture(dry, UV - vec2(0, px.y)).a * IMPASTO + texture(paper, UV - vec2(0, px.y)).r * GRAIN;
	float hd = texture(dry, UV + vec2(0, px.y)).a * IMPASTO + texture(paper, UV + vec2(0, px.y)).r * GRAIN;
	vec2 slope = vec2(hr - hl, hd - hu) / (2.0 * px * metres);
	NORMAL_MAP = normalize(vec3(-slope.x, slope.y, 1.0)) * 0.5 + 0.5;
	float oil = smoothstep(0.02, 0.2, d.a);
	ROUGHNESS = mix(mix(0.92, 0.45, oil), 0.18, damp);
	SPECULAR = mix(0.25, 0.6, max(oil, damp));
}
