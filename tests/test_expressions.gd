extends "res://../tests/support/suite.gd"


func _init() -> void:
	_malformed()
	_controls()
	_fx()
	_bindings()
	_bones_turn_and_shift()
	_node_effects_roundtrip()
	_roundtrip()
	_looks_need_their_index()
	_layers_follow_the_budget()
	_decals_share_pages()
	_moving_targets_leave_regions_bound()
	_lighting()
	_sides()
	_theme_recolours_the_emission()
	_animated_parameters()
	_contacts()
	_clear_coat()
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
	var layered := _definition()
	layered.clips.append({"length": 1.0, "curves": []})
	layered.layers.append({"weight": 1.0, "default": 0, "states": [
		{"motion": {"clip": 2}, "transitions": [{"to": 1, "conditions": [{"parameter": "Down", "mode": "greater", "threshold": 0.5}]}]},
		{"motion": {"clip": 0}, "transitions": [{"to": 0, "conditions": [{"parameter": "Down", "mode": "less", "threshold": 0.5}]}]}]})
	state = ExpressionState.new(layered)
	state.put("Hat", 1)
	state.advance(0.1)
	check(state.outputs == [1.0], "a later layer whose state writes defaults but not the target leaves an earlier layer's value")
	state.put("Down", 1)
	state.advance(0.1)
	check(state.outputs == [0.0], "and overrides it once its state animates the target")
	check(ExpressionState.sample([[0, 0], [1, 1]], 0.25, false) == 0.25, "continuous curves interpolate")
	check(ExpressionState.sample([[0, 0], [1, 1]], 0.25, true) == 0.0, "switch curves stay stepped")
	var timed := _definition()
	timed.clips = [{"length": 0.06666667, "curves": [{"target": 0, "step": true, "keys": [[0, 0], [0.016666668, 1], [0.033333335, 2], [0.05, 3]]}]}]
	timed.layers = [{"weight": 1.0, "default": 0, "states": [{"motion": {"clip": 0, "time": "X"}, "transitions": []}]}]
	var tone := ExpressionState.new(timed)
	var picked: Array[float] = []
	for at: float in [0.0, 0.25, 0.5, 0.75]:
		tone.put("X", at)
		tone.advance(0.1)
		picked.append(tone.outputs[0])
	check(picked == [0.0, 1.0, 2.0, 3.0], "a motion-time radial over a four-frame clip picks each key at its quarter, as Unity does: %s" % [picked])
	check(ExpressionState.sample([[0, 0], [1, 1]], 1.0 - 1e-6, true) == 0.0, "a time a microsecond short of a key is before it")
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
	definition = _definition()
	definition.targets[0].default = 0.5
	definition.clips.append({"length": 1.0, "curves": [{"target": 0, "step": false, "keys": [[0, 2]]}]})
	definition.clips.append({"length": 1.0, "curves": []})
	definition.layers = [{"default": 0, "entry": [], "any": [], "states": [{"motion": {"clip": 1}, "transitions": []}]}, {"default": 0, "entry": [], "any": [], "states": [{"motion": {"blend": "1d", "parameters": ["X", ""], "children": [
		{"motion": {"clip": 3}, "threshold": 0, "parameter": ""}, {"motion": {"clip": 2}, "threshold": 1, "parameter": ""}]}, "transitions": []}]}]
	state = ExpressionState.new(definition)
	state.advance(0.1)
	var resting := state.outputs[0]
	state.put("X", 0.5)
	state.advance(0.1)
	check(resting == 1.0 and is_equal_approx(state.outputs[0], 1.25), "a 1D tree leaves a target only its child at no weight animates to the layer below, and blends one its playing child animates from the default: %s, %s" % [resting, state.outputs[0]])
	definition.layers[1].states[0].motion.blend = "direct"
	definition.layers[1].states[0].motion.children[0].parameter = "Y"
	definition.layers[1].states[0].motion.children[1].parameter = "X"
	state = ExpressionState.new(definition)
	state.put("Y", 1)
	state.put("X", 0.25)
	state.advance(0.1)
	check(is_equal_approx(state.outputs[0], 0.5), "a direct tree's playing child that keys nothing adds nothing: %s" % state.outputs[0])
	definition = _definition()
	definition.layers = [{"default": 0, "entry": [], "any": [{"to": 1, "conditions": [{"mode": "if", "parameter": "Hat"}]}], "states": [
		{"transitions": []}, {"motion": {"clip": 1}, "transitions": [{"to": -1, "conditions": [{"mode": "ifNot", "parameter": "Hat"}]}]}]}]
	state = ExpressionState.new(definition)
	state.put("Hat", 1)
	state.advance(0.1)
	var on := state.outputs[0]
	state.put("Hat", 0)
	state.advance(0.1)
	check(on == 1.0 and state.outputs[0] == 0.0 and state.states[0] == 0, "a toggle that leaves its state through the exit returns through the entry to the default state: %s, %s in %d" % [on, state.outputs[0], state.states[0]])
	definition.layers.append({"default": 0, "entry": [], "any": [{"to": 1, "conditions": [{"mode": "if", "parameter": "Pulse"}]}], "states": [
		{"transitions": []}, {"motion": {"clip": 0}, "transitions": [{"to": -1, "conditions": [{"mode": "ifNot", "parameter": "Pulse"}]}]}]})
	state = ExpressionState.new(definition)
	state.put("Hat", 1)
	state.advance(0.1)
	on = state.outputs[0]
	state.put("Hat", 0)
	state.advance(0.1)
	check(on == 1.0 and state.outputs[0] == 0.0, "a later layer resting in a state without a motion leaves an earlier layer's toggle on, and its own reset off: %s, %s" % [on, state.outputs[0]])
	state.put("Hat", 1)
	state.put("Pulse", 1)
	state.advance(0.1)
	check(state.outputs[0] == 0.0, "a later layer playing its clip overrides the earlier one: %s" % state.outputs[0])
	definition.layers.pop_back()
	definition.layers[0].states[0].writeDefaults = false
	definition.layers[0].states[1].writeDefaults = false
	state = ExpressionState.new(definition)
	state.put("Hat", 1)
	state.advance(0.1)
	state.put("Hat", 0)
	state.advance(0.1)
	check(state.outputs[0] == 1.0 and state.states[0] == 0, "a state without a motion that writes no defaults holds what the layer last wrote: %s" % state.outputs[0])
	definition.layers[0].states[0].erase("writeDefaults")
	definition.layers[0].states[1].erase("writeDefaults")
	definition.layers[0].entry = [{"to": -1, "conditions": []}, {"to": 1, "conditions": [{"mode": "if", "parameter": "Pulse"}]}]
	definition.layers[0].any = []
	state = ExpressionState.new(definition)
	state.put("Pulse", 1)
	state.advance(0.1)
	check(state.states[0] == 1, "an entry transition to the exit is passed over for the next that holds: in %d" % state.states[0])
	definition = _definition()
	definition.layers[0].states[0].transitions = [{"to": 1, "exitTime": 0.5}]
	state = ExpressionState.new(definition)
	state.advance(0.25)
	var early := state.states[0]
	state.advance(0.5)
	check(early == 0 and state.states[0] == 1, "a transition with an exit time waits for its state to play that far: in %d, then %d" % [early, state.states[0]])


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


