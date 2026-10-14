// A quad turned to the eye about `at`, `scale` times its size.
mat4 billboard(mat4 view, mat4 inv_view, vec3 at, float scale) {
	return view * mat4(inv_view[0] * scale, inv_view[1] * scale, inv_view[2] * scale, vec4(at, 1.0));
}
