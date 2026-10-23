class_name HeldShadow
extends Object

## The shadow a held thing lays along the light. The sun's map has texels about 0.2 m across at a headset's field of
## view, so a hand-sized caster covered a texel's centre in some frames and none in others, and its shadow blinked as
## the hand moved. Drawn whole, by a near split or a decal, it cost the Quest 2 over a millisecond a frame. So a held
## thing casts nothing into the map, and the ground darkens what lies beyond it from the light itself
## (held_shadow.gdshaderinc), from one box set here.

## How far beyond the caster, along the light, its shadow reaches.
const REACH := 12.0
## How far beyond the caster the shadow begins, so nothing at the caster itself is darkened.
const CLEAR := 0.02
## How much of what lies in the shadow's albedo it takes once the light stands RISE.y degrees up, easing in from
## RISE.x, and less in proportion below FULL_ENERGY. Fitted on the meadow's ground, which takes bounce light as well as
## the sun and sky, to the sun's own shadow of the book drawn by a split fine enough to hold it, at 11°, 34° and 50°
## up: taking albedo cannot only take the sun away, so a fit to one surface leaves the others near it, not on it.
const SHADE := 0.62
const RISE := Vector2(3.0, 27.0)
const FULL_ENERGY := 1.3


## Lays the shadow of a flat thing spanning `rect` (x and z of `frame`'s plane) along the light shining at `time`.
static func cast(frame: Transform3D, rect: Rect2, time: float) -> void:
	var toward := Daylight.toward_light(time)
	var mid := rect.get_center()
	var at := frame * Vector3(mid.x, 0.0, mid.y) - toward * (CLEAR + REACH * 0.5)
	var box := Transform3D(Basis(frame.basis.x * rect.size.x, toward * REACH, frame.basis.z * rect.size.y), at)
	RenderingServer.global_shader_parameter_set(&"held_shadow", Projection(box.affine_inverse()))
	var up := smoothstep(RISE.x, RISE.y, rad_to_deg(asin(toward.y)))
	var energy: float = Daylight.light(time).energy
	RenderingServer.global_shader_parameter_set(&"held_shade", SHADE * up * clampf(energy / FULL_ENERGY, 0.0, 1.0))


static func clear() -> void:
	RenderingServer.global_shader_parameter_set(&"held_shade", 0.0)
