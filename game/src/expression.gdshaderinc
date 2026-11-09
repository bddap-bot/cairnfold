#include "res://src/ground.gdshaderinc"
#include "res://src/bounce.gdshaderinc"
#include "res://src/daylight.gdshaderinc"

uniform sampler2D picture : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 colour : source_color = vec4(1.0);
uniform bool use_vertex = false;
uniform vec4 atlas = vec4(1.0, 1.0, 0.0, 0.0);
// Each atlas texel's entry in the looks' materials and each entry's looks (Avatar._lit_looks): row 0 red one where
// flat and two where lit through a ramp, green its cap, blue its shadow tint; row 1 its emission's colour and strength
// over the emission map `glow`, alpha how far the glow overrides the lit colour (Poiyomi's lerp toward the glow by its
// brightest channel); rows 2 to RAMP + 1 its ramp. Unset, every texel is lit by angle and glows nowhere.
uniform sampler2D light_index : hint_default_black, filter_nearest, repeat_disable;
uniform sampler2D lighting : hint_default_black, filter_nearest, repeat_disable;
uniform sampler2D glow : source_color, hint_default_black, filter_linear_mipmap, repeat_disable;
// The mirror's view, the one camera that sees just Quality.MIRROR_MASK, lit by the mirror's own light and ambient
// (MirrorTool).
uniform uint mirror_mask;
global uniform vec3 mirror_toward;
global uniform vec3 mirror_light;
global uniform vec3 mirror_ambient;

varying vec4 given;
// One where the vertex's material is flat; then flat_light is the ambient and light given back it takes, capped.
varying float flat_lit;
varying vec3 flat_light;
// A ramp-lit vertex's main light its shadow tint lends the albedo, and the light its cap leaves room for.
varying vec4 tinted;
varying vec4 glow_colour;

