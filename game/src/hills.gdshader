shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 sun : source_color = vec3(1.0);
uniform float energy = 1.0;
uniform vec3 sky : source_color = vec3(0.3, 0.5, 0.85);
uniform vec3 horizon : source_color = vec3(0.86, 0.88, 0.84);
uniform float ambient = 0.7;
uniform vec3 lush : source_color = vec3(0.30, 0.52, 0.10);
uniform vec3 straw : source_color = vec3(0.58, 0.58, 0.20);
uniform vec3 wood : source_color = vec3(0.10, 0.24, 0.08);

varying vec3 world_normal;

void vertex() {
	world_normal = NORMAL;
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec3 ground = mix(mix(lush, straw, smoothstep(0.35, 0.75, COLOR.r)), wood, COLOR.g);
	ALBEDO = ground * (sun * energy * max(dot(n, sun_dir), 0.0) + mix(horizon, sky, 0.4 + 0.3 * n.y) * ambient * 0.5);
}
