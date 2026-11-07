class_name BudgetBar
extends MeshInstance3D

const SIZE := Vector2(0.05, 0.009)
## Where it lies on the hand's body, behind the held tool.
const AT := Vector3(0, 0.027, 0.078)
## How fast the shown fill closes on the garden's, per second.
const EASE := 12.0
## How much bigger the bar grows while what the tool shows would not fit, and at a turned-down edit's jolt.
const SWELL := 0.6
const JOLT := 2.5
## How long a jolt lasts in seconds, how fast it shakes a second, and how far, in metres.
const JOLT_SECONDS := 0.6
const SHAKE_RATE := 34.0
const SHAKE := 0.006

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
	_mat.set_shader_parameter("over", 1.0 if hand.capped or _jolt > 0.0 else 0.0)
	_jolt = move_toward(_jolt, 0.0, delta / JOLT_SECONDS)
	_swell = lerpf(_swell, 1.0 if hand.capped else 0.0, 1.0 - exp(-EASE * delta))
	scale = Vector3.ONE * (1.0 + SWELL * _swell + JOLT * _jolt * _jolt)
	position = AT + Vector3.RIGHT * sin(Time.get_ticks_msec() * 0.001 * SHAKE_RATE) * SHAKE * (_jolt + 0.25 * _swell)
