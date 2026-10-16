class_name Critter
extends MeshInstance3D

## An animal drawn as one mesh whose motions run in its vertex shader, blended by `mode`: one weight per motion,
## eased toward a target at `rate` per second. Every animal of a kind shares one mesh and one material.

static var _shared := {}

var mode := Vector4(1, 0, 0, 0)
var rate := 1.0
## What a hand brushing it feels.
var coat: HandStop.Surface


## `kind` names the mesh `build` makes, once for every animal that shares it.
func _init(kind: String, build: Callable, shader: String, blend_rate: float, phase: float, feel: HandStop.Surface) -> void:
	coat = feel
	add_to_group(HandStop.CRITTERS)
	if not _shared.has(kind):
		_shared[kind] = build.call()
	if not _shared.has(shader):
		var m := ShaderMaterial.new()
		m.shader = load(shader)
		_shared[shader] = m
	mesh = _shared[kind]
	material_override = _shared[shader]
	rate = blend_rate
	set_instance_shader_parameter("phase", phase)
	set_instance_shader_parameter("mode", mode)


func blend(target: Vector4, delta: float) -> void:
	if mode == target:
		return
	var d := target - mode
	var step := delta * rate
	mode = target if d.length() <= step else mode + d * (step / d.length())
	set_instance_shader_parameter("mode", mode)
