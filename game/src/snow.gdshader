shader_type spatial;
// Its own haze, not the fog: the ground layer would hide even the flakes at the face.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://src/billboard.gdshaderinc"
#include "res://src/daylight.gdshaderinc"

// CUSTOM0: xyz where the flake starts in the unit box, w its rank: it falls while rank < amount.
uniform float amount = 0.0;
// The share of the sky the eye sees, so flakes do not fall in a room.
uniform float open = 1.0;
uniform float box = 20.0;
uniform float fall = 1.0;
uniform float size = 0.042;
// Radians: past where a flake would draw smaller than this it grows and dims instead, so none flickers in and out of
// a pixel as the head moves.
uniform float least = 0.0025;

varying float alpha;
varying float far;

void vertex() {
	vec4 seed = CUSTOM0;
	float s = fract(seed.x * 17.3 + seed.z * 5.9);
	vec3 eye = NODE_POSITION_WORLD;
	vec3 p = seed.xyz * box;
	p.y -= TIME * fall * (0.75 + 0.5 * s);
	p.x += sin(TIME * (0.5 + 0.4 * s) + s * 40.0) * 0.35;
	p.z += cos(TIME * (0.4 + 0.3 * s) + s * 23.0) * 0.35;
	p = eye + mod(p - eye + box * 0.5, box) - box * 0.5;
	float d = length(p - CAMERA_POSITION_WORLD);
	float drawn = max(size, d * least);
	float edge = length(p - eye) / (box * 0.5);
	far = edge;
	alpha = step(seed.w, amount) * open * (1.0 - smoothstep(0.7, 1.0, edge)) * smoothstep(0.25, 0.6, d) * (size * size) / (drawn * drawn);
	MODELVIEW_MATRIX = billboard(VIEW_MATRIX, INV_VIEW_MATRIX, p, drawn * (alpha > 0.0 ? 1.0 : 0.0));
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	vec3 lit = vec3(0.97, 0.98, 1.0) * (sun_light * 0.7 + mix(sky_horizon, sky_zenith, 0.5) * sky_ambient * 1.3);
	ALBEDO = mix(lit, sky_haze, 0.4 * far * fog_veil);
	ALPHA = alpha * (1.0 - smoothstep(0.35, 1.0, r));
}
