extends RefCounted


const Yaml = preload("res://../scripts/unity/yaml.gd")
const Assets = preload("res://../scripts/unity/assets.gd")

const ATLAS := 2048
const PAD := 4
const TEXTURES := ["_MainTex", "_BaseMap", "_BaseColorMap", "_MainTexture", "_Albedo"]
const COLOURS := ["_Color", "_BaseColor", "_MainColor"]
enum Alpha { OPAQUE, CUTOUT, BLEND }

var assets: Assets
var materials := {}
var _images := {}
var atlas: Image
var undecoded := {}
var hue_masks := {}
var color_regions := {}


func _init(from: Assets) -> void:
	assets = from


func use(ref: Dictionary, fallback: Color) -> String:
	var guid := str(ref.get("guid", ""))
	var key := guid if assets.by_guid.has(guid) and assets.extension(guid) == "mat" else "missing:" + str(ref.get("name", guid))
	if materials.has(key):
		return key
	var m := {"name": str(ref.get("name", key)), "shader": "", "texture": "", "colour": fallback, "scale": Vector2.ONE, "offset": Vector2.ZERO, "alpha": Alpha.OPAQUE, "cutoff": 0.5, "cull": true, "image": null}
	if key == guid:
		_read(m, guid)
	if m.texture != "":
		m.image = image(m.texture)
	materials[key] = m
	return key


func _read(m: Dictionary, guid: String) -> void:
	var lines: Array[String] = []
	lines.assign(assets.text(guid).split("\n"))
	var mat: Dictionary = Yaml.document(lines).get("Material", {})
	m.name = str(mat.get("m_Name", assets.name(guid)))
	var shader: Dictionary = mat.get("m_Shader", {})
	m.shader = _shader_name(shader)
	m.properties = {}
	var shader_guid := str(shader.get("guid", ""))
	if assets.by_guid.has(shader_guid):
		var property := RegEx.create_from_string("(_[A-Za-z0-9_]+)\\s*\\(\\s*\"")
		for found in property.search_all(assets.text(shader_guid)):
			m.properties[found.get_string(1)] = true
	var saved: Dictionary = mat.get("m_SavedProperties", {})
	var textures := _properties(saved.get("m_TexEnvs"))
	m.textures = textures
	m.keywords = mat.get("m_ValidKeywords", [])
	var floats := _properties(saved.get("m_Floats"))
	m.floats = floats
	var colours := _properties(saved.get("m_Colors"))
	for k: String in TEXTURES:
		var t: Variant = textures.get(k)
		if t is Dictionary and str((t.get("m_Texture", {}) as Dictionary).get("guid", "")) != "":
			m.texture = str(t.m_Texture.guid)
			m.scale = _vector2(t.get("m_Scale"), Vector2.ONE)
			m.offset = _vector2(t.get("m_Offset"), Vector2.ZERO)
			break
	for k: String in COLOURS:
		if colours.get(k) is Dictionary:
			var c: Dictionary = colours[k]
			m.colour = Color(str(c.get("r", "1")).to_float(), str(c.get("g", "1")).to_float(), str(c.get("b", "1")).to_float(), str(c.get("a", "1")).to_float())
			break
	var queue := str(mat.get("m_CustomRenderQueue", "-1")).to_int()
	var tags: Variant = mat.get("stringTagMap")
	var render_type := str((tags as Dictionary).get("RenderType", "")) if tags is Dictionary else ""
	var mode := str(floats.get("_Mode", "0")).to_int()
	if queue >= 3000 or render_type == "Transparent" or m.shader.contains("Transparent") or mode >= 2:
		m.alpha = Alpha.BLEND
	elif queue >= 2450 or render_type == "TransparentCutout" or m.shader.contains("Cutout") or mode == 1:
		m.alpha = Alpha.CUTOUT
		m.cutoff = str(floats.get("_Cutoff", "0.5")).to_float()
	if floats.has("_Cull"):
		m.cull = str(floats._Cull).to_float() != 0.0


func _shader_name(ref: Dictionary) -> String:
	var guid := str(ref.get("guid", ""))
	if assets.by_guid.has(guid):
		for line in assets.text(guid).split("\n", false, 8):
			if line.strip_edges().begins_with("Shader \""):
				return line.strip_edges().get_slice("\"", 1)
		return assets.name(guid)
	return "Standard" if str(ref.get("fileID", "")) == "46" else "not in package (%s)" % guid.left(8)


static func _properties(list: Variant) -> Dictionary:
	var out := {}
	if not list is Array:
		return out
	for e: Variant in list:
		if not e is Dictionary:
			continue
		if e.has("first") and e.first is Dictionary:
			out[str(e.first.get("name", ""))] = e.get("second")
		else:
			for k: Variant in e:
				out[str(k)] = e[k]
	return out


