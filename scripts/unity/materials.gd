extends RefCounted


const Yaml = preload("res://../scripts/unity/yaml.gd")
const Assets = preload("res://../scripts/unity/assets.gd")

const ATLAS := 2048
const PAD := 4
const TEXTURES := ["_MainTex", "_BaseMap", "_BaseColorMap", "_MainTexture", "_Albedo"]
const COLOURS := ["_Color", "_BaseColor", "_MainColor"]
enum Alpha { OPAQUE, CUTOUT, BLEND }
## Unity's cull modes, as a shader's `Cull` reads them.
enum Cull { OFF, FRONT, BACK }
## The shaders packages name without carrying, Unity's built-in ones and the VRChat SDK's: the property a shader's
## `Cull` reads, or its fixed mode. Any other shader missing from a package is taken to read `_Cull`, as most avatar
## shaders do.
const ABSENT_CULL := {
	"0000000000000000f000000000000000": Cull.BACK,
	"e765db0afa7ecfc44ade2e4e2491f65a": "_Culling",
	"051a0ed2f2aedd741aa8186ae92f97e0": "_Culling",
	"d5b89f0c74ccf5049ba803c14a090378": Cull.OFF,
	"9200bec112b65ec4fbbbd33fa89c20f4": Cull.OFF,
	"8b39b95ac85682040beff730e0cfc77a": Cull.OFF,
	"affc81f3d164d734d8f13053effb1c5c": Cull.BACK,
	"2dcd9e0568e0a6f45b92c60ba2eb16a0": Cull.BACK,
	"f8c1f8ac363df824899534a0b30eef00": Cull.BACK,
	"528d55c4e8adab14b974ca665ed1b996": Cull.BACK,
	"584dc70fbb9834e48beb29e3206e3ca0": Cull.BACK,
	"3ad043b7f9839cb48a75a9238d433dec": Cull.BACK,
	"0b7113dea2069fc4e8943843eff19f70": Cull.BACK,
}

var assets: Assets
var materials := {}
var _images := {}
var atlas: Image
var undecoded := {}
var hue_masks := {}
var color_regions := {}
var decal_slots := {}


func _init(from: Assets) -> void:
	assets = from


func use(ref: Dictionary, fallback: Color) -> String:
	var guid := str(ref.get("guid", ""))
	var key := guid if assets.by_guid.has(guid) and assets.extension(guid) == "mat" else "missing:" + str(ref.get("name", guid))
	if materials.has(key):
		return key
	var m := {"name": str(ref.get("name", key)), "shader": "", "texture": "", "colour": fallback, "scale": Vector2.ONE, "offset": Vector2.ZERO, "alpha": Alpha.OPAQUE, "cutoff": 0.5, "cull": Cull.BACK, "image": null}
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
	var cull: Variant = ABSENT_CULL.get(shader_guid, "_Cull")
	if assets.by_guid.has(shader_guid):
		var source := assets.text(shader_guid)
		var property := RegEx.create_from_string("(_[A-Za-z0-9_]+)\\s*\\(\\s*\"")
		for found in property.search_all(source):
			m.properties[found.get_string(1)] = true
		var code := RegEx.create_from_string("//[^\\n]*|/\\*[\\s\\S]*?\\*/|\"[^\"\\n]*\"").sub(source, " ", true)
		var directive := RegEx.create_from_string("(?i)\\bCull\\s+(?:\\[\\s*(\\w+)\\s*\\]|(Off|Front|Back)\\b)").search(code)
		cull = Cull.BACK if directive == null else directive.get_string(1) if directive.get_string(1) != "" else ["off", "front", "back"].find(directive.get_string(2).to_lower())
	var saved: Dictionary = mat.get("m_SavedProperties", {})
	var textures := _properties(saved.get("m_TexEnvs"))
	m.textures = textures
	m.keywords = mat.get("m_ValidKeywords", [])
	var floats := _properties(saved.get("m_Floats"))
	m.floats = floats
	var ints := _properties(saved.get("m_Ints"))
	var colours := _properties(saved.get("m_Colors"))
	m.colours = colours
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
	m.cull = clampi(str(ints.get(cull, floats.get(cull, Cull.BACK))).to_int(), Cull.OFF, Cull.BACK) if cull is String else cull


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
	if not _images.has(guid):
		_images[guid] = _decoded(guid)
	return _images[guid]


