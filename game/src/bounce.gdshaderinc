// Light the builds give back (Bounce): alpha the sky a point sees past them, rgb sunlight thrown off sunlit
// stone, in layers a metre deep that follow the ground. bounce_grid is the corner, the width in metres and
// the layers. Include after ground.gdshaderinc.
global uniform sampler3D bounce_volume : filter_linear, repeat_disable;
global uniform vec3 bounce_grid;
global uniform vec3 bounce_light;
// Lantern light baked on the same probes (Lamps).
global uniform sampler3D lamp_volume : filter_linear, repeat_disable;
global uniform vec3 lamp_light;

// Where the volume holds a point `p` standing over ground at height `ground`.
vec3 volume_coord(vec3 p, float ground) {
	return vec3((p.xz - bounce_grid.x) / bounce_grid.y, (p.y - ground) / bounce_grid.z);
}

// Where a surface at `p` facing `n` reads the volume: half a metre out, so a wall reads the air before it.
vec3 bounce_coord(vec3 p, vec3 n) {
	p += n * 0.5;
	return volume_coord(p, ground_at(p.xz));
}

// The same for what lies on the ground or rises from it, whose height there is known: the lowest layer.
vec3 bounce_on_ground(vec2 xz) {
	return vec3((xz - bounce_grid.x) / bounce_grid.y, 0.5 / bounce_grid.z);
}

// Where a surface reads lantern light: a metre out, so a face of a house's wall or roof reads the air on its own
// side, the probes either side of the shell being a metre apart.
vec3 lamp_coord(vec3 p, vec3 n) {
	return bounce_coord(p + n * 0.5, n);
}

// What a surface reading bounce at `at` and lantern light at `lamp_at` adds over its albedo.
vec3 given_back(vec3 at, vec3 lamp_at, vec4 bounce) {
	return bounce.rgb * bounce_light + textureLod(lamp_volume, lamp_at, 0.0).r * lamp_light;
}

// given_back and the sky seen, read once a vertex for things small or dense enough that the volumes do not vary
// over a triangle: what lights them where they stand without a read per fragment.
vec4 given_at(vec3 p, vec3 n) {
	vec3 at = bounce_coord(p, n);
	vec4 bounce = textureLod(bounce_volume, at, 0.0);
	return vec4(given_back(at, lamp_coord(p, n), bounce), bounce.a);
}

// given_at for a thing whose ground height is known where it stands, as a leaf knows its wall's foot: no ground
// read, which a vertex shader pays for twice in given_at.
vec4 given_over(vec3 p, vec3 n, float ground) {
	vec3 at = volume_coord(p + n * 0.5, ground);
	vec4 bounce = textureLod(bounce_volume, at, 0.0);
	return vec4(given_back(at, volume_coord(p + n, ground), bounce), bounce.a);
}
