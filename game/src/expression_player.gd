class_name ExpressionPlayer
extends Node

const SkeletonBone = preload("res://addons/avatar_workshop/skeleton_bone.gd")
const SpringRuntime = preload("res://addons/avatar_workshop/spring_runtime.gd")

var state: ExpressionState
var contacts: Contacts
var icons: Array[Texture2D] = []
var _bindings: Array = []
var _scales := {}
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
var _last: Array[float] = []
var _materials := {}
var _regions := {}
var _dirty_regions := {}
var _turned := {}
## This player's copies of the looks table (Avatar._lit_looks), which an imported scene shares with every avatar opened
## from it, where Poiyomi global theme colours recolour the emission: by the mesh drawing with its own, one a clip moves
## a theme on, or by the model for its other meshes', where a theme's hue turns at rest: {"table", "texture", "entries"
## by column, each {"theme" (unity/materials.gd `_theme`), "strength", "replace"}, "dirty", "turning"}.
var _glows := {}
## The table entries of the materials whose theme turns at rest that no clip moves, by column, one each whichever tables
## hold them, so each is coloured once a frame.
var _resting := {}
var _seconds := 0.0
var _frame := 0

const TEXTURES := {"hue": ["hue_mask"], "color": ["untinted"], "tone": ["hue_mask"], "look": []}
## Clear texels round each decal on its page, so the first mips of one never read its neighbour.
const DECAL_PAD := 8
## The expression shaders by whether they turn decal hues, each cut out, blended, and blended writing depth.
const SHADERS := [
	[preload("res://src/expression.gdshader"), preload("res://src/expression_blended.gdshader"), preload("res://src/expression_blended_depth.gdshader")],
	[preload("res://src/expression_hue.gdshader"), preload("res://src/expression_blended_hue.gdshader"), preload("res://src/expression_blended_depth_hue.gdshader")]]
