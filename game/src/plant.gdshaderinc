#include "res://src/ground.gdshaderinc"
#include "res://src/water.gdshaderinc"

uniform vec3 albedo : source_color = vec3(1.0);
uniform float roughness = 1.0;
#ifdef BACKLIT
uniform vec3 backlight : source_color = vec3(0.0);
#endif

void vertex() {
	float ground = ground_at(INSTANCE_CUSTOM.zw);
	VERTEX.y += ground;
#ifdef PARTED
	vec3 root = MODEL_MATRIX[3].xyz + vec3(0.0, ground, 0.0);
	VERTEX = mix(root, VERTEX, 1.0 - bare(root.xz));
#endif
	if (drowned(INSTANCE_CUSTOM.zw, ground)) {
		VERTEX = vec3(INSTANCE_CUSTOM.z, ground, INSTANCE_CUSTOM.w);
	}
}

#ifdef FLOWER
uniform vec3 stalk : source_color;
uniform vec3 eye : source_color;
#endif

void fragment() {
#ifdef FLOWER
	vec3 head = mix(albedo * COLOR.rgb, eye, smoothstep(0.55, 0.9, UV.y));
	ALBEDO = mix(stalk, head, UV.x);
#else
	ALBEDO = albedo * COLOR.rgb;
#endif
	ROUGHNESS = roughness;
#ifdef BACKLIT
	BACKLIGHT = backlight;
#endif
}
