class_name ExpressionPlayer
extends Node

const SkeletonBone = preload("res://addons/avatar_workshop/skeleton_bone.gd")
const SpringRuntime = preload("res://addons/avatar_workshop/spring_runtime.gd")

var state: ExpressionState
var contacts: Contacts
var icons: Array[Texture2D] = []
var _bindings: Array = []
var _scales: Array[int] = []
## Each bone a rotation or translation effect moves, [skeleton, bone], to its rest, the Unity local rotation its effects
## set (`turn`) against the one they were authored from (`rest_turn`), each translation's offset, and the pose they make.
var _moved := {}
## The avatar's springs: a moved bone one of them swings is theirs to pose, about the pose its effects make.
var springs: SpringRuntime:
	set(value):
		springs = value
		for moved: Dictionary in _moved.values():
			moved.sent = false
var _shown: Array = []
## Each target's indices in _shown whose meshes it shows or hides, and the value each target last showed them at.
var _shown_by: Array[Array] = []
var _shown_at: Array[float] = []
var _last: Array[float] = []
var _materials := {}
var _regions := {}
var _dirty_regions := {}
var _turned := {}
## This player's copies of the looks table (Avatar._lit_looks), which an imported scene shares with every avatar opened
## from it, where Poiyomi global theme colours recolour the emission: by the mesh drawing with its own, one a clip moves
## a theme on, or by the model for its other meshes', where a theme's hue turns at rest: {"table", "texture", "entries"
## by column, each {"theme" (unity/materials.gd `_theme`), "replace"}, "dirty", "turning"}.
var _glows := {}
var _seconds := 0.0
var _frame := 0
var _marks := {}

const TEXTURES := {"hue": ["hue_mask"], "color": ["untinted", "untinted_cells", "untinted_count"], "tone": ["hue_mask"], "look": []}
## Clear texels round each decal on its page, so the first mips of one never read its neighbour.
const DECAL_PAD := 8
## The expression shaders by whether they turn decal hues (1), draw a clear coat (2) and draw toon looks (4),
## then by whether they draw both sides, each cut out, blended, and blended writing depth.
const SHADERS := [
	[[preload("res://src/expression.gdshader"), preload("res://src/expression_blended.gdshader"), preload("res://src/expression_blended_depth.gdshader")],
	[preload("res://src/expression_two_sided.gdshader"), preload("res://src/expression_blended_two_sided.gdshader"), preload("res://src/expression_blended_depth_two_sided.gdshader")]],
	[[preload("res://src/expression_hue.gdshader"), preload("res://src/expression_blended_hue.gdshader"), preload("res://src/expression_blended_depth_hue.gdshader")],
	[preload("res://src/expression_hue_two_sided.gdshader"), preload("res://src/expression_blended_hue_two_sided.gdshader"), preload("res://src/expression_blended_depth_hue_two_sided.gdshader")]],
	[[preload("res://src/expression_coat.gdshader"), preload("res://src/expression_blended_coat.gdshader"), preload("res://src/expression_blended_depth_coat.gdshader")],
	[preload("res://src/expression_coat_two_sided.gdshader"), preload("res://src/expression_blended_coat_two_sided.gdshader"), preload("res://src/expression_blended_depth_coat_two_sided.gdshader")]],
	[[preload("res://src/expression_hue_coat.gdshader"), preload("res://src/expression_blended_hue_coat.gdshader"), preload("res://src/expression_blended_depth_hue_coat.gdshader")],
	[preload("res://src/expression_hue_coat_two_sided.gdshader"), preload("res://src/expression_blended_hue_coat_two_sided.gdshader"), preload("res://src/expression_blended_depth_hue_coat_two_sided.gdshader")]],
	[[preload("res://src/expression_toon.gdshader"), preload("res://src/expression_blended_toon.gdshader"), preload("res://src/expression_blended_depth_toon.gdshader")],
	[preload("res://src/expression_toon_two_sided.gdshader"), preload("res://src/expression_blended_toon_two_sided.gdshader"), preload("res://src/expression_blended_depth_toon_two_sided.gdshader")]],
	[[preload("res://src/expression_hue_toon.gdshader"), preload("res://src/expression_blended_hue_toon.gdshader"), preload("res://src/expression_blended_depth_hue_toon.gdshader")],
	[preload("res://src/expression_hue_toon_two_sided.gdshader"), preload("res://src/expression_blended_hue_toon_two_sided.gdshader"), preload("res://src/expression_blended_depth_hue_toon_two_sided.gdshader")]],
	[[preload("res://src/expression_coat_toon.gdshader"), preload("res://src/expression_blended_coat_toon.gdshader"), preload("res://src/expression_blended_depth_coat_toon.gdshader")],
	[preload("res://src/expression_coat_toon_two_sided.gdshader"), preload("res://src/expression_blended_coat_toon_two_sided.gdshader"), preload("res://src/expression_blended_depth_coat_toon_two_sided.gdshader")]],
	[[preload("res://src/expression_hue_coat_toon.gdshader"), preload("res://src/expression_blended_hue_coat_toon.gdshader"), preload("res://src/expression_blended_depth_hue_coat_toon.gdshader")],
	[preload("res://src/expression_hue_coat_toon_two_sided.gdshader"), preload("res://src/expression_blended_hue_coat_toon_two_sided.gdshader"), preload("res://src/expression_blended_depth_hue_coat_toon_two_sided.gdshader")]]]
