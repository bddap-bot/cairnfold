// An avatar's particles (AvatarParticles), each a MultiMesh instance written once when it is born: its start position
// and velocity in its system's frame, start size and rotation as MODEL_MATRIX's columns, its birth time, lifetime,
// random seed and gravity in INSTANCE_CUSTOM and its start colour in COLOR. Where it is at any age is worked out here
// in closed form, so no frame touches a living particle on the CPU.

// Now on the clock birth times are on, and the emitter's world placement (rotation and position).
uniform float now;
uniform mat4 emitter;
uniform vec3 gravity;
uniform bool world_space;
// Curves over a particle's life, as many samples wide as the texture: pairs of rows, the low end of each random range
// then the high (AvatarParticles.ROW_*). Velocity and spin also have their integrals over life.
uniform sampler2D curves : filter_nearest;
// ParticleDefinition.MODES and ALIGNS, by index.
uniform int mode;
uniform int align;
uniform vec3 pivot;
uniform float length_scale;
uniform float velocity_scale;
// The share of the view's height a particle may span.
uniform float max_size;
uniform bool has_velocity;
uniform bool velocity_in_world;
uniform bool has_noise;
uniform bool has_limit;
uniform bool has_size_by_speed;
uniform bool has_colour_by_speed;
uniform bool has_colour_over_life;
uniform bool has_spin;
uniform vec4 speed_ranges;
uniform float noise_frequency;
// How fast speed past the limit falls away, per second.
uniform float damping;
uniform vec4 tint = vec4(1.0);
uniform vec3 emission;
uniform vec4 uv_transform = vec4(1.0, 1.0, 0.0, 0.0);
uniform sampler2D albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform bool textured;
uniform float cutoff;

float random(float seed, float k) {
	return fract(sin(seed * 12.9898 + k * 78.233) * 43758.5453);
}

// Row pair `r` at share `u` of the life, blended from its low row to its high one by `k`.
vec4 life_curve(int r, float u, float k) {
	int samples = textureSize(curves, 0).x;
	float x = clamp(u, 0.0, 1.0) * float(samples - 1);
	int i = int(floor(x));
	int j = min(i + 1, samples - 1);
	float f = x - float(i);
	vec4 low = mix(texelFetch(curves, ivec2(i, r), 0), texelFetch(curves, ivec2(j, r), 0), f);
	vec4 high = mix(texelFetch(curves, ivec2(i, r + 1), 0), texelFetch(curves, ivec2(j, r + 1), 0), f);
	return mix(low, high, k);
}

// Unity's Euler turn: about Z, then X, then Y.
mat3 euler(vec3 r) {
	float cx = cos(r.x), sx = sin(r.x), cy = cos(r.y), sy = sin(r.y), cz = cos(r.z), sz = sin(r.z);
	mat3 rx = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, cx, sx), vec3(0.0, -sx, cx));
	mat3 ry = mat3(vec3(cy, 0.0, -sy), vec3(0.0, 1.0, 0.0), vec3(sy, 0.0, cy));
	mat3 rz = mat3(vec3(cz, sz, 0.0), vec3(-sz, cz, 0.0), vec3(0.0, 0.0, 1.0));
	return ry * rx * rz;
}

// A frame whose Z runs along `forward`, upright where it can be.
mat3 look_along(vec3 forward) {
	vec3 z = normalize(forward);
	vec3 up = abs(z.y) > 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
	vec3 x = normalize(cross(up, z));
	return mat3(x, cross(z, x), z);
}

