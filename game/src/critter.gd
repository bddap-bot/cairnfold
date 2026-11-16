class_name Critter
extends MeshInstance3D

## `mode`: one vertex-shader motion weight per channel, eased toward a target at `rate` per second.

static var _shared := {}

var mode := Vector4(1, 0, 0, 0)
var rate := 1.0
var coat: HandStop.Surface
## The hand it flies to or stands on, or null; that hand does not stop against it.
var hand: Node3D


func _init(kind: String, build: Callable, shader: String, blend_rate: float, phase: float, feel: HandStop.Surface) -> void:
	coat = feel
	add_to_group(HandStop.CRITTERS)
	share(kind, build, shader)
	mesh = _shared[kind]
	material_override = _shared[shader]
	rate = blend_rate
	set_instance_shader_parameter("phase", phase)
	set_instance_shader_parameter("mode", mode)


## Made as an animal arrives this costs a late frame on the Frame (21 ms for the first duck), so `prepare` makes them first.
static func share(kind: String, build: Callable, shader: String) -> void:
	if not _shared.has(kind):
		_shared[kind] = build.call()
	if not _shared.has(shader):
		var m := ShaderMaterial.new()
		m.shader = load(shader)
		assert(m.shader != null, shader)
		_shared[shader] = m


func blend(target: Vector4, delta: float) -> void:
	if mode == target:
		return
	var d := target - mode
	var step := delta * rate
	mode = target if d.length() <= step else mode + d * (step / d.length())
	set_instance_shader_parameter("mode", mode)
