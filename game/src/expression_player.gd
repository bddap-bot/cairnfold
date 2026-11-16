class_name ExpressionPlayer
extends Node

const SkeletonBone = preload("res://addons/avatar_workshop/skeleton_bone.gd")
const SpringRuntime = preload("res://addons/avatar_workshop/spring_runtime.gd")

var state: ExpressionState
var contacts: Contacts
var icons: Array[Texture2D] = []
var _bindings: Array = []
var _scales: Array[int] = []
## [skeleton, bone] -> {rest, turn: Unity local rotation its effects set, rest_turn: the authored one, shift: binding
## index -> offset, pose, bone, dirty, sent, sprung}.
var _moved := {}
## A moved bone a spring swings is the spring's to pose, about the pose its effects make, as PhysBones do.
var springs: SpringRuntime:
	set(value):
		springs = value
		for moved: Dictionary in _moved.values():
			moved.sent = false
## After a frame that showed or hid a node or switched a spring on or off.
signal switched
var _shown: Array = []
## Per output: its indices into _shown; _shown_at, the value it last showed them at.
var _shown_by: Array[Array] = []
var _shown_at: Array[float] = []
## The outputs the switches of the definition's springs read, and whether each of those springs was on when last looked.
var _switches_springs := {}
var _springs_on: Array = []
var _last: Array[float] = []
var _materials := {}
var _regions := {}
var _dirty_regions := {}
var _turned := {}
## Copies of the looks table (Avatar._lit_looks), which every avatar from one imported scene shares, keyed by a mesh a
## clip moves a theme on, or by the model for themes turning at rest: {"table", "texture", "entries": column ->
## {"theme", "replace", "frame", "colour"}, "dirty", "turning"}.
var _glows := {}
var _seconds := 0.0
var _frame := 0
var _marks := {}

const TEXTURES := {"hue": ["hue_mask"], "color": ["untinted", "untinted_cells", "untinted_count"], "tone": ["hue_mask"], "look": []}
## Clear texels round each decal on its page, so the first mips of one never read its neighbour.
const DECAL_PAD := 8
const UNITY_GREY := 0.214
## In the shader's field order.
const LOOK_FIELDS := ["decal", "decalIntensity", "decalHue", "clearcoatST", "emission", "matcapIntensity"]
## Set only while the target is off its rest; at rest each covered material keeps its own.
const RESTING_FIELDS := ["emission", "matcapIntensity"]
const POST_CHANNELS := {"lightAdd": 0, "brightness": 1}
const POST_RESTS: Array[float] = [0.0, 1.0]

