// Light the builds give back (Bounce): alpha the sky a point sees past them, rgb sunlight thrown off sunlit
// stone, in layers a metre deep that follow the ground. bounce_grid is the corner, the width in metres and
// the layers. Include after ground.gdshaderinc.
global uniform sampler3D bounce_volume : filter_linear, repeat_disable;
global uniform vec3 bounce_grid;
global uniform vec3 bounce_light;
// Lantern light baked on the same probes (Lamps).
global uniform sampler3D lamp_volume : filter_linear, repeat_disable;
global uniform vec3 lamp_light;

// Where a surface at `p` facing `n` reads the volume: half a metre out, so a wall reads the air before it.
vec3 bounce_coord(vec3 p, vec3 n) {
	p += n * 0.5;
	return vec3((p.xz - bounce_grid.x) / bounce_grid.y, (p.y - ground_at(p.xz)) / bounce_grid.z);
}

// The same for what lies on the ground or rises from it, whose height there is known: the lowest layer.
vec3 bounce_on_ground(vec2 xz) {
	return vec3((xz - bounce_grid.x) / bounce_grid.y, 0.5 / bounce_grid.z);
}

// What a surface reading the volumes at `at` adds over its albedo: light off the builds and from lanterns.
vec3 given_back(vec3 at, vec4 bounce) {
	return bounce.rgb * bounce_light + textureLod(lamp_volume, at, 0.0).r * lamp_light;
}
