class_name Scatter
extends MultiMeshInstance3D

## A handful of seeds tossed from the seed dish: the grains fly apart, settle where they land on the ground or float on
## a pond, and go one by one as an animal pecks at them, or sink away unneeded once they have lain a while.

const GRAINS := 28
## Metres a second the grains spread apart from the throw.
const SPREAD := 0.6
const GRAVITY := 9.8
const LASTS := Vector2(50.0, 70.0)
const FADE := 6.0
## Grains a feeding animal takes a second.
const PECKS := 1.6

static var _mesh: Mesh

var rng := RandomNumberGenerator.new()
var age := 0.0
var lasts := LASTS.x
var _floor: Callable
var _at := PackedVector3Array()
var _vel := PackedVector3Array()
var _turn: Array[Basis] = []
var _down := PackedByteArray()
var _flying := GRAINS
var _left := GRAINS
var _eat_next := 0.0
var _order := PackedInt32Array()


func _init(from: Vector3, velocity: Vector3, floor_at: Callable, seed := -1) -> void:
	if seed >= 0:
		rng.seed = seed
	_floor = floor_at
	lasts = rng.randf_range(LASTS.x, LASTS.y)
	position = from
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = grain()
	multimesh.instance_count = GRAINS
	material_override = ToolModels._vertex_mat("seeds", 0.7, false)
	for i in GRAINS:
		var spread := Vector3(rng.randfn(), rng.randfn() * 0.5, rng.randfn()) * SPREAD
		_at.append(from + Vector3(rng.randf_range(-0.012, 0.012), 0, rng.randf_range(-0.012, 0.012)))
		_vel.append(velocity + spread)
		_turn.append(Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)))
		_order.append(i)
		_down.append(0)
		var tint := rng.randi_range(0, 2)
		multimesh.set_instance_color(i, [Color(0.93, 0.8, 0.5), Color(0.2, 0.19, 0.17), Color(0.62, 0.48, 0.3)][tint])
	for i in range(GRAINS - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := _order[i]
		_order[i] = _order[j]
		_order[j] = t
	_place()


## One grain: a small seed, shared by every handful.
static func grain() -> Mesh:
	if _mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		Meshes.ellipsoid(st, 0, Vector3.ZERO, Vector3(0.0035, 0.0075, 0.0025), Color.WHITE, 2, 5)
		_mesh = st.commit()
	return _mesh


## Whether every grain has come down, so an animal may come for them.
func landed() -> bool:
	return _flying == 0


func left() -> int:
	return _left


## Whether there is nothing left of it.
func gone() -> bool:
	return _left <= 0 or age >= lasts


## An animal feeding here takes a grain now and then.
func peck(delta: float) -> void:
	_eat_next -= delta
	while _eat_next <= 0.0 and _left > 0:
		_eat_next += 1.0 / PECKS
		_left -= 1
		multimesh.set_instance_transform(_order[_left], Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))


func tick(delta: float) -> void:
	if _flying > 0:
		_fly(delta)
		return
	age += delta
	if age > lasts - FADE:
		_place()


func _fly(delta: float) -> void:
	_flying = 0
	for i in GRAINS:
		if _down[i]:
			continue
		var v := _vel[i] + Vector3.DOWN * GRAVITY * delta
		var p := _at[i] + v * delta
		var under: float = _floor.call(p)
		if p.y <= under:
			p.y = under + 0.0025
			_down[i] = 1
		else:
			_flying += 1
		_at[i] = p
		_vel[i] = v
	if _flying == 0:
		var mid := Vector3.ZERO
		for p in _at:
			mid += p
		mid /= GRAINS
		position = Vector3(mid.x, _floor.call(mid), mid.z)
	_place()


func _place() -> void:
	var size := clampf((lasts - age) / FADE, 0.0, 1.0)
	var sink := (1.0 - size) * 0.006
	var eaten := {}
	for k in range(_left, GRAINS):
		eaten[_order[k]] = true
	for i in GRAINS:
		if eaten.has(i):
			continue
		multimesh.set_instance_transform(i, Transform3D(_turn[i].scaled(Vector3.ONE * size), _at[i] - position + Vector3.DOWN * sink))
