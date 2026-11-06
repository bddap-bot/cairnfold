class_name ExpressionPlayer
extends Node

var state: ExpressionState
var icons: Array[Texture2D] = []
var _bindings: Array = []
var _scales := {}
var _shown: Array = []
var _last: Array[float] = []
var _materials := {}
var _regions := {}
var _dirty_regions := {}

const TEXTURES := {"hue": ["hue_mask"], "color": ["untinted"], "tone": ["hue_mask"], "look": []}
## Clear texels round each decal on its page, so the first mips of one never read its neighbour.
const DECAL_PAD := 8


func _init(model: Node3D) -> void:
	var data: Dictionary = model.get_meta("expressions", {})
	process_priority = 1
	state = ExpressionState.new(data)
	var nodes := {}
	for n: Node in model.find_children("*", "", true, false):
		nodes[str(n.name)] = n
	icons.assign(model.get_meta("expression_icons", []))
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
				for n: Node in nodes.values():
					if n is Skeleton3D:
						var skeleton := n as Skeleton3D
						var bone := skeleton.find_bone(str(effect.scale.node))
						var axis := int(effect.scale.axis)
						if bone >= 0:
							binds.append(func(v: float) -> void:
								var s := skeleton.get_bone_pose_scale(bone)
								s[axis] = v
								skeleton.set_bone_pose_scale(bone, s))
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
					if mesh == null or (kind == "look" and not str(region.get("field", "")).begins_with("decal")):
						continue
					var mats := _material(mesh)
					var decals: Dictionary = model.get_meta("expression_decal_sets", {}).get(str(region.node), {})
					var place: Array = decals.get("places", {}).get(int(region.get("image", -1)), [0, 0.0, 0.0, 0.0, 0.0])
					var entry := {"rect": region.rect, "value": float(target.get("default", 0)), "kind": ExpressionDefinition.REGIONS.find(kind), "settings": _settings(kind, region, place[0]), "decal": place.slice(1)}
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
	_light_flat(model)
	for shown: Dictionary in data.get("shown", []):
		var node: Node3D = nodes.get(str(shown.node))
		if node != null:
			_shown.append({"node": node, "when": shown.when})
	_last.resize(state.outputs.size())
	_last.fill(NAN)


func _process(delta: float) -> void:
	state.advance(delta)
	apply()


func apply() -> void:
	for i in state.outputs.size():
		var v := state.outputs[i]
		if _scales.has(i) or not is_equal_approx(v, _last[i]):
			for bind: Callable in _bindings[i]:
				bind.call(v)
			_last[i] = v
	for mat: ShaderMaterial in _dirty_regions:
		var entries: Array = _regions[mat]
		var image := Image.create(entries.size(), 4, false, Image.FORMAT_RGBAF)
		for k in entries.size():
			var e: Dictionary = entries[k]
			var s: Array = e.settings
			image.set_pixel(k, 0, Color(e.rect[0], e.rect[1], e.rect[2], e.rect[3]))
			image.set_pixel(k, 1, Color(e.value, e.kind, s[0], s[1]))
			image.set_pixel(k, 2, Color(s[2], s[3], s[4], 0))
			image.set_pixel(k, 3, Color(e.decal[0], e.decal[1], e.decal[2], e.decal[3]))
		var texture := mat.get_shader_parameter("regions") as ImageTexture
		if texture == null:
			texture = ImageTexture.create_from_image(image)
			mat.set_shader_parameter("regions", texture)
			mat.set_shader_parameter("region_count", entries.size())
		else:
			texture.update(image)
	_dirty_regions.clear()
	for shown: Dictionary in _shown:
		shown.node.visible = shows(state.outputs, shown.when)


## Whether a mesh drawn under `when`, [[switch target, 1]...], draws at `outputs`. A direct blend tree sums its
## children, so a switch two of them turn on reads two.
static func shows(outputs: Array[float], when: Array) -> bool:
	return when.all(func(w: Array) -> bool: return is_equal_approx(minf(outputs[int(w[0])], 1.0), float(w[1])))


static func prepare(model: Node3D) -> void:
	var icons: Array[Texture2D] = []
	for encoded: String in (model.get_meta("expressions", {}) as Dictionary).get("icons", []):
		var img := Image.new()
		icons.append(ImageTexture.create_from_image(img) if img.load_png_from_buffer(Marshalls.base64_to_raw(encoded)) == OK else null)
	model.set_meta("expression_icons", icons)
	var data: Dictionary = model.get_meta("expressions", {})
	var shrink: int = model.get_meta("texture_shrink", 1)
	var decode := func(encoded: Variant, mipmapped: bool) -> Image:
		var img := Image.new()
		if not encoded is String or img.load_png_from_buffer(Marshalls.base64_to_raw(encoded)) != OK:
			return null
		img.convert(Image.FORMAT_RGBA8)
		if shrink > 1:
			img.resize(maxi(1, img.get_width() / shrink), maxi(1, img.get_height() / shrink), Image.INTERPOLATE_LANCZOS)
		if mipmapped:
			img.generate_mipmaps()
		return img
	for pair: Array in [["hueMask", "hue_mask", false], ["colorAtlas", "untinted", true]]:
		var img: Image = decode.call(data.get(pair[0]), pair[2])
		if img != null:
			model.set_meta("expression_" + pair[1], ImageTexture.create_from_image(img))
	var looks: Dictionary = data.get("looks", {})
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


## Binds the material index and lighting table (Avatar._flat_lit) to the meshes whose materials carry them, the ones
## that show a flat material, and to every mesh already drawn animated, since a material swapped in may be flat.
func _light_flat(model: Node3D) -> void:
	var textures: Array = []
	var flat := []
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for i in mesh.mesh.get_surface_count():
			var m := mesh.get_active_material(i)
			if m != null and m.has_meta("light_index"):
				textures = [m.get_meta("light_index"), m.get_meta("lighting")]
				flat.append(mesh)
				break
	if textures.is_empty():
		return
	for mesh: MeshInstance3D in flat:
		_material(mesh)
	for mats: Array[ShaderMaterial] in _materials.values():
		for mat in mats:
			mat.set_shader_parameter("light_index", textures[0])
			mat.set_shader_parameter("lighting", textures[1])
			mat.set_shader_parameter("mirror_mask", Quality.MIRROR_MASK)


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
	return [region.get("slot", 0), 1 if region.get("multiply", false) else 0, region.get("alpha", 1), 1 if region.get("field") == "decalIntensity" else 0, page]


## The materials drawing every surface of `mesh` as animated, one for each way its surfaces draw: cut out, blended, or
## blended writing depth.
func _material(mesh: MeshInstance3D) -> Array[ShaderMaterial]:
	if _materials.has(mesh):
		return _materials[mesh]
	var by_shader := {}
	for i in mesh.mesh.get_surface_count():
		var base := mesh.get_active_material(i) as BaseMaterial3D
		var shader: Shader = preload("res://src/expression.gdshader")
		if base != null and base.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
			shader = preload("res://src/expression_blended_depth.gdshader") if base.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_ALWAYS else preload("res://src/expression_blended.gdshader")
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