## All avatars; metrics.gd reads and resets it.
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
						# A bone turned both as Euler angles and as a quaternion keeps its first effect's form.
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
					if mesh != null and kind == "look" and POST_CHANNELS.has(str(region.get("field", ""))):
						var column := _column(region, data.get("looks", {}))
						if column > 0:
							var glows: Dictionary = _glows.get_or_add(mesh, {"entries": {}, "dirty": true, "turning": false})
							var posts: Dictionary = glows.get_or_add("posts", {})
							var channel: int = POST_CHANNELS[str(region.field)]
							var rest := float(region.get("rest", POST_RESTS[channel]))
							var resting := float(target.get("default", 0))
							posts.get_or_add(column, Color(0.0, 0.0, 0.0, 0.0))
							binds.append(func(v: float) -> void:
								var post: Color = posts[column]
								var value := rest if v == resting else v
								post[channel] = value if channel == 0 else 1.0 - value
								posts[column] = post
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
		if not lighting is ImageTexture or glows.entries.is_empty() and glows.get("posts", {}).is_empty():
			_glows.erase(owner)
			continue
		_turning(glows.entries, looks, resting)
		glows.table = (lighting as ImageTexture).get_image().duplicate() as Image
		glows.texture = ImageTexture.create_from_image(glows.table)
		for mat: ShaderMaterial in mats:
			if mat.get_shader_parameter("lighting") == lighting:
				_set_lighting(mat, "lighting", glows.texture)
				if mat.has_meta("hull") and not glows.get("posts", {}).is_empty():
					(mat.get_meta("hull") as ShaderMaterial).set_shader_parameter("lit_by_menu", true)
	_shown_by.resize(state.outputs.size())
	_shown_at.resize(state.outputs.size())
	_shown_at.fill(NAN)
	for shown: Dictionary in data.get("shown", []):
		var node: Node3D = nodes.get(str(shown.node))
		if node != null:
			for w: Array in shown.when:
				_shown_by[int(w[0])].append(_shown.size())
			_shown.append({"node": node, "when": shown.when})
	for spring: Dictionary in data.get("springs", []):
		for w: Array in spring.when:
			_switches_springs[int(w[0])] = true
	_last.resize(state.outputs.size())
	_last.fill(NAN)
	for i in mini(_bindings.size(), state.outputs.size()):
		var effect: Variant = data.get("targets", [])[i].get("effect")
		if effect is Dictionary and (effect.has("rotation") or effect.has("translation")):
			for bind: Callable in _bindings[i]:
				bind.call(state.outputs[i])
	_move_bones()


## After saved values are restored, so a still figure, which never processes, shows its controller's starting look.
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


## `targets`: output indices; null binds every output.
func apply(targets: Variant = null) -> void:
	var showing := {}
	var switching := false
	var respring := _frame == 0
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
		if v != _shown_at[i] and (not _shown_by[i].is_empty() or _switches_springs.has(i)):
			_shown_at[i] = v
			respring = respring or _switches_springs.has(i)
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
			for column: int in glows.get("posts", {}):
				glows.table.set_pixel(column, Avatar.POST_ROW, glows.posts[column])
			glows.texture.update(glows.table)
	for k: int in showing:
		var node: Node3D = _shown[k].node
		var shown := shows(state.outputs, _shown[k].when)
		switching = switching or node.visible != shown
		node.visible = shown
	if respring:
		var on: Array = (state.data.get("springs", []) as Array).map(func(s: Dictionary) -> bool: return shows(state.outputs, s.when))
		switching = switching or on != _springs_on
		_springs_on = on
	if switching:
		switched.emit()


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


## In glTF local space; `from` and `to` are Unity localEulerAngles in degrees (three components) or a quaternion (four).
static func turn(from: Array, to: Array) -> Quaternion:
	var delta := (_unity(from).inverse() * _unity(to)).normalized()
	return Quaternion(delta.x, -delta.y, -delta.z, delta.w)


static func _unity(c: Array) -> Quaternion:
	if c.size() == 4:
		return Quaternion(c[0], c[1], c[2], c[3]).normalized()
	return Quaternion(Vector3.UP, deg_to_rad(c[1])) * Quaternion(Vector3.RIGHT, deg_to_rad(c[0])) * Quaternion(Vector3(0, 0, 1), deg_to_rad(c[2]))


static func _bones(nodes: Dictionary, bone: Variant) -> Array:
	var found := []
	for n: Node in nodes.values():
		if n is Skeleton3D and (n as Skeleton3D).find_bone(str(bone)) >= 0:
			found.append([n, (n as Skeleton3D).find_bone(str(bone))])
	return found


## `when`: [[switch target, 1]...]. A direct blend tree sums its children, so a switch two of them turn on reads two.
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
	var fallbacks: Array = looks.get("clearcoatFallbacks", []) if looks.get("clearcoatFallbacks") is Array else []
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


static func _set_lighting(mat: ShaderMaterial, parameter: StringName, value: Texture2D) -> void:
	mat.set_shader_parameter(parameter, value)
	if mat.has_meta("hull"):
		(mat.get_meta("hull") as ShaderMaterial).set_shader_parameter(parameter, value)


## Also binds every mesh already drawn animated, since a material swapped in may carry the looks. Returns the shared
## looks table (Avatar._lit_looks), or null for none.
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
			_set_lighting(mat, "light_index", textures[0])
			_set_lighting(mat, "lighting", textures[1])
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


## `drawn`: index -> image. {"images": the pages, "places": index -> [page, its rect in the page's UV]}.
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


## Linear, so the shader's filtering blends light and not its encoding. A stack that is no such image becomes Unity's
## default grey, keeping the rest at their layers.
static func coat_fallbacks(stacks: Array) -> Texture2DArray:
	var size := Vector2i(Avatar.FALLBACK_SIDE, Avatar.FALLBACK_SIDE / 2 * Avatar.FALLBACK_LEVELS) if not stacks.is_empty() else Vector2i.ONE
	var layers: Array[Image] = []
	for stack: Variant in stacks + [null]:
		var layer := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBH)
		layer.fill(Color(UNITY_GREY, UNITY_GREY, UNITY_GREY))
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


## `entries`: looks table column -> entry, added if new; {} where no material at the region's rect glows in its slot.
static func _glow(entries: Dictionary, region: Dictionary, looks: Dictionary) -> Dictionary:
	var materials: Array = looks.get("materials", [])
	for k in materials.size():
		var rect: Array = materials[k].get("rect", [])
		if _theme_of(materials[k]) is Dictionary and int(materials[k].emission.theme) == int(region.get("slot", 0)) and same_rect(rect, region.rect):
			return entries.get_or_add(k + 1, _entry(materials[k]))
	return {}


