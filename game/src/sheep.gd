class_name Sheep
extends Critter

## A low-poly sheep: a fleece of overlapping soft blobs, a dark face and legs. Idle, graze, walk and lie run in
## its vertex shader, blended by `mode`; the legs step by `gait`, which the CPU advances by the ground covered
## so the hooves stay planted at any pace. Part ids ride in UV2.x so the shader knows each vertex's pivot.

enum Part { BODY, HEAD, EAR_L, EAR_R, LEG_FL, LEG_FR, LEG_BL, LEG_BR, TAIL, NECK }

const WOOL := Color(0.95, 0.86, 0.68)
const FACE := Color(0.24, 0.22, 0.22)
const MUZZLE := Color(0.31, 0.28, 0.28)
const LEG := Color(0.15, 0.13, 0.13)
const EYE := Color(0.03, 0.025, 0.03)
const SHINE := Color(1.0, 1.0, 1.0)
## Wool tints a sheep's fleece may lean toward, a little.
const TINTS := [Color(1.0, 0.95, 0.86), Color(0.93, 0.92, 0.9), Color(1.0, 0.98, 0.95)]
const SIZE := Vector2(0.88, 1.08)
## Ground a sheep of size 1 covers in one full cycle of its legs.
const STRIDE := 0.62
const IDLE := Vector4(1, 0, 0, 0)
const GRAZE := Vector4(0, 1, 0, 0)
const WALK := Vector4(0, 0, 1, 0)
const LIE := Vector4(0, 0, 0, 1)
const POSES := {Grazers.Motion.IDLE: IDLE, Grazers.Motion.GRAZE: GRAZE, Grazers.Motion.STEP: GRAZE + WALK * 0.5, Grazers.Motion.WALK: WALK, Grazers.Motion.RUN: WALK, Grazers.Motion.LIE: LIE}
## Mode change per second: slow enough that lying down and getting up read as motions.
const BLEND := 1.6
const KIND := "sheep"
const SHADER := "res://src/sheep.gdshader"
## From the middle of the fleece to its rim, at size 1: how near two sheep stand.
const RADIUS := 0.42
## The shader turns legs about HIP high, keeping the same number.
const HIP := 0.32
const FACE_AT := Vector3(0, 0.7, -0.47)

var size := 1.0
var gait := 0.0
## What `Herds` has this sheep doing, until when, and where to.
var state := Grazers.State.ENTER
var timer := 0.0
var goal := Vector3.ZERO
## How long until it goes for seeds again; the hand it eats from is `hand`.
var full := 0.0
## How long until, cornered, it looks again for a way to run.
var retry := 0.0


static func prepare() -> void:
	share(KIND, build, SHADER)


func _init(phase: float, scale_by: float, tint: Color) -> void:
	super(KIND, build, SHADER, BLEND, phase, HandStop.Surface.WOOL)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	size = scale_by
	scale = Vector3.ONE * size
	set_instance_shader_parameter("gait", gait)
	set_instance_shader_parameter("wool", Vector3(tint.r, tint.g, tint.b))


func pose(m: Grazers.Motion, delta: float) -> void:
	blend(POSES[m], delta)


## Advances the legs by `distance` walked, showing `m`.
func walked(m: Grazers.Motion, distance: float, delta: float) -> void:
	if distance > 0.0:
		gait = fposmod(gait + distance / (STRIDE * size) * TAU, TAU)
		set_instance_shader_parameter("gait", gait)
	pose(m, delta)


## Nibbling from a hand `height` above its hooves, the head lowered as far as the hand is low.
func eat(height: float, delta: float) -> void:
	var muzzle := FACE_AT.y * size
	blend(IDLE.lerp(GRAZE, clampf((muzzle - height) / muzzle, 0.0, 1.0)), delta)


## How far it has got to its feet, from 0 lying to 1 standing.
func upright() -> float:
	return 1.0 - mode.w


func radius() -> float:
	return RADIUS * size


