shader_type spatial;
render_mode unshaded;

#include "res://src/roof_shadow.gdshaderinc"

// Drawn only in the light's shadow pass (Wall.kinds).
void vertex() {
	VERTEX += inverse(mat3(MODEL_MATRIX)) * sun_toward * ROOF_PULL;
}
