shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

// A fairy ring: red-capped, white-spotted toadstools that pop up round where the player will land.
#include "res://src/landing.gdshaderinc"

const float RADIUS = 0.42;

varying vec3 local;
varying float cap;

void vertex() {
	vec3 c = MODEL_MATRIX[3].xyz;
	float k = length(MODEL_MATRIX[0].xyz);
	float i = float(INSTANCE_ID);
	float n = float(count);
	float a = TAU * (i + 0.35 * hash(i)) / n;
	float r = RADIUS * k * (0.9 + 0.2 * hash(i + 2.0));
	float h = k * (0.17 + 0.09 * hash(i + 4.0)) * spring((clock - 0.05 * i) / 0.28);
	float yaw = TAU * hash(i + 6.0);
	float lean = 0.18 * (hash(i + 8.0) - 0.5);
	local = VERTEX;
	cap = COLOR.a;
	mat3 turn = mat3(vec3(cos(yaw), 0.0, -sin(yaw)), vec3(0.0, 1.0, 0.0), vec3(sin(yaw), 0.0, cos(yaw)));
	mat3 tip = mat3(vec3(cos(lean), sin(lean), 0.0), vec3(-sin(lean), cos(lean), 0.0), vec3(0.0, 0.0, 1.0));
	mat3 b = turn * tip * h;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(b[0], 0.0), vec4(b[1], 0.0), vec4(b[2], 0.0), vec4(c + vec3(cos(a) * r, -0.01 * k, sin(a) * r), 1.0));
}

void fragment() {
	vec3 stem = vec3(0.96, 0.92, 0.82) * (0.75 + 0.3 * local.y);
	vec3 p = local * vec3(9.0, 7.0, 9.0);
	vec3 cell = floor(p);
	vec3 centre = cell + 0.5 + 0.3 * (vec3(hash(dot(cell, vec3(1.0, 57.0, 113.0))), hash(dot(cell, vec3(7.0, 31.0, 5.0))), hash(dot(cell, vec3(3.0, 11.0, 71.0)))) - 0.5);
	float spot = step(length(p - centre), 0.3) * step(0.72, local.y);
	vec3 red = vec3(0.85, 0.07, 0.05) * (0.7 + 0.45 * smoothstep(0.6, 1.0, local.y));
	ALBEDO = mix(stem, mix(red, vec3(1.0, 0.97, 0.9), spot), smoothstep(0.4, 0.6, cap));
}
