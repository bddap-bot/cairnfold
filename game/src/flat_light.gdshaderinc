#include "res://src/ground.gdshaderinc"
#include "res://src/bounce.gdshaderinc"
#include "res://src/daylight.gdshaderinc"

// The mirror's view, the one camera that sees just Quality.MIRROR_MASK, lit by the mirror's own light and ambient
// (MirrorTool).
uniform uint mirror_mask;
global uniform vec3 mirror_toward;
global uniform vec3 mirror_light;
global uniform vec3 mirror_ambient;

vec3 key_toward(bool mirrored) {
	vec3 toward = mirrored ? mirror_toward : sun_toward;
	return length(toward) > 1e-4 ? normalize(toward) : vec3(0.0, 1.0, 0.0);
}

// A flat surface, as Poiyomi's Flat lighting and Toon Lit light it, takes the main light whole whichever way it faces,
// scaled by `level`, plus the ambient, capped at `cap`: its texture's painted shading is the only shading. The ambient
// and the light `given` back are returned capped, for the emission, the engine's ambient left out; the main light
// stays the engine's, so the sun's shadow still falls on it, through `normal` turned toward the light and away by as
// much as keeps the whole under the cap. The cap clips the ambient per channel and the main light by its brightest
// channel. `key` is the main light and `spare` the room the cap leaves past what the surface takes of it.
vec3 lit_flat(vec4 given, float cap, float level, bool mirrored, mat4 model, inout vec3 normal, out vec3 key, out float spare) {
	vec3 ambient = (mirrored ? mirror_ambient : mix(sky_horizon, sky_zenith, 0.5) * sky_ambient) * given.a;
	key = mirrored ? mirror_light : sun_light;
	vec3 toward = key_toward(mirrored);
	vec3 light = min(ambient + given.rgb, vec3(cap));
	float room = cap - max(light.r, max(light.g, light.b));
	float brightest = max(max(key.r, max(key.g, key.b)), 1e-4);
	float facing = clamp(min(level, room / brightest), 0.0, 1.0);
	spare = max(room - facing * brightest, 0.0);
	vec3 across = vec3(0.0, 1.0, 0.0) - toward * toward.y;
	across = dot(across, across) > 1e-6 ? normalize(across) : vec3(1.0, 0.0, 0.0);
	normal = normalize(transpose(mat3(model)) * (facing * toward + sqrt(1.0 - facing * facing) * across));
	return light;
}
