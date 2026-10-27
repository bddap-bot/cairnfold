// A roof's covering casts its shadow pulled ROOF_PULL toward the light (roof_shadow.gdshader), and its own faces take
// their shadows from as far out, so the covering shades itself as before while the shadow depth bias no longer lets
// the light through onto the gable and wall tops just under it.
global uniform vec3 sun_toward;
const float ROOF_PULL = 0.5;