## The look fields the shader reads from a region, in its order: those driving a decal, a component of a clear coat's
## maps' tiling and offset, then an emission's strength and a matcap's intensity, which a region sets only while its
## target is off its rest (`apply`).
const LOOK_FIELDS := ["decal", "decalIntensity", "decalHue", "clearcoatST", "emission", "matcapIntensity"]
## The look fields a region sets only off its target's rest, where each material it covers otherwise keeps its own.
const RESTING_FIELDS := ["emission", "matcapIntensity"]

## The main thread's microseconds every avatar's expressions took to advance and apply since the metrics last took them.
static var process_us := 0



func _init(model: Node3D) -> void:
	var data: Dictionary = model.get_meta("expressions", {})
	process_priority = 1
	state = ExpressionState.new(data)
	var nodes := {}
	for n: Node in model.find_children("*", "", true, false):
		nodes[str(n.name)] = n
	contacts = Contacts.new(state.data.get("contacts", []), func(name: Variant) -> Array:
		var found := _bones(nodes, name)
		return found[0] if not found.is_empty() else [])
	icons.assign(model.get_meta("expression_icons", []))
	for target: Dictionary in data.get("targets", []):
		var effect: Variant = target.get("effect")
		if effect is Dictionary and effect.has("look"):
			for region: Dictionary in effect.look:
				if region.get("hue") is Dictionary:
					_turned[str(region.node)] = true
	for target: Dictionary in data.get("targets", []):
		var binds := []
		var effect: Variant = target.get("effect")
		if effect is Dictionary:
			if effect.has("morph"):
				for b: Array in effect.morph:
					var mesh: MeshInstance3D = nodes.get(str(b[0]))
					if mesh != null:
						var index := mesh.find_blend_shape_by_name(str(b[1]))
						if index >= 0:
							binds.append(func(v: float) -> void: mesh.set_blend_shape_value(index, v))
			elif effect.has("scale"):
				_scales.append(_bindings.size())
				for at: Array in _bones(nodes, effect.scale.node):
					var skeleton: Skeleton3D = at[0]
					var bone: int = at[1]
					var axis := int(effect.scale.axis)
					binds.append(func(v: float) -> void:
						var was := skeleton.get_bone_pose_scale(bone)
						var s := was
						s[axis] = v
						if s != was:
							skeleton.set_bone_pose_scale(bone, s))
			elif effect.has("rotation") or effect.has("translation"):
				for at: Array in _bones(nodes, effect.values()[0].node):
					var rest: Transform3D = at[0].get_bone_rest(at[1])
					var moved: Dictionary = _moved.get_or_add(at, {"rest": rest, "turn": [], "shift": {}, "pose": rest, "bone": SkeletonBone.new(at[0], at[1])})
					var i := _bindings.size()
					if effect.has("rotation"):
						var axis := int(effect.rotation.axis)
						if moved.turn.is_empty():
							moved.turn = (effect.rotation.rest as Array).map(func(c: Variant) -> float: return float(c))
							moved.rest_turn = moved.turn.duplicate()
						# A bone turned both as Euler angles and as a quaternion takes the form its first effect has.
						if (effect.rotation.rest as Array).size() == moved.turn.size():
							binds.append(func(v: float) -> void:
								moved.turn[axis] = v
								moved.dirty = true)
					else:
						var direction := Vector3(effect.translation.direction[0], effect.translation.direction[1], effect.translation.direction[2])
						binds.append(func(v: float) -> void:
							moved.shift[i] = direction * v
							moved.dirty = true)
			elif effect.has("constraint"):
				for at: Array in _bones(nodes, effect.constraint.node):
					var solver := Constraints.of(at[0])
					if solver != null:
						var bone: int = at[1]
						binds.append(func(v: float) -> void: solver.weights[bone] = v)
			elif effect.has("material"):
				var mesh: MeshInstance3D = nodes.get(str(effect.material.node))
				if mesh != null:
					var mats := _material(mesh)
					var choices: Array = effect.material.choices
					binds.append(func(v: float) -> void:
						var uv: Array = choices[clampi(roundi(v), 0, choices.size() - 1)]
						for mat in mats:
							mat.set_shader_parameter("atlas", Vector4(uv[0], uv[1], uv[2], uv[3]))
							if mat.has_meta("hull"):
								(mat.get_meta("hull") as ShaderMaterial).set_shader_parameter("atlas", Vector4(uv[0], uv[1], uv[2], uv[3])))
			elif ExpressionDefinition.region(effect) != "":
				var kind: String = effect.keys()[0]
				for region: Dictionary in effect[kind]:
					var mesh: MeshInstance3D = nodes.get(str(region.node))
					if mesh != null and kind == "look" and str(region.get("field", "")).begins_with("theme"):
						var glows: Dictionary = _glows.get_or_add(mesh, {"entries": {}, "dirty": true, "turning": false})
						var entry := _glow(glows.entries, region, data.get("looks", {}))
						if not entry.is_empty():
							var offset := str(region.field).trim_prefix("theme").to_lower()
							var rest: float = entry.theme[offset]
							var resting := float(target.get("default", 0))
							binds.append(func(v: float) -> void:
								entry.theme[offset] = rest if v == resting else v
								glows.dirty = true)
						continue
					var field := str(region.get("field", ""))
					if mesh == null or (kind == "look" and not field.begins_with("decal") and field not in RESTING_FIELDS and not (field == "clearcoatST" and _marked(mesh, "clearcoat"))):
						continue
					var mats := _material(mesh)
					var decals: Dictionary = model.get_meta("expression_decal_sets", {}).get(str(region.node), {})
					var place: Array = decals.get("places", {}).get(int(region.get("image", -1)), [0, 0.0, 0.0, 0.0, 0.0])
					var entry := {"rect": region.rect, "value": float(target.get("default", 0)), "kind": ExpressionDefinition.REGIONS.find(kind), "settings": _settings(kind, region, place[0]), "decal": place.slice(1), "turn": _turn(region)}
					if kind == "look" and field in RESTING_FIELDS:
						entry.rest = entry.value
					for mat in mats:
						(_regions.get_or_add(mat, []) as Array).append(entry)
						for uniform: String in TEXTURES[kind]:
							if model.has_meta("expression_" + uniform):
								mat.set_shader_parameter(uniform, model.get_meta("expression_" + uniform))
						if decals.has("decals"):
							mat.set_shader_parameter("decals", decals.decals)
					binds.append(func(v: float) -> void:
						entry.value = v
						for mat in mats:
							_dirty_regions[mat] = true)
		_bindings.append(binds)
	var shared: Variant = _light_looks(model)
	var looks: Dictionary = data.get("looks", {})
	# One entry per column whichever tables hold it, so each is coloured once a frame.
	var resting := {}
	if shared is ImageTexture:
		var turning := {"entries": {}, "dirty": true, "turning": false}
		_turning(turning.entries, looks, resting)
		if not turning.entries.is_empty():
			_glows[model] = turning
	for owner: Object in _glows.keys():
		var glows: Dictionary = _glows[owner]
		var mats: Array = _materials.values().reduce(func(all: Array, m: Array) -> Array: return all + m, []) if owner == model else _materials.get(owner, [])
		var lighting: Variant = shared if owner == model else mats[0].get_shader_parameter("lighting") if not mats.is_empty() else null
		if not lighting is ImageTexture or glows.entries.is_empty():
			_glows.erase(owner)
			continue
		_turning(glows.entries, looks, resting)
		glows.table = (lighting as ImageTexture).get_image().duplicate() as Image
		glows.texture = ImageTexture.create_from_image(glows.table)
		for mat: ShaderMaterial in mats:
			if mat.get_shader_parameter("lighting") == lighting:
				mat.set_shader_parameter("lighting", glows.texture)
	_shown_by.resize(state.outputs.size())
	_shown_at.resize(state.outputs.size())
	_shown_at.fill(NAN)
	for shown: Dictionary in data.get("shown", []):
		var node: Node3D = nodes.get(str(shown.node))
		if node != null:
			for w: Array in shown.when:
				_shown_by[int(w[0])].append(_shown.size())
			_shown.append({"node": node, "when": shown.when})
	_last.resize(state.outputs.size())
	_last.fill(NAN)
	for i in mini(_bindings.size(), state.outputs.size()):
		var effect: Variant = data.get("targets", [])[i].get("effect")
		if effect is Dictionary and (effect.has("rotation") or effect.has("translation")):
			for bind: Callable in _bindings[i]:
				bind.call(state.outputs[i])
	_move_bones()


