shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;

#include "res://src/horizon.gdshaderinc"

uniform vec3 snow : source_color = vec3(0.92, 0.93, 0.96);

varying vec3 world_normal;

void vertex() {
	world_normal = NORMAL;
}

void fragment() {
	vec3 n = normalize(world_normal);
	float height = COLOR.r;
	float steep = 1.0 - n.y;
	vec3 ground = mix(slope, stone, smoothstep(0.22, 0.42, steep + height * 0.35));
	ground = mix(ground, snow, COLOR.b * smoothstep(COLOR.b * 0.75, COLOR.b, height) * smoothstep(0.62, 0.3, steep));
	vec3 lit = ground * (sun_light * max(dot(n, sun_toward), 0.0) * 1.0 + mix(sky_horizon, sky_zenith, 0.4 + 0.3 * n.y) * sky_ambient * 0.5);
	float air = COLOR.g * (1.0 - 0.3 * smoothstep(0.0, 0.8, height));
	ALBEDO = mix(lit, sky_haze, air);
}
