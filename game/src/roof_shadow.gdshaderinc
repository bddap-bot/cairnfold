// The covering's faces take shadows from as far out as roof_shadow.gdshader pulls its cast shadow, so it still shades
// itself while the depth bias cannot let light through onto the gable and wall tops just under it.
global uniform vec3 sun_toward;
const float ROOF_PULL = 0.5;
