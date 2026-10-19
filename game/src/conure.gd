class_name Conure
extends Critter

## A small parrot built from soft, slightly ruffled ellipsoids, standing on its feet at the origin and
## facing -Z. Looking about, preening, pecking and flight run in its vertex shader, and its plumage turns
## in the fragment shader: one of the colourings wild conures come in, or iridescent, turning from blue facing the eye
## to green at grazing angles. Part ids ride in UV2.x. Plumage vertices carry brightness in red, a hue bias in green,
## their patch in blue and 1 in alpha; the bill carries its shade with alpha 0.5; the rest carry their colour with
## alpha 0.

enum Part { BODY, HEAD, WING_L, WING_R, TAIL, FEET }
enum Patch { BACK, CHEST, BELLY, CROWN, FACE, FLIGHT, COVERTS, TAIL, BILL }

## Each bird's colouring, as sRGB hex per `Patch`. The first is the iridescent conure, whose feathers the shader
## colours itself; only its bill is read here.
const PLUMAGES := {
	"iridescent": ["", "", "", "", "", "", "", "", "efe7da"],
	"sun": ["f5b51c", "ff9f1a", "ff7418", "ffc41f", "ff8a1e", "2a6f5e", "e6c22e", "6f8f3a", "26262a"],
	"jenday": ["3f9a3a", "f07a22", "e2521e", "f8c81e", "f59a1e", "2f5fa8", "48a23e", "3a6f6a", "222224"],
	"nanday": ["5ea83a", "5f9f98", "86bb3a", "1e1c1e", "2a2626", "2b4f9c", "5aa03a", "4e7f62", "1e1e20"],
	"green-cheeked": ["3f8a35", "8a8070", "8a2a2a", "4a3f3a", "3f9a3a", "2f5f9a", "3f8a35", "7a2526", "2a2a2c"],
	"green-cheeked pineapple": ["9cc24a", "d6c08a", "d0502e", "b8956a", "a8cc55", "8ab0c4", "b8cc4a", "b84a4a", "c8b8a8"],
	"green-cheeked turquoise": ["2f9a8e", "9aa0a0", "7e8a8a", "4a4a50", "3aa59a", "2f60a0", "34a294", "556a78", "2a2a2c"],
	"blue-crowned": ["6aa63a", "7ab246", "8ab846", "3f78b0", "5a8fb0", "4a8a3a", "6aa63a", "6a8f3a", "d8c8b0"],
	"red-masked": ["4a9a32", "52a036", "5aa63a", "d8262a", "d42a2a", "4a8a30", "c83a2a", "4a8a32", "e0d6c4"],
	"golden": ["f5d21e", "f7d624", "f2cf20", "f8d828", "f8d828", "2e8a3a", "f2cf20", "f2cc22", "e8dcc8"],
	"dusky-headed": ["5a9a3a", "8ea67a", "a8c050", "6a6460", "7a7068", "2f5a9a", "5a9a3a", "3a6a7a", "222224"],
	"patagonian": ["6a6a3a", "d8d2c2", "d86a2a", "5e5a3c", "5e5a3c", "2f4f7a", "6e7044", "5f5e3a", "2a2a2c"],
}

const EYE := Color(0.04, 0.03, 0.03, 0.0)
const RING := Color(0.96, 0.95, 0.9, 0.0)
const SHINE := Color(1.0, 1.0, 1.0, 0.0)
const FOOT := Color(0.52, 0.5, 0.5, 0.0)
const IDLE := Vector4(1, 0, 0, 0)
const PREEN := Vector4(0, 1, 0, 0)
const PECK := Vector4(0, 0, 1, 0)
const FLY := Vector4(0, 0, 0, 1)
const BLEND := 5.0
const KIND := "conure"
const SHADER := "res://src/conure.gdshader"
## The body's long axis leans this far forward of upright when perched; the shader pitches it level to fly.
const LEAN := deg_to_rad(35.0)
const BODY := Vector3(0, 0.062, 0.012)
const BILL_SIZE := Vector3(0.009, 0.0105, 0.0125)
const WING_SIZE := Vector3(0.011, 0.052, 0.025)
const TAIL_SIZE := Vector3(0.018, 0.058, 0.006)
const NECK := Vector3(0, 0.098, -0.012)
## How far round and up or down the head turns to look at something, in radians.
const GAZE_TURN := Vector2(1.7, 0.9)
const GAZE_EASE := 4.0

## What it looks at this tick, Vector3.INF to look about; `look` eases the head there.
var looking := Vector3.INF
var _gaze := Vector3.ZERO


static func prepare() -> void:
	share(KIND, build, SHADER)
	var material: ShaderMaterial = _shared[SHADER]
	if material.get_shader_parameter("palette") == null:
		material.set_shader_parameter("palette", palette())


## `plumage` indexes `PLUMAGES`.
func _init(phase: float, plumage: int) -> void:
	super(KIND, build, SHADER, BLEND, phase, HandStop.Surface.FEATHERS)
	prepare()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	set_instance_shader_parameter("plumage", plumage)


func look(delta: float) -> void:
	var to := _gaze
	to.z = move_toward(to.z, 0.0 if looking == Vector3.INF else 1.0, delta * GAZE_EASE)
	if looking != Vector3.INF:
		var l := transform.affine_inverse() * looking - NECK
		to.x = clampf(atan2(-l.x, -l.z), -GAZE_TURN.x, GAZE_TURN.x)
		to.y = clampf(atan2(l.y, Vector2(l.x, l.z).length()), -GAZE_TURN.y, GAZE_TURN.y)
	looking = Vector3.INF
	if to != _gaze:
		_gaze = to
		set_instance_shader_parameter("gaze", _gaze)


