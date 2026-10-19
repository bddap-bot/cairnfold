shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap;

// A leaf of the picture book, hinged at the spine (x 0) and `width` wide: turned `angle` (0 on the right, PI on the
// left), its free edge lagging as paper does by `bend`. Each face is its paint, baked once (`*_paint`, `*_grain`:
// book_paint.gdshader), and in its window a live picture (`*_picture`, a LessonScene) inked over a painted backdrop.
// `wash_*` is the picture's sky, `horizon_*` where its horizon lies, `fade` its loop's fade.

#include "res://src/ground.gdshaderinc"
#include "res://src/bounce.gdshaderinc"
#include "res://src/book.gdshaderinc"

uniform float width = 0.15;
uniform float angle = 0.0;
uniform float bend = 0.0;
// How high a resting leaf bows up out of the gutter, as a bound page does.
uniform float gutter_bow = 0.0;
uniform sampler2D front_picture : source_color, filter_linear, repeat_disable;
uniform sampler2D back_picture : source_color, filter_linear, repeat_disable;
uniform sampler2D front_paint : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D back_paint : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D front_grain : filter_linear_mipmap, repeat_disable;
uniform sampler2D back_grain : filter_linear_mipmap, repeat_disable;
uniform vec3 front_wash : source_color = vec3(0.8, 0.86, 0.86);
uniform vec3 back_wash : source_color = vec3(0.8, 0.86, 0.86);
uniform float front_horizon = 0.5;
uniform float back_horizon = 0.5;
uniform float front_fade = 0.0;
uniform float back_fade = 0.0;
uniform float front_seed = 0.0;
uniform float back_seed = 1.0;

varying vec4 given;

void vertex() {
	float x = VERTEX.x;
	float k = bend * sin(angle) / width;
	float a = angle - k * x;
	vec2 at = abs(k) < 1e-4 ? vec2(cos(angle), sin(angle)) * x : vec2(sin(angle) - sin(a), cos(a) - cos(angle)) / k;
	float rise = gutter_bow * sin(min(x / (width * 0.3), 1.0) * PI * 0.5) * (1.0 - 0.35 * smoothstep(0.3, 1.0, x / width));
	float slope = gutter_bow * cos(min(x / (width * 0.3), 1.0) * PI * 0.5) * PI * 0.5 / (width * 0.3) * step(x, width * 0.3);
	vec2 up_ = vec2(-sin(angle), cos(angle)) * (angle > PI * 0.5 ? -1.0 : 1.0);
	VERTEX = vec3(at.x + up_.x * rise, at.y + up_.y * rise + VERTEX.y, VERTEX.z);
	NORMAL = normalize(vec3(-sin(a), cos(a), 0.0) - vec3(cos(angle), sin(angle), 0.0) * slope);
	given = given_at((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, normalize(mat3(MODEL_MATRIX) * NORMAL));
}

// The painted world behind a page's picture: a watercolour sky of the page's `wash` over the horizon at `horizon`
// (0 the picture's top, 1 its foot), soft clouds, two bands of far hills and a brushed meadow running to the
// picture's foot, which a camera looking down sees all of.
vec3 backdrop(vec2 uv, vec3 wash, float horizon, float seed, float grain) {
	float h = uv.y - horizon;
	float far = horizon - 0.07 - 0.05 * noise(vec2(uv.x * 2.5 + seed, 0.0)) + 0.025 * sin(uv.x * 5.0 + seed);
	vec3 c;
	if (uv.y < far + 0.01) {
		vec3 glow = vec3(1.0, 0.84, 0.56);
		c = mix(wash * vec3(0.78, 0.88, 1.0), mix(wash, glow, 0.75), smoothstep(-0.8, 0.0, h));
		float billow = noise(uv * vec2(3.2, 7.0) + vec2(seed * 2.3, 0.0));
		float cloud = smoothstep(0.52, 0.72, billow) * smoothstep(0.0, -0.18, h);
		c = mix(c, vec3(1.0, 0.97, 0.9) * mix(1.0, 0.93, smoothstep(0.66, 0.72, billow)), cloud * 0.75);
	} else {
		vec3 meadow = vec3(0.7, 0.8, 0.36);
		float patch_ = noise(uv * 6.0 + seed);
		c = mix(meadow * 0.9, meadow * 1.12 + vec3(0.04, 0.03, 0.0), noise(vec2(uv.x * 9.0, uv.y * 55.0) + seed));
		c = mix(c, vec3(0.9, 0.8, 0.46), smoothstep(0.5, 0.8, patch_) * 0.6);
		c = mix(c, srgb_to_linear(PAPER), smoothstep(0.3, 0.12, patch_) * 0.5);
		c *= mix(0.82, 1.0, smoothstep(1.0, horizon + 0.1, uv.y));
		float near = horizon - 0.02 - 0.06 * noise(vec2(uv.x * 3.7 + seed * 1.3, 4.0));
		vec3 hills_far = vec3(0.66, 0.74, 0.74);
		vec3 hills_near = vec3(0.56, 0.7, 0.36);
		vec3 hills = mix(hills_far * (0.92 + 0.12 * grain), hills_far * 0.8, smoothstep(0.008, 0.0, abs(uv.y - far)) * 0.4);
		hills = mix(hills, hills_near * (0.92 + 0.14 * grain), smoothstep(near, near + 0.006, uv.y));
		hills = mix(hills, hills_near * 0.78, smoothstep(0.008, 0.0, abs(uv.y - near)) * 0.45);
		c = mix(hills, c, smoothstep(horizon + 0.02, horizon + 0.06, uv.y));
		if (uv.y < far + 0.006) {
			c = mix(wash, c, smoothstep(far, far + 0.006, uv.y));
		}
	}
	return max(mix(vec3(dot(c, vec3(0.3, 0.55, 0.15))), c, 1.8), vec3(0.0));
}

// The face: its baked paint, and in its window the live picture inked over the backdrop, laid in by the baked weight.
vec3 page(vec2 p, sampler2D paint, sampler2D grain, sampler2D picture, vec3 wash, float horizon, float fade, float seed) {
	vec4 base = texture(paint, p);
	if (base.a <= 0.0) {
		return base.rgb;
	}
	vec2 uv = window_uv(p);
	vec4 shot = texture(picture, clamp(uv, vec2(0.0), vec2(1.0)));
	float outline = clamp(fwidth(shot.a) * 1.8, 0.0, 1.0);
	vec3 ink_shot = max(mix(vec3(dot(shot.rgb, vec3(0.3, 0.55, 0.15))), shot.rgb, 1.7), vec3(0.0)) * 0.9;
	float shown = 1.0 - fade;
	float cover = shot.a * shown;
	vec3 pic = cover > 0.99 ? ink_shot : mix(backdrop(uv, wash, horizon, seed, texture(grain, p).r), ink_shot, cover);
	pic = mix(pic, srgb_to_linear(INK) * 0.8, outline * 0.8 * shown);
	return base.rgb + base.a * pic;
}

void fragment() {
	bool up = FRONT_FACING;
	vec2 p = up ? UV : vec2(1.0 - UV.x, UV.y);
	vec3 c = up ? page(p, front_paint, front_grain, front_picture, front_wash, front_horizon, front_fade, front_seed)
		: page(p, back_paint, back_grain, back_picture, back_wash, back_horizon, back_fade, back_seed);
	ALBEDO = c;
	ROUGHNESS = 0.92;
	SPECULAR = 0.15;
	AO = given.a;
	EMISSION = ALBEDO * given.rgb + ALBEDO * 0.08;
}
