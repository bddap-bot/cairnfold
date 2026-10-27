shader_type spatial;
render_mode unshaded;

#include "res://src/roof_shadow.gdshaderinc"

// The shadow a roof's covering casts (Wall.kinds), never drawn but in the light's shadow pass.
void vertex() {
	VERTEX += inverse(mat3(MODEL_MATRIX)) * sun_toward * ROOF_PULL;
}