## Entered here, after its saved values are restored and before it is first drawn, so a body that never processes, a
## still figure's, shows the look its controller starts in.
func _ready() -> void:
	state.advance(0.0)
	apply()


func _process(delta: float) -> void:
	var start := Time.get_ticks_usec()
	_seconds += delta
	var body := get_parent() as Avatar
	if contacts.receives() and body != null and body.is_in_group(Contacts.BODIES):
		contacts.sense(state, Contacts.gather(get_tree()), body, body.local, delta)
	state.advance(delta)
	var targets := state.moved.keys()
	targets.append_array(_scales)
	apply(targets)
	process_us += Time.get_ticks_usec() - start


## Binds the outputs of `targets`, those the controller moved since the last, or every output where null.
func apply(targets: Variant = null) -> void:
	var showing := {}
	if _frame == 0:
		targets = null
		for k in _shown.size():
			showing[k] = true
	state.moved.clear()
	for i: int in range(state.outputs.size()) if targets == null else targets:
		var v := state.outputs[i]
		if _scales.has(i) or not is_equal_approx(v, _last[i]):
			for bind: Callable in _bindings[i]:
				bind.call(v)
			_last[i] = v
		if v != _shown_at[i] and not _shown_by[i].is_empty():
			_shown_at[i] = v
			for k: int in _shown_by[i]:
				showing[k] = true
	_move_bones()
	for mat: ShaderMaterial in _dirty_regions:
		var entries: Array = _regions[mat]
		var image := Image.create(entries.size(), 5, false, Image.FORMAT_RGBAF)
		for k in entries.size():
			var e: Dictionary = entries[k]
			var s: Array = e.settings
			image.set_pixel(k, 0, Color(e.rect[0], e.rect[1], e.rect[2], e.rect[3]))
			image.set_pixel(k, 1, Color(e.value, e.kind, s[0], s[1]))
			image.set_pixel(k, 2, Color(s[2], -1 if e.get("rest") == e.value else s[3], s[4], e.turn.g))
			image.set_pixel(k, 3, Color(e.decal[0], e.decal[1], e.decal[2], e.decal[3]))
			image.set_pixel(k, 4, e.turn)
		var texture := mat.get_shader_parameter("regions") as ImageTexture
		if texture == null:
			texture = ImageTexture.create_from_image(image)
			mat.set_shader_parameter("regions", texture)
			mat.set_shader_parameter("region_count", entries.size())
		else:
			texture.update(image)
	_dirty_regions.clear()
	_frame += 1
	for glows: Dictionary in _glows.values():
		if glows.dirty:
			glows.turning = glows.entries.values().any(func(e: Dictionary) -> bool: return e.theme.speed != 0.0)
		if glows.dirty or glows.turning:
			glows.dirty = false
			for column: int in glows.entries:
				var e: Dictionary = glows.entries[column]
				if e.frame != _frame:
					e.frame = _frame
					var c := theme_colour(e.theme, _seconds)
					e.colour = Color(c.r, c.g, c.b, e.replace)
				glows.table.set_pixel(column, 1, e.colour)
			glows.texture.update(glows.table)
	for k: int in showing:
		_shown[k].node.visible = shows(state.outputs, _shown[k].when)


