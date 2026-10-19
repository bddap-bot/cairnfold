class_name Pad
extends Node3D

## A soft, rounded controller with only what every supported controller shares: a trigger under the index finger,
## a grip under the middle finger, a thumbstick and two face buttons. The picture book's ghost hands hold it; a
## pressed part sinks, swells and glows, a soft ring pulses out from it, and a held part's ring fills as the hold is
## timed, all drawn large enough to read on a page at arm's length.

const SHELL := Color(0.7, 0.77, 0.86)
const PART := Color(0.3, 0.34, 0.42)
const GLOW := Color(1.0, 0.55, 0.12)
const PULSE := 0.9
const SWELL := 1.6
const TOOL_AT := Vector3(0, 0.02, 0.07)

var side := 1.0
var parts := {}
var _rest := {}
var _mats := {}
var _rings := {}
var _pulses := {}
var _tool: Node3D
var _shown := -1
var _shell_mats: Array[StandardMaterial3D] = []


## `right` false mirrors it for the left hand. `see_through` lets a pressed trigger's glow show through the shell.
func _init(right: bool, see_through := false) -> void:
	side = 1.0 if right else -1.0
	var head := _box(self, Vector3(0.06, 0.024, 0.066), Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.032)), SHELL, 3)
	_shell_mats.append(head.material_override)
	var handle_at := Node3D.new()
	handle_at.transform = Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(0, -0.008, 0.05))
	add_child(handle_at)
	var handle := _box(handle_at, Vector3(0.031, 0.1, 0.036), Transform3D(Basis.IDENTITY, Vector3(0, -0.047, 0)), SHELL, 5)
	_shell_mats.append(handle.material_override)
	_part("trigger_click", self, Vector3(0.017, 0.03, 0.012), Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(0, -0.025, 0.012)), 7)
	_part("grip_click", handle_at, Vector3(0.012, 0.045, 0.014), Transform3D(Basis.IDENTITY, Vector3(0, -0.045, -0.022)), 9)
	_part("primary", self, Vector3(0.019, 0.008, 0.019), Transform3D(Basis.IDENTITY, Vector3(-side * 0.012, 0.017, 0.03)), 11)
	_part("ax_button", self, Vector3(0.012, 0.006, 0.012), Transform3D(Basis.IDENTITY, Vector3(side * 0.013, 0.016, 0.044)), 13)
	_part("by_button", self, Vector3(0.012, 0.006, 0.012), Transform3D(Basis.IDENTITY, Vector3(side * 0.015, 0.016, 0.024)), 15)
	if see_through:
		for m in _shell_mats:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			m.albedo_color.a = 0.42


## Shows `tool` standing on the controller, as a hand holding it does.
func hold(tool: Hand.Tool) -> void:
	if tool == _shown:
		return
	_shown = tool
	if _tool != null:
		_tool.queue_free()
		_tool = null
	if tool == Hand.Tool.BOOK:
		return
	_tool = ToolModels.build(tool)
	_tool.position = TOOL_AT
	_tool.scale = Vector3.ONE * 0.85
	add_child(_tool)


## Shows `input` (an OpenXR input as Controls names them; a stick direction tilts the stick) held for `held_s`
## seconds, or let go with a negative `held_s`. A hold `hold_s` long fills the part's ring as it goes.
func show_input(input: String, held_s: float, hold_s := 0.0) -> void:
	var key := "primary" if Hand.FLICKS.has(input) else input
	var part: Node3D = parts[key]
	var on := held_s >= 0.0
	var rest: Transform3D = _rest[key]
	var mat: StandardMaterial3D = _mats[key]
	mat.emission_enabled = on
	if on:
		var breathe := 0.75 + 0.25 * cos(held_s * TAU / PULSE)
		mat.emission = GLOW * breathe * 3.0
		mat.albedo_color = GLOW
	else:
		mat.albedo_color = PART
	match key:
		"trigger_click":
			part.transform = Transform3D(Basis(Vector3.RIGHT, -0.4 if on else 0.0), Vector3(0, 0.01, -0.004) if on else Vector3.ZERO) * rest
		"grip_click":
			part.transform = rest.translated(Vector3(side * 0.004, 0, 0.003) if on else Vector3.ZERO)
		"primary":
			var d: Vector2 = Hand.FLICKS.get(input, Vector2.ZERO) if on else Vector2.ZERO
			part.transform = Transform3D(Basis(Vector3(d.y, 0, d.x * side).normalized() if d != Vector2.ZERO else Vector3.RIGHT, -0.45 * d.length()), rest.origin) * Transform3D(rest.basis, Vector3.ZERO)
		_:
			part.transform = rest.translated(Vector3(0, -0.0025, 0) if on else Vector3.ZERO)
	if on:
		part.transform = part.transform.scaled_local(Vector3.ONE * SWELL)
	var pulse: MeshInstance3D = _pulses[key]
	pulse.visible = on
	if on:
		var k := fposmod(held_s, PULSE) / PULSE
		var m: ShaderMaterial = pulse.material_override
		m.set_shader_parameter("radius", lerpf(0.02, 0.075, k))
		m.set_shader_parameter("alpha", (1.0 - k) * 1.0)
		pulse.global_position = part.global_position
	var ring: MeshInstance3D = _rings[key]
	ring.visible = on and hold_s > 0.0
	if ring.visible:
		ring.material_override.set_shader_parameter("fill", clampf(held_s / hold_s, 0.0, 1.0))
		ring.global_position = part.global_position


func _part(key: String, parent: Node3D, size: Vector3, at: Transform3D, seed: int) -> void:
	var pivot := Node3D.new()
	pivot.transform = at
	parent.add_child(pivot)
	var mi := _box(pivot, size, Transform3D.IDENTITY, PART, seed)
	parts[key] = pivot
	_rest[key] = at
	_mats[key] = mi.material_override
	_pulses[key] = _ring(0.9, 1.0, 0.0)
	_rings[key] = _ring(1.0, 0.0, 0.35)
	_rings[key].material_override.set_shader_parameter("radius", 0.04)
	_rings[key].material_override.set_shader_parameter("width", 0.013)
	_pulses[key].material_override.set_shader_parameter("width", 0.011)


func _ring(alpha: float, fill: float, track: float) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.18, 0.18)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://src/pad_ring.gdshader")
	mat.set_shader_parameter("alpha", alpha)
	mat.set_shader_parameter("fill", fill)
	mat.set_shader_parameter("track", track)
	mat.set_shader_parameter("half_size", quad.size.x * 0.5)
	mat.render_priority = 2
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = mat
	mi.top_level = true
	mi.visible = false
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


static func _box(parent: Node3D, size: Vector3, at: Transform3D, colour: Color, seed: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.rounded_box(0.42, 3, seed)
	mi.transform = at * Transform3D(Basis.from_scale(size), Vector3.ZERO)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.55
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
