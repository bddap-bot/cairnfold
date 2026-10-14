class_name Duck
extends MeshInstance3D

## A low-poly duck built from soft ellipsoids; idle, paddle, waddle and flight run in its vertex shader.
## Part ids ride in UV2.x so the shader knows which pivot each vertex turns about.

enum Part { BODY, HEAD, WING_L, WING_R, FOOT_L, FOOT_R, TAIL }

const WHITE := Color(1.0, 0.97, 0.90)
const WING := Color(0.90, 0.88, 0.83)
const BILL := Color(1.0, 0.42, 0.04)
const EYE := Color(0.05, 0.04, 0.05)
const SHINE := Color(1.0, 1.0, 1.0)
const CHICK := Color(1.0, 0.84, 0.36)
const CHICK_WING := Color(0.98, 0.78, 0.30)
const CHICK_SIZE := 0.6
## Ground a grown duck covers per second at the shader's step rate, so planted feet stay put.
const STRIDE_SPEED := 0.21
const IDLE := Vector4(1, 0, 0, 0)
const PADDLE := Vector4(0, 1, 0, 0)
const WADDLE := Vector4(0, 0, 1, 0)
const FLY := Vector4(0, 0, 0, 1)
const BLEND := 3.0

static var _meshes := {}
static var _material: ShaderMaterial

var size := 1.0
var pace := 1.0
var mode := IDLE
var afloat := false


func _init(chick: bool, phase: float) -> void:
	if not _meshes.has(chick):
		_meshes[chick] = build(chick)
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://src/duck.gdshader")
	mesh = _meshes[chick]
	material_override = _material
	size = CHICK_SIZE if chick else 1.0
	pace = 1.6 if chick else 1.0
	scale = Vector3.ONE * size
	set_instance_shader_parameter("phase", phase)
	set_instance_shader_parameter("pace", pace)
	set_instance_shader_parameter("mode", mode)


func walk_speed() -> float:
	return STRIDE_SPEED * size * pace


func blend(target: Vector4, delta: float) -> void:
	if mode == target:
		return
	var d := target - mode
	var step := delta * BLEND
	mode = target if d.length() <= step else mode + d * (step / d.length())
	set_instance_shader_parameter("mode", mode)


static func build(chick: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := CHICK if chick else WHITE
	var wing := CHICK_WING if chick else WING
	var head_r := 0.085 if chick else 0.072
	var head := Vector3(0, 0.32, -0.12) if chick else Vector3(0, 0.345, -0.13)
	_blob(st, Part.BODY, Vector3(0, 0.17, 0.02), Vector3(0.12, 0.095, 0.17), body, 7, 12, _body_shape)
	_blob(st, Part.TAIL, Vector3(0, 0.24, 0.18), Vector3(0.035, 0.022, 0.05), body, 3, 6, _tail_shape)
	_blob(st, Part.HEAD, Vector3(0, 0.25, -0.1), Vector3(0.068, 0.075, 0.068), body, 5, 10)
	_blob(st, Part.HEAD, head, Vector3.ONE * head_r, body, 7, 12)
	var bill := head + Vector3(0, -0.024, -head_r * 0.98)
	_blob(st, Part.HEAD, bill, Vector3(0.036, 0.015, 0.042), BILL, 3, 7, _bill_shape)
	for s in [-1.0, 1.0]:
		var eye := head + Vector3(s * head_r * 0.7, head_r * 0.12, -head_r * 0.64)
		_blob(st, Part.HEAD, eye, Vector3.ONE * head_r * 0.21, EYE, 3, 6)
		_blob(st, Part.HEAD, eye + Vector3(s * head_r * 0.08, head_r * 0.09, -head_r * 0.13), Vector3.ONE * head_r * 0.075, SHINE, 2, 4)
		var w := Part.WING_L if s < 0 else Part.WING_R
		_blob(st, w, Vector3(s * 0.088, 0.2, 0.045), Vector3(0.026, 0.06, 0.12), wing, 4, 7, _wing_shape)
		var f := Part.FOOT_L if s < 0 else Part.FOOT_R
		_blob(st, f, Vector3(s * 0.05, 0.05, 0.0), Vector3(0.014, 0.045, 0.014), BILL, 2, 4)
		_foot(st, f, Vector3(s * 0.05, 0.006, -0.01))
	st.index()
	return st.commit()


## A latitude-longitude ellipsoid; `shape` may bend each surface point (given relative to the centre).
static func _blob(st: SurfaceTool, part: int, c: Vector3, r: Vector3, col: Color, lat: int, lon: int, shape := Callable()) -> void:
	var ring := []
	for i in lat + 1:
		var row := []
		var th := PI * i / lat
		for j in lon:
			var ph := TAU * j / lon
			var u := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
			var p := u * r
			if shape.is_valid():
				p = shape.call(p)
			row.append([c + p, (u / r).normalized()])
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
				for v in t:
					st.set_color(col)
					st.set_uv2(Vector2(part, 0))
					st.set_normal(quad[v][1])
					st.add_vertex(quad[v][0])


static func _foot(st: SurfaceTool, part: int, at: Vector3) -> void:
	var outline := [Vector3(0, 0, 0.015), Vector3(-0.035, 0, -0.045), Vector3(-0.012, 0, -0.035), Vector3(0, 0, -0.058), Vector3(0.012, 0, -0.035), Vector3(0.035, 0, -0.045)]
	for i in range(1, outline.size() - 1):
		for tri in [[0, i, i + 1], [0, i + 1, i]]:
			for v in tri:
				st.set_color(BILL)
				st.set_uv2(Vector2(part, 0))
				st.set_normal(Vector3.UP)
				st.add_vertex(at + outline[v])


static func _body_shape(p: Vector3) -> Vector3:
	var back := clampf(p.z / 0.17, 0.0, 1.0)
	p.y += back * back * 0.06
	p.x *= 1.0 - back * 0.25
	if p.y < 0.0:
		p.y *= 0.8
	var front := clampf(-p.z / 0.17, 0.0, 1.0)
	p.y += front * front * 0.02
	return p


static func _tail_shape(p: Vector3) -> Vector3:
	return Basis(Vector3.RIGHT, deg_to_rad(35.0)) * p


static func _bill_shape(p: Vector3) -> Vector3:
	var tip := clampf(-p.z / 0.045, 0.0, 1.0)
	p.y += tip * tip * 0.006
	p.x *= 1.0 + tip * 0.15
	return p


static func _wing_shape(p: Vector3) -> Vector3:
	var back := clampf(p.z / 0.13, 0.0, 1.0)
	p.y += back * back * 0.035
	return p