// A flat material, as Poiyomi's Flat lighting and Toon Lit light it, takes the main light whole whichever way it
// faces, plus the ambient, capped: its texture's painted shading is the only shading. The ambient and the light given
// back are added capped as emission, the engine's ambient left out; the main light stays the engine's, so the sun's
// shadow still falls on it, through a normal turned toward the light and away by as much as keeps the whole under the
// cap. The cap clips the ambient per channel and the main light by its brightest channel. A ramp-lit material, as
// Toon Standard lights it, takes the same ambient and the main light scaled by its ramp at the half-Lambert term, and
// the rest of the main light lent the albedo by its shadow tint in each pixel, under the same cap; that tint, added as
// emission, takes no cast shadow, as Toon Standard's shade does under one.
const int RAMP = 16;
void vertex() {
	float entry = textureLod(light_index, UV * atlas.xy + atlas.zw, 0.0).r;
	ivec2 looked = ivec2(min(int(round(entry * 255.0)), textureSize(lighting, 0).x - 1), 0);
	vec3 light = texelFetch(lighting, looked, 0).rgb;
	glow_colour = textureSize(lighting, 0).y > 1 ? texelFetch(lighting, looked + ivec2(0, 1), 0) : vec4(0.0);
	flat_lit = light.r > 0.5 ? 1.0 : 0.0;
	vec3 at = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
	// A flat or ramp-lit vertex reads the light around it a metre over its mesh's origin, the same place for every
	// vertex: reading the volumes at each vertex of a dense avatar cost a Quest 2 more than its whole lighting.
	vec3 lit_at = flat_lit > 0.5 ? NODE_POSITION_WORLD + vec3(0.0, 1.0, 0.0) : at;
	given = given_over(lit_at, flat_lit > 0.5 ? vec3(0.0) : normal, ground_at(lit_at.xz));
	flat_light = vec3(0.0);
	tinted = vec4(0.0);
	if (flat_lit > 0.5) {
		bool mirrored = CAMERA_VISIBLE_LAYERS == mirror_mask;
		vec3 ambient = (mirrored ? mirror_ambient : mix(sky_horizon, sky_zenith, 0.5) * sky_ambient) * given.a;
		vec3 key = mirrored ? mirror_light : sun_light;
		vec3 toward = mirrored ? mirror_toward : sun_toward;
		flat_light = min(ambient + given.rgb, vec3(light.g));
		float room = light.g - max(flat_light.r, max(flat_light.g, flat_light.b));
		toward = length(toward) > 1e-4 ? normalize(toward) : vec3(0.0, 1.0, 0.0);
		float level = 1.0;
		if (light.r > 1.5) {
			float x = clamp(dot(normal, toward) * 0.5 + 0.5, 0.0, 1.0) * float(RAMP - 1);
			int i = min(int(x), RAMP - 2);
			level = mix(texelFetch(lighting, looked + ivec2(0, 2 + i), 0).r, texelFetch(lighting, looked + ivec2(0, 3 + i), 0).r, x - float(i));
		}
		float brightest = max(max(key.r, max(key.g, key.b)), 1e-4);
		float facing = clamp(min(level, room / brightest), 0.0, 1.0);
		tinted = vec4((1.0 - level) * light.b * key, max(room - facing * brightest, 0.0));
		vec3 across = vec3(0.0, 1.0, 0.0) - toward * toward.y;
		across = dot(across, across) > 1e-6 ? normalize(across) : vec3(1.0, 0.0, 0.0);
		NORMAL = normalize(transpose(mat3(MODEL_MATRIX)) * (facing * toward + sqrt(1.0 - facing * facing) * across));
	}
}
uniform sampler2D regions : filter_nearest, repeat_disable;
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
	for (int i = 0; i < region_count; i++) {
		vec4 rect = texelFetch(regions, ivec2(i, 0), 0);
		if (all(greaterThanEqual(UV, rect.xy)) && all(lessThanEqual(UV, rect.zw))) {
			vec4 s = texelFetch(regions, ivec2(i, 1), 0);
			vec4 e = texelFetch(regions, ivec2(i, 2), 0);
			int kind = int(s.y);
			if (kind == 0) {
				hue = vec4(s.x, s.z, s.w, 1.0);
			} else if (kind == 1) {
				if (tint.x < 0.0) { tint = e.xyz; }
				tint[int(s.z)] = s.x;
			} else if (kind == 2) {
				tone[int(s.z)] = s.x;
			} else {
				int slot = int(s.z);
				decal_mode[slot] = s.w;
				decal_page[slot] = e.z;
				decal_rect[slot] = texelFetch(regions, ivec2(i, 3), 0);
				decal_cell[slot] = rect;
				int field = int(e.y + 0.5);
#ifdef DECAL_HUE
				if (decal_turn[slot] < 0.5 && e.w > 0.5) {
					decal_turn[slot] = e.w;
					decal_shift[slot] = texelFetch(regions, ivec2(i, 4), 0).x;
				}
				if (field == 2) { decal_shift[slot] = s.x; }
#endif
				if (field == 0) {
					decal_alpha[slot] = s.x;
				} else {
					if (field == 1) { decal_intensity[slot] = s.x; }
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
	vec3 glowing = vec3(0.0);
	float replaced = 0.0;
	if (any(greaterThan(glow_colour.rgb, vec3(0.0)))) {
		glowing = textureGrad(glow, uv, dx, dy).rgb * glow_colour.rgb;
		replaced = clamp(max(glowing.r, max(glowing.g, glowing.b)) * glow_colour.a, 0.0, 1.0);
	}
	ALBEDO = base.rgb * (1.0 - replaced);
	ALPHA = base.a;
#ifndef BLENDED
	ALPHA_SCISSOR_THRESHOLD = 0.5;
#endif
	ROUGHNESS = 1.0;
	AO = flat_lit > 0.5 ? 0.0 : given.a;
	EMISSION = ALBEDO * (flat_lit > 0.5 ? flat_light + min(tinted.rgb * base.rgb, vec3(tinted.a)) : given.rgb) + clamp(glowing * glow_colour.a, 0.0, 1.0) * replaced + glowing;
}
