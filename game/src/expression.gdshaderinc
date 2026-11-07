#include "res://src/flat_light.gdshaderinc"

uniform sampler2D picture : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 colour : source_color = vec4(1.0);
uniform bool use_vertex = false;
uniform vec4 atlas = vec4(1.0, 1.0, 0.0, 0.0);
// Each atlas texel's entry in the looks' materials and each entry's looks (Avatar._lit_looks): row 0 red one where
// flat and two where lit through a ramp, green its cap, blue its shadow tint, alpha its emission's strength; row 1 its
// emission's colour over the emission map `glow`, alpha how far the glow overrides the lit colour (Poiyomi's lerp toward
// the glow by its brightest channel); the RAMP rows after those HEAD_ROWS its ramp; from TOON_ROW its toon shadow and
// rim, which the TOON shaders alone draw. Unset, every texel is lit by angle and glows nowhere.
uniform sampler2D light_index : hint_default_black, filter_nearest, repeat_disable;
uniform sampler2D lighting : hint_default_black, filter_nearest, repeat_disable;
uniform sampler2D glow : source_color, hint_default_black, filter_linear_mipmap, repeat_disable;

varying vec4 given;
// One where the vertex's material is flat; then flat_light is the ambient and light given back it takes, capped.
varying float flat_lit;
varying vec3 flat_light;
// A ramp-lit vertex's main light its shadow tint lends the albedo, and the light its cap leaves room for.
varying vec4 tinted;
varying vec4 glow_colour;
varying float glow_strength;
// The looks table column of the vertex's material where it has a matcap (Avatar._lit_looks's rows from MATCAP), else
// -1, and the surface's own normal in world space, which a matcap is looked up by.
varying flat int matcap_entry;
varying vec3 matcap_normal;
uniform sampler2DArray matcaps : source_color, hint_default_white, filter_linear_mipmap, repeat_disable;
uniform sampler2D matcap_masks : hint_default_white, filter_linear_mipmap, repeat_disable;
#ifdef CLEAR_COAT
// The looks table column of the vertex's material where it has a clear coat (Avatar._lit_looks's rows after its ramp),
// else -1: a fragment reads the coat's rows only where it draws one, since carrying them as varyings cost a Quest 2 as
// much as drawing the coat over the whole of every mesh showing one. Its maps are read through UV2.
varying flat int coat_entry;
// The surface's own normal in view space: a flat material's NORMAL is turned to light it.
varying vec3 coat_normal;
uniform sampler2DArray coat_maps : hint_default_white, filter_linear_mipmap, repeat_enable;
#endif
#ifdef TOON
// A flat material's shade colours (unity/liltoon.gd shade), and the albedo elsewhere.
uniform sampler2D shade : source_color, hint_default_black, filter_linear_mipmap, repeat_disable;
uniform sampler2D shade2 : source_color, hint_default_black, filter_linear_mipmap, repeat_disable;
// The looks table column of the vertex's material where the table has toon rows, else -1; how far its true normal
// faces the main light, lilToon's half Lambert; that normal in view space; and the whole light it takes, capped where
// flat, which its rim takes where lit.
varying flat int toon_entry;
varying float toon_toward;
varying vec3 toon_normal;
varying vec3 toon_light;
#endif

