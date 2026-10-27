extends RefCounted

## Unity materials as the one material an imported avatar draws with: each material's colour texture, tinted by its
## colour, takes a cell of one atlas, and its surfaces' UVs move into that cell. Shader programs are not ported: a
## material keeps what its saved properties say of colour, texture, tiling and alpha, whichever shader saved them.

const Yaml = preload("res://../scripts/unity/yaml.gd")
const Assets = preload("res://../scripts/unity/assets.gd")

const ATLAS := 2048
const PAD := 4
const TEXTURES := ["_MainTex", "_BaseMap", "_BaseColorMap", "_MainTexture", "_Albedo"]
const COLOURS := ["_Color", "_BaseColor", "_MainColor"]
enum Alpha { OPAQUE, CUTOUT, BLEND }

var assets: Assets
## Each material read, by key: {"name", "shader", "texture" GUID or "", "colour", "scale", "offset", "alpha", "cull",
## "cutoff", "image" (null if its texture did not decode), "cell" Rect2i once packed}.
var materials := {}
var _images := {}
var atlas: Image
## Texture files that did not decode, by path.
var undecoded := {}


func _init(from: Assets) -> void:
	assets = from


## The key of a material reference from a renderer's m_Materials, reading the material the first time; a material the
## package lacks keeps the name its model gave it and draws its model's colour.
func use(ref: Dictionary, fallback: Color) -> String:
	var guid := str(ref.get("guid", ""))
	var key := guid if assets.by_guid.has(guid) and assets.extension(guid) == "mat" else "missing:" + str(ref.get("name", guid))
	if materials.has(key):
		return key
	var m := {"name": str(ref.get("name", key)), "shader": "", "texture": "", "colour": fallback, "scale": Vector2.ONE, "offset": Vector2.ZERO, "alpha": Alpha.OPAQUE, "cutoff": 0.5, "cull": true, "image": null}
	if key == guid:
		_read(m, guid)
	if m.texture != "":
		m.image = _image(m.texture)
	materials[key] = m
	return key


func _read(m: Dictionary, guid: String) -> void:
	var lines: Array[String] = []
	lines.assign(assets.text(guid).split("\n"))
	var mat: Dictionary = Yaml.document(lines).get("Material", {})
	m.name = str(mat.get("m_Name", assets.name(guid)))
	var shader: Dictionary = mat.get("m_Shader", {})
	m.shader = _shader_name(shader)
	var saved: Dictionary = mat.get("m_SavedProperties", {})
	var textures := _properties(saved.get("m_TexEnvs"))
	var floats := _properties(saved.get("m_Floats"))
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


## A material's saved property list as a Dictionary, from either layout Unity has written it in: entries of one key,
## or {first: {name}, second: value}.
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


## The texture's image, decoded once from its own bytes; null, and recorded, if it is no PNG, JPEG, TGA, BMP or WebP.
func _image(guid: String) -> Image:
	if _images.has(guid):
		return _images[guid]
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


## Packs the materials `used` names into one atlas, each cell its texture tinted by its colour, alpha kept only where
## the material is cut out or blended, each scaled by the largest factor at which all fit.
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


## Multiplies a cell by its material's colour, and sets its alpha as the atlas's one cutoff of 0.5 should treat it:
## opaque everywhere, cut where the material cuts at its own cutoff, or as it is for a blended material.
static func _tint(img: Image, colour: Color, alpha: Alpha, cutoff: float) -> void:
	var data := img.get_data()
	var mul := [colour.r, colour.g, colour.b, colour.a]
	for i in range(0, data.size(), 4):
		for c in 3:
			data[i + c] = int(data[i + c] * mul[c])
		var a: float = data[i + 3] * float(mul[3]) / 255.0
		data[i + 3] = 255 if alpha == Alpha.OPAQUE or (alpha == Alpha.CUTOUT and a >= cutoff) else 0 if alpha == Alpha.CUTOUT else int(a * 255.0)
	img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)


## Cells for each size scaled by `factor`, tallest first along shelves; empty if they do not fit the atlas.
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


## Where a vertex's UV lands in the atlas for material `key`: its texture's tiling and offset applied in Unity's UV
## frame (V up), then clamped into the cell. The second value says whether it was clamped.
func place(key: String, uv: Vector2) -> Array:
	var m: Dictionary = materials[key]
	var u := Vector2(uv.x, 1.0 - uv.y) * (m.scale as Vector2) + (m.offset as Vector2)
	var inside := u.x >= -0.001 and u.x <= 1.001 and u.y >= -0.001 and u.y <= 1.001
	u = u.clamp(Vector2.ZERO, Vector2.ONE)
	var cell: Rect2i = m.cell
	return [(Vector2(cell.position) + Vector2(u.x, 1.0 - u.y) * Vector2(cell.size)) / ATLAS, not inside]


## The material every surface draws with: the atlas, cut out where any packed material is not opaque.
func material() -> StandardMaterial3D:
	var out := StandardMaterial3D.new()
	out.resource_name = "atlas"
	atlas.generate_mipmaps()
	out.albedo_texture = ImageTexture.create_from_image(atlas)
	if materials.values().any(func(m: Dictionary) -> bool: return m.has("cell") and m.alpha != Alpha.OPAQUE):
		out.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		out.alpha_scissor_threshold = 0.5
	return out
