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

const TEXTURES := {"hue": ["hue_mask"], "color": ["untinted"], "tone": ["hue_mask"], "look": ["decals"]}


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
					var mat := _material(mesh)
					var choices: Array = effect.material.choices
					binds.append(func(v: float) -> void:
						var uv: Array = choices[clampi(roundi(v), 0, choices.size() - 1)]
						mat.set_shader_parameter("atlas", Vector4(uv[0], uv[1], uv[2], uv[3])))
			else:
				var kind: String = effect.keys()[0]
				for region: Dictionary in effect[kind]:
					var mesh: MeshInstance3D = nodes.get(str(region.node))
					if mesh == null or (kind == "look" and not str(region.get("field", "")).begins_with("decal")):
						continue
					var mat := _material(mesh)
					var list: Array = _regions.get_or_add(mat, [])
					var entry := {"rect": region.rect, "value": float(target.get("default", 0)), "kind": ExpressionDefinition.REGIONS.find(kind), "settings": _settings(kind, region)}
					list.append(entry)
					for uniform: String in TEXTURES[kind]:
						if model.has_meta("expression_" + uniform):
							mat.set_shader_parameter(uniform, model.get_meta("expression_" + uniform))
					binds.append(func(v: float) -> void:
						entry.value = v
						_dirty_regions[mat] = true)
		_bindings.append(binds)
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
		var image := Image.create(entries.size(), 3, false, Image.FORMAT_RGBAF)
		for k in entries.size():
			var e: Dictionary = entries[k]
			var s: Array = e.settings
			image.set_pixel(k, 0, Color(e.rect[0], e.rect[1], e.rect[2], e.rect[3]))
			image.set_pixel(k, 1, Color(e.value, e.kind, s[0], s[1]))
			image.set_pixel(k, 2, Color(s[2], s[3], s[4], 0))
		var texture := mat.get_shader_parameter("regions") as ImageTexture
		if texture == null:
			texture = ImageTexture.create_from_image(image)
			mat.set_shader_parameter("regions", texture)
			mat.set_shader_parameter("region_count", entries.size())
		else:
			texture.update(image)
	_dirty_regions.clear()
	for shown: Dictionary in _shown:
		shown.node.visible = (shown.when as Array).all(func(w: Array) -> bool: return is_equal_approx(state.outputs[int(w[0])], float(w[1])))


static func prepare(model: Node3D) -> void:
	var icons: Array[Texture2D] = []
	for encoded: String in (model.get_meta("expressions", {}) as Dictionary).get("icons", []):
		var img := Image.new()
		icons.append(ImageTexture.create_from_image(img) if img.load_png_from_buffer(Marshalls.base64_to_raw(encoded)) == OK else null)
	model.set_meta("expression_icons", icons)
	var data: Dictionary = model.get_meta("expressions", {})
	var decode := func(encoded: Variant, mipmapped: bool) -> Image:
		var img := Image.new()
		if not encoded is String or img.load_png_from_buffer(Marshalls.base64_to_raw(encoded)) != OK:
			return null
		img.convert(Image.FORMAT_RGBA8)
		if mipmapped:
			img.generate_mipmaps()
		return img
	for pair: Array in [["hueMask", "hue_mask", false], ["colorAtlas", "untinted", true]]:
		var img: Image = decode.call(data.get(pair[0]), pair[2])
		if img != null:
			model.set_meta("expression_" + pair[1], ImageTexture.create_from_image(img))
	var layers: Array[Image] = []
	for encoded: Variant in data.get("looks", {}).get("decals", []):
		layers.append(decode.call(encoded, true))
	if not layers.is_empty() and layers.all(func(l: Image) -> bool: return l != null and l.get_size() == layers[0].get_size()):
		var decals := Texture2DArray.new()
		if decals.create_from_images(layers) == OK:
			model.set_meta("expression_decals", decals)


static func _settings(kind: String, region: Dictionary) -> Array:
	match kind:
		"hue":
			return [region.get("space", 0), region.get("shift", 1), 0, 0, 0]
		"color":
			var c: Array = region.get("color", [1, 1, 1])
			return [region.get("channel", 0), 0, c[0], c[1], c[2]]
		"tone":
			return [region.get("channel", 0), 0, 0, 0, 0]
	return [region.get("slot", 0), 1 if region.get("multiply", false) else 0, region.get("alpha", 1), 1 if region.get("field") == "decalIntensity" else 0, 0]


func _material(mesh: MeshInstance3D) -> ShaderMaterial:
	if _materials.has(mesh):
		return _materials[mesh]
	var base := mesh.get_active_material(0) as BaseMaterial3D
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://src/expression.gdshader")
	if base != null:
		mat.set_shader_parameter("picture", base.albedo_texture)
		mat.set_shader_parameter("colour", base.albedo_color)
		mat.set_shader_parameter("use_vertex", base.vertex_color_use_as_albedo)
		mat.set_meta("icon_material", Hand._icon_material(base, mesh))
	mesh.set_surface_override_material(0, mat)
	_materials[mesh] = mat
	return mat