// Places a corner of the particle in view space and gives its colour; a particle not alive collapses to a point.
void particle_vertex(inout vec3 vertex, inout vec3 normal, inout vec4 particle_color, mat4 model, vec4 custom, mat4 view, mat4 inv_view, mat4 projection) {
	float age = now - custom.x;
	float life = custom.y;
	float seed = custom.z;
	if (age < 0.0 || age >= life) {
		vertex = vec3(0.0);
		return;
	}
	float u = age / life;
	vec3 v0 = model[1].xyz;
	mat3 turn = mat3(emitter);
	vec3 down = world_space ? gravity : transpose(turn) * gravity;
	vec3 moved = v0 * age;
	vec3 velocity = v0;
	if (has_limit) {
		float limit = life_curve(10, 0.0, 0.5).y;
		float speed = length(v0);
		if (speed > limit && damping > 0.0) {
			vec3 held = v0 / speed * limit;
			float fade = exp(-damping * age);
			moved = held * age + (v0 - held) * (1.0 - fade) / damping;
			velocity = held + (v0 - held) * fade;
		}
	}
	moved += 0.5 * down * custom.w * age * age;
	velocity += down * custom.w * age;
	if (has_velocity) {
		float k = random(seed, 1.0);
		vec3 path = life * life_curve(4, u, k).xyz;
		vec3 now_v = life_curve(6, u, k).xyz;
		bool other = velocity_in_world != world_space;
		mat3 into = world_space ? turn : transpose(turn);
		moved += other ? into * path : path;
		velocity += other ? into * now_v : now_v;
	}
	if (has_noise) {
		float strength = life_curve(10, u, random(seed, 5.0)).x;
		float w = 6.2831853 * max(noise_frequency, 0.05);
		vec3 phase = vec3(random(seed, 6.0), random(seed, 7.0), random(seed, 8.0)) * 6.2831853;
		moved += strength / w * (cos(phase) - cos(w * age + phase));
		velocity += strength * sin(w * age + phase);
	}
	vec3 at = model[0].xyz + moved;
	vec3 world_at = world_space ? at : (emitter * vec4(at, 1.0)).xyz;
	vec3 world_velocity = world_space ? velocity : turn * velocity;
	float speed = length(world_velocity);
	vec3 size = model[2].xyz * life_curve(2, u, random(seed, 2.0)).xyz;
	if (has_size_by_speed) {
		size *= life_curve(14, (speed - speed_ranges.x) / (speed_ranges.y - speed_ranges.x), random(seed, 9.0)).xyz;
	}
	vec3 spun = model[3].xyz;
	if (has_spin) {
		spun += life * life_curve(8, u, random(seed, 3.0)).xyz;
	}
	if (has_colour_over_life) {
		particle_color *= life_curve(0, u, random(seed, 10.0));
	}
	if (has_colour_by_speed) {
		particle_color *= life_curve(12, (speed - speed_ranges.z) / (speed_ranges.w - speed_ranges.z), random(seed, 11.0));
	}
	vec3 eye = inv_view[3].xyz;
	vec3 to_eye = eye - world_at;
	vec3 world;
	if (mode != 4) {
		// Unity holds a quad's size to its share of the view at the particle's distance.
		size = min(size, vec3(max_size * 2.0 * length(to_eye) / abs(projection[1][1])));
	}
	mat3 frame = align == 4 && speed > 1e-6 ? look_along(world_velocity) : align == 2 ? turn : align == 1 ? mat3(1.0) : align == 3 ? look_along(to_eye) : mat3(inv_view);
	if (mode == 4) {
		world = world_at + frame * (euler(spun) * ((vertex + pivot) * size));
		normal = frame * euler(spun) * normal;
	} else if (mode == 1 && length(world_velocity - dot(world_velocity, normalize(to_eye)) * normalize(to_eye)) > 1e-6) {
		vec3 along = normalize(world_velocity - dot(world_velocity, normalize(to_eye)) * normalize(to_eye));
		vec3 across = normalize(cross(along, normalize(to_eye)));
		float stretch = size.x * length_scale + speed * velocity_scale;
		world = world_at + across * vertex.x * size.x + along * (vertex.y - 0.5) * stretch;
		normal = normalize(to_eye);
	} else if (mode == 2) {
		float c = cos(spun.z), s = sin(spun.z);
		vec2 turned = mat2(vec2(c, s), vec2(-s, c)) * (vertex.xy * size.xy);
		world = world_at + vec3(turned.x, 0.0, -turned.y);
		normal = vec3(0.0, 1.0, 0.0);
	} else if (mode == 3) {
		float c = cos(spun.z), s = sin(spun.z);
		vec2 turned = mat2(vec2(c, s), vec2(-s, c)) * (vertex.xy * size.xy);
		vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), length(to_eye.xz) > 1e-6 ? vec3(to_eye.x, 0.0, to_eye.z) : vec3(0.0, 0.0, 1.0)));
		world = world_at + right * turned.x + vec3(0.0, turned.y, 0.0);
		normal = normalize(to_eye);
	} else {
		world = world_at + frame * (euler(align == 0 ? vec3(0.0, 0.0, spun.z) : spun) * vec3(vertex.xy * size.xy, 0.0));
		normal = frame[2];
	}
	vertex = (view * vec4(world, 1.0)).xyz;
	normal = mat3(view) * normal;
}

vec4 particle_fragment(vec4 particle_color, vec2 uv) {
	vec4 c = particle_color * tint;
	if (textured) {
		vec2 unity = vec2(uv.x, 1.0 - uv.y) * uv_transform.xy + uv_transform.zw;
		c *= texture(albedo, vec2(unity.x, 1.0 - unity.y));
	}
	c.rgb += emission;
	return c;
}
