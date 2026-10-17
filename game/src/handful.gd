class_name Handful
extends MultiMeshInstance3D

## A handful of seeds thrown from the seed dish, grains larger and paler than the dish's so they read on grass and water
## from a few metres: the grains fly apart, settle where they land on the ground or float on
## a pond, and go one by one as an animal pecks at them, or shrink and sink away once they have lain a while.

const GRAINS := 28
## Metres a second the grains spread apart from the throw.
const SPREAD := 0.6
const GRAVITY := 9.8
## Seconds from landing until it is gone, the last FADE of them fading.
const LASTS := Vector2(50.0, 70.0)
const FADE := 6.0
## Grains a feeding animal takes a second.
const PECKS := 1.6

static var _grain: Mesh

var age := 0.0
var lasts := LASTS.x
var flying := 0
var _floor: Callable
var _at := PackedVector3Array()
var _vel := PackedVector3Array()
var _turn: Array[Basis] = []
var _eat_next := 0.0


func _init(floor_at: Callable) -> void:
	_floor = floor_at
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _grain == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		Meshes.ellipsoid(st, 0, Vector3.ZERO, Vector3(0.008, 0.016, 0.006), Color.WHITE, 2, 5)
		_grain = st.commit()
	multimesh = ToolModels.multimesh(_grain, GRAINS)
	material_override = ToolModels.seed_material()
	_at.resize(GRAINS)
	_vel.resize(GRAINS)
	_turn.resize(GRAINS)
	visible = false


## Throws the grains from `from` at `velocity`, each spread a little apart; whatever was left of an earlier throw goes.
func toss(from: Vector3, velocity: Vector3, rng: RandomNumberGenerator) -> void:
	position = from
	age = 0.0
	lasts = rng.randf_range(LASTS.x, LASTS.y)
	flying = GRAINS
	_eat_next = 0.0
	multimesh.visible_instance_count = GRAINS
	for i in GRAINS:
		_at[i] = from + Vector3(rng.randf_range(-0.012, 0.012), 0, rng.randf_range(-0.012, 0.012))
		_vel[i] = velocity + Vector3(rng.randfn(), rng.randfn() * 0.5, rng.randfn()) * SPREAD
		_turn[i] = Basis.from_euler(Vector3(rng.randf(), rng.randf(), rng.randf()) * TAU)
		multimesh.set_instance_color(i, ToolModels.SEED_COLOURS[0].lightened(rng.randf() * 0.5))
	visible = true
	_place()


func landed() -> bool:
	return visible and flying == 0


func left() -> int:
	return multimesh.visible_instance_count if visible else 0


func peck(delta: float) -> void:
	_eat_next -= delta
	while _eat_next <= 0.0 and left() > 0:
		_eat_next += 1.0 / PECKS
		multimesh.visible_instance_count -= 1
	visible = left() > 0


func tick(delta: float) -> void:
	if not visible:
		return
	if flying > 0:
		_fly(delta)
		return
	age += delta
	if age >= lasts:
		visible = false
	elif age > lasts - FADE:
		_place()


func _fly(delta: float) -> void:
	flying = 0
	for i in GRAINS:
		if _vel[i] == Vector3.ZERO:
			continue
		var v := _vel[i] + Vector3.DOWN * GRAVITY * delta
		var p := _at[i] + v * delta
		var under: float = _floor.call(p)
		if p.y <= under:
			p.y = under + 0.004
			v = Vector3.ZERO
		else:
			flying += 1
		_at[i] = p
		_vel[i] = v
	if flying == 0:
		var mid := Vector3.ZERO
		for p in _at:
			mid += p
		mid /= GRAINS
		position = Vector3(mid.x, _floor.call(mid), mid.z)
	_place()


func _place() -> void:
	var size := clampf((lasts - age) / FADE, 0.0, 1.0)
	var sink := Vector3.DOWN * (1.0 - size) * 0.01
	for i in GRAINS:
		multimesh.set_instance_transform(i, Transform3D(_turn[i].scaled(Vector3.ONE * size), _at[i] - position + sink))