## Poses each moved bone as its effects set it. A bone a spring swings gets that pose as the rest it swings about, as
## VRChat's PhysBones swing about the pose the animator left, and is left to the spring.
func _move_bones() -> void:
	for at: Array in _moved:
		var moved: Dictionary = _moved[at]
		if moved.get("dirty", false):
			moved.dirty = false
			moved.sent = false
			var rest: Transform3D = moved.rest
			var turned := rest.basis.get_rotation_quaternion()
			if not moved.turn.is_empty():
				turned = (turned * turn(moved.rest_turn, moved.turn)).normalized()
			var shift := Vector3.ZERO
			for offset: Vector3 in moved.shift.values():
				shift += offset
			moved.pose = Transform3D(Basis(turned).scaled_local(rest.basis.get_scale()), rest.origin + shift)
		if springs != null and not moved.get("sent", false):
			moved.sent = true
			moved.sprung = springs.set_rest(moved.bone, moved.pose)
		if not moved.get("sprung", false):
			var pose: Transform3D = moved.pose
			if not moved.turn.is_empty():
				at[0].set_bone_pose_rotation(at[1], pose.basis.get_rotation_quaternion())
			if not moved.shift.is_empty():
				at[0].set_bone_pose_position(at[1], pose.origin)


## The turn of a bone's glTF local rotation that takes a Unity local rotation from `from` to `to`, each its
## localEulerAngles in degrees when three components, a quaternion when four.
static func turn(from: Array, to: Array) -> Quaternion:
	var delta := (_unity(from).inverse() * _unity(to)).normalized()
	return Quaternion(delta.x, -delta.y, -delta.z, delta.w)


