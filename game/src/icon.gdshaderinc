// A wheel icon's one look (Hand.unlit): a colour shaded by a light fixed to the eye, then the view's exposure and
// saturation (Look) undone, so no hour, lamp or fog of the garden reaches it. A shader including it renders unshaded.
// The saturation is applied after the tone curve and undone before it, where the square root of its inverse matched
// day and night pixels best.
global uniform vec2 view_grade;

vec3 icon_look(vec3 c, vec3 normal) {
	c *= 0.75 + 0.25 * dot(normal, normalize(vec3(-0.3, 0.8, 0.5)));
	float grey = (c.r + c.g + c.b) / 3.0;
	return max(mix(vec3(grey), c, inversesqrt(view_grade.y)), vec3(0.0)) / view_grade.x;
}