static func same_rect(a: Variant, b: Variant) -> bool:
	return a is Array and b is Array and a.size() == 4 and b.size() == 4 and range(4).all(func(c: int) -> bool: return is_equal_approx(a[c], b[c]))


static func _column(region: Dictionary, looks: Dictionary) -> int:
	var materials: Array = looks.get("materials", [])
	for k in materials.size():
		if same_rect(materials[k].get("rect", []), region.get("rect")):
			return k + 1
	return -1


static func _turning(entries: Dictionary, looks: Dictionary, resting: Dictionary) -> void:
	var materials: Array = looks.get("materials", [])
	for k in materials.size():
		var theme: Variant = _theme_of(materials[k])
		if theme is Dictionary and theme.speed != 0.0 and not entries.has(k + 1):
			entries[k + 1] = resting.get_or_add(k + 1, _entry(materials[k]))


static func _theme_of(look: Dictionary) -> Variant:
	var glow: Variant = look.get("emission")
	return look.themes[int(glow.theme)] if glow is Dictionary and glow.get("theme") != null else null


static func _entry(look: Dictionary) -> Dictionary:
	return {"theme": (_theme_of(look) as Dictionary).duplicate(), "replace": float(look.emission.get("replace", 0.0)), "frame": -1, "colour": Color()}


## Linear; offsets applied as Poiyomi's ModifyViaHSV does, hue turning `speed` per Unity _Time.x (seconds / 20).
static func theme_colour(theme: Dictionary, seconds: float) -> Color:
	var hsv: Array = theme.hsv
	var moved := Color.from_hsv(fposmod(hsv[0] + fposmod(theme.hue + theme.speed * seconds / 20.0, 1.0), 1.0), clampf(hsv[1] + theme.saturation, 0.0, 1.0), clampf(hsv[2] + theme.value, 0.0, 1.0))
	return Color(moved.r * theme.exposure, moved.g * theme.exposure, moved.b * theme.exposure)


## (shift, 1 + 2 * colour space + select), or zero where the image holds its colour. One number for the mode keeps the
## shader's per-slot state in vectors, which a Quest's GPU indexes far more cheaply than an array.
static func _turn(region: Dictionary) -> Color:
	var hue: Variant = region.get("hue")
	if not hue is Dictionary:
		return Color(0, 0, 0, 0)
	return Color(float(hue.get("shift", 0)), 1 + 2 * float(hue.get("space", 0)) + float(hue.get("select", 1)), 0, 0)


static func shader_for(base: BaseMaterial3D, turned: bool, coated := false, tooned := false) -> Shader:
	var way := 0
	if base != null and base.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
		way = 2 if base.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_ALWAYS else 1
	var both := base != null and base.cull_mode == BaseMaterial3D.CULL_DISABLED
	var shader: Shader = Main.need("res://src/expression%s%s%s%s%s.gdshader" % [["", "_blended", "_blended_depth"][way], "_hue" if turned else "", "_coat" if coated else "", "_toon" if tooned else "", "_two_sided" if both else ""])
	return shader


## Only a mesh that needs hue turns, a clear coat or a toon look gets those shaders: compiled in, each costs Quest 2 GPU
## time on every surface, drawn or not.
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


## `mark`, set by Avatar._lit_looks: "clearcoat", "coat_forces_fallback" or "toon".
func _marked(mesh: MeshInstance3D, mark: String) -> bool:
	var key := [mesh, mark]
	if not _marks.has(key):
		_marks[key] = range(mesh.mesh.get_surface_count()).any(func(i: int) -> bool: return mesh.mesh.surface_get_material(i) != null and mesh.mesh.surface_get_material(i).has_meta(mark))
	return _marks[key]


## False where the world has no reflection probe; coats then reflect their fallback cubemaps.
static var world_reflects := true:
	set(v):
		world_reflects = v
		RenderingServer.global_shader_parameter_set(&"world_reflects", v)

static var _fallback_shaders := {}


static func fallback_shader(coat: Shader) -> Shader:
	if not _fallback_shaders.has(coat):
		var shader := Shader.new()
		shader.code = coat.code.replace("#define CLEAR_COAT", "#define CLEAR_COAT\n#define COAT_FALLBACK")
		assert(shader.code != coat.code)
		_fallback_shaders[coat] = shader
	return _fallback_shaders[coat]


static var _clear: Texture2DArray


## A sampler array left unbound fails the material's whole uniform set, and the surface draws nothing.
static func _empty_array() -> Texture2DArray:
	if _clear == null:
		var texel := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
		_clear = Texture2DArray.new()
		_clear.create_from_images([texel])
	return _clear
