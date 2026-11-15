// Sun and moon reach a room only through its openings (Interior), so no shadow-map gap, nor a ladder step drawing no
// sun shadow, lets light in elsewhere. Include after bounce.gdshaderinc. ROOM_HERE goes after vertex()'s last write to
// world_pos and world_nrm, TAKE_ROOM(sky) after fragment()'s EMISSION; each is several statements, so brace it.
// room_field filtered: x metres inside the walls' centre line, y floor, z ceiling; room_nearest the same unfiltered,
// alpha the room_data row, its fraction > 0 across an opening.
global uniform sampler2D room_field : filter_linear, repeat_disable;
global uniform sampler2D room_nearest : filter_nearest, repeat_disable;
global uniform sampler2D room_data : filter_nearest, repeat_disable;
global uniform vec3 sky_zenith;
global uniform vec3 sky_horizon;
global uniform float sky_ambient;

// Metres along the normal for the inside test; a stone's lumps stand well within the half-thickness either side.
const float ROOM_NUDGE = 0.05;
// Metres an opening's edge fades over, so a patch of sun on the floor does not alias.
const float ROOM_EDGE = 0.02;
// Metres inside the centre line a room's face reads from: Bounce keeps a room's probes up to half a metre past that
// line and a read filters probes a metre apart, so a read nearer the walls than this takes in the open sky of a column
// outside.
const float ROOM_READ = 1.0;
// Texels per opening in a room_data row, after the row's count texel (Interior.OPENING).
const int OPENING = 4;
// The room_data row no room uses (Interior.NO_ROOM).
const int NO_ROOM = 0;
// Layers lie a metre apart and a read filters a column toward the wall, where a pitched roof comes a metre lower, so a
// read this far under the ceiling stays in the room's layers.
const float ROOM_UNDER = 1.5;
// How far past the centre line a stone's read may start and stay the room's: its own half of the wall and part of the
// half metre it reads out, short of the outer face's read.
const float ROOM_STONE_REACH = 0.7;
// The furthest past the centre line a stone of the room's own wall has its middle.
const float ROOM_MIDDLE = 0.35;
// Torching this far past the centre line still lies over the wall below, inside its outer face.
const float ROOM_TORCHING_REACH = 0.3;

// room_in is 1 where the vertex lies in its room, so only a triangle across the walls' centre line (0 < room_in < 1)
// asks again per fragment.
varying flat int room_row;
varying float room_in;

#define ROOM_HERE room_row = room_row_at(world_pos); room_in = room_in_at(room_row, world_pos, world_nrm)
#define TAKE_ROOM(sky) float sun_share = interior_light(world_pos, world_nrm, room_row, room_in); vec2 room_ao = interior_ao(sun_share, sky); AO = room_ao.x; AO_LIGHT_AFFECT = room_ao.y; EMISSION += ALBEDO * interior_ambient(sun_share, sky, world_nrm)

int room_row_at(vec3 p) {
	ivec2 size = textureSize(room_nearest, 0);
	// A scene with no Look installs no rooms, and an unset global reads as a 1x1 default texture.
	if (size.x < 2) {
		return NO_ROOM;
	}
	ivec2 cell = ivec2(floor((p.xz - bounce_grid.x) / bounce_grid.y * vec2(size)));
	if (any(lessThan(cell, ivec2(0))) || any(greaterThanEqual(cell, size))) {
		return NO_ROOM;
	}
	return int(texelFetch(room_nearest, cell, 0).a + 0.5);
}

vec4 room_at(vec2 xz) {
	return textureLod(room_field, (xz - bounce_grid.x) / bounce_grid.y, 0.0);
}

bool room_holds(vec3 p, vec3 n) {
	vec3 q = p + n * ROOM_NUDGE;
	vec4 room = room_at(q.xz);
	return room.x > 0.0 && q.y > room.y && q.y < room.z;
}

bool within_walls(vec2 xz) {
	return room_at(xz).x > 0.0;
}

bool room_across_opening(vec2 xz) {
	ivec2 size = textureSize(room_nearest, 0);
	ivec2 cell = ivec2(floor((xz - bounce_grid.x) / bounce_grid.y * vec2(size)));
	if (any(lessThan(cell, ivec2(0))) || any(greaterThanEqual(cell, size))) {
		return false;
	}
	return fract(texelFetch(room_nearest, cell, 0).a) > 0.0;
}