static func _vector2(v: Variant, otherwise: Vector2) -> Vector2:
	if v is Dictionary:
		return Vector2(str(v.get("x", otherwise.x)).to_float(), str(v.get("y", otherwise.y)).to_float())
	return otherwise


func image(guid: String) -> Image:
	if _images.has(guid):
		return _images[guid]
	if not assets.by_guid.has(guid):
		undecoded["not in the package: " + guid] = true
		_images[guid] = null
		return null
	var bytes := FileAccess.get_file_as_bytes(assets.by_guid[guid].file)
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	match assets.extension(guid):
		"png":
			err = img.load_png_from_buffer(bytes)
		"jpg", "jpeg":
			err = img.load_jpg_from_buffer(bytes)
		"tga":
			err = img.load_tga_from_buffer(bytes)
		"bmp":
			err = img.load_bmp_from_buffer(bytes)
		"webp":
			err = img.load_webp_from_buffer(bytes)
	if err != OK:
		undecoded[assets.by_guid[guid].path] = true
		img = null
	else:
		img.decompress()
		img.convert(Image.FORMAT_RGBA8)
	_images[guid] = img
	return img


func pack(used: Array) -> void:
	var sizes := {}
	for key: String in used:
		var m: Dictionary = materials[key]
		var img: Image = m.image
		var side := Vector2i(8, 8) if img == null else img.get_size()
		var big := maxi(side.x, side.y)
		if big > ATLAS / 2:
			side = Vector2i(maxi(1, side.x * (ATLAS / 2) / big), maxi(1, side.y * (ATLAS / 2) / big))
		sizes[key] = side
	var factor := 1.0
	var cells := {}
	while true:
		cells = _shelves(used, sizes, factor)
		if not cells.is_empty():
			break
		factor *= 0.9
	atlas = Image.create_empty(ATLAS, ATLAS, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0.5, 0.5, 0.5, 1.0))
	for key: String in used:
		var m: Dictionary = materials[key]
		var cell: Rect2i = cells[key]
		m.cell = cell
		var img: Image
		if m.image == null:
			img = Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
			img.fill(Color.WHITE)
		else:
			img = (m.image as Image).duplicate()
		img.resize(cell.size.x, cell.size.y, Image.INTERPOLATE_CUBIC)
		_tint(img, m.colour, m.alpha, m.cutoff)
		var outer := img.duplicate() as Image
		outer.resize(cell.size.x + 2 * PAD, cell.size.y + 2 * PAD, Image.INTERPOLATE_BILINEAR)
		atlas.blit_rect(outer, Rect2i(Vector2i.ZERO, outer.get_size()), cell.position - Vector2i(PAD, PAD))
		atlas.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), cell.position)


static func _tint(img: Image, colour: Color, alpha: Alpha, cutoff: float) -> void:
	var data := img.get_data()
	var mul := [colour.r, colour.g, colour.b, colour.a]
	for i in range(0, data.size(), 4):
		for c in 3:
			data[i + c] = int(data[i + c] * mul[c])
		var a: float = data[i + 3] * float(mul[3]) / 255.0
		data[i + 3] = 255 if alpha == Alpha.OPAQUE or (alpha == Alpha.CUTOUT and a >= cutoff) else 0 if alpha == Alpha.CUTOUT else int(a * 255.0)
	img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)


static func _shelves(keys: Array, sizes: Dictionary, factor: float) -> Dictionary:
	var order := keys.duplicate()
	order.sort_custom(func(a: String, b: String) -> bool: return sizes[a].y > sizes[b].y)
	var out := {}
	var x := 0
	var y := 0
	var row := 0
	for key: String in order:
		var s := Vector2i(maxi(1, int(sizes[key].x * factor)), maxi(1, int(sizes[key].y * factor)))
		var w := s.x + 2 * PAD
		var h := s.y + 2 * PAD
		if x + w > ATLAS:
			x = 0
			y += row
			row = 0
		if y + h > ATLAS:
			return {}
		out[key] = Rect2i(Vector2i(x + PAD, y + PAD), s)
		x += w
		row = maxi(row, h)
	return out


func place(key: String, uv: Vector2) -> Array:
	var m: Dictionary = materials[key]
	var u := Vector2(uv.x, 1.0 - uv.y) * (m.scale as Vector2) + (m.offset as Vector2)
	var inside := u.x >= -0.001 and u.x <= 1.001 and u.y >= -0.001 and u.y <= 1.001
	u = u.clamp(Vector2.ZERO, Vector2.ONE)
	var cell: Rect2i = m.cell
	return [(Vector2(cell.position) + Vector2(u.x, 1.0 - u.y) * Vector2(cell.size)) / ATLAS, not inside]


