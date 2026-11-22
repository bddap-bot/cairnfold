// Set by Look (Daylight.light). sun_light is the sun's colour times its energy.
global uniform vec3 sun_toward;
global uniform vec3 sun_light;
global uniform vec3 sky_zenith;
global uniform vec3 sky_horizon;
global uniform vec3 sky_haze;
global uniform float sky_ambient;
// Set by Look (Weather.veil): what far things lose to a fog thicker than the clear one, besides their own haze.
global uniform float fog_veil;
