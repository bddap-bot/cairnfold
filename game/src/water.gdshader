shader_type spatial;
// Unshaded, lit by hand from the hour's light as the far lake is: Godot's own lighting in the transparent pass is most
// of what a view full of water cost a Quest 2 (docs/design.md, "Water").
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

#include "res://src/ground.gdshaderinc"
#include "res://src/water.gdshaderinc"
#include "res://src/daylight.gdshaderinc"
#include "res://src/detail.gdshaderinc"

// Depth comes from the shared ground heights, not the depth buffer: on a tiled GPU reading the depth
// buffer back costs a full-frame resolve per eye.
uniform sampler2D waves : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float level;
uniform float drop = 0.0;
uniform vec4 ripples[12];
uniform bool rippling = false;
uniform vec3 shallow : source_color = vec3(0.30, 0.68, 0.58);
uniform vec3 deep : source_color = vec3(0.03, 0.19, 0.29);
uniform vec3 foam_color : source_color = vec3(0.96, 0.98, 0.94);
uniform float wave_strength = 0.22;
// Air over water seen from under it, which Look keeps to the sky overhead at this hour.
global uniform vec3 sky_overhead;
// Light leaves water for air only within 48.6 degrees of straight up (Snell's window, cos = sqrt(1 - 1/1.333^2));
// past that the surface mirrors the water below.
const float WINDOW_COS = 0.661;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 s = wp.xz;
	// The grid's bilinear depth stands in for the spline far from any shore, where neither foam nor the fade reads it.
	float depth = water_depth_at(s) - drop;
	if (depth < 0.45) {
		depth = level - drop - grid_smooth(ground_height, s);
	}
	vec2 slope = (texture(waves, s * 0.21 + TIME * vec2(0.019, 0.011)).xy
		+ texture(waves, s * 0.33 - TIME * vec2(0.012, 0.021)).xy - 1.0) * wave_strength;
	if (rippling) {
		for (int i = 0; i < 12; i++) {
			vec4 r = ripples[i];
			if (r.w > 0.0) {
				vec2 dv = s - r.xy;
				float d = length(dv) + 1e-4;
				float x = d - r.z * 0.42;
				slope += dv / d * cos(x * 26.0) * r.w * exp(-r.z * 1.3 - x * x * 14.0);
			}
		}
	}
	vec3 n = normalize(vec3(-slope.x, 1.0, -slope.y));
	// Only an eye under the surface sees its back face, so each eye of a head halfway in sees its own side.
	if (!FRONT_FACING) {
		vec3 up = normalize((INV_VIEW_MATRIX * vec4(-VIEW, 0.0)).xyz);
		// The window's edge follows the broad swell, not every ripple, so it reads as a circle that wavers.
		float c = dot(up, normalize(vec3(-slope.x, 2.5, -slope.y)));
		float window = smoothstep(WINDOW_COS - 0.03, WINDOW_COS + 0.03, c);
		float rim = smoothstep(0.09, 0.0, abs(c - WINDOW_COS - 0.035));
		float glint = texture(detail, s * 1.3 - slope * 2.0 + TIME * vec2(0.03, 0.02)).r;
		vec3 air = sky_overhead * (1.7 + 0.8 * smoothstep(0.75, 1.0, c)) * (0.85 + glint * 0.3);
		vec3 mirror = mix(deep, shallow, 0.3) * dot(sky_overhead, vec3(0.3, 0.55, 0.15)) * (0.8 + glint * 0.4);
		ALBEDO = mix(mirror, air, window) + sky_overhead * rim * 0.9;
		ALPHA = smoothstep(0.0, 0.07, depth);
	} else {
		vec3 v = normalize(CAMERA_POSITION_WORLD - wp);
		vec3 r = reflect(-v, n);

		float body = 1.0 - exp(-max(depth, 0.0) * 2.8);
		vec3 col = mix(shallow, deep, body);
		float alpha = mix(0.2, 0.93, body);

		float foam = 0.0;
		if (depth < 0.3) {
			float grain = texture(detail, s * 0.6 + TIME * vec2(0.01, -0.008)).r;
			// The ground mesh is 1 m triangles while depth here is a smooth spline, so the surface fades out over the
			// last few centimetres and the foam line sits just inside where it meets the ground.
			float shore = smoothstep(0.03, 0.08, depth) * smoothstep(0.16, 0.09, depth + (grain - 0.5) * 0.05);
			float lines = smoothstep(0.86, 0.98, sin(depth * 48.0 - TIME * 1.2 + grain * 4.0) * 0.5 + 0.5) * smoothstep(0.3, 0.1, depth);
			foam = clamp(max(shore * 0.8, lines * 0.55) * smoothstep(0.35, 0.65, grain + shore * 0.25), 0.0, 1.0);
		}

		float fresnel = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 4.0);
		alpha = mix(alpha, 0.95, fresnel * 0.7);
		col = mix(col, foam_color, foam);
		alpha = max(alpha, foam * 0.9) * smoothstep(0.0, 0.07, depth);

		vec3 lit = col * (sun_light * max(dot(n, sun_toward), 0.0) + mix(sky_horizon, sky_zenith, 0.6) * sky_ambient * 0.65);
		vec3 sky = mix(sky_horizon, sky_zenith, pow(clamp(r.y, 0.0, 1.0), 0.55));
		lit = mix(lit, sky, (0.04 + 0.96 * fresnel) * (1.0 - foam));
		lit += sun_light * pow(max(dot(r, sun_toward), 0.0), 1500.0) * 4.0 * (1.0 - foam);

		ALBEDO = lit;
		ALPHA = alpha;
	}
}
