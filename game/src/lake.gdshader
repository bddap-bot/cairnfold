shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 sun : source_color = vec3(1.0);
uniform float energy = 1.0;
uniform vec3 sky : source_color = vec3(0.3, 0.5, 0.85);
uniform vec3 horizon : source_color = vec3(0.86, 0.88, 0.84);
uniform float ambient = 0.7;
uniform vec3 haze : source_color = vec3(0.86, 0.88, 0.84);
uniform vec3 deep : source_color = vec3(0.08, 0.27, 0.34);
uniform vec3 stone : source_color = vec3(0.56, 0.52, 0.48);
uniform vec3 slope : source_color = vec3(0.26, 0.38, 0.20);
// Mountains.ridge_image: each range's ridge over the water round the circle.
uniform sampler2D ridges : filter_linear, repeat_enable;
uniform float level = 3.5;
uniform vec2 radii = vec2(560.0, 1300.0);
uniform float top = 520.0;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// How far along the level ray from `p` toward `d` the circle of `radius` lies, and the ridge it meets there.
vec2 ridge_ahead(vec2 p, vec2 d, float radius, vec2 range) {
	float b = dot(p, d);
	float t = -b + sqrt(max(b * b - dot(p, p) + radius * radius, 0.0));
	vec2 q = p + d * t;
	float h = dot(texture(ridges, vec2(atan(q.y, q.x) / TAU + 0.5 / float(textureSize(ridges, 0).x), 0.5)).rg, range) * top;
	return vec2(t, h);
}

void fragment() {
	vec3 to_eye = CAMERA_POSITION_WORLD - wp;
	float dist = length(to_eye);
	vec3 v = to_eye / dist;
	vec2 s = wp.xz;
	vec2 swell = vec2(sin(s.x * 0.23 + s.y * 0.07 + TIME * 0.8) + 0.6 * sin(s.y * 0.41 - TIME * 0.6),
		cos(s.y * 0.19 - s.x * 0.05 + TIME * 0.7) + 0.6 * cos(s.x * 0.37 + TIME * 0.5)) * 0.02;
	vec3 n = normalize(vec3(swell.x, 1.0, swell.y));
	vec3 r = reflect(-v, n);
	float fresnel = 0.02 + 0.98 * pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 5.0);

	// The ranges seen in the water: the reflected ray meets a range where it climbs less than that ridge stands.
	vec2 d = normalize(r.xz + vec2(1e-5));
	float climb = r.y / max(length(r.xz), 1e-4);
	vec2 near = ridge_ahead(s, d, radii.x, vec2(1.0, 0.0));
	vec2 far = ridge_ahead(s, d, radii.y, vec2(0.0, 1.0));
	vec3 light = sun * energy * 0.45 + mix(horizon, sky, 0.5) * ambient * 0.5;
	vec3 seen = mix(horizon, sky, pow(clamp(r.y, 0.0, 1.0), 0.55));
	seen = climb * far.x < far.y ? mix(mix(slope, stone, climb * far.x / far.y) * light, haze, 0.55) : seen;
	seen = climb * near.x < near.y ? mix(mix(slope, stone, climb * near.x / near.y) * light, haze, 0.35) : seen;

	vec3 body = deep * (sun * energy * max(sun_dir.y, 0.0) * 0.5 + mix(horizon, sky, 0.6) * ambient * 0.6);
	vec3 col = mix(body, seen * 0.85, fresnel);
	col += sun * energy * pow(max(dot(r, sun_dir), 0.0), 400.0) * 3.0;
	ALBEDO = mix(col, haze, 0.2 * smoothstep(0.0, radii.x - 300.0, dist));
}