static func _unity(c: Array) -> Quaternion:
	if c.size() == 4:
		return Quaternion(c[0], c[1], c[2], c[3]).normalized()
	return Quaternion(Vector3.UP, deg_to_rad(c[1])) * Quaternion(Vector3.RIGHT, deg_to_rad(c[0])) * Quaternion(Vector3(0, 0, 1), deg_to_rad(c[2]))


## Every [skeleton, bone] named `bone` among `nodes`.
static func _bones(nodes: Dictionary, bone: Variant) -> Array:
	var found := []
	for n: Node in nodes.values():
		if n is Skeleton3D and (n as Skeleton3D).find_bone(str(bone)) >= 0:
			found.append([n, (n as Skeleton3D).find_bone(str(bone))])
	return found


## Whether a mesh drawn under `when`, [[switch target, 1]...], draws at `outputs`. A direct blend tree sums its
## children, so a switch two of them turn on reads two.
static func shows(outputs: Array[float], when: Array) -> bool:
	return when.all(func(w: Array) -> bool: return is_equal_approx(minf(outputs[int(w[0])], 1.0), float(w[1])))


static func prepare(model: Node3D) -> void:
	var data: Dictionary = model.get_meta("expressions", {})
	var icons: Array[Texture2D] = []
	var made := {}
	for img: Image in data.get("icons", []):
		if not made.has(img):
			made[img] = ImageTexture.create_from_image(img)
		icons.append(made[img])
	model.set_meta("expression_icons", icons)
	var looks: Dictionary = data.get("looks", {})
	var untinted: Dictionary = data.get("untinted", {})
	for pair: Array in [[data.get("hueMask"), "hue_mask"], [untinted.get("image"), "untinted"], [looks.get("emission"), "glow"], [looks.get("shade"), "shade"], [looks.get("shade2"), "shade2"], [looks.get("rimTint"), "rim_tint"]]:
		if pair[0] is Image:
			model.set_meta("expression_" + pair[1], ImageTexture.create_from_image(pair[0]))
	var cells: Array = untinted.get("cells", [])
	if not cells.is_empty():
		var table := Image.create_empty(cells.size(), 2, false, Image.FORMAT_RGBAF)
		for k in cells.size():
			table.set_pixel(k, 0, Color(cells[k][0], cells[k][1], cells[k][2], cells[k][3]))
			table.set_pixel(k, 1, Color(cells[k][4], cells[k][5], cells[k][6], cells[k][7]))
		model.set_meta("expression_untinted_cells", ImageTexture.create_from_image(table))
		model.set_meta("expression_untinted_count", cells.size())
	var maps: Array = looks.get("clearcoatMaps", []).map(func(img: Variant) -> Image: return img if img is Image else Image.create_empty(1, 1, false, Image.FORMAT_RGBA8))
	if not maps.is_empty():
		model.set_meta("expression_coat_maps", _layers(maps))
	if not looks.get("matcaps", []).is_empty():
		model.set_meta("expression_matcaps", _layers(looks.matcaps))
	if looks.get("matcapMasks") is Image:
		model.set_meta("expression_matcap_masks", ImageTexture.create_from_image(looks.matcapMasks))
	var fallbacks: Array = looks.get("clearcoatFallbacks", [])
	if not fallbacks.is_empty():
		model.set_meta("expression_coat_fallbacks", coat_fallbacks(fallbacks))
	var decals: Array = looks.get("decals", [])
	Vrm.drop_layers(data)
	var by_node := {}
	for target: Dictionary in data.get("targets", []):
		var effect: Variant = target.get("effect")
		if effect is Dictionary and effect.has("look"):
			for region: Dictionary in effect.look:
				var k := int(region.get("image", -1))
				if str(region.get("field", "")).begins_with("decal") and k >= 0 and k < decals.size() and decals[k] is Image:
					(by_node.get_or_add(str(region.node), {}) as Dictionary)[k] = decals[k]
	var sets := {}
	var laid := {}
	for node: String in by_node:
		var drawn: Dictionary = by_node[node]
		var key := drawn.keys()
		key.sort()
		if not laid.has(key):
			var pages := _pages(drawn)
			var array := Texture2DArray.new()
			laid[key] = {"decals": array, "places": pages.places} if array.create_from_images(pages.images) == OK else {}
		if not laid[key].is_empty():
			sets[node] = laid[key]
	model.set_meta("expression_decal_sets", sets)


