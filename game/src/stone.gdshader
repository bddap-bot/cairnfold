shader_type spatial;
render_mode diffuse_lambert_wrap;

uniform sampler2D detail : filter_linear_mipmap, repeat_enable;
uniform vec3 moss : source_color = vec3(0.30, 0.42, 0.14);

varying vec3 world_pos;
varying vec3 world_nrm;
varying float occlusion;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	occlusion = INSTANCE_CUSTOM.x;
}

void fragment() {
	vec3 p = world_pos * 1.7;
	vec3 an = abs(world_nrm);
	float tri = texture(detail, p.yz).r * an.x + texture(detail, p.xz).r * an.y + texture(detail, p.xy).r * an.z;
	vec3 base = COLOR.rgb * (0.78 + tri * 0.45);
	float mossy = smoothstep(0.55, 0.9, world_nrm.y) * smoothstep(0.45, 0.7, texture(detail, world_pos.xz * 0.3).r);
	ALBEDO = mix(base, moss, mossy * 0.8) * occlusion;
	ROUGHNESS = 0.92;
	SPECULAR = 0.25;
}
