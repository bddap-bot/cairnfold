shader_type spatial;
render_mode unshaded, shadows_disabled, fog_disabled;

// A cover of the picture book (book.gdshaderinc's `cover`) in the icon look (icon.gdshaderinc).

#include "res://src/book.gdshaderinc"
#include "res://src/icon.gdshaderinc"

uniform vec3 size = vec3(0.16, 0.003, 0.16);
uniform bool front = false;
uniform vec3 cloth;
uniform vec3 leather;

varying vec3 local;
varying vec3 local_n;

void vertex() {
	local = VERTEX;
	local_n = NORMAL;
}

void fragment() {
	float rough;
	float metal;
	ALBEDO = icon_look(cover(local, normalize(local_n), size, front, cloth, leather, rough, metal), NORMAL);
}