## Binds the material index, looks table (Avatar._lit_looks) and the looks' layers to the meshes whose materials carry
## them, the ones that show a flat, glowing, coated or toon material, and to every mesh already drawn animated, since a
## material swapped in may be any of them. Returns the looks table they share, or null for none.
func _light_looks(model: Node3D) -> Variant:
	var textures: Array = []
	var looked := []
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for i in mesh.mesh.get_surface_count():
			var m := mesh.mesh.surface_get_material(i)
			if m != null and m.has_meta("light_index"):
				textures = [m.get_meta("light_index"), m.get_meta("lighting")]
				looked.append(mesh)
				break
	if textures.is_empty():
		return null
	var glow: Texture2D = model.get_meta("expression_glow") if model.has_meta("expression_glow") else null
	var coat_maps: Texture2DArray = model.get_meta("expression_coat_maps") if model.has_meta("expression_coat_maps") else _empty_array()
	var matcaps: Texture2DArray = model.get_meta("expression_matcaps") if model.has_meta("expression_matcaps") else _empty_array()
	var masks: Texture2D = model.get_meta("expression_matcap_masks") if model.has_meta("expression_matcap_masks") else null
	var layers: Array = ["shade", "shade2", "rim_tint"].map(func(layer: String) -> Variant: return model.get_meta("expression_" + layer) if model.has_meta("expression_" + layer) else null)
	var coat_fallbacks: Texture2DArray = model.get_meta("expression_coat_fallbacks") if model.has_meta("expression_coat_fallbacks") else _empty_array()
	for mesh: MeshInstance3D in looked:
		_material(mesh)
	for mats: Array[ShaderMaterial] in _materials.values():
		for mat in mats:
			mat.set_shader_parameter("light_index", textures[0])
			mat.set_shader_parameter("lighting", textures[1])
			mat.set_shader_parameter("glow", glow)
			mat.set_shader_parameter("coat_maps", coat_maps)
			mat.set_shader_parameter("matcaps", matcaps)
			mat.set_shader_parameter("matcap_masks", masks)
			mat.set_shader_parameter("shade", layers[0])
			mat.set_shader_parameter("shade2", layers[1])
			mat.set_shader_parameter("rim_tint", layers[2])
			mat.set_shader_parameter("coat_fallbacks", coat_fallbacks)
			mat.set_shader_parameter("mirror_mask", Quality.MIRROR_MASK)
	return textures[1]


## The decals `drawn` (index to image) laid on pages as wide as the widest of them, each with DECAL_PAD clear texels round
## it, tallest first along shelves: {"images": the pages, mipmapped, "places": each index to [page, its rect in the
## page's UV]}.
static func _pages(drawn: Dictionary) -> Dictionary:
	var side := 1
	for img: Image in drawn.values():
		side = maxi(side, maxi(img.get_width(), img.get_height()) + 2 * DECAL_PAD)
	var order := drawn.keys()
	order.sort_custom(func(a: int, b: int) -> bool: return drawn[a].get_height() > drawn[b].get_height())
	var pages: Array[Image] = []
	var places := {}
	var x := side
	var y := 0
	var row := 0
	for k: int in order:
		var img: Image = (drawn[k] as Image).duplicate()
		img.clear_mipmaps()
		img.convert(Image.FORMAT_RGBA8)
		var w := img.get_width() + 2 * DECAL_PAD
		var h := img.get_height() + 2 * DECAL_PAD
		if x + w > side:
			x = 0
			y += row
			row = 0
		if pages.is_empty() or y + h > side:
			var page := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
			page.fill(Color(0, 0, 0, 0))
			pages.append(page)
			x = 0
			y = 0
			row = 0
		var at := Vector2i(x + DECAL_PAD, y + DECAL_PAD)
		pages[-1].blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), at)
		places[k] = [pages.size() - 1, float(at.x) / side, float(at.y) / side, float(at.x + img.get_width()) / side, float(at.y + img.get_height()) / side]
		x += w
		row = maxi(row, h)
	for page in pages:
		page.generate_mipmaps()
	return {"images": pages, "places": places}


## The fallback cubemaps `stacks` (Avatar.FALLBACK_SIDE) in linear light, a layer each, so the shader's filtering blends
## light and not its encoding; one that is no such image is Unity's default grey, which keeps the rest at their layers.
static func coat_fallbacks(stacks: Array) -> Texture2DArray:
	var size := Vector2i(Avatar.FALLBACK_SIDE, Avatar.FALLBACK_SIDE / 2 * Avatar.FALLBACK_LEVELS)
	var layers: Array[Image] = []
	for stack: Variant in stacks:
		var layer := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBH)
		layer.fill(Color(0.214, 0.214, 0.214))
		if stack is Image and (stack as Image).get_size() == size:
			var encoded := (stack as Image).duplicate() as Image
			encoded.convert(Image.FORMAT_RGBA8)
			for y in size.y:
				for x in size.x:
					var c := encoded.get_pixel(x, y)
					layer.set_pixel(x, y, Color(c.r, c.g, c.b) * (c.a * Avatar.FALLBACK_RANGE))
		layers.append(layer)
	var out := Texture2DArray.new()
	out.create_from_images(layers)
	return out


