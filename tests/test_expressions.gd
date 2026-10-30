extends "res://../tests/support/suite.gd"


func _init() -> void:
	_malformed()
	_controls()
	_fx()
	_bindings()
	_roundtrip()
	finish()


func _definition() -> Dictionary:
	return {"parameters": [
		{"name": "Hat", "type": "bool", "default": 0.0, "saved": true},
		{"name": "Pulse", "type": "int", "default": 0.0, "saved": false},
		{"name": "Open", "type": "int", "default": 0.0, "saved": false},
		{"name": "X", "type": "float", "default": 0.0, "saved": true},
		{"name": "Y", "type": "float", "default": 0.0, "saved": true},
		{"name": "Down", "type": "float", "default": 0.0, "saved": true},
		{"name": "Left", "type": "float", "default": 0.0, "saved": true}],
		"targets": [{"effect": "switch", "default": 0.0}], "shown": [], "menu": [],
		"clips": [{"length": 1.0, "curves": [{"target": 0, "step": true, "keys": [[0, 0]]}]},
			{"length": 1.0, "curves": [{"target": 0, "step": true, "keys": [[0, 1]]}]}],
		"layers": [{"weight": 1.0, "default": 0, "states": [
			{"motion": {"clip": 0}, "transitions": [{"to": 1, "conditions": [{"parameter": "Hat", "mode": "if"}]}]},
			{"motion": {"clip": 1}, "transitions": [{"to": 0, "conditions": [{"parameter": "Hat", "mode": "ifNot"}]}]}]}]}


func _controls() -> void:
	var state := ExpressionState.new(_definition())
	var toggle := {"type": "toggle", "parameter": "Hat", "value": 1.0}
	state.activate(toggle)
	check(state.active(toggle), "toggle sets the declared value")
	state.activate(toggle)
	check(not state.active(toggle), "toggle resets to zero")
	state.activate({"type": "button", "parameter": "Pulse", "value": 7.0})
	state.advance(0.5)
	check(state.values.Pulse == 7.0, "button remains set for its pulse")
	state.advance(0.5)
	check(state.values.Pulse == 0.0, "button resets without a release edge")
	state.activate({"type": "submenu", "parameter": "Open", "value": 2.0})
	state.activate({"type": "radial", "parameter": "", "axes": ["X"]})
	state.puppet({"type": "radial", "axes": ["X"]}, Vector2.ZERO, 0.65)
	state.back()
	check(is_equal_approx(state.values.X, 0.65) and state.values.Open == 2.0, "closing a puppet keeps its value and parent gate")
	state.back()
	check(state.values.Open == 0.0, "leaving a submenu resets its gate")
	state.puppet({"type": "twoAxis", "axes": ["X", "Y"]}, Vector2(-0.3, 0.7), 0.0)
	check(is_equal_approx(state.values.X, -0.3) and is_equal_approx(state.values.Y, 0.7), "two axes use horizontal and vertical signed values")
	state.puppet({"type": "fourAxis", "axes": ["Y", "X", "Down", "Left"]}, Vector2(-0.6, -0.8), 0.0)
	check(state.values.X == 0.0 and state.values.Y == 0.0 and is_equal_approx(state.values.Down, 0.8) and is_equal_approx(state.values.Left, 0.6), "four axes map up right down left independently")
	state.put("Pulse", 999)
	state.put("X", -5)
	check(state.values.Pulse == 255 and state.values.X == -1.0, "parameter values respect their types")
	var restored := ExpressionState.new(_definition())
	restored.restore(state.saved())
	check(restored.values.X == -1 and restored.values.Pulse == 0, "only saved parameters survive an avatar reload")
	state.activate({"type": "submenu", "parameter": "Open", "value": 2.0})
	state.put("Open", 3)
	state.advance(0)
	check(state.opened.is_empty(), "an animator changing a submenu gate closes that submenu")


