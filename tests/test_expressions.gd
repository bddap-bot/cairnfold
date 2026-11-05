extends "res://../tests/support/suite.gd"


func _init() -> void:
	_malformed()
	_controls()
	_fx()
	_bindings()
	_roundtrip()
	_wide_layers_shrink()
	_lighting()
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
	var unity: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../tests/unity/unity-curves.json"))
	for name: String in unity:
		var samples: Array = unity[name].unity
		var values := samples.map(func(at: Array) -> float: return at[1])
		var range_of: float = values.max() - values.min()
		var worst := 0.0
		for at: Array in samples:
			worst = maxf(worst, absf(ExpressionState.sample(unity[name]["keys"], at[0], false) - at[1]))
		check(samples.size() == 20 and worst <= 0.01 * range_of, "a %s curve samples as Unity does: worst %.6f of range %.3f" % [name, worst, range_of])
		check(ExpressionDefinition.valid({"targets": [{"effect": "switch"}], "clips": [{"curves": [{"target": 0, "keys": unity[name]["keys"]}]}]}), "%s keys are valid curve data" % name)
	check(not ExpressionDefinition.valid({"targets": [{"effect": "switch"}], "clips": [{"curves": [{"target": 0, "keys": [[0, 0, 1]]}]}]}), "a key with a lone slope is rejected")
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
	definition.targets.push_front({"effect": {"translation": {"node": "Hat", "direction": [0, 1, 0]}}, "default": 0.0})
	definition.clips.map(func(c: Dictionary) -> void: c.curves[0].target = 1)
	definition.shown = [{"node": "Hat", "when": [[1, 1]]}]
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


func _wide_layers_shrink() -> void:
	var wide := Image.create_empty(4096, 4096, false, Image.FORMAT_RGBA8)
	var root := Node3D.new()
	root.set_meta("expressions", {"colorAtlas": Marshalls.raw_to_base64(wide.save_png_to_buffer()), "looks": {"decals": [Marshalls.raw_to_base64(wide.save_png_to_buffer())]}})
	ExpressionPlayer.prepare(root)
	var decals: Texture2DArray = root.get_meta("expression_decals", null)
	var untinted: Texture2D = root.get_meta("expression_untinted", null)
	check(decals != null and decals.get_width() == Avatar.MAX_LAYER and untinted != null and untinted.get_width() == Avatar.MAX_LAYER, "a 4096 expression layer is held at %d: %s %s" % [Avatar.MAX_LAYER, decals.get_width() if decals else null, untinted.get_width() if untinted else null])
	root.free()


