#[compute]
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(set = 0, binding = 0) uniform sampler2D dry;
layout(set = 0, binding = 1) uniform sampler2D paper;
layout(set = 0, binding = 2) uniform sampler2D previous;
layout(rgba8, set = 0, binding = 3) uniform restrict writeonly image2D result;
layout(push_constant, std430) uniform Params {
	ivec4 rect;
	vec4 scale;
} pc;

float height_at(ivec2 p) {
	p = clamp(p, ivec2(0), textureSize(dry, 0) - 1);
	return texelFetch(dry, p, 0).a * pc.scale.x + texelFetch(paper, p, 0).r * pc.scale.y;
}

void main() {
	ivec2 local = ivec2(gl_GlobalInvocationID.xy);
	if (any(greaterThanEqual(local, pc.rect.zw))) return;
	ivec2 p = pc.rect.xy + local;
	vec3 normal;
	if (pc.scale.w == 0.0) {
		vec2 slope = vec2(height_at(p + ivec2(1, 0)) - height_at(p - ivec2(1, 0)),
			height_at(p + ivec2(0, 1)) - height_at(p - ivec2(0, 1))) * pc.scale.z;
		normal = normalize(vec3(-slope.x, slope.y, 1.0)) * 0.5 + 0.5;
	} else {
		// Do not renormalize: the shortened mean retains unresolved normal variance for the gloss.
		normal = textureLod(previous, (vec2(p) + 0.5) / vec2(imageSize(result)), 0.0).rgb;
	}
	imageStore(result, p, vec4(normal, 1.0));
}