func _layers_follow_the_budget() -> void:
	var wide := Image.create_empty(4096, 4096, false, Image.FORMAT_RGBA8)
	var full := 4096 * 4096 * 4 * 4 / 3
	check(Avatar.shrink_for(full, full) == 1 and Avatar.shrink_for(full, full / 4) == 2 and Avatar.shrink_for(full, full / 5) == 4, "an avatar's textures shrink by halves only until they fit its budget: %d %d %d" % [Avatar.shrink_for(full, full), Avatar.shrink_for(full, full / 4), Avatar.shrink_for(full, full / 5)])
	check(Avatar.meminfo_available() > 0 and Avatar.meminfo_available() <= OS.get_memory_info().physical, "the memory available is read from the kernel, as on Android where Godot reports none: %d of %d" % [Avatar.meminfo_available(), OS.get_memory_info().physical])
	var held := Avatar.launch_memory
	Avatar.launch_memory = Avatar.MEMORY_FLOOR + (Session.MAX_PLAYERS - 1) * (8 << 20)
	check(Avatar.texture_budget() == 8 << 20, "the budget is the memory available at launch above the floor, shared among the other players, whatever is available now: %d" % Avatar.texture_budget())
	Avatar.launch_memory = held
	for shrink: int in [1, 4]:
		for layer: String in Vrm.LAYERS:
			var layered := wide.duplicate() as Image
			Avatar.hold(layered, layer, shrink)
			var side := Avatar.INDEX_SIDE if layer == "index" else int(Avatar.ICON_SIDE) if layer == "icons" else 4096 / shrink
			check(layered.get_width() == side and layered.has_mipmaps() == (layer not in Avatar.UNSHRUNK and layer != "hueMask"), "a 4096 %s shrunk %d times is held at %d: %d" % [layer, shrink, side, layered.get_width()])


func _decals_share_pages() -> void:
	var sized := func(side: int, colour: Color) -> Image:
		var img := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
		img.fill(colour)
		return img
	var region := func(image: int) -> Dictionary: return {"effect": {"look": [{"node": "Body", "rect": [0, 0, 1, 1], "field": "decal", "slot": 0, "colorBlend": 0, "image": image}]}}
	var root := Node3D.new()
	root.set_meta("expressions", {"targets": [region.call(0), region.call(2), region.call(3)], "looks": {"decals": [sized.call(64, Color.RED), sized.call(4096, Color.WHITE), sized.call(16, Color.GREEN), sized.call(16, Color.BLUE)]}})
	ExpressionPlayer.prepare(root)
	var body: Dictionary = root.get_meta("expression_decal_sets", {}).get("Body", {})
	var pages: Texture2DArray = body.get("decals")
	var places: Dictionary = body.get("places", {})
	check(pages != null and pages.get_layers() == 2 and pages.get_width() == 64 + 2 * ExpressionPlayer.DECAL_PAD, "the decals a mesh draws lie on pages as wide as the widest of them, an undrawn one on none: %s" % [[pages.get_layers(), pages.get_width()] if pages else null])
	check(places.keys().size() == 3 and not places.has(1) and places[2][0] == places[3][0] and places[0][0] != places[2][0], "each drawn decal has its page, the small two sharing one: %s" % [places])
	var laid := ExpressionPlayer._pages({0: sized.call(64, Color.RED), 3: sized.call(16, Color.BLUE)})
	var place: Array = laid.places[3]
	var centre := Vector2((place[1] + place[3]) / 2.0, (place[2] + place[4]) / 2.0) * 80
	check((laid.images[place[0]] as Image).get_pixelv(Vector2i(centre)).is_equal_approx(Color.BLUE), "a decal's place on its page holds it")
	check(not (root.get_meta("expressions").looks as Dictionary).has("decals"), "the decal images leave the model once laid on pages")
	root.free()


