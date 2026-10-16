class_name Duck
extends Critter

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

var size := 1.0
var pace := 1.0
var afloat := false
var pecking := 0.0


func _init(chick: bool, phase: float) -> void:
	super("duckling" if chick else "duck", build.bind(chick), "res://src/duck.gdshader", BLEND, phase)
	size = CHICK_SIZE if chick else 1.0
	pace = 1.6 if chick else 1.0
	scale = Vector3.ONE * size
	set_instance_shader_parameter("pace", pace)


## Eases its pecking at seeds toward `target`, 1 eating and 0 not.
func peck(target: float, delta: float) -> void:
	var next := move_toward(pecking, target, delta * 3.0)
	if next != pecking:
		pecking = next
		set_instance_shader_parameter("peck", pecking)


func walk_speed() -> float:
	return STRIDE_SPEED * size * pace


static func build(chick: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := CHICK if chick else WHITE
	var wing := CHICK_WING if chick else WING
	var head_r := 0.085 if chick else 0.072
	var head := Vector3(0, 0.32, -0.12) if chick else Vector3(0, 0.345, -0.13)
	Meshes.ellipsoid(st, Part.BODY, Vector3(0, 0.17, 0.02), Vector3(0.12, 0.095, 0.17), body, 7, 12, _body_shape)
	Meshes.ellipsoid(st, Part.TAIL, Vector3(0, 0.24, 0.18), Vector3(0.035, 0.022, 0.05), body, 3, 6, _tail_shape)
	Meshes.ellipsoid(st, Part.HEAD, Vector3(0, 0.25, -0.1), Vector3(0.068, 0.075, 0.068), body, 5, 10)
	Meshes.ellipsoid(st, Part.HEAD, head, Vector3.ONE * head_r, body, 7, 12)
	var bill := head + Vector3(0, -0.024, -head_r * 0.98)
	Meshes.ellipsoid(st, Part.HEAD, bill, Vector3(0.036, 0.015, 0.042), BILL, 3, 7, _bill_shape)
	for s in [-1.0, 1.0]:
		var eye := head + Vector3(s * head_r * 0.7, head_r * 0.12, -head_r * 0.64)
		Meshes.ellipsoid(st, Part.HEAD, eye, Vector3.ONE * head_r * 0.21, EYE, 3, 6)
		Meshes.ellipsoid(st, Part.HEAD, eye + Vector3(s * head_r * 0.08, head_r * 0.09, -head_r * 0.13), Vector3.ONE * head_r * 0.075, SHINE, 2, 4)
		var w := Part.WING_L if s < 0 else Part.WING_R
		Meshes.ellipsoid(st, w, Vector3(s * 0.088, 0.2, 0.045), Vector3(0.026, 0.06, 0.12), wing, 4, 7, _wing_shape)
		var f := Part.FOOT_L if s < 0 else Part.FOOT_R
		Meshes.ellipsoid(st, f, Vector3(s * 0.05, 0.05, 0.0), Vector3(0.014, 0.045, 0.014), BILL, 2, 4)
		_foot(st, f, Vector3(s * 0.05, 0.006, -0.01))
	st.index()
	return st.commit()


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
