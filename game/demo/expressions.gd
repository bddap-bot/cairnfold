extends RefCounted

const HAT := Color(0.9, 0.12, 0.06)
const SIZE := 32


## Authored test controls on Cairnfold's generated avatar, used by the device replay and headless checks.
static func scene() -> PackedScene:
	var model := Avatar.built_in(0).instantiate() as Node3D
	var bones: Dictionary = model.get_meta("humanoid")
	var skeleton := model.get_node(str(bones.head).get_slice(":", 0)) as Skeleton3D
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = (bones.head as NodePath).get_concatenated_subnames()
	skeleton.add_child(attachment)
	var hat := MeshInstance3D.new()
	hat.name = "ExpressionHat"
	var shape := CylinderMesh.new()
	shape.top_radius = 0.17
	shape.bottom_radius = 0.22
	shape.height = 0.16
	hat.mesh = shape
	hat.position.y = 0.18
	var mat := StandardMaterial3D.new()
	var picture := untinted()
	for y in picture.get_height():
		for x in picture.get_width():
			picture.set_pixel(x, y, picture.get_pixel(x, y) * HAT)
	mat.albedo_texture = ImageTexture.create_from_image(picture)
	hat.set_surface_override_material(0, mat)
	attachment.add_child(hat)
	model.set_meta("expressions", definition())
	return Avatar.model(model)


static func definition() -> Dictionary:
	var parameters := []
	for key: String in ["Hat", "Size", "Horizontal", "Vertical", "Up", "Right", "Down", "Left", "Pulse", "Menu", "Puppet", "Colour", "Tone", "Decal"]:
		parameters.append({"name": key, "type": "bool" if key == "Hat" else "float", "default": 0.5 if key == "Size" else 0.0, "saved": key not in ["Pulse", "Menu", "Puppet"]})
	var control := func(name: String, kind: String, parameter: String, axes: Array = []) -> Dictionary:
		return {"name": name, "type": kind, "parameter": parameter, "value": 1.0, "axes": axes}
	var toggle: Dictionary = control.call("Hat", "toggle", "Hat")
	var radial: Dictionary = control.call("Size", "radial", "Puppet", ["Size"])
	var two: Dictionary = control.call("Two axes", "twoAxis", "Puppet", ["Horizontal", "Vertical"])
	var four: Dictionary = control.call("Four axes", "fourAxis", "Puppet", ["Up", "Right", "Down", "Left"])
	var nested: Dictionary = control.call("Shape", "submenu", "Menu")
	nested.controls = [radial, two, four]
	var data := {"parameters": parameters, "menu": [toggle, control.call("Flash", "button", "Pulse"), nested], "icons": [],
		"targets": [{"effect": "switch", "default": 0.0}], "shown": [{"node": "ExpressionHat", "when": [[0, 1]]}],
		"clips": [{"length": 1.0, "curves": [{"target": 0, "step": true, "keys": [[0, 0]]}]},
			{"length": 1.0, "curves": [{"target": 0, "step": true, "keys": [[0, 1]]}]}],
		"layers": [{"default": 0, "weight": 1.0, "states": [
			{"motion": {"clip": 0}, "transitions": [
				{"to": 1, "conditions": [{"parameter": "Hat", "mode": "if"}]},
				{"to": 1, "conditions": [{"parameter": "Pulse", "mode": "if"}]}]},
			{"motion": {"clip": 1}, "transitions": [{"to": 0, "conditions": [
				{"parameter": "Hat", "mode": "ifNot"}, {"parameter": "Pulse", "mode": "ifNot"}]}]}]}]}

	data.targets.append({"effect": {"scale": {"node": "head", "axis": 0}}, "default": 1.0})
	data.clips.append({"length": 1.0, "curves": [{"target": 1, "step": false, "keys": [[0, 0.7], [1, 1.3]]}]})
	data.layers.append({"weight": 1.0, "default": 0, "states": [{"writeDefaults": false, "motion": {"clip": 2, "time": "Size"}}]})

	var region := {"node": "ExpressionHat", "rect": [0, 0, 1, 1]}
	var drives := [
		["Colour", {"color": [region.merged({"channel": 2, "color": [HAT.r, HAT.g, HAT.b]})]}, HAT.b, 1.0],
		["Tone", {"tone": [region.merged({"channel": 1})]}, 0.0, -1.0],
		["Decal", {"decal": [region.merged({"slot": 0, "multiply": false, "intensity": false, "alpha": 0.0})]}, 0.0, 1.0]]
	for drive: Array in drives:
		data.menu.append(control.call(drive[0], "toggle", drive[0]))
		data.targets.append({"effect": drive[1], "default": drive[2]})
		data.clips.append({"length": 1.0, "curves": [{"target": data.targets.size() - 1, "step": false, "keys": [[0, drive[2]], [1, drive[3]]]}]})
		data.layers.append({"weight": 1.0, "default": 0, "states": [{"writeDefaults": false, "motion": {"clip": data.clips.size() - 1, "time": drive[0]}}]})
	data.colorAtlas = Marshalls.raw_to_base64(untinted().save_png_to_buffer())
	data.decals = [Marshalls.raw_to_base64(decal().save_png_to_buffer())]
	return data


static func untinted() -> Image:
	var image := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			image.set_pixel(x, y, Color.WHITE if (y / 4) % 2 == 0 else Color(0.75, 0.75, 0.75))
	return image


static func decal() -> Image:
	var image := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			image.set_pixel(x, y, Color(0.1, 0.35, 1.0) if ((x + y) / 4) % 2 == 0 else Color(0, 0, 0, 0))
	return image