## Looks that name materials carry each one's lighting, and any emission a colour and strength, or the file is
## refused. A mesh that shows a flat or glowing material draws by the material index, held nearest-sampled at most
## INDEX_SIDE wide, the looks table and the emission map; one that shows only lit materials, dark at rest, keeps its own.
func _lighting() -> void:
	var index := Image.create_empty(4096, 4096, false, Image.FORMAT_L8)
	index.fill_rect(Rect2i(0, 0, 2048, 4096), Color8(1, 1, 1))
	index.fill_rect(Rect2i(2048, 0, 1536, 4096), Color8(2, 2, 2))
	index.fill_rect(Rect2i(3584, 0, 512, 4096), Color8(3, 3, 3))
	var encoded := index.duplicate() as Image
	Avatar.hold(encoded, "index", 1)
	var glow := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	glow.fill(Color.WHITE)
	var looks := {"index": encoded, "emission": glow, "materials": [{"lighting": {"model": "flat", "cap": 0.8}}, {"lighting": {"model": "lit"}, "emission": {"color": [0.0, 0.5, 1.0], "strength": 2.0, "hue": 0.0, "shiftsHue": false, "replace": 0.5}}, {"lighting": {"model": "lit"}, "emission": {"color": [1.0, 1.0, 1.0], "strength": 0.0, "hue": 0.0, "shiftsHue": false}}]}
	check(ExpressionDefinition.valid({"looks": looks}), "looks lighting each material are valid")
	for bad: Dictionary in [{"index": encoded, "materials": [{}]}, {"index": encoded, "materials": [{"lighting": {"model": "glow"}}]}, {"index": encoded, "materials": [{"lighting": {"model": "flat", "cap": "1"}}]}, {"index": encoded, "materials": [{"lighting": {"model": "lit", "ramp": [1.0]}}]}, {"index": encoded, "materials": [{"lighting": {"model": "lit", "ramp": [0.0, 1.0], "shadowTint": "0.5"}}]}, {"index": "a PNG", "materials": []}, {"index": encoded, "materials": [{"lighting": {"model": "lit"}, "emission": {"color": [1, 1], "strength": 1}}]}, {"index": encoded, "materials": [{"lighting": {"model": "lit"}, "emission": {"color": [1, 1, 1], "strength": 1, "replace": "1"}}]}]:
		check(not ExpressionDefinition.valid({"looks": bad}), "looks without a lighting for each material are refused: %s" % [bad.get("materials")])
	var root := Node3D.new()
	var meshes: Array[ImporterMesh] = []
	for u: float in [0.25, 0.75, 0.88]:
		var im := ImporterMesh.new()
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(u, 0.1), Vector2(u, 0.5), Vector2(u + 0.1, 0.9)])
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, StandardMaterial3D.new())
		meshes.append(im)
	Avatar._lit_looks(looks, meshes)
	var shown: Array[MeshInstance3D] = []
	for im in meshes:
		var mi := MeshInstance3D.new()
		mi.mesh = im.get_mesh()
		root.add_child(mi)
		shown.append(mi)
	root.set_meta("expressions", {"looks": looks})
	ExpressionPlayer.prepare(root)
	var player := ExpressionPlayer.new(root)
	var mat := shown[0].get_surface_override_material(0) as ShaderMaterial
	var held: Texture2D = mat.get_shader_parameter("light_index") if mat else null
	var table: Texture2D = mat.get_shader_parameter("lighting") if mat else null
	check(held != null and held.get_width() == Avatar.INDEX_SIDE and held.get_image().get_pixel(Avatar.INDEX_SIDE / 2 - 1, 0).r8 == 1 and held.get_image().get_pixel(Avatar.INDEX_SIDE / 2, 0).r8 == 2, "a mesh showing a flat material draws by the material index, held at %d without blending entries" % Avatar.INDEX_SIDE)
	var rows := table.get_image() if table else null
	check(rows != null and rows.get_width() == 4 and rows.get_pixel(0, 0).r == 0.0 and rows.get_pixel(1, 0).r == 1.0 and is_equal_approx(rows.get_pixel(1, 0).g, 0.8) and rows.get_pixel(2, 0).r == 0.0, "the lighting table has no entry lit flat at zero, the flat one capped at 0.8, the lit one not flat")
	check(rows != null and rows.get_height() == 2 + Avatar.RAMP and rows.get_pixel(1, 1) == Color(0, 0, 0, 0) and rows.get_pixel(2, 1).is_equal_approx(Color(0.0, 1.0, 2.0, 0.5)), "the table's second row holds each entry's emission colour times its strength, and how far it overrides the lit colour")
	var lit := shown[1].get_surface_override_material(0) as ShaderMaterial
	check(lit != null and lit.get_shader_parameter("glow") is Texture2D, "a mesh showing a glowing material draws by the looks with their emission map")
	check(shown[2].get_surface_override_material(0) == null and shown[2].get_active_material(0) is StandardMaterial3D, "a mesh showing only lit materials dark at rest keeps its plain material")
	player.free()
	root.free()

## An animated surface draws the sides its plain material draws: both where its file is double-sided, front faces only
## where it is not, whether cut out, blended or blended writing depth, its decal hues turned or not.
func _sides() -> void:
	for turned: bool in [false, true]:
		for blend: Array in [[BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR, false], [BaseMaterial3D.TRANSPARENCY_ALPHA, false], [BaseMaterial3D.TRANSPARENCY_ALPHA, true]]:
			for cull: int in [BaseMaterial3D.CULL_BACK, BaseMaterial3D.CULL_DISABLED]:
				var m := StandardMaterial3D.new()
				m.cull_mode = cull
				m.transparency = blend[0]
				m.set_meta("extras", {"depthWrite": blend[1]})
				Avatar._plain(m)
				var code := ExpressionPlayer.shader_for(m, turned).code
				var mode := "cull_disabled" if cull == BaseMaterial3D.CULL_DISABLED else "cull_back"
				check(mode in code and ("BLENDED" in code) == (blend[0] == BaseMaterial3D.TRANSPARENCY_ALPHA) and ("depth_draw_always" in code) == blend[1] and ("DECAL_HUE" in code) == turned, "a %s material, blended %s writing depth %s, hues turned %s, animates with %s" % ["two-sided" if cull == BaseMaterial3D.CULL_DISABLED else "one-sided", blend[0] == BaseMaterial3D.TRANSPARENCY_ALPHA, blend[1], turned, mode])