// A ramp-lit material, as Toon Standard lights it, takes the flat light's ambient and its main light scaled by its ramp
// at the half-Lambert term (lit_flat), and the rest of the main light lent the albedo by its shadow tint in each pixel,
// under the same cap; that tint, added as emission, takes no cast shadow, as Toon Standard's shade does under one.
const int HEAD_ROWS = 2;
const int RAMP = 16;
#ifdef CLEAR_COAT
const int COAT = HEAD_ROWS + RAMP;
#endif
const int COAT_ROWS = 6;
const int MATCAP = HEAD_ROWS + RAMP + COAT_ROWS;
const int MATCAP_ROWS = 6;
const int MATCAPS = 4;
const int TOON_ROW = MATCAP + 1 + MATCAPS * MATCAP_ROWS;
void vertex() {
	float entry = textureLod(light_index, UV * atlas.xy + atlas.zw, 0.0).r;
	ivec2 looked = ivec2(min(int(round(entry * 255.0)), textureSize(lighting, 0).x - 1), 0);
	vec4 light = texelFetch(lighting, looked, 0);
	glow_colour = textureSize(lighting, 0).y > 1 ? texelFetch(lighting, looked + ivec2(0, 1), 0) : vec4(0.0);
	glow_strength = light.a;
#ifdef CLEAR_COAT
	bool coated = texelFetch(lighting, looked + ivec2(0, COAT), 0).x > 0.0 || texelFetch(lighting, looked + ivec2(0, COAT + 4), 0).x > 0.5;
	coat_entry = coated ? looked.x : -1;
	coat_normal = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
#endif
	flat_lit = light.r > 0.5 ? 1.0 : 0.0;
	vec3 at = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
	matcap_entry = textureSize(lighting, 0).y > MATCAP && texelFetch(lighting, looked + ivec2(0, MATCAP), 0).r > 0.5 ? looked.x : -1;
	matcap_normal = normal;
	bool mirrored = CAMERA_VISIBLE_LAYERS == mirror_mask;
#ifdef TOON
	toon_entry = textureSize(lighting, 0).y > TOON_ROW ? looked.x : -1;
	toon_toward = dot(normal, key_toward(mirrored)) * 0.5 + 0.5;
	toon_normal = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
#endif
	// A flat or ramp-lit vertex reads the light around it a metre over its mesh's origin, the same place for every
	// vertex: reading the volumes at each vertex of a dense avatar cost a Quest 2 more than its whole lighting.
	vec3 lit_at = flat_lit > 0.5 ? NODE_POSITION_WORLD + vec3(0.0, 1.0, 0.0) : at;
	given = given_over(lit_at, flat_lit > 0.5 ? vec3(0.0) : normal, ground_at(lit_at.xz));
	flat_light = vec3(0.0);
	tinted = vec4(0.0);
	if (flat_lit > 0.5) {
		float level = 1.0;
		if (light.r > 1.5) {
			float x = clamp(dot(normal, key_toward(mirrored)) * 0.5 + 0.5, 0.0, 1.0) * float(RAMP - 1);
			int i = min(int(x), RAMP - 2);
			level = mix(texelFetch(lighting, looked + ivec2(0, HEAD_ROWS + i), 0).r, texelFetch(lighting, looked + ivec2(0, HEAD_ROWS + 1 + i), 0).r, x - float(i));
		}
		vec3 key;
		float spare;
		flat_light = lit_flat(given, light.g, level, mirrored, MODEL_MATRIX, NORMAL, key, spare);
		tinted = vec4((1.0 - level) * light.b * key, spare);
	}
#ifdef TOON
	vec3 key_light = mirrored ? mirror_light : sun_light;
	toon_light = flat_lit > 0.5 ? min(flat_light + key_light, vec3(light.g)) : (mirrored ? mirror_ambient : mix(sky_horizon, sky_zenith, 0.5) * sky_ambient) * given.a + given.rgb + key_light;
#endif
}
uniform sampler2D regions : filter_nearest, repeat_disable;
// A region's kind (ExpressionDefinition.REGIONS, the rest a look) and a look's field (ExpressionPlayer.LOOK_FIELDS).
const int REGION_HUE = 0;
const int REGION_COLOR = 1;
const int REGION_TONE = 2;
const int LOOK_DECAL = 0;
const int LOOK_DECAL_INTENSITY = 1;
const int LOOK_DECAL_HUE = 2;
const int LOOK_CLEARCOAT_ST = 3;
const int LOOK_EMISSION = 4;
const int LOOK_MATCAP_INTENSITY = 5;
uniform int region_count = 0;
uniform sampler2D hue_mask : hint_default_white, filter_linear, repeat_disable;
uniform sampler2D untinted : source_color, hint_default_white, filter_linear_mipmap_anisotropic;
// Each recoloured cell, padding included: row 0 its rect in the atlas, row 1 its rect in `untinted`.
uniform sampler2D untinted_cells : filter_nearest, repeat_disable;
uniform int untinted_count = 0;
uniform sampler2DArray decals : source_color, hint_default_black, filter_linear_mipmap, repeat_disable;

vec3 hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

vec3 rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

