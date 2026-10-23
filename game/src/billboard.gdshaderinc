// A quad turned to the eye about `at`, `scale` times its size: facing the eye itself, not the view's plane, which
// would foreshorten it toward the edge of a wide view.
mat4 billboard(mat4 view, mat4 inv_view, vec3 at, float scale) {
	vec3 back = normalize(inv_view[3].xyz - at);
	vec3 right = normalize(cross(inv_view[1].xyz, back));
	return view * mat4(vec4(right * scale, 0.0), vec4(cross(back, right) * scale, 0.0), vec4(back * scale, 0.0), vec4(at, 1.0));
}