## A clip moving a global theme colour's offset recolours the emission drawn in it on the meshes the clip names, through
## their own copy of the looks table, the rest keeping the colour at rest, and a material keeps its own offset while the
## clip rests, and at the value its FX default state animates; a theme whose hue turns at rest turns on every mesh, as
## time passes.
func _theme_recolours_the_emission() -> void:
	var index := Image.create_empty(4, 4, false, Image.FORMAT_L8)
	index.fill_rect(Rect2i(0, 0, 2, 4), Color8(1, 1, 1))
	index.fill_rect(Rect2i(2, 0, 2, 4), Color8(2, 2, 2))
	var glow := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	glow.fill(Color.WHITE)
	var theme := {"slot": 1, "hsv": [0.0, 1.0, 1.0], "exposure": 2.0, "hue": 0.0, "saturation": 0.0, "value": 0.0, "speed": 0.0}
	var turning := theme.merged({"slot": 0, "speed": 1.0}, true)
	var looks := {"index": index, "emission": glow, "materials": [
		{"rect": [0.0, 0.0, 0.5, 1.0], "lighting": {"model": "lit"}, "emission": {"color": [2.0, 0.0, 0.0], "strength": 1.5, "hue": 0.0, "shiftsHue": false, "replace": 0.25, "theme": 1}, "themes": [null, theme, null, null]},
		{"rect": [0.5, 0.0, 1.0, 1.0], "lighting": {"model": "lit"}, "emission": {"color": [2.0, 0.0, 0.0], "strength": 1.0, "hue": 0.0, "shiftsHue": false, "replace": 0.0, "theme": 0}, "themes": [turning, null, null, null]}]}
	check(ExpressionDefinition.valid({"looks": looks}), "looks whose emissions name their themes are valid")
	for bad: Variant in [[null, null, null, null], [null, {"slot": 1, "hsv": [0, 1]}, null, null], "themes"]:
		var broken := looks.duplicate(true)
		broken.materials[0].themes = bad
		check(not ExpressionDefinition.valid({"looks": broken}), "an emission naming a theme its look does not carry whole is refused: %s" % [bad])
	var root := Node3D.new()
	var shown: Array[MeshInstance3D] = []
	var meshes: Array[ImporterMesh] = []
	for u: float in [0.2, 0.2, 0.7]:
		var im := ImporterMesh.new()
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(u, 0.2), Vector2(u + 0.1, 0.2), Vector2(u, 0.8)])
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, StandardMaterial3D.new())
		meshes.append(im)
	Avatar._lit_looks(looks, meshes)
	for n in 3:
		var mi := MeshInstance3D.new()
		mi.name = ["Suit", "Shoes", "Lamp"][n]
		mi.mesh = meshes[n].get_mesh()
		root.add_child(mi)
		shown.append(mi)
	var region := func(field: String) -> Dictionary: return {"look": [{"node": "Suit", "rect": [0.0, 0.0, 0.5, 1.0], "field": field, "slot": 1}]}
	var targets := [{"effect": region.call("themeHue"), "default": 0.5}, {"effect": region.call("themeSpeed"), "default": 0.0}, {"effect": region.call("themeValue"), "default": 0.0}]
	var resting := {"length": 1.0, "curves": [{"target": 2, "keys": [[0, -0.5]]}]}
	root.set_meta("expressions", {"parameters": [], "targets": targets, "clips": [resting], "layers": [{"weight": 1.0, "default": 0, "states": [{"motion": {"clip": 0}, "transitions": []}]}], "shown": [], "menu": [], "looks": looks})
	ExpressionPlayer.prepare(root)
	var player := ExpressionPlayer.new(root)
	var entry := func(mesh: MeshInstance3D, column: int) -> Color:
		var mat := mesh.get_surface_override_material(0) as ShaderMaterial
		var table: Variant = mat.get_shader_parameter("lighting") if mat else null
		for glows: Dictionary in player._glows.values():
			if glows.texture == table:
				return glows.table.get_pixel(column, 1)
		return (table as Texture2D).get_image().get_pixel(column, 1) if table is Texture2D else Color(-1, -1, -1, -1)
	player.apply()
	check(entry.call(shown[0], 1).is_equal_approx(Color(3.0, 0.0, 0.0, 0.25)), "while the clip rests at another material's offset, the theme keeps its own and glows as the converter left it, times its strength: %s" % [entry.call(shown[0], 1)])
	player.state.advance(0.1)
	player.apply()
	check(entry.call(shown[0], 1).is_equal_approx(Color(1.5, 0.0, 0.0, 0.25)), "a theme offset the FX controller's default state animates glows at its animated value, not the one its material saves: %s" % [entry.call(shown[0], 1)])
	player.state.outputs[0] = 1.0 / 3.0
	player.state.outputs[2] = -0.5
	player.apply()
	check(entry.call(shown[0], 1).is_equal_approx(Color(0.0, 1.5, 0.0, 0.25)), "a third of a turn of hue and half its value make the red glow a darker green: %s" % [entry.call(shown[0], 1)])
	check(entry.call(shown[1], 1).is_equal_approx(Color(3.0, 0.0, 0.0, 0.25)), "a mesh the clip does not name keeps the colour at rest: %s" % [entry.call(shown[1], 1)])
	check(ExpressionPlayer.theme_colour(theme, 0.0).is_equal_approx(Color(2.0, 0.0, 0.0)), "a theme at rest shows its own colour")
	player.state.outputs[0] = 0.5
	player.state.outputs[1] = 1.0
	player.state.outputs[2] = 0.0
	player.apply()
	player._seconds = 20.0 / 3.0
	player.apply()
	check(entry.call(shown[0], 1).is_equal_approx(Color(0.0, 3.0, 0.0, 0.25)), "a hue speed of one turns the hue once every twenty seconds, as Unity's _Time.x: %s" % [entry.call(shown[0], 1)])
	for mesh: MeshInstance3D in [shown[0], shown[2]]:
		check(entry.call(mesh, 2).is_equal_approx(Color(0.0, 2.0, 0.0, 0.0)), "a theme turning at rest turns on %s, which no clip names, and on a mesh with its own table: %s" % [mesh.name, entry.call(mesh, 2)])
	var original: Texture2D = meshes[2].get_surface_material(0).get_meta("lighting")
	var lamp := shown[2].get_surface_override_material(0) as ShaderMaterial
	check(lamp != null and lamp.get_shader_parameter("lighting") != original, "the player turns its own copy of the looks table, never the one every avatar opened from the scene shares")
	root.free()
	player.free()



