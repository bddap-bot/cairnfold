// Bounce's volume: rgb sunlight thrown off sunlit stone, a the sky seen; layers a metre deep that follow the ground.
// bounce_grid: corner, width in metres, layers. Include after ground.gdshaderinc.
global uniform sampler3D bounce_volume : filter_linear, repeat_disable;
global uniform vec3 bounce_grid;
global uniform vec3 bounce_light;
// Lamps' bake, on the same probes.
global uniform sampler3D lamp_volume : filter_linear, repeat_disable;
global uniform vec3 lamp_light;

vec3 volume_coord(vec3 p, float ground) {
	return vec3((p.xz - bounce_grid.x) / bounce_grid.y, (p.y - ground) / bounce_grid.z);
}

// Half a metre out, so a wall reads the air before it.
const float READ_OUT = 0.5;

vec3 read_over(vec3 p, vec3 n) {
	return p + n * READ_OUT;
}

vec3 bounce_over(vec3 p, vec3 n, float ground) {
	return volume_coord(read_over(p, n), ground);
}

// A roof's upper faces read above the layer Bounce keeps dark over the room below.
vec3 read_over_cover(vec3 p, vec3 n) {
	return read_over(p, n) + vec3(0.0, 1.5 * max(n.y, 0.0), 0.0);
}

vec3 bounce_on_ground(vec2 xz) {
	return vec3((xz - bounce_grid.x) / bounce_grid.y, 0.5 / bounce_grid.z);
}

// A metre out, so a wall or roof face reads the air on its own side: probes either side of the shell are a metre apart.
vec3 lamp_over(vec3 p, vec3 n, float ground) {
	return volume_coord(p + n, ground);
}

vec3 given_back(vec3 lamp_at, vec4 bounce) {
	return bounce.rgb * bounce_light + textureLod(lamp_volume, lamp_at, 0.0).rgb * lamp_light;
}

// Per vertex, for things small or dense enough that the volumes do not vary over a triangle.
vec4 given_read(vec3 at, vec3 lamp_at) {
	vec4 bounce = textureLod(bounce_volume, at, 0.0);
	return vec4(given_back(lamp_at, bounce), bounce.a);
}

vec4 given_over(vec3 p, vec3 n, float ground) {
	return given_read(bounce_over(p, n, ground), lamp_over(p, n, ground));
}

vec4 given_at(vec3 p, vec3 n) {
	return given_over(p, n, ground_at(p.xz));
}
