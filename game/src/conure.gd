class_name Conure
extends MeshInstance3D

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
## How far plumage normals lean from each blob's own toward the body's or head's as a whole.
const ROUND := 0.6

static var _mesh: ArrayMesh
static var _material: ShaderMaterial

var mode := IDLE


func _init(phase: float) -> void:
	if _mesh == null:
		_mesh = build()
		_material = ShaderMaterial.new()
		_material.shader = load("res://src/conure.gdshader")
	mesh = _mesh
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	set_instance_shader_parameter("phase", phase)
	set_instance_shader_parameter("mode", mode)


func blend(target: Vector4, delta: float) -> void:
	if mode == target:
		return
	var d := target - mode
	var step := delta * BLEND
	mode = target if d.length() <= step else mode + d * (step / d.length())
	set_instance_shader_parameter("mode", mode)


static func plumage(brightness: float, hue: float) -> Color:
	return Color(brightness, 0.5 + hue, 0.0, 1.0)


static func build() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lean := Basis(Vector3.RIGHT, -LEAN)
	var up := lean.y
	var back := lean.z
	var head := BODY + up * 0.062 - back * 0.004
	_blob(st, Part.BODY, BODY, Vector3(0.036, 0.052, 0.038), lean, plumage(1.0, 0.0), 8, 14, 0.03, BODY)
	_blob(st, Part.BODY, BODY + up * 0.014 - back * 0.012, Vector3(0.033, 0.036, 0.032), lean, plumage(1.05, 0.06), 6, 11, 0.035, BODY)
	_blob(st, Part.BODY, BODY - up * 0.024 - back * 0.006, Vector3(0.031, 0.031, 0.031), lean, plumage(1.08, 0.18), 6, 11, 0.04, BODY)
	_blob(st, Part.BODY, BODY + up * 0.008 + back * 0.013, Vector3(0.031, 0.042, 0.026), lean, plumage(0.95, -0.04), 6, 11, 0.03, BODY)
	_blob(st, Part.HEAD, head, Vector3(0.031, 0.03, 0.032), Basis(), plumage(1.0, -0.12), 8, 13, 0.025, head)
	_blob(st, Part.HEAD, head + Vector3(0, 0.004, -0.019), Vector3(0.023, 0.021, 0.017), Basis(), plumage(1.05, -0.08), 5, 9, 0.04, head)
	var bill := head + Vector3(0, -0.006, -0.03)
	_blob(st, Part.HEAD, bill, Vector3(0.009, 0.0105, 0.0125), Basis(), BILL, 5, 8, 0.0, Vector3.INF, _hook)
	_blob(st, Part.HEAD, bill + Vector3(0, -0.0075, 0.003), Vector3(0.0065, 0.0045, 0.0065), Basis(), BILL * Color(0.8, 0.8, 0.8), 4, 8)
	for s in [-1.0, 1.0]:
		var out := Vector3(s * 0.8, 0.22, -0.56).normalized()
		var eye := head + out * 0.028
		_blob(st, Part.HEAD, head + out * 0.0295, Vector3(0.0098, 0.0098, 0.004), Basis.looking_at(out), RING, 3, 14)
		_blob(st, Part.HEAD, eye, Vector3.ONE * 0.0071, Basis(), EYE, 4, 10)
		_blob(st, Part.HEAD, eye + out * 0.0052 + Vector3(0, 0.0024, -0.002), Vector3.ONE * 0.0019, Basis(), SHINE, 2, 5)
		var w := Part.WING_L if s < 0 else Part.WING_R
		var shoulder: Vector3 = BODY + up * 0.004 + back * 0.012 + Vector3(s * 0.029, 0, 0)
		var wing := lean * Basis(Vector3.BACK, s * 0.08)
		_blob(st, w, shoulder, Vector3(0.011, 0.052, 0.025), wing, plumage(0.88, -0.18), 6, 10, 0.03, BODY, _wing_shape)
		_blob(st, w, shoulder + up * 0.018 + Vector3(s * 0.003, 0, 0), Vector3(0.011, 0.024, 0.023), wing, plumage(0.95, -0.08), 4, 8, 0.04, BODY)
		_foot(st, Vector3(s * 0.012, 0, 0.004))
	var rump := BODY - up * 0.036 + back * 0.014
	var tail := Basis(Vector3.RIGHT, deg_to_rad(101.0))
	_blob(st, Part.TAIL, rump + tail.y * 0.05, Vector3(0.018, 0.058, 0.006), tail, plumage(0.8, -0.25), 6, 8, 0.0, Vector3.INF, _tail_shape)
	st.index()
	return st.commit()


