class_name Handful
extends MultiMeshInstance3D

## Grains larger and paler than the dish's to read from a few metres; a throw is start, velocity and seed, so copies agree.

const GRAINS := 28
const SPREAD_SPEED := 0.6
const GRAVITY := 9.8
## DRAG per second; RISE and SPREAD_UNDER metres a second.
const DRAG := 6.0
const RISE := 0.2
const SPREAD_UNDER := 1.0
## Metres, and radians a second.
const BOB := 0.003
const BOB_RATE := 2.2
## Seconds from landing until gone, the last FADE of them fading.
const LASTS := Vector2(50.0, 70.0)
const FADE := 6.0
## Grains a second.
const PECKS := 1.6
## Fixed, so every player's grains land alike however their frames fall.
const STEP := 1.0 / 240.0

static var _grain: Mesh

signal splashed(pond: PondWater, at: Vector3)

var age := 0.0
var lasts := LASTS.x
var flying := 0
var _water: Water
var _terrain: Terrain
var _splashed := false
var _afloat := false
var _at := PackedVector3Array()
var _vel := PackedVector3Array()
var _carry := 0.0
var _turn: Array[Basis] = []
var _eat_next := 0.0


func _init(water: Water, terrain: Terrain) -> void:
	_water = water
	_terrain = terrain
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


## Whatever was left of an earlier throw goes.
func toss(from: Vector3, velocity: Vector3, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	position = from
	age = 0.0
	lasts = rng.randf_range(LASTS.x, LASTS.y)
	flying = GRAINS
	_carry = 0.0
	_eat_next = 0.0
	_splashed = false
	_afloat = false
	multimesh.visible_instance_count = GRAINS
	for i in GRAINS:
		_at[i] = from + Vector3(rng.randf_range(-0.012, 0.012), 0, rng.randf_range(-0.012, 0.012))
		_vel[i] = velocity + Vector3(rng.randfn(), rng.randfn() * 0.5, rng.randfn()) * SPREAD_SPEED
		_turn[i] = Basis.from_euler(Vector3(rng.randf(), rng.randf(), rng.randf()) * TAU)
		multimesh.set_instance_color(i, ToolModels.SEED_COLOURS[0].lightened(rng.randf() * 0.5))
	visible = true
	_place()


func landed() -> bool:
	return visible and flying == 0


func left() -> int:
	return multimesh.visible_instance_count if visible else 0


func grains() -> PackedVector3Array:
	return _at.slice(0, left())


## `reach` is measured level; false if no grain is within it.
func take_near(p: Vector3, reach: float) -> bool:
	var best := -1
	for i in left():
		var d := Vector2(_at[i].x - p.x, _at[i].z - p.z).length()
		if d < reach:
			reach = d
			best = i
	if best < 0:
		return false
	var last := left() - 1
	var colour := multimesh.get_instance_color(best)
	multimesh.set_instance_color(best, multimesh.get_instance_color(last))
	multimesh.set_instance_color(last, colour)
	var at := _at[best]
	_at[best] = _at[last]
	_at[last] = at
	var turn := _turn[best]
	_turn[best] = _turn[last]
	_turn[last] = turn
	multimesh.set_instance_transform(best, multimesh.get_instance_transform(last))
	multimesh.visible_instance_count = last
	visible = last > 0
	return true


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
		_carry += delta
		while flying > 0 and _carry >= STEP:
			_carry -= STEP
			_step(STEP)
		_place()
		return
	age += delta
	if age >= lasts:
		visible = false
	elif _afloat or age > lasts - FADE:
		_place()


func _step(delta: float) -> void:
	flying = 0
	for i in GRAINS:
		if _vel[i] == Vector3.ZERO:
			continue
		var p := _at[i]
		var v := _vel[i]
		var pond := _water.pond_at(p.x, p.z)
		var surface := pond.surface_y() if pond != null else -INF
		var was := p.y
		if p.y < surface:
			var slow := Vector3.UP * RISE + (v - Vector3.UP * RISE) * exp(-DRAG * delta)
			p += Vector3.UP * RISE * delta + (v - slow) / DRAG
			v = slow
		else:
			v += Vector3.DOWN * GRAVITY * delta
			p += v * delta
		pond = _water.pond_at(p.x, p.z)
		surface = pond.surface_y() if pond != null else -INF
		var ground := _terrain.height_at(p.x, p.z)
		if was >= surface and p.y < surface:
			var turn := TAU * i / GRAINS
			v += Vector3(cos(turn), 0, sin(turn)) * SPREAD_UNDER
			if not _splashed:
				_splashed = true
				splashed.emit(pond, Vector3(p.x, surface, p.z))
		if p.y <= ground:
			p.y = ground + 0.004
			v = Vector3.ZERO if pond == null else Vector3(v.x, 0, v.z)
		if was < surface and p.y >= surface:
			p.y = surface + 0.004
			v = Vector3.ZERO
		if v != Vector3.ZERO:
			flying += 1
		_at[i] = p
		_vel[i] = v
	if flying == 0:
		var mid := Vector3.ZERO
		for p in _at:
			mid += p
		mid /= GRAINS
		position = Vector3(mid.x, _water.floor_at(mid), mid.z)
		_afloat = _splashed


func drawn(i: int) -> Vector3:
	var at := _at[i] + Vector3.DOWN * (1.0 - _size()) * 0.01
	if _afloat and flying == 0 and _water.pond_at(at.x, at.z) != null:
		at.y += sin(age * BOB_RATE + i) * BOB
	return at


func _size() -> float:
	return clampf((lasts - age) / FADE, 0.0, 1.0)


func _place() -> void:
	for i in GRAINS:
		multimesh.set_instance_transform(i, Transform3D(_turn[i].scaled(Vector3.ONE * _size()), drawn(i) - position))