## The look fields that drive a decal, in the order the shader reads them.
const DECAL_FIELDS := ["decal", "decalIntensity", "decalHue"]


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
				_scales[_bindings.size()] = true
				for at: Array in _bones(nodes, effect.scale.node):
					var skeleton: Skeleton3D = at[0]
					var bone: int = at[1]
					var axis := int(effect.scale.axis)
					binds.append(func(v: float) -> void:
						var s := skeleton.get_bone_pose_scale(bone)
						s[axis] = v
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
			elif effect.has("material"):
				var mesh: MeshInstance3D = nodes.get(str(effect.material.node))
				if mesh != null:
					var mats := _material(mesh)
					var choices: Array = effect.material.choices
					binds.append(func(v: float) -> void:
						var uv: Array = choices[clampi(roundi(v), 0, choices.size() - 1)]
						for mat in mats:
							mat.set_shader_parameter("atlas", Vector4(uv[0], uv[1], uv[2], uv[3])))
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
					if mesh == null or (kind == "look" and not str(region.get("field", "")).begins_with("decal")):
						continue
					var mats := _material(mesh)
					var decals: Dictionary = model.get_meta("expression_decal_sets", {}).get(str(region.node), {})
					var place: Array = decals.get("places", {}).get(int(region.get("image", -1)), [0, 0.0, 0.0, 0.0, 0.0])
					var entry := {"rect": region.rect, "value": float(target.get("default", 0)), "kind": ExpressionDefinition.REGIONS.find(kind), "settings": _settings(kind, region, place[0]), "decal": place.slice(1), "turn": _turn(region)}
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
	if shared is ImageTexture:
		var turning := {"entries": {}, "dirty": true, "turning": false}
		_turning(turning.entries, looks, _resting)
		if not turning.entries.is_empty():
			_glows[model] = turning
	for owner: Object in _glows.keys():
		var glows: Dictionary = _glows[owner]
		var mats: Array = _materials.values().reduce(func(all: Array, m: Array) -> Array: return all + m, []) if owner == model else _materials.get(owner, [])
		var lighting: Variant = shared if owner == model else mats[0].get_shader_parameter("lighting") if not mats.is_empty() else null
		if not lighting is ImageTexture or glows.entries.is_empty():
			_glows.erase(owner)
			continue
		_turning(glows.entries, looks, _resting)
		glows.table = (lighting as ImageTexture).get_image().duplicate() as Image
		glows.texture = ImageTexture.create_from_image(glows.table)
		for mat: ShaderMaterial in mats:
			if mat.get_shader_parameter("lighting") == lighting:
				mat.set_shader_parameter("lighting", glows.texture)
	for shown: Dictionary in data.get("shown", []):
		var node: Node3D = nodes.get(str(shown.node))
		if node != null:
			_shown.append({"node": node, "when": shown.when})
	_last.resize(state.outputs.size())
	_last.fill(NAN)
	for i in mini(_bindings.size(), state.outputs.size()):
		var effect: Variant = data.get("targets", [])[i].get("effect")
		if effect is Dictionary and (effect.has("rotation") or effect.has("translation")):
			for bind: Callable in _bindings[i]:
				bind.call(state.outputs[i])
	_move_bones()


func _process(delta: float) -> void:
	_seconds += delta
	var body := get_parent() as Avatar
	if contacts.receives() and body != null and body.is_in_group(Contacts.BODIES):
		contacts.sense(state, Contacts.gather(get_tree()), body, body.local, delta)
	state.advance(delta)
	apply()


func apply() -> void:
	for i in state.outputs.size():
		var v := state.outputs[i]
		if _scales.has(i) or not is_equal_approx(v, _last[i]):
			for bind: Callable in _bindings[i]:
				bind.call(v)
			_last[i] = v
	_move_bones()
	for mat: ShaderMaterial in _dirty_regions:
		var entries: Array = _regions[mat]
		var image := Image.create(entries.size(), 5, false, Image.FORMAT_RGBAF)
		for k in entries.size():
			var e: Dictionary = entries[k]
			var s: Array = e.settings
			image.set_pixel(k, 0, Color(e.rect[0], e.rect[1], e.rect[2], e.rect[3]))
			image.set_pixel(k, 1, Color(e.value, e.kind, s[0], s[1]))
			image.set_pixel(k, 2, Color(s[2], s[3], s[4], e.turn.g))
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
					var c := theme_colour(e.theme, _seconds) * float(e.strength)
					e.colour = Color(c.r, c.g, c.b, e.replace)
				glows.table.set_pixel(column, 1, e.colour)
			glows.texture.update(glows.table)
	for shown: Dictionary in _shown:
		shown.node.visible = shows(state.outputs, shown.when)


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
	for encoded: String in data.get("icons", []):
		var img := Image.new()
		icons.append(ImageTexture.create_from_image(img) if img.load_png_from_buffer(Marshalls.base64_to_raw(encoded)) == OK else null)
	model.set_meta("expression_icons", icons)
	var shrink: int = model.get_meta("texture_shrink", 1)
	var decode := func(encoded: Variant, mipmapped: bool) -> Image:
		var img := Image.new()
		if not encoded is String or img.load_png_from_buffer(Marshalls.base64_to_raw(encoded)) != OK:
			return null
		img.convert(Image.FORMAT_RGBA8)
		Avatar.scale_down(img, shrink, mipmapped)
		return img
	var looks: Dictionary = data.get("looks", {})
	for pair: Array in [[data.get("hueMask"), "hue_mask", false], [data.get("colorAtlas"), "untinted", true], [looks.get("emission"), "glow", true]]:
		var img: Image = decode.call(pair[0], pair[2])
		if img != null:
			model.set_meta("expression_" + pair[1], ImageTexture.create_from_image(img))
	var decals: Array = looks.get("decals", [])
	looks.erase("decals")
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


## Binds the material index, looks table (Avatar._lit_looks) and emission map to the meshes whose materials carry them,
## the ones that show a flat or glowing material, and to every mesh already drawn animated, since a material swapped in
## may be either. Returns the looks table they share, or null for none.
func _light_looks(model: Node3D) -> Variant:
	var textures: Array = []
	var looked := []
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for i in mesh.mesh.get_surface_count():
			var m := mesh.get_active_material(i)
			if m != null and m.has_meta("light_index"):
				textures = [m.get_meta("light_index"), m.get_meta("lighting")]
				looked.append(mesh)
				break
	if textures.is_empty():
		return null
	var glow: Texture2D = model.get_meta("expression_glow") if model.has_meta("expression_glow") else null
	for mesh: MeshInstance3D in looked:
		_material(mesh)
	for mats: Array[ShaderMaterial] in _materials.values():
		for mat in mats:
			mat.set_shader_parameter("light_index", textures[0])
			mat.set_shader_parameter("lighting", textures[1])
			mat.set_shader_parameter("glow", glow)
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


static func _settings(kind: String, region: Dictionary, page: int) -> Array:
	match kind:
		"hue":
			return [region.get("space", 0), region.get("shift", 1), 0, 0, 0]
		"color":
			var c: Array = region.get("color", [1, 1, 1])
			return [region.get("channel", 0), 0, c[0], c[1], c[2]]
		"tone":
			return [region.get("channel", 0), 0, 0, 0, 0]
	return [region.get("slot", 0), region.colorBlend, region.get("alpha", 1), DECAL_FIELDS.find(region.get("field", "decal")), page]


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
	return {"theme": (_theme_of(look) as Dictionary).duplicate(), "strength": look.emission.strength, "replace": float(look.emission.get("replace", 0.0)), "frame": -1, "colour": Color()}


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


## The materials drawing every surface of `mesh` as animated, one for each way its surfaces draw: cut out, blended, or
## blended writing depth. Only a mesh with a decal whose hue turns draws with the shaders that turn it: compiled in, the
## turn costs a Quest 2 a few milliseconds a frame on every surface, turned or not.
func _material(mesh: MeshInstance3D) -> Array[ShaderMaterial]:
	if _materials.has(mesh):
		return _materials[mesh]
	var by_shader := {}
	for i in mesh.mesh.get_surface_count():
		var base := mesh.get_active_material(i) as BaseMaterial3D
		var way := 0
		if base != null and base.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
			way = 2 if base.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_ALWAYS else 1
		var shader: Shader = SHADERS[1 if _turned.has(str(mesh.name)) else 0][way]
		if not by_shader.has(shader):
			var mat := ShaderMaterial.new()
			mat.shader = shader
			mat.set_shader_parameter("decals", _no_decals())
			if base != null:
				mat.set_shader_parameter("picture", base.albedo_texture)
				mat.set_shader_parameter("colour", base.albedo_color)
				mat.set_shader_parameter("use_vertex", base.vertex_color_use_as_albedo)
				mat.set_meta("icon_material", Hand._icon_material(base, mesh))
			by_shader[shader] = mat
		mesh.set_surface_override_material(i, by_shader[shader])
	var out: Array[ShaderMaterial] = []
	out.assign(by_shader.values())
	_materials[mesh] = out
	return out


static var _clear: Texture2DArray


## A material whose model draws no decals still binds a decal array: a sampler array left unbound fails the material's
## whole uniform set, and the surface draws nothing.
static func _no_decals() -> Texture2DArray:
	if _clear == null:
		var texel := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
		_clear = Texture2DArray.new()
		_clear.create_from_images([texel])
	return _clear
