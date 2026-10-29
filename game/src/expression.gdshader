shader_type spatial;
render_mode diffuse_lambert, specular_disabled, vertex_lighting, cull_back;

#include "res://src/ground.gdshaderinc"
#include "res://src/bounce.gdshaderinc"

varying vec4 given;

void vertex() {
	given = given_at((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, normalize(mat3(MODEL_MATRIX) * NORMAL));
}

uniform sampler2D picture : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 colour : source_color = vec4(1.0);
uniform bool use_vertex = false;
uniform vec4 atlas = vec4(1.0, 1.0, 0.0, 0.0);
uniform sampler2D regions : filter_nearest, repeat_disable;
uniform int region_count = 0;
uniform sampler2D hue_mask : filter_linear, repeat_disable;
uniform bool masked = false;

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

void fragment() {
	vec2 uv = UV * atlas.xy + atlas.zw;
	vec4 base = texture(picture, uv) * colour;
	if (use_vertex) { base *= COLOR; }
	for (int i = 0; i < region_count; i++) {
		vec4 rect = texelFetch(regions, ivec2(i, 0), 0);
		if (all(greaterThanEqual(UV, rect.xy)) && all(lessThanEqual(UV, rect.zw))) {
			vec4 settings = texelFetch(regions, ivec2(i, 1), 0);
			base.rgb = mix(base.rgb, shift_hue(base.rgb, settings.xyz), masked ? texture(hue_mask, UV).r : 1.0);
		}
	}
	ALBEDO = base.rgb;
	ALPHA = base.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
	AO = given.a;
	EMISSION = ALBEDO * given.rgb;
}
