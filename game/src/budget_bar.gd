class_name BudgetBar
extends MeshInstance3D

## A bar along the back of a controller's top: how much of the frame budget the garden's builds take (Budget), on the
## most loaded headset it is shown on, so visitors see the host garden's. What the hand's tool is showing joins it in a
## paler stretch; where it would not fit, the whole bar pulses red.

const SIZE := Vector2(0.05, 0.009)
## Where it lies on the controller (Hand's body), behind the tool's model.
const AT := Vector3(0, 0.027, 0.078)
## How fast the shown fill closes on the garden's, per second.
const EASE := 12.0
const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;
uniform float fill = 0.0;
uniform float pending = 0.0;
uniform float over = 0.0;
uniform vec2 size = vec2(0.036, 0.0065);
const vec3 TRACK = vec3(0.16, 0.14, 0.12);
const vec3 CALM = vec3(0.52, 0.74, 0.42);
const vec3 NEAR = vec3(0.95, 0.68, 0.28);
const vec3 GHOST = vec3(0.98, 0.95, 0.86);
const vec3 NO = vec3(0.92, 0.3, 0.26);
void fragment() {
	vec2 p = (UV - 0.5) * size;
	float r = size.y * 0.5;
	vec2 q = abs(p) - vec2(size.x * 0.5 - r, 0.0);
	float d = length(max(q, 0.0)) - r;
	if (d > 0.0) {
		discard;
	}
	float x = UV.x;
	float inset = step(d, -size.y * 0.18);
	vec3 c = TRACK;
	float shown = clamp(fill, 0.0, 1.0);
	if (inset > 0.5 && x < shown) {
		c = mix(CALM, NEAR, smoothstep(0.7, 1.0, shown));
	} else if (inset > 0.5 && x < clamp(fill + pending, 0.0, 1.0)) {
		c = GHOST;
	}
	if (over > 0.5) {
		c = mix(c, NO, 0.65 + 0.35 * sin(TIME * 12.0));
	}
	ALBEDO = c;
}
"""

static var _shader: Shader

var world: World
var hand: Node
var _shown := 0.0
var _mat := ShaderMaterial.new()


func _init(garden: World, on: Node) -> void:
	world = garden
	hand = on
	var quad := QuadMesh.new()
	quad.size = SIZE
	quad.orientation = PlaneMesh.FACE_Y
	mesh = quad
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	_mat.shader = _shader
	_mat.set_shader_parameter("size", SIZE)
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	position = AT


func _process(delta: float) -> void:
	var now := world.fill()
	var with := world.fill(hand)
	_shown = lerpf(_shown, now, 1.0 - exp(-EASE * delta))
	_mat.set_shader_parameter("fill", _shown)
	_mat.set_shader_parameter("pending", maxf(with - now, 0.0))
	_mat.set_shader_parameter("over", 1.0 if with > 1.0 and with > now + 0.0001 else 0.0)
