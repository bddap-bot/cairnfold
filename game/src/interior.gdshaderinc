// Sun and moon inside a house or tower come in only through its openings (Interior): a shell shader lights a point
// in a room only where the way to the light leaves through a door, window, arch or dormer window, so no gap in the
// shadow map, and no ladder step drawing no sun shadows, lets light in anywhere else. Include after
// bounce.gdshaderinc. ROOM_HERE follows vertex()'s last write to world_pos and world_nrm; TAKE_ROOM(sky) follows
// fragment()'s EMISSION, `sky` the share of the sky the surface sees (Bounce). Each is several statements, so needs
// braces under an if.
// room_field twice over: filtered for how far inside a room a point lies and its floor and ceiling, nearest for the
// row its alpha names.
global uniform sampler2D room_field : filter_linear, repeat_disable;
global uniform sampler2D room_nearest : filter_nearest, repeat_disable;
global uniform sampler2D room_data : filter_nearest, repeat_disable;
global uniform sampler2D room_top : filter_linear, repeat_disable;
global uniform vec3 sky_zenith;
global uniform vec3 sky_horizon;
global uniform float sky_ambient;

// How far along its normal a surface is taken as standing when asking which side of the walls it is on. The walls'
// centre line divides inside from out, a stone's lumps standing well within the half-thickness either side.
const float ROOM_NUDGE = 0.05;
// How wide in metres an opening's edge fades from lit to dark, so a patch of sun on the floor does not alias.
const float ROOM_EDGE = 0.02;
// How far inside its walls' centre line a face of a room reads the bounce volume from. Bounce keeps a room's probes up
// to half a metre past that line and a read filters in probes a metre apart, so a read nearer the walls than this takes
// in the open sky of a column outside, wherever the walls run across the grid.
const float ROOM_READ = 1.0;

// The room_data row over a vertex, 0 for none, and whether it lies in that room: a triangle whose corners all do is
// in it everywhere, one whose corners all lie out of every room is out everywhere, and only one across the walls'
// centre line asks again per fragment.
varying flat int room_row;
varying float room_in;

#define ROOM_HERE room_row = room_row_at(world_pos); room_in = room_in_at(room_row, world_pos, world_nrm)
#define TAKE_ROOM(sky) float sun_share = interior_light(world_pos, world_nrm, room_row, room_in); vec2 room_ao = interior_ao(sun_share, sky); AO = room_ao.x; AO_LIGHT_AFFECT = room_ao.y; EMISSION += ALBEDO * interior_ambient(sun_share, sky, world_nrm)

int room_row_at(vec3 p) {
	ivec2 size = textureSize(room_nearest, 0);
	// A scene with no Look installs no rooms, and an unset global reads as a 1x1 default texture.
	if (size.x < 2) {
		return 0;
	}
	ivec2 cell = ivec2(floor((p.xz - bounce_grid.x) / bounce_grid.y * vec2(size)));
	if (any(lessThan(cell, ivec2(0))) || any(greaterThanEqual(cell, size))) {
		return 0;
	}
	return int(texelFetch(room_nearest, cell, 0).a + 0.5);
}

vec4 room_at(vec2 xz) {
	return textureLod(room_field, (xz - bounce_grid.x) / bounce_grid.y, 0.0);
}

// Whether `p` facing `n` lies inside a room: within its walls' centre line, over its floor and under its roof.
bool room_holds(vec3 p, vec3 n) {
	vec3 q = p + n * ROOM_NUDGE;
	vec4 room = room_at(q.xz);
	return room.x > 0.0 && q.y > room.y && q.y < room.z;
}

// Whether `xz` lies within a room's walls' centre line, at any height: in its roof space too.
bool within_walls(vec2 xz) {
	return room_at(xz).x > 0.0;
}