vec3 shift_hue(vec3 c, vec3 settings) {
	float angle = settings.x * 6.28318530718;
	if (settings.y > 1.5) {
		vec3 axis = vec3(0.57735026919);
		return c * cos(settings.x) + cross(axis, c) * sin(settings.x) + axis * dot(axis, c) * (1.0 - cos(settings.x));
	}
	if (settings.y > 0.5) {
		vec3 value = hsv(c);
		value.x = settings.z > 0.5 ? value.x + settings.x : settings.x;
		return rgb(value);
	}
	vec3 lms = vec3(dot(c, vec3(0.4122214708, 0.5363325363, 0.0514459929)),
		dot(c, vec3(0.2119034982, 0.6806995451, 0.1073969566)),
		dot(c, vec3(0.0883024619, 0.2817188376, 0.6299787005)));
	lms = sign(lms) * pow(abs(lms), vec3(1.0 / 3.0));
	vec3 lab = vec3(dot(lms, vec3(0.2104542553, 0.7936177850, -0.0040720468)),
		dot(lms, vec3(1.9779984951, -2.4285922050, 0.4505937099)),
		dot(lms, vec3(0.0259040371, 0.7827717662, -0.8086757660)));
	if (settings.z < 0.5) { lab.yz = vec2(length(lab.yz), 0.0); }
	lab.yz = vec2(cos(angle) * lab.y - sin(angle) * lab.z, sin(angle) * lab.y + cos(angle) * lab.z);
	lms = vec3(lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z,
		lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z,
		lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z);
	lms = lms * lms * lms;
	return vec3(dot(lms, vec3(4.0767416621, -3.3077115913, 0.2309699292)),
		dot(lms, vec3(-1.2684380046, 2.6097574011, -0.3413193965)),
		dot(lms, vec3(-0.0041960863, -0.7034186147, 1.7076147010)));
}

// Poiyomi's decal Color Blend Modes by their _DecalBlendType numbers (its customBlend).
vec3 decal_blend(vec3 base, vec3 laid, int mode) {
	if (mode == 1) { return min(base, laid); }
	if (mode == 2) { return base * laid; }
	if (mode == 5) { return max(base, laid); }
	if (mode == 6) { return 1.0 - (1.0 - base) * (1.0 - laid); }
	if (mode == 7) { return max(base - laid, 0.0); }
	if (mode == 8) { return base + laid; }
	if (mode == 9) { return mix(2.0 * base * laid, 1.0 - 2.0 * (1.0 - base) * (1.0 - laid), step(0.5, base)); }
	if (mode == 20) { return base + base * laid; }
	return laid;
}

vec3 linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

#ifdef CLEAR_COAT
float pow5(float x) {
	float x2 = x * x;
	return x2 * x2 * x;
}

// Poiyomi's clear coat (poiClearCoat) at levels `level` (mask, smoothness, reflection, specular), each a vector in
// view space: Unity's GGX highlight of the main light `key` coming from `l` and a reflection of the sky, each through
// the coat's Fresnel, masked, to add over the lit colour. The sky stands in for the reflection probe Unity reads,
// blurred toward its mean as the coat roughens. Poiyomi takes N.L twice, in the highlight and in its light's
// attenuation, and its dielectric reflectance is gamma space's in linear space too.
vec3 clear_coat(vec4 level, float perceptual, vec4 specular, vec3 reflection_tint, vec3 n, vec3 v, vec3 l, vec3 key, vec3 sky_reflected) {
	const float dielectric = 0.220916301;
	float rough = max(perceptual * perceptual, 0.002);
	vec3 h = normalize(l + v);
	float nl = clamp(dot(n, l), 0.0, 1.0);
	float nv = clamp(dot(n, v), 0.0, 1.0);
	float nh = clamp(dot(n, h), 0.0, 1.0);
	float lh = clamp(dot(l, h), 0.0, 1.0);
	float ggx = 0.0;
	if (nl > 0.0) {
		float r2 = rough * rough;
		float visible = 0.5 / (nl * (nv * (1.0 - rough) + rough) + nv * (nl * (1.0 - rough) + rough) + 1e-5);
		float d = (nh * r2 - nh) * nh + 1.0;
		ggx = visible * r2 / (d * d + 1e-7);
	}
	float fresnel = dielectric + (1.0 - dielectric) * pow5(1.0 - lh);
	vec3 highlight = key * max(0.0, ggx * max(1e-5, nl)) * fresnel * level.w * specular.rgb * nl;
	float grazing = clamp(level.y + 0.04, 0.0, 1.0);
	float glancing = mix(dielectric, grazing, pow5(1.0 - nv));
	vec3 reflection = sky_reflected / (rough * rough + 1.0) * mix(1.0, glancing, specular.a) * reflection_tint * level.z;
	return clamp((highlight + reflection) * level.x, 0.0, 1.0);
}
#endif

