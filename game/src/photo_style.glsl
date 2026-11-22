#[vertex]
#version 450

layout(location = 0) out vec2 uv;

void main() {
	uv = vec2((gl_VertexIndex << 1) & 2, gl_VertexIndex & 2);
	gl_Position = vec4(uv * 2.0 - 1.0, 0.0, 1.0);
}

#[fragment]
#version 450

layout(location = 0) in vec2 uv;
layout(location = 0) out vec4 colour;
layout(set = 0, binding = 0) uniform sampler2D seen;

// The scene's colour is held as the square root of its light (scripts/engine.patch, scene_encode).
vec3 light(vec2 at) {
	vec3 c = texture(seen, at).rgb;
	return c * c;
}

// `tone` rows map linear rgb to rgb; `brush`: the strokes' reach in texels (x, y), samples a side (z), 1 to copy.
layout(push_constant, std430) uniform Style {
	vec4 r;
	vec4 g;
	vec4 b;
	vec4 brush;
} style;

// Kuwahara's four quadrants, each sampled on a fixed grid whatever the reach, so a photo's strokes cost what a
// preview's do a pixel.
vec3 painted() {
	int n = int(style.brush.z);
	vec2 stride = style.brush.xy / float(n);
	vec3 best = vec3(0.0);
	float least = 1e30;
	for (int q = 0; q < 4; q++) {
		vec2 dir = vec2((q & 1) == 0 ? -1.0 : 1.0, (q & 2) == 0 ? -1.0 : 1.0);
		vec3 sum = vec3(0.0);
		vec3 squares = vec3(0.0);
		for (int y = 0; y <= n; y++) {
			for (int x = 0; x <= n; x++) {
				vec3 c = light(uv + dir * stride * vec2(x, y));
				sum += c;
				squares += c * c;
			}
		}
		float count = float((n + 1) * (n + 1));
		vec3 mean = sum / count;
		vec3 spread = squares / count - mean * mean;
		float v = spread.r + spread.g + spread.b;
		if (v < least) {
			least = v;
			best = mean;
		}
	}
	return best;
}

void main() {
	vec3 c = style.brush.z > 0.0 ? painted() : light(uv);
	colour = vec4(sqrt(max(vec3(dot(style.r.rgb, c), dot(style.g.rgb, c), dot(style.b.rgb, c)), vec3(0.0))), texture(seen, uv).a);
}