func _fx() -> void:
	var state := ExpressionState.new(_definition())
	state.advance(0.1)
	check(state.outputs == [0.0], "default FX state hides the target")
	state.put("Hat", 1)
	state.advance(0.1)
	check(state.outputs == [1.0], "a menu parameter transitions FX to show the target")
	state.put("Hat", 0)
	state.advance(0.1)
	check(state.outputs == [0.0], "turning the toggle off transitions back")
	check(ExpressionState.sample([[0, 0], [1, 1]], 0.25, false) == 0.25, "continuous curves interpolate")
	check(ExpressionState.sample([[0, 0], [1, 1]], 0.25, true) == 0.0, "switch curves stay stepped")
	var definition := _definition()
	definition.layers = [{"states": [{"motion": {"blend": "1d", "parameters": ["X", ""], "children": [
		{"motion": {"clip": 0}, "threshold": 0}, {"motion": {"clip": 1}, "threshold": 1}]}}]}]
	state = ExpressionState.new(definition)
	state.put("X", 0.25)
	state.advance(0.1)
	check(is_equal_approx(state.outputs[0], 0.25), "a radial drives an imported blend tree")
	definition.layers[0].weight = 0.5
	state = ExpressionState.new(definition)
	state.put("X", 1)
	for i in 100:
		state.advance(0.1)
	check(is_equal_approx(state.outputs[0], 0.5), "a half-weight layer stays half-weight over time")


func _bindings() -> void:
	var root := Node3D.new()
	var hat := Node3D.new()
	hat.name = "Hat"
	root.add_child(hat)
	var definition := _definition()
	definition.shown = [{"node": "Hat", "when": [[0, 1]]}]
	root.set_meta("expressions", definition)
	var player := ExpressionPlayer.new(root)
	player.state.advance(0)
	player.apply()
	check(not hat.visible, "the imported switch hides the actual node")
	player.state.put("Hat", 1)
	player.state.advance(0)
	player.apply()
	check(hat.visible, "the imported switch shows the actual node")
	player.free()
	root.free()


func _roundtrip() -> void:
	var scene: PackedScene = preload("res://demo/expressions.gd").scene()
	var model := scene.instantiate() as Node3D
	model.set_meta("springs", {})
	Vrm.write(model, "user://expressions.vrm")
	model.free()
	var reloaded := Avatar.read(FileAccess.get_file_as_bytes("user://expressions.vrm"))
	check(reloaded != null, "the expression fixture survives a VRM export and import")
	if reloaded == null:
		return
	var avatar := Avatar.open(reloaded, Color.WHITE)
	check(avatar.expressions != null, "VRM import keeps the expression controller")
	if avatar.expressions != null:
		avatar.expressions.state.put("Hat", 1)
		avatar.expressions.state.advance(0)
		avatar.expressions.apply()
		check(avatar.find_child("ExpressionHat", true, false).visible, "VRM node indices resolve to the runtime target")
		var hat := avatar.find_child("ExpressionHat", true, false) as MeshInstance3D
		var mat := hat.get_surface_override_material(0) as ShaderMaterial
		check(mat != null and mat.get_shader_parameter("region_count") == 3 and mat.get_shader_parameter("untinted") != null and mat.get_shader_parameter("decals") is Texture2DArray, "VRM import binds the colour, tone and decal regions and their layers to the hat")
	avatar.free()


func _malformed() -> void:
	check(ExpressionDefinition.valid({"targets": [{"effect": {"scale": {"node": &"head", "axis": 0}}, "default": 1.0}]}), "imported bone names remain valid before JSON serialization")
	for kind: String in ["color", "tone", "decal"]:
		check(ExpressionDefinition.valid({"targets": [{"effect": {kind: [{"node": 0, "rect": [0, 0, 1, 1], "channel": 1, "slot": 2}]}}]}), "an imported %s region is a valid target" % kind)
	check(not ExpressionDefinition.valid({"targets": [{"effect": {"tone": [{"node": 0}]}}]}), "a region without its atlas rect is rejected")
	check(not ExpressionDefinition.valid({"targets": [{"effect": {"color": [{"node": 0, "rect": [0, 0, 1, 1], "channel": 3}]}}]}), "a colour region past blue is rejected")
	check(not ExpressionDefinition.valid({"targets": [{"effect": {"decal": [{"node": 0, "rect": [0, 0, 1, 1], "slot": 4}]}}]}), "a decal region past the fourth slot is rejected")
	check(not ExpressionDefinition.valid({"layers": [{}]}), "a layer without states is rejected")
	var invalid := _definition()
	invalid.clips[0].curves[0].target = 200
	check(not ExpressionDefinition.valid(invalid), "out-of-range animation targets are rejected")
	invalid = _definition()
	invalid.layers[0].states[0].motion.clip = -1
	check(not ExpressionDefinition.valid(invalid), "negative clip references are rejected")
	var state := ExpressionState.new({"layers": [{}]})
	state.advance(0.1)
	check(state.outputs.is_empty(), "malformed external data never enters the evaluator")