## A look's clear coat carries its levels, tints, maps' tiling and offset, inversions and a map among the looks', or
## the file is refused. Only a mesh showing a coated material draws with the shaders that draw a coat, by the looks
## table's coat rows and the coat maps; a region moving its maps' offset reaches that mesh alone.
func _clear_coat() -> void:
	var index := Image.create_empty(4, 4, false, Image.FORMAT_L8)
	index.fill_rect(Rect2i(0, 0, 2, 4), Color8(1, 1, 1))
	index.fill_rect(Rect2i(2, 0, 2, 4), Color8(2, 2, 2))
	var map := Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)
	map.fill(Color.WHITE)
	var coat := {"strength": 0.87, "smoothness": 0.92, "reflection": 1.0, "specular": 0.5, "fresnel": 1.0, "gsaa": [0.15, 0.1], "specularTint": [1.0, 1.0, 1.0], "reflectionTint": [1.0, 0.5, 1.0], "st": [1.0, 1.0, 0.0, 0.22], "inverts": [false, false, false, true], "map": 0}
	Avatar.hold(index, "index", 1)
	var looks := {"index": index, "clearcoatMaps": [map], "materials": [{"lighting": {"model": "lit"}, "clearcoat": coat}, {"lighting": {"model": "flat", "cap": 1.0}}]}
	check(ExpressionDefinition.valid({"looks": looks}), "looks with a clear coat are valid")
	for bad: Variant in [{"strength": 1.0}, coat.merged({"map": 0.5}, true), coat.merged({"st": [1, 1, 0]}, true), coat.merged({"inverts": [0, 0, 0, 0]}, true), coat.merged({"specularTint": "white"}, true), coat.merged({"gsaa": [0.15]}, true)]:
		var broken := looks.duplicate(true)
		broken.materials[0].clearcoat = bad
		check(not ExpressionDefinition.valid({"looks": broken}), "a malformed clear coat is refused: %s" % [bad])
	var root := Node3D.new()
	var meshes: Array[ImporterMesh] = []
	for u: float in [0.2, 0.7]:
		var im := ImporterMesh.new()
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(u, 0.1), Vector2(u, 0.5), Vector2(u + 0.1, 0.9)])
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, StandardMaterial3D.new())
		meshes.append(im)
	Avatar._lit_looks(looks, meshes)
	var shown: Array[MeshInstance3D] = []
	for k in meshes.size():
		var mi := MeshInstance3D.new()
		mi.name = ["Wet", "Dry"][k]
		mi.mesh = meshes[k].get_mesh()
		root.add_child(mi)
		shown.append(mi)
	var wet := {"effect": {"look": [{"node": "Wet", "rect": [0, 0, 0.5, 1], "field": "clearcoatST", "slot": 3}, {"node": "Dry", "rect": [0, 0, 0.5, 1], "field": "clearcoatST", "slot": 3}]}, "default": 0.22}
	root.set_meta("expressions", {"looks": looks, "parameters": [], "targets": [wet], "clips": [], "layers": [], "shown": [], "menu": []})
	ExpressionPlayer.prepare(root)
	var player := ExpressionPlayer.new(root)
	player.apply()
	var coated := shown[0].get_surface_override_material(0) as ShaderMaterial
	var dry := shown[1].get_surface_override_material(0) as ShaderMaterial
	check(coated != null and coated.shader.resource_path.ends_with("expression_coat.gdshader"), "a mesh showing a coated material draws with the shader that draws a coat")
	check(dry != null and dry.shader.resource_path.ends_with("expression.gdshader"), "one showing none draws as it did")
	var rows: Image = (coated.get_shader_parameter("lighting") as Texture2D).get_image() if coated else null
	check(rows != null and rows.get_height() == 2 + Avatar.RAMP + Avatar.COAT_ROWS and rows.get_pixel(1, 2 + Avatar.RAMP).is_equal_approx(Color(0.87, 0.92, 1.0, 0.5)) and rows.get_pixel(1, 3 + Avatar.RAMP).is_equal_approx(Color(1, 1, 0, 0.22)) and rows.get_pixel(1, 5 + Avatar.RAMP).is_equal_approx(Color(1, 0.5, 1, 0)) and rows.get_pixel(1, 6 + Avatar.RAMP) == Color(0, 0, 0, 1), "the looks table carries the coat's levels, tiling and offset, reflection tint with its map's layer, and inversions")
	check(coated != null and coated.get_shader_parameter("coat_maps") is Texture2DArray and (coated.get_shader_parameter("coat_maps") as Texture2DArray).get_layers() == 1, "the coat maps are bound as one layer each")
	check(coated != null and coated.get_shader_parameter("region_count") == 1, "a region moving the coat maps' offset reaches the coated mesh")
	check(dry != null and dry.get_shader_parameter("region_count") in [null, 0], "and not a mesh that draws no coat")
	player.free()
	root.free()

func _moving_targets_leave_regions_bound() -> void:
	var model := Node3D.new()
	var hat := MeshInstance3D.new()
	hat.name = "Hat"
	hat.mesh = BoxMesh.new()
	model.add_child(hat)
	var colour := {"effect": {"color": [{"node": "Hat", "rect": [0, 0, 1, 1], "channel": 0, "color": [1, 1, 1]}]}, "default": 1.0}
	var turn := {"effect": {"rotation": {"node": "Hat", "axis": 0, "rest": [0, 0, 0]}}, "default": 0.0}
	model.set_meta("expressions", {"parameters": [], "targets": [turn, colour], "clips": [], "layers": [], "shown": [], "menu": []})
	var player := ExpressionPlayer.new(model)
	player.apply()
	var mat := hat.get_surface_override_material(0) as ShaderMaterial
	check(mat != null and mat.get_shader_parameter("region_count") == 1, "a rotation target before a colour region leaves the region bound")
	check(mat != null and mat.get_shader_parameter("decals") is Texture2DArray, "a material whose model draws no decals still binds a decal array, which left unbound fails its uniform set and draws nothing")
	player.free()
	model.free()