#ifdef TOON
// lilToon's toon step of `v` across `border`, `blur` wide, its low end `range` further down, antialiased over `width`,
// how far `v` moves across a pixel.
float toon(float v, float border, float blur, float range, float width) {
	float low = clamp(border - 0.5 * blur - range, 0.0, 1.0);
	float high = clamp(border + 0.5 * blur, 0.0, 1.0);
	return clamp((v - low) / max(clamp(high - low + width, 0.0, 1.0), 1e-4), 0.0, 1.0);
}
#endif

// Poiyomi's matcaps over `base`, the material's colour, each looked up by the world normal `n` as seen along `v` (toward
// the eye) in Unity's left-handed axes, Godot's mirrored through X, and masked by its channel of `matcap_masks` at the
// atlas's `uv`, by a circle where it has one, and where `light_mask` says by the lit side, each slot's intensity `at`
// where `moved`; returns the light they add.
vec3 matcapped(inout vec3 base, int entry, vec2 uv, vec2 dx, vec2 dy, vec3 n, vec3 v, float lit, vec4 moved, vec4 at) {
	vec4 masks = textureGrad(matcap_masks, uv, dx, dy);
	vec3 up = vec3(0.0, 1.0, 0.0) - v * v.y;
	up = dot(up, up) > 1e-8 ? normalize(up) : vec3(0.0, 0.0, -sign(v.y));
	vec3 right = cross(up, v);
	vec3 r = reflect(-v, n);
	vec3 added = vec3(0.0);
	int count = min(int(texelFetch(lighting, ivec2(entry, MATCAP), 0).r + 0.5), MATCAPS);
	for (int slot = 0; slot < count; slot++) {
		int row = MATCAP + 1 + slot * MATCAP_ROWS;
		vec4 circle = texelFetch(lighting, ivec2(entry, row + 5), 0);
		vec4 paint = texelFetch(lighting, ivec2(entry, row), 0);
		vec4 map = texelFetch(lighting, ivec2(entry, row + 1), 0);
		vec4 strengths = texelFetch(lighting, ivec2(entry, row + 2), 0);
		vec4 rest = texelFetch(lighting, ivec2(entry, row + 3), 0);
		vec4 hue = texelFetch(lighting, ivec2(entry, row + 4), 0);
		vec2 mapped = (map.y > 0.5 ? vec2(-r.x, r.y) : vec2(dot(right, n), dot(up, n))) * map.z + 0.5;
		vec4 sampled = (map.x >= 0.0 ? textureLod(matcaps, vec3(mapped.x, 1.0 - mapped.y, map.x), 0.0) : vec4(1.0)) * paint;
		int own = int(circle.a + 0.5);
		vec3 light = sampled.rgb * mix(map.w, at[own], moved[own]);
		float mask = masks[own] * mix(1.0, lit, rest.w);
		if (circle.r > 0.5) {
			mask *= 1.0 - smoothstep(circle.y - 0.5 * circle.z, circle.y + 0.5 * circle.z, distance(mapped, vec2(0.5)));
		}
		float cover = sampled.a * mask;
		vec3 coloured = mix(light, light * base, rest.y);
		if (hue.a > 0.5) {
			coloured = shift_hue(coloured, hue.xyz);
		}
		strengths *= cover;
		base = mix(base, coloured, strengths.x);
		base *= mix(vec3(1.0), coloured, strengths.y);
		base += coloured * strengths.z;
		base = mix(base, 1.0 - (1.0 - base) * (1.0 - coloured), strengths.w);
		base = mix(base, base + base * coloured, rest.x * cover);
		added += coloured * rest.z * cover;
	}
	return added;
}