func _decoded(guid: String) -> Image:
	if not assets.by_guid.has(guid):
		undecoded["not in the package: " + guid] = true
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
		return null
	img.decompress()
	img.convert(Image.FORMAT_RGBA8)
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


## The atlas as the material of the faces whose materials draw one side, and as that of those drawing both.
func atlas_materials() -> Array[StandardMaterial3D]:
	atlas.generate_mipmaps()
	var texture := ImageTexture.create_from_image(atlas)
	var cut := materials.values().any(func(m: Dictionary) -> bool: return m.has("cell") and m.alpha != Alpha.OPAQUE)
	var out: Array[StandardMaterial3D] = []
	for two_sided: bool in [false, true]:
		var drawn := StandardMaterial3D.new()
		drawn.resource_name = "atlas, two-sided" if two_sided else "atlas"
		drawn.albedo_texture = texture
		drawn.cull_mode = BaseMaterial3D.CULL_DISABLED if two_sided else BaseMaterial3D.CULL_BACK
		if cut:
			drawn.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			drawn.alpha_scissor_threshold = 0.5
		out.append(drawn)
	return out


func hue_mask() -> String:
	var out: Image
	for key: String in hue_masks:
		var m: Dictionary = materials[key]
		var mobile: bool = m.shader == "VRChat/Mobile/Toon Standard"
		var entry: Dictionary = (m.textures as Dictionary).get("_HueShiftMask" if mobile else "_MainColorAdjustTexture", {})
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
				var value := _sample(source, uv)
				out.set_pixel(cell.position.x + x, cell.position.y + y, Color(value[channel], value[channel], value[channel], 1.0) if mobile else value)
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


## Poiyomi decal `slot` of the material at `key` as {"multiply": bool}, or {} where the decal draws in a way the atlas
## layers cannot hold: anything but the whole UV0 square, untiled, unrotated, at its saved hue and with an alpha
## intensity of one unless animated, replacing or multiplying the albedo.
func decal(key: String, slot: int) -> Dictionary:
	var m: Dictionary = materials[key]
	var floats: Dictionary = m.get("floats", {})
	var colours: Dictionary = m.get("colours", {})
	var n := "" if slot == 0 else str(slot)
	var number := func(name: String) -> float: return str(floats.get(name, "0")).to_float()
	var vector := func(name: String) -> Color: return _colour(colours.get(name), Color(0, 0, 0, 0))
	if not m.has("cell") or number.call("_DecalEnabled" + n) == 0.0:
		return {}
	var blend: float = number.call("_DecalBlendType" + n)
	var position: Color = vector.call("_DecalPosition" + n)
	var scale: Color = vector.call("_DecalScale" + n)
	var still := ["_DecalTexture%sUV" % n, "_DecalRotation" + n, "_DecalRotationSpeed" + n, "_DecalTiled" + n, "_DecalSymmetryMode" + n, "_DecalMirroredUVMode" + n, "_DecalOverrideAlpha" + n, "_Decal%sGlobalMask" % slot, "_DecalFaceMask" + n, "_DecalDepth" + n]
	if blend not in [0.0, 2.0] or still.any(func(name: String) -> bool: return number.call(name) != 0.0):
		return {}
	if (m.get("properties", {}) as Dictionary).has("_DecalAlphaIntensity" + n) and str(floats.get("_DecalAlphaIntensity" + n, "1")).to_float() != 1.0:
		return {}
	if number.call("_DecalHueShiftEnabled" + n) != 0.0 and floats.keys().any(func(name: String) -> bool: return (name == "_DecalHueShift" + n or name.begins_with("_DecalHueShift%s_" % n)) and number.call(name) != 0.0):
		return {}
	if not position.is_equal_approx(Color(0.5, 0.5, 0, 0)) or not is_equal_approx(scale.r, 1.0) or not is_equal_approx(scale.g, 1.0) or vector.call("_DecalSideOffset" + n) != Color(0, 0, 0, 0) or vector.call("_DecalTexture%sPan" % n) != Color(0, 0, 0, 0):
		return {}
	return {"multiply": blend == 2.0}