## One row per plumage, one linear texel per patch, so a bird's colouring is one instance parameter on the shared
## material and the vertex shader looks up each patch once.
static func palette() -> ImageTexture:
	var image := Image.create(Patch.size(), PLUMAGES.size(), false, Image.FORMAT_RGBH)
	var y := 0
	for hexes: Array in PLUMAGES.values():
		for x in Patch.size():
			image.set_pixel(x, y, Color.html(hexes[x]).srgb_to_linear() if hexes[x] else Color.BLACK)
		y += 1
	return ImageTexture.create_from_image(image)


static func feathers(brightness: float, hue: float, patch: Patch) -> Color:
	return Color(brightness, 0.5 + hue, float(patch) / Patch.size(), 1.0)


static func build() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lean := Basis(Vector3.RIGHT, -LEAN)
	var up := lean.y
	var back := lean.z
	var head := BODY + up * 0.062 - back * 0.004
	var none := Callable()
	var shade := func(s: float) -> Color: return Color(s, 0.0, 0.0, 0.5)
	Meshes.ellipsoid(st, Part.BODY, BODY, Vector3(0.036, 0.052, 0.038), feathers(1.0, 0.0, Patch.BACK), 8, 14, none, lean, 0.03, BODY)
	Meshes.ellipsoid(st, Part.BODY, BODY + up * 0.014 - back * 0.012, Vector3(0.033, 0.036, 0.032), feathers(1.05, 0.06, Patch.CHEST), 6, 11, none, lean, 0.035, BODY)
	Meshes.ellipsoid(st, Part.BODY, BODY - up * 0.024 - back * 0.006, Vector3(0.031, 0.031, 0.031), feathers(1.08, 0.18, Patch.BELLY), 6, 11, none, lean, 0.04, BODY)
	Meshes.ellipsoid(st, Part.BODY, BODY + up * 0.008 + back * 0.013, Vector3(0.031, 0.042, 0.026), feathers(0.95, -0.04, Patch.BACK), 6, 11, none, lean, 0.03, BODY)
	Meshes.ellipsoid(st, Part.HEAD, head, Vector3(0.031, 0.03, 0.032), feathers(1.0, -0.12, Patch.CROWN), 8, 13, none, Basis(), 0.025, head)
	Meshes.ellipsoid(st, Part.HEAD, head + Vector3(0, 0.004, -0.019), Vector3(0.023, 0.021, 0.017), feathers(1.05, -0.08, Patch.FACE), 5, 9, none, Basis(), 0.04, head)
	var bill := head + Vector3(0, -0.006, -0.03)
	Meshes.ellipsoid(st, Part.HEAD, bill, BILL_SIZE, shade.call(1.0), 5, 8, _hook)
	Meshes.ellipsoid(st, Part.HEAD, bill + Vector3(0, -0.0075, 0.003), Vector3(0.0065, 0.0045, 0.0065), shade.call(0.8), 4, 8)
	for s in [-1.0, 1.0]:
		var out := Vector3(s * 0.8, 0.22, -0.56).normalized()
		var eye := head + out * 0.028
		Meshes.ellipsoid(st, Part.HEAD, head + out * 0.0295, Vector3(0.0098, 0.0098, 0.004), RING, 3, 14, none, Basis.looking_at(out))
		Meshes.ellipsoid(st, Part.HEAD, eye, Vector3.ONE * 0.0071, EYE, 4, 10)
		Meshes.ellipsoid(st, Part.HEAD, eye + out * 0.0052 + Vector3(0, 0.0024, -0.002), Vector3.ONE * 0.0019, SHINE, 2, 5)
		var w := Part.WING_L if s < 0 else Part.WING_R
		var shoulder: Vector3 = BODY + up * 0.004 + back * 0.012 + Vector3(s * 0.029, 0, 0)
		var wing := lean * Basis(Vector3.BACK, s * 0.08)
		Meshes.ellipsoid(st, w, shoulder, WING_SIZE, feathers(0.88, -0.18, Patch.FLIGHT), 6, 10, _wing_shape, wing, 0.03, BODY)
		Meshes.ellipsoid(st, w, shoulder + up * 0.018 + Vector3(s * 0.003, 0, 0), Vector3(0.011, 0.024, 0.023), feathers(0.95, -0.08, Patch.COVERTS), 4, 8, none, wing, 0.04, BODY)
		var foot := Vector3(s * 0.012, 0, 0.004)
		Meshes.ellipsoid(st, Part.FEET, foot + Vector3(0, 0.009, 0), Vector3(0.0045, 0.009, 0.0045), FOOT, 2, 5)
		Meshes.ellipsoid(st, Part.FEET, foot + Vector3(0, 0.0025, 0), Vector3(0.006, 0.0022, 0.011), FOOT, 2, 5)
	var rump := BODY - up * 0.036 + back * 0.014
	var tail := Basis(Vector3.RIGHT, deg_to_rad(101.0))
	Meshes.ellipsoid(st, Part.TAIL, rump + tail.y * 0.05, TAIL_SIZE, feathers(0.8, -0.25, Patch.TAIL), 6, 8, _tail_shape, tail)
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