func _bones_turn_and_shift() -> void:
	var root := Node3D.new()
	var skeleton := Skeleton3D.new()
	root.add_child(skeleton)
	var rest := Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(0, 0.5, 0))
	for bone: String in ["wing", "tail"]:
		skeleton.add_bone(bone)
		skeleton.set_bone_rest(skeleton.find_bone(bone), rest)
	skeleton.set_bone_parent(skeleton.find_bone("tail"), skeleton.find_bone("wing"))
	skeleton.reset_bone_poses()
	var tail := skeleton.find_bone("tail")
	var held := Quaternion(Vector3.UP, 1.0)
	skeleton.set_bone_pose_rotation(tail, held)
	var definition := _definition()
	for axis in 3:
		definition.targets.append({"effect": {"rotation": {"node": "wing", "axis": axis, "rest": [0, 0, 0]}}, "default": [0.0, 90.0, 0.0][axis]})
	definition.targets.append({"effect": {"translation": {"node": "tail", "direction": [0, 1, 0]}}, "default": 0.25})
	root.set_meta("expressions", definition)
	var player := ExpressionPlayer.new(root)
	player.state.advance(0)
	player.apply()
	var wing := skeleton.get_bone_pose_rotation(skeleton.find_bone("wing"))
	var expected := rest.basis.get_rotation_quaternion() * Quaternion(Vector3.UP, -PI / 2)
	check(wing.is_equal_approx(expected) or wing.is_equal_approx(-expected), "a Unity turn of 90 degrees about Y turns the bone's glTF rotation from its rest by -90 degrees about Y: %s, expected %s" % [wing, expected])
	check(skeleton.get_bone_pose_position(tail).is_equal_approx(Vector3(0, 0.75, 0)), "a translation moves the bone from its rest along its direction: %s" % skeleton.get_bone_pose_position(tail))
	check(skeleton.get_bone_pose_rotation(tail).is_equal_approx(held), "a bone only translated keeps the rotation it was given")
	var springs := ExpressionPlayer.SpringRuntime.new({"colliders": [], "springs": [{"colliders": [], "center": -1, "joints": [{"node": 0, "radius": 0.0, "stiffness": 1.0, "drag": 0.4, "gravity": Vector3.ZERO}, {"node": 1, "radius": 0.0, "stiffness": 1.0, "drag": 0.4, "gravity": Vector3.ZERO}]}]},
		{0: ExpressionPlayer.SkeletonBone.new(skeleton, skeleton.find_bone("wing")), 1: ExpressionPlayer.SkeletonBone.new(skeleton, tail)})
	check(springs.chains[0].joints[0].rest.basis.get_rotation_quaternion().is_equal_approx(expected), "a spring built after the player swings about the turned pose")
	var swung := Quaternion(Vector3.FORWARD, 0.4)
	springs.chains[0].joints[0].rest = rest
	player.springs = springs
	player.apply()
	check(springs.chains[0].joints[0].rest.basis.get_rotation_quaternion().is_equal_approx(expected), "the player gives the spring its bone's turned pose as its rest")
	skeleton.set_bone_pose_rotation(skeleton.find_bone("wing"), swung)
	player.apply()
	check(skeleton.get_bone_pose_rotation(skeleton.find_bone("wing")).is_equal_approx(swung), "the turned bone a spring swings keeps the spring's pose")
	player.state.outputs[definition.targets.size() - 3] = 0.0
	player.apply()
	check(springs.chains[0].joints[0].rest.basis.get_rotation_quaternion().is_equal_approx(rest.basis.get_rotation_quaternion()), "an expression turning that bone back moves the rest its spring swings about")
	player.free()
	root.free()


func _node_effects_roundtrip() -> void:
	var state := GLTFState.new()
	var node := GLTFNode.new()
	node.resource_name = "wing"
	state.set_nodes([node])
	var named := Vrm._named({"targets": [
		{"effect": {"rotation": {"node": 0, "axis": 1, "rest": [0, 0, 0]}}, "default": 0.0},
		{"effect": {"translation": {"node": 0, "direction": [0, 1, 0]}}, "default": 0.0},
		{"effect": {"scale": {"node": 0, "axis": 0}}, "default": 1.0}]}, state)
	check(named.targets.all(func(t: Dictionary) -> bool: return t.effect.values()[0].node == "wing"), "every node effect read from a VRM names its node: %s" % [named.targets])
	var indexed := Vrm._indexed({"targets": named.targets, "shown": []}, state, {"wing": 0})
	check(indexed.targets.all(func(t: Dictionary) -> bool: return t.effect.values()[0].node == 0), "every node effect written to a VRM indexes its node: %s" % [indexed.targets])


## A file whose looks name materials without the material index they are drawn by is refused.
func _looks_need_their_index() -> void:
	var model := preload("res://demo/expressions.gd").scene().instantiate() as Node3D
	model.set_meta("springs", {})
	var definition: Dictionary = preload("res://demo/expressions.gd").definition()
	definition.looks.materials = [{"lighting": {"model": "flat"}}]
	model.set_meta("expressions", definition)
	Vrm.write(model, "user://unindexed.vrm")
	model.free()
	check(Avatar.read(FileAccess.get_file_as_bytes("user://unindexed.vrm")) == null, "a file whose looks name materials without their index is refused")


func _roundtrip() -> void:
	var scene: PackedScene = preload("res://demo/expressions.gd").scene()
	var model := scene.instantiate() as Node3D
	model.set_meta("springs", {})
	model.set_meta("expressions", preload("res://demo/expressions.gd").definition())
	Vrm.write(model, "user://expressions.vrm")
	model.free()
	var bytes := FileAccess.get_file_as_bytes("user://expressions.vrm")
	var json: Dictionary = Vrm.json_chunk(bytes)
	var decals: Array = json.extensions.VRCHAT_expressions.looks.decals
	var untinted: Variant = json.extensions.VRCHAT_expressions.untinted.image
	check(decals.size() == 1 and json.images[int(decals[0])].mimeType == "image/webp" and untinted is float and json.images[int(untinted)].mimeType == "image/webp" and (json.images as Array).all(func(i: Dictionary) -> bool: return i.mimeType == "image/webp"), "every image, the decal and the untinted colours each their own, is written as WebP: %s" % [json.images])
	if decals.size() == 1:
		var view: Dictionary = json.bufferViews[int(json.images[int(decals[0])].bufferView)]
		var at := 28 + bytes.decode_u32(12) + int(view.get("byteOffset", 0))
		var decal := Image.new()
		decal.load_webp_from_buffer(bytes.slice(at, at + int(view.byteLength)))
		check(decal.get_data() == preload("res://demo/expressions.gd").decal().get_data(), "the decal's WebP is lossless")
		check(Vrm._image_size(bytes.slice(at, at + 32)) == decal.get_size(), "a WebP is measured from its header: %s" % Vrm._image_size(bytes.slice(at, at + 32)))
	var reloaded := Avatar.read(bytes)
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
		check(mat != null and mat.get_shader_parameter("region_count") == 7 and mat.get_shader_parameter("untinted") != null and mat.get_shader_parameter("untinted_count") == 1 and mat.get_shader_parameter("decals") is Texture2DArray, "VRM import binds the colour, tone, decal, decal hue, darkening, lightening and screening decal regions and their layers to the hat")
		check(mat != null and mat.shader.resource_path.ends_with("expression_hue.gdshader"), "the hat, whose decal turns its hue, draws with the shader that turns it")
		var cells: Texture2D = mat.get_shader_parameter("untinted_cells") if mat != null else null
		check(cells != null and cells.get_image().get_pixel(0, 0).is_equal_approx(Color(0, 0, 1, 1)) and cells.get_image().get_pixel(0, 1).is_equal_approx(Color(1.0 / 6, 1.0 / 6, 5.0 / 6, 5.0 / 6)), "the hat's cell names its place in the untinted colours: %s" % [cells.get_image().get_pixel(0, 1) if cells else null])
		var regions: Texture2D = mat.get_shader_parameter("regions") if mat != null else null
		var pad := float(ExpressionPlayer.DECAL_PAD) / (preload("res://demo/expressions.gd").SIZE + 2 * ExpressionPlayer.DECAL_PAD)
		check(regions != null and regions.get_image().get_pixel(2, 3).is_equal_approx(Color(pad, pad, 1.0 - pad, 1.0 - pad)), "the decal region names its decal's place on its page: %s" % [regions.get_image().get_pixel(2, 3) if regions else null])
	avatar.free()


