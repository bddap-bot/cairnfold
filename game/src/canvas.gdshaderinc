// What a canvas looks like, shared by the canvas in the garden (canvas.gdshader) and the flat copy a photo saves of it
// (canvas_flat.gdshader): paper under the pigment laid and the pigment still in the water, darkened where wet, and
// standing off the board as high as its oil and the paper's grain lift it. `tooth` is the paper's grain.

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
