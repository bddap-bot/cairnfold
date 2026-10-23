// The shadow a held thing lays (HeldShadow): held_shadow takes a world point into the box it darkens, x and z across
// the caster, y from 0.5 at it down to -0.5 where the shadow ends; held_shade is how much albedo it takes there.
global uniform mat4 held_shadow;
global uniform float held_shade;

// With no held shadow the box is skipped: one uniform test where most frames hold no book.
vec3 held_coord(vec3 world) {
	return held_shade > 0.0 ? (held_shadow * vec4(world, 1.0)).xyz : vec3(1.0);
}

// What of a point's albedo the held shadow leaves, for `q` from held_coord: its edges soften over a few hundredths of
// the caster's width, the penumbra of a small sun at arm's length, and it fades over its last fifth.
float held_lit(vec3 q) {
	vec2 edge = 0.5 - abs(q.xz);
	float inside = smoothstep(0.0, 0.03, min(edge.x, edge.y)) * smoothstep(-0.5, -0.3, q.y) * step(q.y, 0.5);
	return 1.0 - held_shade * inside;
}