## Looks that name materials carry each one's lighting or the file is refused. A mesh that shows a flat material
## draws by the material index, held nearest-sampled at most MAX_LAYER wide, and the lighting table; one that shows only
## lit materials keeps its plain material.
func _lighting() -> void:
	var index := Image.create_empty(4096, 4096, false, Image.FORMAT_L8)
	index.fill_rect(Rect2i(0, 0, 2048, 4096), Color8(1, 1, 1))
	index.fill_rect(Rect2i(2048, 0, 2048, 4096), Color8(2, 2, 2))
	var encoded := Marshalls.raw_to_base64(index.save_png_to_buffer())
	var looks := {"index": encoded, "materials": [{"lighting": {"model": "flat", "cap": 0.8}}, {"lighting": {"model": "lit"}}]}
	check(ExpressionDefinition.valid({"looks": looks}), "looks lighting each material are valid")
	for bad: Dictionary in [{"index": encoded, "materials": [{}]}, {"index": encoded, "materials": [{"lighting": {"model": "glow"}}]}, {"index": encoded, "materials": [{"lighting": {"model": "flat", "cap": "1"}}]}, {"materials": []}]:
		check(not ExpressionDefinition.valid({"looks": bad}), "looks without a lighting for each material are refused: %s" % [bad.get("materials")])
	var root := Node3D.new()
	var meshes: Array[ImporterMesh] = []
	for u: float in [0.25, 0.75]:
		var im := ImporterMesh.new()
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(u, 0.1), Vector2(u, 0.5), Vector2(u + 0.1, 0.9)])
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, StandardMaterial3D.new())
		meshes.append(im)
	Avatar._flat_lit(looks, meshes)
	var shown: Array[MeshInstance3D] = []
	for im in meshes:
		var mi := MeshInstance3D.new()
		mi.mesh = im.get_mesh()
		root.add_child(mi)
		shown.append(mi)
	root.set_meta("expressions", {"looks": looks})
	var player := ExpressionPlayer.new(root)
	var mat := shown[0].get_surface_override_material(0) as ShaderMaterial
	var held: Texture2D = mat.get_shader_parameter("light_index") if mat else null
	var table: Texture2D = mat.get_shader_parameter("lighting") if mat else null
	check(held != null and held.get_width() == Avatar.MAX_LAYER and held.get_image().get_pixel(Avatar.MAX_LAYER / 2 - 1, 0).r8 == 1 and held.get_image().get_pixel(Avatar.MAX_LAYER / 2, 0).r8 == 2, "a mesh showing a flat material draws by the material index, held at %d without blending entries" % Avatar.MAX_LAYER)
	var rows := table.get_image() if table else null
	check(rows != null and rows.get_width() == 3 and rows.get_pixel(0, 0).r == 0.0 and rows.get_pixel(1, 0).r == 1.0 and is_equal_approx(rows.get_pixel(1, 0).g, 0.8) and rows.get_pixel(2, 0).r == 0.0, "the lighting table has no entry lit flat at zero, the flat one capped at 0.8, the lit one not flat")
	check(shown[1].get_surface_override_material(0) == null and shown[1].get_active_material(0) is StandardMaterial3D, "a mesh showing only lit materials keeps its plain material")
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
	for kind: String in ["color", "tone", "look"]:
		check(ExpressionDefinition.valid({"targets": [{"effect": {kind: [{"node": 0, "rect": [0, 0, 1, 1], "channel": 1, "slot": 2}]}}]}), "an imported %s region is a valid target" % kind)
	check(not ExpressionDefinition.valid({"targets": [{"effect": {"tone": [{"node": 0}]}}]}), "a region without its atlas rect is rejected")
	check(not ExpressionDefinition.valid({"targets": [{"effect": {"color": [{"node": 0, "rect": [0, 0, 1, 1], "channel": 3}]}}]}), "a colour region past blue is rejected")
	check(not ExpressionDefinition.valid({"targets": [{"effect": {"look": [{"node": 0, "rect": [0, 0, 1, 1], "field": "decal", "slot": 4}]}}]}), "a decal region past the fourth slot is rejected")
	for effect: Dictionary in [{"rotation": {"node": 2, "axis": 2, "rest": [-85, 0, 1]}}, {"rotation": {"node": 2, "axis": 3, "rest": [0, 0, 0, 1]}}, {"translation": {"node": 2, "direction": [-1, 0, 0]}}]:
		check(ExpressionDefinition.valid({"targets": [{"effect": effect, "default": 0.0}]}), "an imported %s target is valid" % effect.keys()[0])
	for effect: Dictionary in [{"rotation": {"node": 2, "axis": 3, "rest": [0, 0, 0]}}, {"translation": {"node": 2, "direction": [1, 0]}}]:
		check(not ExpressionDefinition.valid({"targets": [{"effect": effect, "default": 0.0}]}), "a malformed %s target is rejected" % effect.keys()[0])
	check(not ExpressionDefinition.valid({"layers": [{}]}), "a layer without states is rejected")
	var switch := [{"effect": "switch", "default": 1.0}]
	check(ExpressionDefinition.valid({"targets": switch, "springs": [{"joints": [&"tail", 3], "when": [[0, 1]]}], "colliders": [{"collider": 2, "when": [[0, 1]]}]}), "switched springs and colliders are valid")
	for bad: Dictionary in [{"springs": [{"joints": [], "when": [[0, 1]]}]}, {"springs": [{"joints": [3], "when": [[1, 1]]}]}, {"colliders": [{"collider": -1, "when": [[0, 1]]}]}, {"colliders": [{"collider": 0.5, "when": []}]}, {"colliders": [{"collider": 0}]}]:
		bad.targets = switch
		check(not ExpressionDefinition.valid(bad), "a malformed switched spring or collider is rejected: %s" % [bad])
	var invalid := _definition()
	invalid.clips[0].curves[0].target = 200
	check(not ExpressionDefinition.valid(invalid), "out-of-range animation targets are rejected")
	invalid = _definition()
	invalid.layers[0].states[0].motion.clip = -1
	check(not ExpressionDefinition.valid(invalid), "negative clip references are rejected")
	var state := ExpressionState.new({"layers": [{}]})
	state.advance(0.1)
	check(state.outputs.is_empty(), "malformed external data never enters the evaluator")