static func build() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wool: Array[Array] = [
		[Part.BODY, Vector3(0, 0.58, -0.15), Vector3(0.17, 0.15, 0.18)], [Part.BODY, Vector3(0, 0.59, 0.13), Vector3(0.18, 0.15, 0.19)],
		[Part.BODY, Vector3(-0.13, 0.46, -0.06), Vector3(0.15, 0.16, 0.18)], [Part.BODY, Vector3(0.13, 0.46, -0.06), Vector3(0.15, 0.16, 0.18)],
		[Part.BODY, Vector3(-0.12, 0.45, 0.18), Vector3(0.15, 0.15, 0.17)], [Part.BODY, Vector3(0.12, 0.45, 0.18), Vector3(0.15, 0.15, 0.17)],
		[Part.BODY, Vector3(0, 0.43, -0.25), Vector3(0.15, 0.15, 0.13)], [Part.BODY, Vector3(0, 0.48, 0.33), Vector3(0.14, 0.14, 0.11)],
		[Part.NECK, Vector3(0, 0.58, -0.33), Vector3(0.12, 0.12, 0.11)],
		[Part.NECK, Vector3(0, 0.47, -0.36), Vector3(0.11, 0.11, 0.1)],
		[Part.TAIL, Vector3(0, 0.51, 0.43), Vector3(0.055, 0.07, 0.05)],
		[Part.HEAD, FACE_AT + Vector3(0, 0.085, 0.01), Vector3(0.075, 0.05, 0.07)],
	]
	for w in wool:
		var rings: Vector2i = {Part.BODY: Vector2i(5, 8), Part.HEAD: Vector2i(4, 7)}.get(w[0], Vector2i(3, 6))
		Meshes.ellipsoid(st, w[0], w[1], w[2], WOOL, rings.x, rings.y)
	Meshes.ellipsoid(st, Part.HEAD, FACE_AT, Vector3(0.09, 0.1, 0.115), FACE, 4, 8)
	Meshes.ellipsoid(st, Part.HEAD, FACE_AT + Vector3(0, -0.05, -0.085), Vector3(0.066, 0.06, 0.07), MUZZLE, 3, 7)
	for s in [-1.0, 1.0]:
		var ear := Part.EAR_L if s < 0 else Part.EAR_R
		Meshes.ellipsoid(st, ear, FACE_AT + Vector3(s * 0.13, 0.03, 0.04), Vector3(0.072, 0.02, 0.036), FACE, 3, 5, _ear_shape.bind(s))
		var eye := FACE_AT + Vector3(s * 0.064, 0.025, -0.082)
		Meshes.ellipsoid(st, Part.HEAD, eye, Vector3.ONE * 0.02, EYE, 3, 5)
		Meshes.ellipsoid(st, Part.HEAD, eye + Vector3(s * 0.006, 0.008, -0.014), Vector3.ONE * 0.007, SHINE, 2, 4)
	for leg in [Part.LEG_FL, Part.LEG_FR, Part.LEG_BL, Part.LEG_BR]:
		Meshes.ellipsoid(st, leg, hip(leg) - Vector3(0, HIP * 0.5, 0), Vector3(0.04, HIP * 0.5 + 0.01, 0.04), LEG, 3, 5)
	st.index()
	var arrays := st.commit_to_arrays()
	_shade_under(arrays)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Darkens wool toward the belly, as the sky lights it least there.
static func _shade_under(arrays: Array) -> void:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for i in verts.size():
		if colors[i] == WOOL:
			colors[i] = WOOL * lerpf(0.78, 1.0, smoothstep(0.28, 0.56, verts[i].y))
	arrays[Mesh.ARRAY_COLOR] = colors


## Where a leg hangs from; the shader keeps the same numbers.
static func hip(leg: Part) -> Vector3:
	var x := -0.12 if leg == Part.LEG_FL or leg == Part.LEG_BL else 0.12
	var z := -0.17 if leg == Part.LEG_FL or leg == Part.LEG_FR else 0.22
	return Vector3(x, HIP, z)


## Ears stand out sideways and droop at their tips.
static func _ear_shape(p: Vector3, s: float) -> Vector3:
	return Basis(Vector3.BACK, -s * 0.45) * p