## One atlas-sized layer per decal slot in `decal_slots`, each texel the decal's colour and coverage over the material
## cell beneath it, for the renderer to blend by the slot's animated alpha.
func decal_layers() -> Array:
	var slots := 0
	for key: String in decal_slots:
		for slot: int in decal_slots[key]:
			slots = maxi(slots, slot + 1)
	var out := []
	for slot in slots:
		var layer := Image.create_empty(ATLAS, ATLAS, false, Image.FORMAT_RGBA8)
		layer.fill(Color(0, 0, 0, 0))
		for key: String in decal_slots:
			if not decal_slots[key].has(slot):
				continue
			var m: Dictionary = materials[key]
			var n := "" if slot == 0 else str(slot)
			var cell: Rect2i = m.cell
			var texture := func(entry: Dictionary) -> Image:
				var guid := str((entry.get("m_Texture", {}) as Dictionary).get("guid", ""))
				var decoded := _decoded(guid) if guid != "" else null
				if decoded != null:
					decoded.resize(cell.size.x, cell.size.y, Image.INTERPOLATE_BILINEAR)
				return decoded
			var entry: Dictionary = (m.textures as Dictionary).get("_DecalTexture" + n, {})
			var source: Image = texture.call(entry)
			var tiling := [_vector2(entry.get("m_Scale"), Vector2.ONE), _vector2(entry.get("m_Offset"), Vector2.ZERO)]
			var mask_entry: Dictionary = (m.textures as Dictionary).get("_DecalMask", {})
			var mask: Image = texture.call(mask_entry)
			var mask_tiling := [_vector2(mask_entry.get("m_Scale"), Vector2.ONE), _vector2(mask_entry.get("m_Offset"), Vector2.ZERO)]
			var channel := clampi(str(m.floats.get("_Decal%sMaskChannel" % slot, "0")).to_int(), 0, 3)
			var tint := _colour((m.get("colours", {}) as Dictionary).get("_DecalColor" + n), Color.WHITE)
			for y in range(-PAD, cell.size.y + PAD):
				for x in range(-PAD, cell.size.x + PAD):
					var uv := Vector2((clampi(x, 0, cell.size.x - 1) + 0.5) / cell.size.x, 1.0 - (clampi(y, 0, cell.size.y - 1) + 0.5) / cell.size.y)
					uv = (uv - (m.offset as Vector2)) / (m.scale as Vector2)
					if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
						continue
					var value := tint * (_sample(source, uv * (tiling[0] as Vector2) + (tiling[1] as Vector2)) if source != null else Color.WHITE)
					if mask != null:
						value.a *= _sample(mask, uv * (mask_tiling[0] as Vector2) + (mask_tiling[1] as Vector2))[channel]
					layer.set_pixel(cell.position.x + x, cell.position.y + y, value)
		out.append(Marshalls.raw_to_base64(layer.save_png_to_buffer()))
	return out


static func _colour(v: Variant, otherwise: Color) -> Color:
	if v is Dictionary:
		return Color(str(v.get("r", otherwise.r)).to_float(), str(v.get("g", otherwise.g)).to_float(), str(v.get("b", otherwise.b)).to_float(), str(v.get("a", otherwise.a)).to_float())
	return otherwise


static func _sample(source: Image, uv: Vector2) -> Color:
	var pixel := Vector2(uv.x, 1.0 - uv.y) * Vector2(source.get_size()) - Vector2(0.5, 0.5)
	var base := Vector2i(pixel.floor())
	var fraction := pixel - pixel.floor()
	var at := func(dx: int, dy: int) -> Color: return source.get_pixel(posmod(base.x + dx, source.get_width()), posmod(base.y + dy, source.get_height()))
	return at.call(0, 0).lerp(at.call(1, 0), fraction.x).lerp(at.call(0, 1).lerp(at.call(1, 1), fraction.x), fraction.y)
