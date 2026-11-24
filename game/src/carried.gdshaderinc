// A build in hand is drawn carried (Wall.carry) but keeps the light of where it was laid: what it reads of the garden's
// light (rooms, bounce, lamps, ground) it reads there. The carry as its offset and the cosine and sine of its turn about up.
instance uniform vec3 carried_by = vec3(0.0);
instance uniform vec2 carried_turn = vec2(1.0, 0.0);

vec3 laid_dir(vec3 d) {
	return vec3(carried_turn.x * d.x - carried_turn.y * d.z, d.y, carried_turn.y * d.x + carried_turn.x * d.z);
}

vec3 laid_point(vec3 p) {
	return laid_dir(p - carried_by);
}