void fragment() {
	vec2 uv = UV * atlas.xy + atlas.zw;
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	vec2 uv_dx = dFdx(UV);
	vec2 uv_dy = dFdy(UV);
	vec4 base = texture(picture, uv);
	vec4 hue = vec4(0.0);
	vec3 tint = vec3(-1.0);
	vec3 tone = vec3(1.0, 0.0, 0.0);
	vec4 decal_alpha = vec4(-1.0);
	vec4 decal_intensity = vec4(1.0);
	vec4 decal_mode = vec4(0.0);
	vec4 decal_page = vec4(0.0);
	vec4 decal_rect[4];
	vec4 decal_cell[4];
#ifdef DECAL_HUE
	vec4 decal_shift = vec4(0.0);
	vec4 decal_turn = vec4(0.0);
#endif
#ifdef CLEAR_COAT
	vec4 coat_moved = vec4(0.0);
	vec4 coat_at = vec4(0.0);
#endif
	float strength = glow_strength;
	vec4 matcap_moved = vec4(0.0);
	vec4 matcap_at = vec4(0.0);
	for (int i = 0; i < region_count; i++) {
		vec4 rect = texelFetch(regions, ivec2(i, 0), 0);
		if (all(greaterThanEqual(UV, rect.xy)) && all(lessThanEqual(UV, rect.zw))) {
			vec4 s = texelFetch(regions, ivec2(i, 1), 0);
			vec4 e = texelFetch(regions, ivec2(i, 2), 0);
			int kind = int(s.y);
			if (kind == REGION_HUE) {
				hue = vec4(s.x, s.z, s.w, 1.0);
			} else if (kind == REGION_COLOR) {
				if (tint.x < 0.0) { tint = e.xyz; }
				tint[int(s.z)] = s.x;
			} else if (kind == REGION_TONE) {
				tone[int(s.z)] = s.x;
			} else {
				// Field -1 is a target at rest, where each material keeps its own (ExpressionPlayer.apply).
				if (e.y < -0.5) { continue; }
				int slot = int(s.z);
				int field = int(e.y + 0.5);
				if (field == LOOK_EMISSION) {
					strength = s.x;
					continue;
				}
				if (field == LOOK_MATCAP_INTENSITY) {
					matcap_moved[slot] = 1.0;
					matcap_at[slot] = s.x;
					continue;
				}
#ifdef CLEAR_COAT
				if (field == LOOK_CLEARCOAT_ST) {
					coat_at[slot] = s.x;
					coat_moved[slot] = 1.0;
					continue;
				}
#endif
				decal_mode[slot] = s.w;
				decal_page[slot] = e.z;
				decal_rect[slot] = texelFetch(regions, ivec2(i, 3), 0);
				decal_cell[slot] = rect;
#ifdef DECAL_HUE
				if (decal_turn[slot] < 0.5 && e.w > 0.5) {
					decal_turn[slot] = e.w;
					decal_shift[slot] = texelFetch(regions, ivec2(i, 4), 0).x;
				}
				if (field == LOOK_DECAL_HUE) { decal_shift[slot] = s.x; }
#endif
				if (field == LOOK_DECAL) {
					decal_alpha[slot] = s.x;
				} else {
					if (field == LOOK_DECAL_INTENSITY) { decal_intensity[slot] = s.x; }
					if (decal_alpha[slot] < 0.0) { decal_alpha[slot] = e.x; }
				}
			}
		}
	}
	if (tint.x >= 0.0) {
		vec3 raw = vec3(1.0);
		for (int i = 0; i < untinted_count; i++) {
			vec4 cell = texelFetch(untinted_cells, ivec2(i, 0), 0);
			if (all(greaterThanEqual(uv, cell.xy)) && all(lessThanEqual(uv, cell.zw))) {
				vec4 place = texelFetch(untinted_cells, ivec2(i, 1), 0);
				vec2 to = (place.zw - place.xy) / (cell.zw - cell.xy);
				raw = textureGrad(untinted, place.xy + (uv - cell.xy) * to, dx * to, dy * to).rgb;
				break;
			}
		}
		base.rgb = raw * linear(clamp(tint, 0.0, 1.0));
	}
	base *= colour;
	if (use_vertex) { base *= COLOR; }
	vec4 adjust = texture(hue_mask, UV);
	if (hue.w > 0.5) {
		base.rgb = mix(base.rgb, shift_hue(base.rgb, hue.xyz), adjust.r);
	}
	if (tone != vec3(1.0, 0.0, 0.0)) {
		base.rgb = mix(base.rgb, sign(base.rgb) * pow(abs(base.rgb), vec3(tone.x)), adjust.a);
		base.rgb = mix(base.rgb, vec3(dot(base.rgb, vec3(0.3, 0.59, 0.11))), -tone.y * adjust.b);
		base.rgb = mix(base.rgb, base.rgb * (tone.z + 1.0), adjust.g);
	}
	for (int slot = 0; slot < 4; slot++) {
		if (decal_alpha[slot] >= 0.0) {
			vec4 cell = decal_cell[slot];
			vec4 place = decal_rect[slot];
			vec2 to_page = (place.zw - place.xy) / (cell.zw - cell.xy);
			vec2 at = place.xy + (clamp(UV, cell.xy, cell.zw) - cell.xy) * to_page;
			vec4 decal = textureGrad(decals, vec3(at, decal_page[slot]), uv_dx * to_page, uv_dy * to_page);
			vec3 laid = decal.rgb;
#ifdef DECAL_HUE
			if (decal_turn[slot] > 0.5) {
				float mode = decal_turn[slot] - 1.0;
				laid = shift_hue(laid, vec3(decal_shift[slot], floor(mode * 0.5), mod(mode, 2.0)));
			}
#endif
			float alpha = clamp(decal_intensity[slot] * decal.a * clamp(decal_alpha[slot], 0.0, 1.0), 0.0, 1.0);
			base.rgb = mix(base.rgb, decal_blend(base.rgb, laid, int(decal_mode[slot] + 0.5)), alpha);
		}
	}
#ifdef TOON
	// Taken before any branch on the entry, which differs within a quad along a material's edge.
	float toward = clamp(toon_toward, 0.0, 1.0);
	float toward_width = fwidth(toon_toward);
	vec3 toon_n = normalize(toon_normal);
	float facing = abs(dot(toon_n, VIEW));
	float facing_width = fwidth(facing);
	vec4 shade_texel = textureGrad(shade, uv, dx, dy);
	vec3 albedo = base.rgb;
	bool shadowed = false;
	float shadowmix = 1.0;
	vec3 rim_light = vec3(0.0);
	if (toon_entry >= 0) {
		vec4 shadow = texelFetch(lighting, ivec2(toon_entry, TOON_ROW), 0);
		if (shadow.a > 0.5) {
			vec4 second = texelFetch(lighting, ivec2(toon_entry, TOON_ROW + 1), 0);
			vec4 edge = texelFetch(lighting, ivec2(toon_entry, TOON_ROW + 2), 0);
			vec3 dark = shade_texel.rgb;
			if (second.z > 0.0) {
				dark = mix(dark, textureGrad(shade2, uv, dx, dy).rgb, second.z * (1.0 - toon(toward, second.x, second.y, 0.0, toward_width)));
			}
			dark = min(dark, albedo);
			dark = mix(dark, albedo, toon(toward, shadow.x, shadow.y, edge.a, toward_width) * edge.rgb);
			shadowmix = toon(toward, shadow.x, shadow.y, 0.0, toward_width);
			shadowed = true;
			base.rgb = mix(dark, albedo, mix(1.0, shadowmix, shadow.z * shade_texel.a));
		}
	}
#endif
	vec3 matcap_light = vec3(0.0);
	if (matcap_entry >= 0) {
		bool mirrored = CAMERA_VISIBLE_LAYERS == mirror_mask;
		vec3 n = normalize(matcap_normal) * (FRONT_FACING ? 1.0 : -1.0);
		vec3 toward = mirrored ? mirror_toward : sun_toward;
		float lit = smoothstep(0.4, 0.6, dot(n, length(toward) > 1e-4 ? normalize(toward) : vec3(0.0, 1.0, 0.0)) * 0.5 + 0.5);
#ifdef TOON
		if (shadowed) { lit = shadowmix; }
#endif
		matcap_light = matcapped(base.rgb, matcap_entry, uv, dx, dy, n, normalize(mat3(INV_VIEW_MATRIX) * VIEW), lit, matcap_moved, matcap_at);
	}
#ifdef TOON
	if (toon_entry >= 0) {
		vec4 rim = texelFetch(lighting, ivec2(toon_entry, TOON_ROW + 3), 0);
		if (rim.a > 0.0) {
			vec4 edge = texelFetch(lighting, ivec2(toon_entry, TOON_ROW + 4), 0);
			vec4 reach = texelFetch(lighting, ivec2(toon_entry, TOON_ROW + 5), 0);
			float fresnel = pow(1.0 - facing, edge.w);
			float fresnel_width = edge.w * pow(max(1.0 - facing, 1e-4), edge.w - 1.0) * facing_width;
			float r = toon(fresnel, edge.y, edge.z, 0.0, fresnel_width) * mix(1.0, shadowmix, reach.y) * rim.a;
			rim_light = rim.rgb * mix(vec3(1.0), albedo, edge.x) * mix(vec3(1.0), toon_light, reach.x) * r;
		}
	}
#endif
	vec3 glowing = vec3(0.0);
	float replaced = 0.0;
	vec3 glows = glow_colour.rgb * strength;
	if (any(greaterThan(glows, vec3(0.0)))) {
		glowing = textureGrad(glow, uv, dx, dy).rgb * glows;
		replaced = clamp(max(glowing.r, max(glowing.g, glowing.b)) * glow_colour.a, 0.0, 1.0);
	}
	ALBEDO = base.rgb * (1.0 - replaced);
	ALPHA = base.a;
#ifndef BLENDED
	ALPHA_SCISSOR_THRESHOLD = 0.5;
#endif
	ROUGHNESS = 1.0;
	AO = flat_lit > 0.5 ? 0.0 : given.a;
	EMISSION = ALBEDO * (flat_lit > 0.5 ? flat_light + min(tinted.rgb * base.rgb, vec3(tinted.a)) : given.rgb) + clamp(glowing * glow_colour.a, 0.0, 1.0) * replaced + glowing + matcap_light;
#ifdef TOON
	EMISSION += rim_light;
#endif
#ifdef CLEAR_COAT
	if (coat_entry >= 0) {
		vec4 coat_level = texelFetch(lighting, ivec2(coat_entry, COAT), 0);
		vec4 st = mix(texelFetch(lighting, ivec2(coat_entry, COAT + 1), 0), coat_at, coat_moved);
		vec4 specular = texelFetch(lighting, ivec2(coat_entry, COAT + 2), 0);
		vec4 reflection = texelFetch(lighting, ivec2(coat_entry, COAT + 3), 0);
		vec4 invert = texelFetch(lighting, ivec2(coat_entry, COAT + 4), 0);
		vec2 gsaa = texelFetch(lighting, ivec2(coat_entry, COAT + 5), 0).xy;
		vec3 coat_n = normalize(coat_normal) * (FRONT_FACING ? 1.0 : -1.0);
		vec3 coat_dx = dFdx(coat_n);
		vec3 coat_dy = dFdy(coat_n);
		vec4 maps = vec4(1.0);
		if (reflection.a >= 0.0) {
			vec2 at = vec2(UV2.x, 1.0 - UV2.y) * st.xy + st.zw;
			maps = texture(coat_maps, vec3(at.x, 1.0 - at.y, reflection.a));
		}
		vec4 level = coat_level * maps;
		level = mix(level, 1.0 - level, invert);
		bool mirrored = CAMERA_VISIBLE_LAYERS == mirror_mask;
		vec3 toward = (VIEW_MATRIX * vec4(mirrored ? mirror_toward : sun_toward, 0.0)).xyz;
		toward = length(toward) > 1e-4 ? normalize(toward) : vec3(0.0, 1.0, 0.0);
		vec3 n = coat_n;
		vec3 r = (INV_VIEW_MATRIX * vec4(reflect(-VIEW, n), 0.0)).xyz;
		float perceptual = 1.0 - level.y;
		vec3 mean = mix(sky_horizon, sky_zenith, 0.5);
		vec3 sky = mix(mix(sky_horizon, sky_zenith, clamp(r.y, 0.0, 1.0)), mean, perceptual * (1.7 - 0.7 * perceptual));
		// Poiyomi's geometric specular antialiasing (Filament's): the highlight roughens where the normal turns fast
		// across a pixel, which spreads a near-mirror coat's highlight over a curved surface.
		float kernel = min(2.0 * gsaa.x * (dot(coat_dx, coat_dx) + dot(coat_dy, coat_dy)), gsaa.y);
		float squared = perceptual * perceptual;
		float widened = sqrt(sqrt(clamp(squared * squared + kernel, 0.0, 1.0)));
		EMISSION += clear_coat(level, widened, specular, reflection.rgb, n, VIEW, toward, mirrored ? mirror_light : sun_light, (mirrored ? mirror_ambient : sky * sky_ambient));
	}
#endif
}
