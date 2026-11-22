shader_type spatial;
// Drawn whole from both sides: a back face lies behind its own front, so the depth test drops it on a closed surface.
render_mode depth_draw_never, cull_disabled;

#include "res://src/sculpture.gdshaderinc"
#include "res://src/given.gdshaderinc"

// Drawn over a Godot material (PhotoStyle.carve), only for a camera that carves; for every other its vertices are
// dropped before they rasterise.
void vertex() {
	GIVE_HERE;
	if (!SCULPTED) {
		VERTEX = vec3(intBitsToFloat(0x7fc00000));
	}
}

void fragment() {
	ALBEDO = SCULPTURE;
	TAKE_GIVEN;
}