func _malformed() -> void:
	check(ExpressionDefinition.valid({"targets": [{"effect": {"scale": {"node": &"head", "axis": 0}}, "default": 1.0}]}), "imported bone names remain valid before JSON serialization")
	for kind: String in ["color", "tone", "look"]:
		check(ExpressionDefinition.valid({"targets": [{"effect": {kind: [{"node": 0, "rect": [0, 0, 1, 1], "channel": 1, "slot": 2}]}}]}), "an imported %s region is a valid target" % kind)
	check(not ExpressionDefinition.valid({"targets": [{"effect": {"tone": [{"node": 0}]}}]}), "a region without its atlas rect is rejected")
	check(not ExpressionDefinition.valid({"targets": [{"effect": {"color": [{"node": 0, "rect": [0, 0, 1, 1], "channel": 3}]}}]}), "a colour region past blue is rejected")
	check(not ExpressionDefinition.valid({"targets": [{"effect": {"look": [{"node": 0, "rect": [0, 0, 1, 1], "field": "decal", "slot": 4, "colorBlend": 0}]}}]}), "a decal region past the fourth slot is rejected")
	var blended := {"node": 0, "rect": [0, 0, 1, 1], "field": "decal", "slot": 0, "colorBlend": 20.0}
	check(ExpressionDefinition.valid({"targets": [{"effect": {"look": [blended]}}]}) and ExpressionPlayer._settings("look", blended, 0)[1] == 20.0, "a decal region's Color Blend Mode reaches the shader")
	check(not ExpressionDefinition.valid({"targets": [{"effect": {"look": [blended.merged({"colorBlend": 3.0}, true)]}}]}), "a decal region naming a blend mode Poiyomi has not is rejected")
	var unnamed := blended.duplicate()
	unnamed.erase("colorBlend")
	check(not ExpressionDefinition.valid({"targets": [{"effect": {"look": [unnamed.merged({"multiply": true})]}}]}), "a decal region converted before decals named their blend mode is rejected, not drawn replacing")
	var turned := {"node": 0, "rect": [0, 0, 1, 1], "field": "decalHue", "slot": 1, "colorBlend": 0, "alpha": 0.5, "hue": {"shift": 0.25, "space": 1.0, "select": 1.0}}
	check(ExpressionDefinition.valid({"targets": [{"effect": {"look": [turned]}}]}), "a decal region turning its hue is valid")
	check(not ExpressionDefinition.valid({"targets": [{"effect": {"look": [turned.merged({"hue": {"shift": "a"}}, true)]}}]}), "a decal region with a malformed hue turn is rejected")
	check(not ExpressionDefinition.valid({"targets": [{"effect": {"look": [turned.merged({"hue": null}, true)]}}]}), "a decal hue region without the turn it drives is rejected")
	var settings := ExpressionPlayer._settings("look", turned, 3)
	check(settings == [1, 0, 0.5, 2, 3], "a decal hue region drives its slot's turn, not its alpha, which stays at the saved one: %s" % [settings])
	check(ExpressionPlayer._turn(turned) == Color(0.25, 4.0, 0.0, 0.0) and ExpressionPlayer._turn({"field": "decal"}).g == 0.0, "a decal's turn at rest reaches the shader, and an unturned decal's is clear")
	for effect: Dictionary in [{"rotation": {"node": 2, "axis": 2, "rest": [-85, 0, 1]}}, {"rotation": {"node": 2, "axis": 3, "rest": [0, 0, 0, 1]}}, {"translation": {"node": 2, "direction": [-1, 0, 0]}}, {"constraint": {"node": 2}}]:
		check(ExpressionDefinition.valid({"targets": [{"effect": effect, "default": 0.0}]}), "an imported %s target is valid" % effect.keys()[0])
	for effect: Dictionary in [{"rotation": {"node": 2, "axis": 3, "rest": [0, 0, 0]}}, {"translation": {"node": 2, "direction": [1, 0]}}, {"constraint": {}}]:
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


