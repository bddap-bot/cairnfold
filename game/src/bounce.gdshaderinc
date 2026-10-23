// Light the builds give back (Bounce): alpha the sky a point sees past them, rgb sunlight thrown off sunlit
// stone, in layers a metre deep that follow the ground. bounce_grid is the corner, the width in metres and
// the layers. Include after ground.gdshaderinc.
global uniform sampler3D bounce_volume : filter_linear, repeat_disable;
global uniform vec3 bounce_grid;
global uniform vec3 bounce_light;
// Lantern light baked on the same probes (Lamps), in each lantern's colour.
global uniform sampler3D lamp_volume : filter_linear, repeat_disable;
global uniform vec3 lamp_light;

// Where the volume holds a point `p` standing over ground at height `ground`.
vec3 volume_coord(vec3 p, float ground) {
	return vec3((p.xz - bounce_grid.x) / bounce_grid.y, (p.y - ground) / bounce_grid.z);
}

// Where a surface at `p` facing `n` over ground at height `ground` reads the volume: half a metre out, so a wall
// reads the air before it.
vec3 bounce_over(vec3 p, vec3 n, float ground) {
	return volume_coord(p + n * 0.5, ground);
}

// The same for what lies on the ground or rises from it, whose height there is known: the lowest layer.
vec3 bounce_on_ground(vec2 xz) {
	return vec3((xz - bounce_grid.x) / bounce_grid.y, 0.5 / bounce_grid.z);
}

// Where a surface reads lantern light: a metre out, so a face of a house's wall or roof reads the air on its own
// side, the probes either side of the shell being a metre apart.
vec3 lamp_over(vec3 p, vec3 n, float ground) {
	return volume_coord(p + n, ground);
}

// What a surface reading bounce at `at` and lantern light at `lamp_at` adds over its albedo.
vec3 given_back(vec3 at, vec3 lamp_at, vec4 bounce) {
	return bounce.rgb * bounce_light + textureLod(lamp_volume, lamp_at, 0.0).rgb * lamp_light;
}

// given_back and the sky seen, read once a vertex for things small or dense enough that the volumes do not vary
// over a triangle: what lights them where they stand without a read per fragment. A thing whose ground height is
// known where it stands, as a leaf knows its wall's foot, passes it and reads no ground.
vec4 given_over(vec3 p, vec3 n, float ground) {
	vec3 at = bounce_over(p, n, ground);
	vec4 bounce = textureLod(bounce_volume, at, 0.0);
	return vec4(given_back(at, lamp_over(p, n, ground), bounce), bounce.a);
}

vec4 given_at(vec3 p, vec3 n) {
	return given_over(p, n, ground_at(p.xz));
}
