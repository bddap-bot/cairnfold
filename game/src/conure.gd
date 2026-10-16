class_name Conure
extends Critter

## A small parrot built from soft, slightly ruffled ellipsoids, standing on its feet at the origin and
## facing -Z. Looking about, preening, pecking and flight run in its vertex shader, and its plumage turns
## from blue facing the eye to green at grazing angles in the fragment shader. Part ids ride in UV2.x.
## Plumage vertices carry brightness in red, a hue bias in green and 1 in alpha; the rest carry their
## colour with alpha 0.

enum Part { BODY, HEAD, WING_L, WING_R, TAIL, FEET }

const BILL := Color(0.86, 0.8, 0.7, 0.0)
const EYE := Color(0.04, 0.03, 0.03, 0.0)
const RING := Color(0.96, 0.95, 0.9, 0.0)
const SHINE := Color(1.0, 1.0, 1.0, 0.0)
const FOOT := Color(0.52, 0.5, 0.5, 0.0)
const IDLE := Vector4(1, 0, 0, 0)
const PREEN := Vector4(0, 1, 0, 0)
const PECK := Vector4(0, 0, 1, 0)
const FLY := Vector4(0, 0, 0, 1)
const BLEND := 5.0
## The body's long axis leans this far forward of upright when perched; the shader pitches it level to fly.
const LEAN := deg_to_rad(35.0)
const BODY := Vector3(0, 0.062, 0.012)
const BILL_SIZE := Vector3(0.009, 0.0105, 0.0125)
const WING_SIZE := Vector3(0.011, 0.052, 0.025)
const TAIL_SIZE := Vector3(0.018, 0.058, 0.006)


func _init(phase: float) -> void:
	super("conure", build, "res://src/conure.gdshader", BLEND, phase, HandStop.Surface.FEATHERS)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func plumage(brightness: float, hue: float) -> Color:
	return Color(brightness, 0.5 + hue, 0.0, 1.0)


static func build() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lean := Basis(Vector3.RIGHT, -LEAN)
	var up := lean.y
	var back := lean.z
	var head := BODY + up * 0.062 - back * 0.004
	var none := Callable()
	Meshes.ellipsoid(st, Part.BODY, BODY, Vector3(0.036, 0.052, 0.038), plumage(1.0, 0.0), 8, 14, none, lean, 0.03, BODY)
	Meshes.ellipsoid(st, Part.BODY, BODY + up * 0.014 - back * 0.012, Vector3(0.033, 0.036, 0.032), plumage(1.05, 0.06), 6, 11, none, lean, 0.035, BODY)
	Meshes.ellipsoid(st, Part.BODY, BODY - up * 0.024 - back * 0.006, Vector3(0.031, 0.031, 0.031), plumage(1.08, 0.18), 6, 11, none, lean, 0.04, BODY)
	Meshes.ellipsoid(st, Part.BODY, BODY + up * 0.008 + back * 0.013, Vector3(0.031, 0.042, 0.026), plumage(0.95, -0.04), 6, 11, none, lean, 0.03, BODY)
	Meshes.ellipsoid(st, Part.HEAD, head, Vector3(0.031, 0.03, 0.032), plumage(1.0, -0.12), 8, 13, none, Basis(), 0.025, head)
	Meshes.ellipsoid(st, Part.HEAD, head + Vector3(0, 0.004, -0.019), Vector3(0.023, 0.021, 0.017), plumage(1.05, -0.08), 5, 9, none, Basis(), 0.04, head)
	var bill := head + Vector3(0, -0.006, -0.03)
	Meshes.ellipsoid(st, Part.HEAD, bill, BILL_SIZE, BILL, 5, 8, _hook)
	Meshes.ellipsoid(st, Part.HEAD, bill + Vector3(0, -0.0075, 0.003), Vector3(0.0065, 0.0045, 0.0065), BILL * Color(0.8, 0.8, 0.8), 4, 8)
	for s in [-1.0, 1.0]:
		var out := Vector3(s * 0.8, 0.22, -0.56).normalized()
		var eye := head + out * 0.028
		Meshes.ellipsoid(st, Part.HEAD, head + out * 0.0295, Vector3(0.0098, 0.0098, 0.004), RING, 3, 14, none, Basis.looking_at(out))
		Meshes.ellipsoid(st, Part.HEAD, eye, Vector3.ONE * 0.0071, EYE, 4, 10)
		Meshes.ellipsoid(st, Part.HEAD, eye + out * 0.0052 + Vector3(0, 0.0024, -0.002), Vector3.ONE * 0.0019, SHINE, 2, 5)
		var w := Part.WING_L if s < 0 else Part.WING_R
		var shoulder: Vector3 = BODY + up * 0.004 + back * 0.012 + Vector3(s * 0.029, 0, 0)
		var wing := lean * Basis(Vector3.BACK, s * 0.08)
		Meshes.ellipsoid(st, w, shoulder, WING_SIZE, plumage(0.88, -0.18), 6, 10, _wing_shape, wing, 0.03, BODY)
		Meshes.ellipsoid(st, w, shoulder + up * 0.018 + Vector3(s * 0.003, 0, 0), Vector3(0.011, 0.024, 0.023), plumage(0.95, -0.08), 4, 8, none, wing, 0.04, BODY)
		var foot := Vector3(s * 0.012, 0, 0.004)
		Meshes.ellipsoid(st, Part.FEET, foot + Vector3(0, 0.009, 0), Vector3(0.0045, 0.009, 0.0045), FOOT, 2, 5)
		Meshes.ellipsoid(st, Part.FEET, foot + Vector3(0, 0.0025, 0), Vector3(0.006, 0.0022, 0.011), FOOT, 2, 5)
	var rump := BODY - up * 0.036 + back * 0.014
	var tail := Basis(Vector3.RIGHT, deg_to_rad(101.0))
	Meshes.ellipsoid(st, Part.TAIL, rump + tail.y * 0.05, TAIL_SIZE, plumage(0.8, -0.25), 6, 8, _tail_shape, tail)
	st.index()
	return st.commit()


## The upper bill curves down over the lower to a hooked tip.
static func _hook(p: Vector3) -> Vector3:
	var tip := clampf(-p.z / BILL_SIZE.z, 0.0, 1.0)
	p.y -= tip * tip * 0.011
	p.x *= 1.0 - tip * 0.5
	if p.z > 0.0:
		p.z *= 0.6
	return p


## The folded wing narrows to its tip, which reaches down over the tail.
static func _wing_shape(p: Vector3) -> Vector3:
	var tip := clampf(-p.y / WING_SIZE.y, 0.0, 1.0)
	p.z *= 1.0 - tip * 0.55
	p.x *= 1.0 - tip * 0.4
	return p


## Long and tapering: widest at the rump, narrowing to a point.
static func _tail_shape(p: Vector3) -> Vector3:
	var along := clampf(p.y / TAIL_SIZE.y * 0.5 + 0.5, 0.0, 1.0)
	p.x *= lerpf(1.0, 0.35, along)
	p.z += (1.0 - absf(p.x) / TAIL_SIZE.x) * 0.002
	return p