## A latitude-longitude ellipsoid with half-axes `r` along `axes`; `ruffle` pushes its surface in and out a
## little, like fluffed feathers, and `shape` may bend each point (given in the ellipsoid's own frame).
## Normals lean toward pointing away from `round`, so overlapping blobs shade as one soft mass.
static func _blob(st: SurfaceTool, part: int, c: Vector3, r: Vector3, axes: Basis, col: Color, lat: int, lon: int, ruffle := 0.0, round := Vector3.INF, shape := Callable()) -> void:
	var ring := []
	for i in lat + 1:
		var row := []
		var th := PI * i / lat
		for j in lon:
			var ph := TAU * j / lon
			var u := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
			var bump := 1.0 + ruffle * (sin(ph * 5.0 + th * 3.0) * 0.6 + sin(ph * 3.0 - th * 7.0 + 1.3) * 0.4) * sin(th)
			var p := u * r * bump
			if shape.is_valid():
				p = shape.call(p, r)
			var at := c + axes * p
			var n := (axes * (u / r)).normalized()
			if round != Vector3.INF:
				n = n.lerp((at - round).normalized(), ROUND).normalized()
			row.append([at, n])
		ring.append(row)
	for i in lat:
		for j in lon:
			var k := (j + 1) % lon
			var quad := [ring[i][j], ring[i + 1][j], ring[i + 1][k], ring[i][k]]
			for t in [[0, 2, 1], [0, 3, 2]]:
				if i == 0 and t[0] == 0 and t[1] == 3:
					continue
				if i == lat - 1 and t[1] == 2 and t[2] == 1:
					continue
				for v in [t[0], t[2], t[1]]:
					st.set_color(col)
					st.set_uv2(Vector2(part, 0))
					st.set_normal(quad[v][1])
					st.add_vertex(quad[v][0])


## A short leg and two toes forward, two back, gripping the perch.
static func _foot(st: SurfaceTool, at: Vector3) -> void:
	_blob(st, Part.FEET, at + Vector3(0, 0.009, 0), Vector3(0.0045, 0.009, 0.0045), Basis(), FOOT, 2, 5)
	for z in [-1.0, 1.0]:
		for x in [-1.0, 1.0]:
			_blob(st, Part.FEET, at + Vector3(x * 0.0035, 0.0025, z * 0.008), Vector3(0.0022, 0.0022, 0.0085), Basis(Vector3.UP, x * z * 0.3), FOOT, 2, 5)


## The upper bill curves down over the lower to a hooked tip.
static func _hook(p: Vector3, r: Vector3) -> Vector3:
	var tip := clampf(-p.z / r.z, 0.0, 1.0)
	p.y -= tip * tip * 0.011
	p.x *= 1.0 - tip * 0.5
	if p.z > 0.0:
		p.z *= 0.6
	return p


## The folded wing narrows to its tip, which reaches down over the tail.
static func _wing_shape(p: Vector3, r: Vector3) -> Vector3:
	var tip := clampf(-p.y / r.y, 0.0, 1.0)
	p.z *= 1.0 - tip * 0.55
	p.x *= 1.0 - tip * 0.4
	return p


## Long and tapering: widest at the rump, narrowing to a point.
static func _tail_shape(p: Vector3, r: Vector3) -> Vector3:
	var along := clampf(p.y / r.y * 0.5 + 0.5, 0.0, 1.0)
	p.x *= lerpf(1.0, 0.35, along)
	p.z += (1.0 - absf(p.x) / r.x) * 0.002
	return p