vec2 room_slope(vec2 xz, float texel) {
	return vec2(
		room_at(xz + vec2(texel, 0.0)).x - room_at(xz - vec2(texel, 0.0)).x,
		room_at(xz + vec2(0.0, texel)).x - room_at(xz - vec2(0.0, texel)).x) / (2.0 * texel);
}

// Asked of a piece's middle, as a stone's rounded corners lean past its face and a corner's nearest wall changes along it.
bool room_looks_out(vec2 xz, vec2 n) {
	float at = room_at(xz).x;
	return at < -ROOM_MIDDLE || room_at(xz + n * ROOM_MIDDLE).x < at - ROOM_MIDDLE * 0.3;
}

// Moves a read into the room so a filtered read takes no probe of the open air round the shell. A stone passes its
// lowest point at its middle as `anchor`, so one rising through the ceiling stays whole where its corners would
// disagree. The step is over the slope's square as the slope shortens along a corner's bisector.
vec3 room_read(int row, vec3 q, vec3 n, vec3 anchor, float reach) {
	if (row == NO_ROOM) {
		return q;
	}
	vec4 room = room_at(q.xz);
	if (room.x <= -reach || room.x >= ROOM_READ || anchor.y >= room_at(anchor.xz).z) {
		return q;
	}
	float texel = bounce_grid.y / float(textureSize(room_field, 0).x);
	vec2 slope = room_slope(q.xz, texel);
	float steep = dot(slope, slope);
	// Where two joined rooms' fields meet the slope flattens, and both sides of the old wall are dark already.
	if (steep < 0.25 || (room.x <= 0.0 && (room_looks_out(anchor.xz, n.xz) || room_across_opening(q.xz)))) {
		return q;
	}
	q.xz += slope * (ROOM_READ - room.x) / steep;
	// A step from outside the centre line falls short where the field bends, at a corner or a stack's set-in walls.
	float landed = room_at(q.xz).x;
	vec2 again = room_slope(q.xz, texel);
	if (landed < ROOM_READ && dot(again, again) >= 0.25) {
		q.xz += again * (ROOM_READ - landed) / dot(again, again);
	}
	// A face of the outer half reads at its own height, which Bounce keeps dark a layer over the roof; held under the
	// ceiling as well, a reveal's would read the room's darker layers.
	if (room.x > 0.0) {
		vec4 over = room_at(q.xz);
		q.y = max(min(q.y, over.z - ROOM_UNDER), over.y + ROOM_UNDER);
	}
	return q;
}

float room_in_at(int row, vec3 p, vec3 n) {
	return row != NO_ROOM && room_holds(p, n) ? 1.0 : 0.0;
}

// Signed distance to the opening's outline, negative inside; `at` in metres across from its middle and up from its
// sill; `round` rounds the top corners, -`round` all four.
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

// 1 outside every room; inside, the share the openings toward the light leave open (as Interior.crossing).
float interior_light(vec3 p, vec3 n, int vertex_row, float vertex_in) {
	int row = vertex_row;
	if (vertex_in < 0.001) {
		return 1.0;
	}
	if (vertex_in < 0.999) {
		row = room_row_at(p);
		if (row == NO_ROOM || !room_holds(p, n)) {
			return 1.0;
		}
	}
	vec4 counts = texelFetch(room_data, ivec2(0, row), 0);
	int first = 1;
	int openings = int(counts.x);
	float lit = 0.0;
	for (int i = 0; i < openings; i++) {
		int texel = first + OPENING * i;
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

// Godot scales ambient by AO and the sun by mix(1, AO, AO_LIGHT_AFFECT), so both are exact while the sun's share is at
// least the sky's; below, AO is the sun's share and interior_ambient gives the rest of the sky's light back.
vec2 interior_ao(float lit, float sky) {
	return lit >= sky ? vec2(sky, (1.0 - lit) / max(1.0 - sky, 1e-3)) : vec2(lit, 1.0);
}

// `n` world space. A downward face sees the room's lit floor and walls, not the darker ground outside.
vec3 interior_ambient(float lit, float sky, vec3 n) {
	vec3 seen = mix(sky_horizon, sky_zenith, max(n.y, 0.0));
	return lit >= sky ? vec3(0.0) : (sky - lit) * sky_ambient * seen;
}