## `maps`, the clear coats' packed maps (unity/materials.gd coat_map) or the matcaps, as one array, each layer as wide
## as the widest of them, mipmapped.
static func _layers(maps: Array) -> Texture2DArray:
	var side := 1
	for img: Image in maps:
		side = maxi(side, maxi(img.get_width(), img.get_height()))
	var layers: Array[Image] = []
	for img: Image in maps:
		var layer := img.duplicate() as Image
		layer.clear_mipmaps()
		layer.convert(Image.FORMAT_RGBA8)
		layer.resize(side, side, Image.INTERPOLATE_LANCZOS)
		layer.generate_mipmaps()
		layers.append(layer)
	var out := Texture2DArray.new()
	out.create_from_images(layers)
	return out


static func _settings(kind: String, region: Dictionary, page: int) -> Array:
	match kind:
		"hue":
			return [region.get("space", 0), region.get("shift", 1), 0, 0, 0]
		"color":
			var c: Array = region.get("color", [1, 1, 1])
			return [region.get("channel", 0), 0, c[0], c[1], c[2]]
		"tone":
			return [region.get("channel", 0), 0, 0, 0, 0]
	return [region.get("slot", 0), region.get("colorBlend", 0), region.get("alpha", 1), LOOK_FIELDS.find(region.get("field", "decal")), page]


## Among `entries`, by looks table column, the one of the material `region` recolours where it glows in the global theme
## colour the region's slot names, added if new, or {} where it glows in none.
static func _glow(entries: Dictionary, region: Dictionary, looks: Dictionary) -> Dictionary:
	var materials: Array = looks.get("materials", [])
	for k in materials.size():
		var rect: Array = materials[k].get("rect", [])
		if _theme_of(materials[k]) is Dictionary and int(materials[k].emission.theme) == int(region.get("slot", 0)) and rect.size() == 4 and range(4).all(func(c: int) -> bool: return is_equal_approx(rect[c], region.rect[c])):
			return entries.get_or_add(k + 1, _entry(materials[k]))
	return {}


## Adds to `entries` each material that glows in a global theme colour whose hue turns at rest, but those already there,
## sharing its entry from `resting`.
static func _turning(entries: Dictionary, looks: Dictionary, resting: Dictionary) -> void:
	var materials: Array = looks.get("materials", [])
	for k in materials.size():
		var theme: Variant = _theme_of(materials[k])
		if theme is Dictionary and theme.speed != 0.0 and not entries.has(k + 1):
			entries[k + 1] = resting.get_or_add(k + 1, _entry(materials[k]))


## The global theme colour a looks material's emission glows in, or null.
static func _theme_of(look: Dictionary) -> Variant:
	var glow: Variant = look.get("emission")
	return look.themes[int(glow.theme)] if glow is Dictionary and glow.get("theme") != null else null


static func _entry(look: Dictionary) -> Dictionary:
	return {"theme": (_theme_of(look) as Dictionary).duplicate(), "replace": float(look.emission.get("replace", 0.0)), "frame": -1, "colour": Color()}


## The colour a Poiyomi global theme colour (unity/materials.gd `_theme`) shows `seconds` in, in linear light: its
## colour moved by its offsets as Poiyomi's ModifyViaHSV moves it, the hue also turning `speed` times a Unity _Time.x,
## a twentieth of a second, and its exposure put back.
static func theme_colour(theme: Dictionary, seconds: float) -> Color:
	var hsv: Array = theme.hsv
	var moved := Color.from_hsv(fposmod(hsv[0] + fposmod(theme.hue + theme.speed * seconds / 20.0, 1.0), 1.0), clampf(hsv[1] + theme.saturation, 0.0, 1.0), clampf(hsv[2] + theme.value, 0.0, 1.0))
	return Color(moved.r * theme.exposure, moved.g * theme.exposure, moved.b * theme.exposure)


