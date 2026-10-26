// The hour's light as Look sets it for every shader that lights itself (Daylight.light): the sun's direction and its
// colour times its energy, the sky at the zenith and horizon, the haze and the ambient energy.
global uniform vec3 sun_toward;
global uniform vec3 sun_light;
global uniform vec3 sky_zenith;
global uniform vec3 sky_horizon;
global uniform vec3 sky_haze;
global uniform float sky_ambient;
