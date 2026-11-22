// A camera whose cull mask holds `sculpture_layer` (Quality.SCULPTURE_LAYER, which nothing is drawn on) sees the garden
// carved whole from one white stone: its shapes, light and shadows, none of its colours (PhotoStyle's sculpture).
#ifndef SCULPTURE_GDSHADERINC
#define SCULPTURE_GDSHADERINC
global uniform uint sculpture_layer;
const vec3 SCULPTURE = vec3(0.8);
#define SCULPTED ((CAMERA_VISIBLE_LAYERS & sculpture_layer) != 0u)
#endif