## A decal's hue turn at rest as (shift, 1 + 2 * colour space + select or shift), or zero where its image holds its
## colour: one number for how it turns keeps the shader's per-slot state in vectors, which a Quest's GPU indexes far more
## cheaply than an array of them.
static func _turn(region: Dictionary) -> Color:
	var hue: Variant = region.get("hue")
	if not hue is Dictionary:
		return Color(0, 0, 0, 0)
	return Color(float(hue.get("shift", 0)), 1 + 2 * float(hue.get("space", 0)) + float(hue.get("select", 1)), 0, 0)


## The expression shader drawing `base` as it draws: cut out, blended or blended writing depth, front faces only or both
## sides, turning decal hues where `turned`, drawing a clear coat where `coated` and toon looks where `tooned`.
static func shader_for(base: BaseMaterial3D, turned: bool, coated := false, tooned := false) -> Shader:
	var way := 0
	if base != null and base.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
		way = 2 if base.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_ALWAYS else 1
	var both := base != null and base.cull_mode == BaseMaterial3D.CULL_DISABLED
	return SHADERS[(1 if turned else 0) + (2 if coated else 0) + (4 if tooned else 0)][1 if both else 0][way]


## The materials drawing every surface of `mesh` as animated, one for each way its surfaces draw: cut out, blended, or
## blended writing depth, each front faces only or both sides as its material draws them, outlined or not. Only a mesh
## with a decal whose hue turns draws with the shaders that turn it, and only one showing a clear coat or a toon look
## (Avatar._lit_looks) with the shaders that draw it: compiled in, each costs a Quest 2 GPU time on every surface, drawn
## or not.
func _material(mesh: MeshInstance3D) -> Array[ShaderMaterial]:
	if _materials.has(mesh):
		return _materials[mesh]
	var by_shader := {}
	var coated := _marked(mesh, "clearcoat")
	var tooned := _marked(mesh, "toon")
	for i in mesh.mesh.get_surface_count():
		var base := mesh.get_active_material(i) as BaseMaterial3D
		var shader := shader_for(base, _turned.has(str(mesh.name)), coated, tooned)
		if coated and (not world_reflects or _marked(mesh, "coat_forces_fallback")):
			shader = fallback_shader(shader)
		var key := [shader, base != null and base.has_meta("hull")]
		if not by_shader.has(key):
			var mat := ShaderMaterial.new()
			mat.shader = shader
			if tooned:
				Avatar.tooned(mat, shader_for(base, _turned.has(str(mesh.name)), coated))
			mat.set_shader_parameter("decals", _empty_array())
			if base != null:
				mat.set_shader_parameter("picture", base.albedo_texture)
				mat.set_shader_parameter("colour", base.albedo_color)
				mat.set_shader_parameter("use_vertex", base.vertex_color_use_as_albedo)
				mat.set_meta("icon_material", Hand._icon_material(base, mesh))
				if base.has_meta("hull"):
					Avatar.hulled(mat, base.get_meta("hull").duplicate())
			by_shader[key] = mat
		mesh.set_surface_override_material(i, by_shader[key])
	var out: Array[ShaderMaterial] = []
	out.assign(by_shader.values())
	_materials[mesh] = out
	return out


## Whether `mesh` shows a material Avatar._lit_looks marked `mark`: "clearcoat", "coat_forces_fallback" or "toon".
func _marked(mesh: MeshInstance3D, mark: String) -> bool:
	var key := [mesh, mark]
	if not _marks.has(key):
		_marks[key] = range(mesh.mesh.get_surface_count()).any(func(i: int) -> bool: return mesh.mesh.surface_get_material(i) != null and mesh.mesh.surface_get_material(i).has_meta(mark))
	return _marks[key]


## Whether the world has a reflection probe for a clear coat to reflect, as the garden's sky is; the reference replay,
## whose harness has none, clears it before it loads an avatar, and coats then reflect their fallback cubemaps.
static var world_reflects := true:
	set(v):
		world_reflects = v
		RenderingServer.global_shader_parameter_set(&"world_reflects", v)

static var _fallback_shaders := {}


## The clear coat shader `coat` with a coat's fallback cubemap compiled in, made once from its source.
static func fallback_shader(coat: Shader) -> Shader:
	if not _fallback_shaders.has(coat):
		var shader := Shader.new()
		shader.code = coat.code.replace("#define CLEAR_COAT", "#define CLEAR_COAT\n#define COAT_FALLBACK")
		assert(shader.code != coat.code)
		_fallback_shaders[coat] = shader
	return _fallback_shaders[coat]


static var _clear: Texture2DArray


## A material whose model draws no decals or coat maps still binds an array for each: a sampler array left unbound
## fails the material's whole uniform set, and the surface draws nothing.
static func _empty_array() -> Texture2DArray:
	if _clear == null:
		var texel := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
		_clear = Texture2DArray.new()
		_clear.create_from_images([texel])
	return _clear