// Where a shell's face facing `n` over room_data row `row` reads the bounce volume instead of `q`: under the rooms
// over it, ROOM_READ from the nearest wall's centre line. A face looking at the nearest wall is the outside of a storey
// set in from the walls below it. The step along the field's slope is over the slope's square because the slope
// shortens along a corner's bisector, where the nearest wall changes.
vec3 room_read(int row, vec3 q, vec3 n) {
	if (row == 0) {
		return q;
	}
	float inside = room_at(q.xz).x;
	if (inside <= 0.0 || inside >= ROOM_READ || q.y >= textureLod(room_top, (q.xz - bounce_grid.x) / bounce_grid.y, 0.0).r) {
		return q;
	}
	float texel = bounce_grid.y / float(textureSize(room_field, 0).x);
	vec2 slope = vec2(
		room_at(q.xz + vec2(texel, 0.0)).x - room_at(q.xz - vec2(texel, 0.0)).x,
		room_at(q.xz + vec2(0.0, texel)).x - room_at(q.xz - vec2(0.0, texel)).x) / (2.0 * texel);
	float steep = dot(slope, slope);
	// Where two joined rooms' fields meet the slope flattens, and both sides of the old wall are dark already.
	if (steep < 0.25 || dot(n.xz, slope) < -0.5) {
		return q;
	}
	q.xz += slope * (ROOM_READ - inside) / steep;
	return q;
}

float room_in_at(int row, vec3 p, vec3 n) {
	return row > 0 && room_holds(p, n) ? 1.0 : 0.0;
}

// Signed distance from the opening's outline to `at`, metres across from its middle and up from its sill: `half` wide
// either way, `tall` high, its top corners rounded by `round` (all four by -`round`).
float opening_edge(vec2 at, float half_width, float tall, float round) {
	float top = abs(round);
	float bottom = round < 0.0 ? top : 0.0;
	float x = abs(at.x);
	float edge = max(x - half_width, max(-at.y, at.y - tall));
	vec2 upper = vec2(x - (half_width - top), at.y - (tall - top));
	if (upper.x > 0.0 && upper.y > 0.0) {
		edge = length(upper) - top;
	}
	vec2 lower = vec2(x - (half_width - bottom), bottom - at.y);
	if (lower.x > 0.0 && lower.y > 0.0) {
		edge = length(lower) - bottom;
	}
	return edge;
}

// How much of the sun or moon reaches `p` facing `n`: all of it outside every room, and inside one as much as its way
// out through the openings facing the light leaves open (Interior.crossing).
float interior_light(vec3 p, vec3 n, int vertex_row, float vertex_in) {
	int row = vertex_row;
	if (vertex_in < 0.001) {
		return 1.0;
	}
	if (vertex_in < 0.999) {
		row = room_row_at(p);
		if (row == 0 || !room_holds(p, n)) {
			return 1.0;
		}
	}
	vec4 counts = texelFetch(room_data, ivec2(0, row), 0);
	int first = 1;
	int openings = int(counts.x);
	float lit = 0.0;
	for (int i = 0; i < openings; i++) {
		int texel = first + 4 * i;
		vec4 plane = texelFetch(room_data, ivec2(texel + 2, row), 0);
		if (p.x * plane.x + p.z * plane.y > plane.z) {
			continue;
		}
		vec4 across = texelFetch(room_data, ivec2(texel, row), 0);
		vec4 up = texelFetch(room_data, ivec2(texel + 1, row), 0);
		vec4 size = texelFetch(room_data, ivec2(texel + 3, row), 0);
		vec2 at = vec2(dot(p, across.xyz) + across.w, dot(p, up.xyz) + up.w);
		lit = max(lit, clamp(0.5 - opening_edge(at, plane.w, size.x, size.y) / ROOM_EDGE, 0.0, 1.0));
	}
	return lit;
}

// AO and AO_LIGHT_AFFECT for a surface `lit` by that share of the sun that sees `sky` of the sky (Bounce): Godot scales
// ambient light by AO and the sun by mix(1, AO, AO_LIGHT_AFFECT), so both come out exact while the sun reaches at least
// as far as the sky does, as everywhere outside a room. Where less does, AO is the sun's share and interior_ambient
// gives the rest of the sky's light back.
vec2 interior_ao(float lit, float sky) {
	return lit >= sky ? vec2(sky, (1.0 - lit) / max(1.0 - sky, 1e-3)) : vec2(lit, 1.0);
}

// The sky's light AO took from a surface facing world `n` over interior_ao's sun share, as an emission over its albedo:
// the sky's own colours at the ambient strength Look gives the environment. A downward face sees the room's lit floor
// and walls, not the darker ground outside.
vec3 interior_ambient(float lit, float sky, vec3 n) {
	vec3 seen = mix(sky_horizon, sky_zenith, max(n.y, 0.0));
	return lit >= sky ? vec3(0.0) : (sky - lit) * sky_ambient * seen;
}
