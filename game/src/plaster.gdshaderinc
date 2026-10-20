// World coordinates keep neighbouring panels and a bake of their faces on the same patch.
float plaster_surface(sampler2D detail, vec3 world, vec3 normal, float height) {
	vec3 n = abs(normal);
	vec2 uv = n.y > max(n.x, n.z) ? world.xz : (n.x > n.z ? world.zy : world.xy);
	vec2 turned = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * uv;
	float grain = 0.5 * (texture(detail, uv * 1.7).r + texture(detail, turned * 2.317 + vec2(0.37, 0.81)).r);
	float weather = texture(detail, turned * 0.043 + vec2(9.7, 3.2)).r;
	float foot = (1.0 - smoothstep(0.0, 1.4, height)) * (0.04 + 0.08 * weather);
	return (0.86 + grain * 0.28) * (0.85 + weather * 0.3) - foot;
}
