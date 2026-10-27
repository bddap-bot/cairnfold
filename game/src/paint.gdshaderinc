// Paint as every surface it lies on draws it: the canvas in the garden (canvas.gdshader), the flat copy a photo saves of
// it (canvas_flat.gdshader) and the oil palette's board (board.gdshader). Pigment is an optical density per channel
// over the canvas's sheet, so a colour mixed on the palette shows there as it will on the canvas; oil stands off its
// surface as high as it is thick, and the light catches its ridges.

uniform float impasto;
uniform float grain;

const vec3 SHEET = vec3(0.93, 0.91, 0.86);

float canvas_damp(vec4 w) {
	return smoothstep(0.0, 0.25, w.a);
}

vec3 canvas_colour(vec4 w, vec4 d, vec2 tooth) {
	vec3 sheet = SHEET * (0.97 + 0.03 * tooth.x + 0.02 * tooth.y);
	return sheet * exp(-(d.rgb + w.rgb)) * (1.0 - 0.12 * canvas_damp(w));
}

// Metres above the board.
float canvas_height(vec4 d, vec2 tooth) {
	return d.a * impasto + tooth.x * grain;
}

float paint_filtered_roughness(float roughness, vec3 mean_normal) {
	// A mip's shortened mean measures the subpixel slopes that would otherwise sparkle.
	float variance = min(2.0 * max(1.0 - length(mean_normal), 0.0), 0.5);
	return pow(min(pow(roughness, 4.0) + variance, 1.0), 0.25);
}

// How glossy a surface is under `oil` (0 bare to 1 a full body of oil paint) and `damp` (water standing on it).
float paint_roughness(float oil, float damp) {
	return mix(mix(0.92, 0.45, oil), 0.18, damp);
}

float paint_specular(float oil, float damp) {
	return mix(0.25, 0.6, max(oil, damp));
}
