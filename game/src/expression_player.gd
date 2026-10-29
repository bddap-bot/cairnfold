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
			elif effect.has("hue"):
				for region: Dictionary in effect.hue:
					var mesh: MeshInstance3D = nodes.get(str(region.node))
					if mesh == null:
						continue
					var mat := _material(mesh)
					var list: Array = _regions.get_or_add(mat, [])
					var entry := {"rect": region.rect, "value": float(target.get("default", 0)), "space": region.get("space", 0), "shift": region.get("shift", 1)}
					list.append(entry)
					if model.has_meta("expression_hue_mask"):
						mat.set_shader_parameter("hue_mask", model.get_meta("expression_hue_mask"))
						mat.set_shader_parameter("masked", true)
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
		var image := Image.create(entries.size(), 2, false, Image.FORMAT_RGBAF)
		for k in entries.size():
			var e: Dictionary = entries[k]
			image.set_pixel(k, 0, Color(e.rect[0], e.rect[1], e.rect[2], e.rect[3]))
			image.set_pixel(k, 1, Color(e.value, e.space, e.shift, 0))
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
	if data.has("hueMask"):
		var img := Image.new()
		if img.load_png_from_buffer(Marshalls.base64_to_raw(data.hueMask)) == OK:
			model.set_meta("expression_hue_mask", ImageTexture.create_from_image(img))


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