func moved(from: String, to: String) -> Array:
	var affine := func(key: String) -> Array:
		var m: Dictionary = materials[key]
		var cell: Rect2 = Rect2(m.cell)
		var scale: Vector2 = m.scale
		var offset: Vector2 = m.offset
		return [Vector2(scale.x * cell.size.x, scale.y * cell.size.y) / ATLAS, Vector2(cell.position.x + offset.x * cell.size.x, cell.position.y + cell.size.y * (1.0 - scale.y - offset.y)) / ATLAS]
	var a: Array = affine.call(from)
	var b: Array = affine.call(to)
	var s: Vector2 = Vector2(b[0].x / a[0].x if a[0].x != 0.0 else 1.0, b[0].y / a[0].y if a[0].y != 0.0 else 1.0)
	return [s, (b[1] as Vector2) - (a[1] as Vector2) * s]


func material() -> StandardMaterial3D:
	var out := StandardMaterial3D.new()
	out.resource_name = "atlas"
	atlas.generate_mipmaps()
	out.albedo_texture = ImageTexture.create_from_image(atlas)
	if materials.values().any(func(m: Dictionary) -> bool: return m.has("cell") and m.alpha != Alpha.OPAQUE):
		out.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		out.alpha_scissor_threshold = 0.5
	return out


func hue_mask() -> String:
	var out: Image
	for key: String in hue_masks:
		var m: Dictionary = materials[key]
		var entry: Dictionary = (m.textures as Dictionary).get("_HueShiftMask", {})
		var guid := str((entry.get("m_Texture", {}) as Dictionary).get("guid", ""))
		if guid == "":
			continue
		var source := image(guid)
		if source == null:
			continue
		if out == null:
			out = Image.create_empty(ATLAS, ATLAS, false, Image.FORMAT_RGBA8)
			out.fill(Color.WHITE)
		var scale := _vector2(entry.get("m_Scale"), Vector2.ONE)
		var offset := _vector2(entry.get("m_Offset"), Vector2.ZERO)
		var cell: Rect2i = m.cell
		var channel := clampi(str(m.floats.get("_HueShiftMaskChannel", "1")).to_int(), 0, 3)
		for y in range(-PAD, cell.size.y + PAD):
			for x in range(-PAD, cell.size.x + PAD):
				var uv := Vector2((clampi(x, 0, cell.size.x - 1) + 0.5) / cell.size.x, 1.0 - (clampi(y, 0, cell.size.y - 1) + 0.5) / cell.size.y)
				uv = (uv - (m.offset as Vector2)) / (m.scale as Vector2) * scale + offset
				var pixel := Vector2(uv.x, 1.0 - uv.y) * Vector2(source.get_size()) - Vector2(0.5, 0.5)
				var base := Vector2i(pixel.floor())
				var fraction := pixel - pixel.floor()
				var at := func(dx: int, dy: int) -> Color: return source.get_pixel(posmod(base.x + dx, source.get_width()), posmod(base.y + dy, source.get_height()))
				var value: float = at.call(0, 0).lerp(at.call(1, 0), fraction.x).lerp(at.call(0, 1).lerp(at.call(1, 1), fraction.x), fraction.y)[channel]
				out.set_pixel(cell.position.x + x, cell.position.y + y, Color(value, value, value, 1.0))
	return "" if out == null else Marshalls.raw_to_base64(out.save_png_to_buffer())


func color_atlas() -> String:
	if color_regions.is_empty():
		return ""
	var out := atlas.duplicate() as Image
	out.clear_mipmaps()
	for key: String in color_regions:
		var m: Dictionary = materials[key]
		var cell: Rect2i = m.cell
		var raw: Image
		if m.image == null:
			raw = Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
			raw.fill(Color.WHITE)
		else:
			raw = (m.image as Image).duplicate()
		raw.resize(cell.size.x, cell.size.y, Image.INTERPOLATE_CUBIC)
		var outer := raw.duplicate() as Image
		outer.resize(cell.size.x + 2 * PAD, cell.size.y + 2 * PAD, Image.INTERPOLATE_BILINEAR)
		out.blit_rect(outer, Rect2i(Vector2i.ZERO, outer.get_size()), cell.position - Vector2i(PAD, PAD))
		out.blit_rect(raw, Rect2i(Vector2i.ZERO, raw.get_size()), cell.position)
	var data := out.get_data()
	var original := atlas.get_data()
	for i in range(3, data.size(), 4):
		data[i] = original[i]
	out.set_data(ATLAS, ATLAS, false, Image.FORMAT_RGBA8, data)
	return Marshalls.raw_to_base64(out.save_png_to_buffer())
