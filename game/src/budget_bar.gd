class_name BudgetBar
extends MeshInstance3D

const SIZE := Vector2(0.05, 0.009)
## On the hand's body, behind the held tool.
const AT := Vector3(0, 0.027, 0.078)
const EASE := 12.0
const SWELL := 0.6
const JOLT := 2.5
const JOLT_SECONDS := 0.6
const SHAKE_RAD_PER_S := 34.0
const SHAKE_METRES := 0.006

var world: World
var hand: Hand
var _shown := 0.0
var _mat := ShaderMaterial.new()
var _swell := 0.0
var _jolt := 0.0


func _init(garden: World, on: Hand) -> void:
	world = garden
	hand = on
	var quad := QuadMesh.new()
	quad.size = SIZE
	quad.orientation = PlaneMesh.FACE_Y
	mesh = quad
	_mat.shader = preload("res://src/budget_bar.gdshader")
	_mat.set_shader_parameter("size", SIZE)
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	position = AT
	visible = false
	world.capped.connect(func(h: XRController3D) -> void:
		if h == hand:
			_jolt = 1.0)


func _process(delta: float) -> void:
	var placing := not world.pending(hand).is_empty()
	var now := world.fill()
	if not visible and placing:
		_shown = now
	visible = placing
	if not placing:
		_swell = 0.0
		_jolt = 0.0
		return
	_shown = lerpf(_shown, now, 1.0 - exp(-EASE * delta))
	_mat.set_shader_parameter("fill", _shown)
	_mat.set_shader_parameter("pending", maxf(world.fill(hand) - now, 0.0))
	var capped := hand.capped()
	_mat.set_shader_parameter("over", 1.0 if capped or _jolt > 0.0 else 0.0)
	_jolt = move_toward(_jolt, 0.0, delta / JOLT_SECONDS)
	_swell = lerpf(_swell, 1.0 if capped else 0.0, 1.0 - exp(-EASE * delta))
	scale = Vector3.ONE * (1.0 + SWELL * _swell + JOLT * _jolt * _jolt)
	position = AT + Vector3.RIGHT * sin(Time.get_ticks_msec() * 0.001 * SHAKE_RAD_PER_S) * SHAKE_METRES * (_jolt + 0.25 * _swell)