## A clip animating a parameter writes it every frame, past the menu's range, and the layers read what it wrote.
func _animated_parameters() -> void:
	var definition := {"parameters": [{"name": "Reset", "type": "bool", "default": 0.0}, {"name": "Wetness", "type": "float", "default": 0.0}],
		"targets": [{"effect": {"parameter": "Wetness"}, "default": 0.0}, {"effect": "switch", "default": 0.0}], "menu": [],
		"clips": [{"length": 1.0, "curves": [{"target": 0, "keys": [[0, 0], [1, 2000]]}]}, {"length": 0.0, "curves": [{"target": 1, "keys": [[0, 1]]}]}],
		"layers": [{"states": [{"motion": {"clip": 0}, "transitions": [{"to": 1, "conditions": [{"parameter": "Reset", "mode": "if"}]}]}, {"motion": {}, "transitions": []}]},
			{"states": [{"motion": {}, "transitions": [{"to": 1, "conditions": [{"parameter": "Wetness", "mode": "greater", "threshold": 500.0}]}]}, {"motion": {"clip": 1}, "transitions": []}]}]}
	check(ExpressionDefinition.valid(definition), "a parameter target is valid")
	var state := ExpressionState.new(definition)
	state.advance(0.5)
	check(is_equal_approx(state.values.Wetness, 1000.0), "the clip writes the parameter beyond the menu's range: %s" % [state.values.Wetness])
	state.put("Wetness", 0.0)
	state.advance(0.0)
	check(is_equal_approx(state.values.Wetness, 1000.0), "the animator overwrites what else set it")
	state.advance(0.0)
	check(state.outputs[1] == 1.0, "another layer reads the animated value")
	state.put("Reset", 1.0)
	state.advance(0.1)
	check(state.values.Wetness == 0.0, "a state not animating it, writing defaults, returns it to its default")


class Body:
	extends RefCounted
	var rows := []

	func _init(r: Array) -> void:
		rows = r


## Receivers write their parameters from tagged senders touching them: constant while one does, on enter for the frame
## one arrives fast enough, proximity by how near the centre the nearest surface reaches; self and others as allowed.
func _contacts() -> void:
	var sk := Skeleton3D.new()
	sk.add_bone("Head")
	sk.set_bone_rest(0, Transform3D(Basis.IDENTITY, Vector3(0, 1.5, 0)))
	sk.reset_bone_poses()
	var receiver := func(type: String, parameter: String, others := true, own := false) -> Dictionary:
		return {"node": "Head", "shape": {"offset": [0, 0, 0], "radius": 0.2}, "tags": ["Hand"], "when": [], "receiver": {"type": type, "parameter": parameter, "self": own, "others": others, "local": false, "minVelocity": 1.0}}
	var definition := {"parameters": [{"name": "Near", "type": "float", "default": 0.0}, {"name": "On", "type": "bool", "default": 0.0}, {"name": "Tap", "type": "bool", "default": 0.0}, {"name": "Mine", "type": "bool", "default": 0.0}],
		"targets": [], "clips": [], "layers": [], "menu": [],
		"contacts": [receiver.call("proximity", "Near"), receiver.call("constant", "On"), receiver.call("onEnter", "Tap"), receiver.call("constant", "Mine", false, true),
			{"node": "Head", "shape": {"offset": [0, 0, 0.1], "radius": 0.05}, "tags": ["Hand"], "when": []}]}
	check(ExpressionDefinition.valid(definition), "contacts are valid")
	check(not ExpressionDefinition.valid({"contacts": [{"node": "Head", "shape": {"offset": [0, 0], "radius": 1}, "tags": [], "when": []}]}), "a contact without a point is refused")
	var partial: Dictionary = definition.contacts[0].duplicate(true)
	partial.receiver.erase("self")
	check(not ExpressionDefinition.valid({"contacts": [partial]}), "a receiver missing a field is refused")
	var state := ExpressionState.new(definition)
	var contacts := Contacts.new(definition.contacts, func(_n: Variant) -> Array: return [sk, 0])
	var me := Body.new([])
	var other := Body.new([])
	var hand := func(at: Vector3, tags := ["Hand"]) -> Array: return [at, at, 0.05, Contacts._tagged(tags), other, [other.get_instance_id(), "handL"]]
	var head := Vector3(0, 1.5, 0)
	contacts.sense(state, [hand.call(head + Vector3(0, 0, 0.35))], me, true, 1.0 / 60.0)
	check(state.values.Near == 0.0 and state.values.On == 0.0, "a hand short of the receiver touches nothing")
	contacts.sense(state, [hand.call(head + Vector3(0, 0, 0.15))], me, true, 1.0 / 60.0)
	check(is_equal_approx(state.values.Near, 0.5) and state.values.On == 1.0 and state.values.Tap == 1.0, "inside, proximity reads from the hand's surface and the entry taps: %s" % [state.values])
	contacts.sense(state, [hand.call(head + Vector3(0, 0, 0.15))], me, true, 1.0 / 60.0)
	check(state.values.Tap == 0.0 and state.values.On == 1.0, "the tap lasts one frame; contact holds")
	contacts.sense(state, [hand.call(head + Vector3(0, 0, 0.5))], me, true, 1.0 / 60.0)
	contacts.sense(state, [hand.call(head + Vector3(0, 0, 0.49))], me, true, 1.0 / 60.0)
	contacts.sense(state, [hand.call(head + Vector3(0, 0, 0.24))], me, true, 1.0)
	check(state.values.Tap == 0.0 and state.values.On == 1.0, "an entry slower than its minimum velocity does not tap")
	contacts.sense(state, [hand.call(head, ["Foot"])], me, true, 1.0 / 60.0)
	check(state.values.On == 0.0, "a sender without a shared tag touches nothing")
	var own := contacts.senders(state.outputs, me)
	check(own.size() == 1 and (own[0][0] as Vector3).is_equal_approx(head + Vector3(0, 0, 0.1)) and own[0][4] == me, "the avatar's own sender is placed by its bone: %s" % [own])
	contacts.sense(state, [own[0]], me, true, 1.0 / 60.0)
	check(state.values.Mine == 1.0 and state.values.On == 0.0, "its own sender reaches only the receiver allowing self")
	var body := Contacts.body_senders(func(b: String) -> Variant: return {"leftHand": Vector3(0.5, 1.2, 0), "leftMiddleProximal": Vector3(0.6, 1.2, 0), "leftFoot": Vector3.ZERO}.get(b), 1.5, me)
	var keys := body.map(func(s: Array) -> String: return s[5][1])
	check(keys == ["handL", "footL"] and (body[0][1] as Vector3).is_equal_approx(Vector3(0.6, 1.2, 0)) and is_equal_approx(body[0][2], 0.014 * 1.5), "a body without toes or a head sends from what it has, its foot from the foot: %s" % [body])
	sk.free()
