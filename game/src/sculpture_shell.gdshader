shader_type spatial;
render_mode depth_draw_never;

#include "res://src/sculpture.gdshaderinc"

// Drawn over a Godot material (PhotoStyle.carve), only for a camera that carves; for every other its vertices are
// dropped before they rasterise.
void vertex() {
	if (!SCULPTED) {
		VERTEX = vec3(intBitsToFloat(0x7fc00000));
	}
}

void fragment() {
	ALBEDO = SCULPTURE;
}
