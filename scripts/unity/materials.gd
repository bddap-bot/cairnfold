extends RefCounted


const Yaml = preload("res://../scripts/unity/yaml.gd")
const Assets = preload("res://../scripts/unity/assets.gd")
const Sdk = preload("res://../scripts/unity/sdk_shaders.gd")
const Toon = preload("res://../scripts/unity/toon_shaders.gd")
const Liltoon = preload("res://../scripts/unity/liltoon.gd")

const ATLAS := 2048
const STEP := 256
## Layers mask or index the albedo; at a widened atlas's side each would cost as much memory as it.
const LAYER := 4096
## A full-colour emission map at LAYER would weigh as much as the atlas and push heavy avatars past Avatar.FLOOR_BYTES.
const GLOW_LAYER := LAYER / 2
const PAD := 4
## A cell shrinks its texture several-fold: bilinear and cubic read 2x2 or 4x4 texels and alias; Lanczos widens.
const RESAMPLE := Image.INTERPOLATE_LANCZOS
const TEXTURES := ["_MainTex", "_BaseMap", "_BaseColorMap", "_MainTexture", "_Albedo"]
const COLOURS := ["_Color", "_BaseColor", "_MainColor"]
enum Alpha { OPAQUE, CUTOUT, BLEND }
enum Pass { SOLID, BLENDED, BLENDED_DEPTH }
const PASSES := 3
## Unity's CullMode values, which a saved `_Cull` holds.
enum Cull { OFF, FRONT, BACK }
## By GUID, the shaders packages name without carrying (Unity's and the VRChat SDK's): the property their `Cull`
## reads, or its fixed mode. Other absent shaders are taken to read `_Cull`, as most avatar shaders do.
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
const MATCAPS := ["_Matcap", "_Matcap2", "_Matcap3", "_Matcap4"]
const MATCAP := 256

var assets: Assets
var materials := {}
var _images := {}
var atlas: Image
var atlas_side := ATLAS
var widest: int
var undecoded := {}
## Texture GUIDs no package holds.
var absent := {}
var hue_masks := {}
var color_regions := {}
## Materials whose emission a clip drives: one dark at rest glows only if listed.
var glow_regions := {}
## Materials whose first emission's strength a clip animates: it draws alone, at the clip's strength.
var strength_driven := {}
## Caches of `_poiyomi_glows` and `_glow_and_peak` ([map, peak strength]); `looks` drops the map.
var _glow_lists := {}
var _folded_maps := {}
## By material key: {property a clip animates on a renderer drawing it: true}.
var animated := {}
var decal_images: Array[Image] = []
var _decal_of := {}
var _decal_index := {}
var _layer_decals := {}


func _init(from: Assets, atlas_widest := Avatar.MAX_IMAGE_SIDE) -> void:
	assets = from
	widest = atlas_widest


func use(ref: Dictionary, fallback: Color) -> String:
	var guid := Yaml.guid(ref)
	var key := guid if assets.by_guid.has(guid) and assets.extension(guid) == "mat" else "missing:" + str(ref.get("name", guid))
	if materials.has(key):
		return key
	var m := {"name": str(ref.get("name", key)), "shader": "", "outline_pass": false, "outline": {}, "outline_scale": 0.0, "texture": "", "colour": fallback, "scale": Vector2.ONE, "offset": Vector2.ZERO, "alpha": Alpha.OPAQUE, "cutoff": 0.5, "alpha_mod": 0.0, "depth": false, "cull": Cull.BACK, "image": null}
	if key == guid:
		_read(m, guid)
	if m.texture != "":
		m.image = image(m.texture)
		m.shown = shown(m.texture)
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
	m.colour_attributes = {}
	var shader_guid := Yaml.guid(shader)
	var cull: Variant = ABSENT_CULL.get(shader_guid, "_Cull")
	if assets.by_guid.has(shader_guid):
		var source := assets.text(shader_guid)
		var property := RegEx.create_from_string("((?:\\[[^\\]\\n]*\\]\\s*)*)(_[A-Za-z0-9_]+)\\s*\\(\\s*\"")
		for found in property.search_all(source):
			m.properties[found.get_string(2)] = true
			var attributes := found.get_string(1).to_lower()
			if "[gamma]" in attributes or "[hdr]" in attributes:
				m.colour_attributes[found.get_string(2)] = {"hdr": "[hdr]" in attributes, "gamma": "[gamma]" in attributes}
		var code := RegEx.create_from_string("//[^\\n]*|/\\*[\\s\\S]*?\\*/|\"[^\"\\n]*\"").sub(source, " ", true)
		var directive := RegEx.create_from_string("(?i)\\bCull\\s+(?:\\[\\s*(\\w+)\\s*\\]|(Off|Front|Back)\\b)").search(code)
		cull = Cull.BACK if directive == null else directive.get_string(1) if directive.get_string(1) != "" else ["off", "front", "back"].find(directive.get_string(2).to_lower())
		m.outline_pass = OUTLINE_PASS.search(RegEx.create_from_string("//[^\\n]*|/\\*[\\s\\S]*?\\*/").sub(source, " ", true)) != null
	elif Sdk.SHADERS.has(shader_guid):
		for name: String in Sdk.SHADERS[shader_guid].properties:
			m.properties[name] = true
		m.outline_pass = Sdk.SHADERS[shader_guid].get("outline", false)
	elif Toon.SHADERS.has(shader_guid):
		m.outline_pass = Toon.SHADERS[shader_guid].outline
		for name: String in Liltoon.properties(m.shader):
			m.properties[name] = true
	var saved: Dictionary = mat.get("m_SavedProperties", {})
	var textures := _properties(saved.get("m_TexEnvs"))
	m.textures = textures
	# Unity before 2021 saves the keywords as one string.
	m.keywords = mat.get("m_ValidKeywords", Array(str(mat.get("m_ShaderKeywords", "")).split(" ", false)))
	var floats := _properties(saved.get("m_Floats"))
	m.floats = floats
	var ints := _properties(saved.get("m_Ints"))
	m.ints = ints
	var colours := _properties(saved.get("m_Colors"))
	m.colours = colours
	for k: String in TEXTURES:
		if _texture_guid(m, k) != "":
			m.texture = _texture_guid(m, k)
			m.scale = _vector2(textures[k].get("m_Scale"), Vector2.ONE)
			m.offset = _vector2(textures[k].get("m_Offset"), Vector2.ZERO)
			break
	for k: String in COLOURS:
		if colours.get(k) is Dictionary:
			m.colour = _colour(colours[k], Color.WHITE)
			break
	var queue := str(mat.get("m_CustomRenderQueue", "-1")).to_int()
	var tags: Variant = mat.get("stringTagMap")
	var render_type := str((tags as Dictionary).get("RenderType", "")) if tags is Dictionary else ""
	m.animated = {}
	for tag: String in (tags as Dictionary if tags is Dictionary else {}):
		if tag.ends_with("Animated") and str(tags[tag]).to_float() > 0.0:
			m.animated[tag.trim_suffix("Animated")] = true
	var mode := str(floats.get("_Mode", "0")).to_int()
	var declared := func(name: String) -> bool: return m.properties.has(name) and (ints.has(name) or floats.has(name))
	# `Blend [_SrcBlend] [_DstBlend]` blends exactly when the destination factor is not Zero; queue and preset names
	# are the evidence only without it.
	var blended: bool = _number(m, "_DstBlend", 0.0) != 0.0 if declared.call("_DstBlend") else queue >= 3000 or render_type == "Transparent" or m.shader.contains("Transparent") or mode >= 2
	if blended:
		m.alpha = Alpha.BLEND
		m.depth = declared.call("_ZWrite") and _number(m, "_ZWrite", 0.0) != 0.0
	elif queue >= 2450 or render_type == "TransparentCutout" or m.shader.contains("Cutout") or mode == 1:
		m.alpha = Alpha.CUTOUT
		m.cutoff = _float(m, "_Cutoff", 0.5)
	if declared.call("_AlphaMod"):
		m.alpha_mod = _number(m, "_AlphaMod", 0.0)
	m.cull = clampi(str(ints.get(cull, floats.get(cull, Cull.BACK))).to_int(), Cull.OFF, Cull.BACK) if cull is String else cull
	if Liltoon.is_liltoon(m):
		Liltoon.read(m)
	m.outline = _outline(m)


func _shader_name(ref: Dictionary) -> String:
	var guid := Yaml.guid(ref)
	if assets.by_guid.has(guid):
		for line in assets.text(guid).split("\n", false, 8):
			if line.strip_edges().begins_with("Shader \""):
				return line.strip_edges().get_slice("\"", 1)
		return assets.name(guid)
	if Sdk.SHADERS.has(guid):
		return Sdk.SHADERS[guid].name
	if Toon.SHADERS.has(guid):
		return Toon.SHADERS[guid].name
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
		absent[guid] = true
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


## The widest side Unity imports the texture at for a PC; 0 where its .meta names none. The default platform's size
## beats the legacy field: Unity imports a texture whose default is 1024 and legacy field 2048 at 1024.
func shown(guid: String) -> int:
	var importer: Dictionary = assets.meta(guid).get("TextureImporter", {})
	var side := str(importer.get("maxTextureSize", "0")).to_int()
	var platforms: Variant = importer.get("platformSettings", [])
	for target: String in ["DefaultTexturePlatform", "Standalone"]:
		for platform: Variant in platforms if platforms is Array else []:
			if platform is Dictionary and str(platform.get("buildTarget", "")) == target and (target == "DefaultTexturePlatform" or str(platform.get("overridden", "0")) == "1"):
				side = str(platform.get("maxTextureSize", side)).to_int()
	return side


func pack(used: Array) -> void:
	var cells := {}
	atlas_side = mini(ATLAS, widest)
	var sizes := {}
	for key: String in used:
		var m: Dictionary = materials[key]
		var img: Image = m.image
		var wanted := Vector2i(8, 8) if img == null else img.get_size()
		var big := maxi(wanted.x, wanted.y)
		var most: int = mini(m.get("shown", 0) if m.get("shown", 0) > 0 else big, widest - 2 * PAD)
		if big > most:
			wanted = Vector2i(maxi(1, wanted.x * most / big), maxi(1, wanted.y * most / big))
		sizes[key] = wanted
	while true:
		cells = _shelves(used, sizes, 1.0, atlas_side)
		if not cells.is_empty() or atlas_side >= widest:
			break
		atlas_side = mini(atlas_side + STEP, widest)
	var factor := 1.0
	while cells.is_empty():
		factor *= 0.9
		cells = _shelves(used, sizes, factor, atlas_side)
	atlas = Image.create_empty(atlas_side, atlas_side, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0.5, 0.5, 0.5, 1.0))
	for key: String in used:
		var m: Dictionary = materials[key]
		var cell: Rect2i = cells[key]
		m.cell = cell
		var img := _cell_image(m, cell)
		_adjust_main(key, img)
		_tint(img, m.colour, m.alpha, m.cutoff, m.alpha_mod, _alpha_overrides(key, img.get_size()))
		_adjust(m, img)
		_detail(key, img)
		_blit_padded(atlas, img, cell)


## Each Poiyomi Color Adjust property, in its base pass's order (unity_avatar.gd indexes the keys), with the value
## that changes nothing.
const ADJUSTS := {"_MainHueShift": 0.0, "_MainGamma": 1.0, "_Saturation": 0.0, "_MainBrightness": 0.0}


## Whether `_adjust` lays Color Adjust `name` into the atlas: a locked shader holds fixed any property without Thry's
## `Animated` tag, so clips move nothing, as in Unity. A hue that turns over time is not laid.
static func adjust_laid(m: Dictionary, name: String) -> bool:
	if not poiyomi(m) or _float(m, "_MainColorAdjustToggle") == 0.0 or (m.get("animated", {}) as Dictionary).has(name):
		return false
	return name != "_MainHueShift" or _float(m, "_MainHueShiftToggle") != 0.0 and _float(m, "_MainHueShiftSpeed") == 0.0


## Whether the atlas holds `name` moved off its no-op value, so a clip binding it would apply it over itself.
static func adjust_baked(m: Dictionary, name: String) -> bool:
	return adjust_laid(m, name) and _saved(m, name, ADJUSTS[name]) != ADJUSTS[name]


## Under the adjust mask's channels, in linear space: hue shift (r), gamma (a), saturation (b), then brightness (g).
func _adjust(m: Dictionary, img: Image) -> void:
	var at := func(name: String) -> float: return _saved(m, name, ADJUSTS[name]) if adjust_laid(m, name) else ADJUSTS[name]
	var shifted := adjust_laid(m, "_MainHueShift")
	var shift: float = at.call("_MainHueShift")
	var space := _float(m, "_MainHueShiftColorSpace")
	var select := _float(m, "_MainHueShiftSelectOrShift", 1.0)
	var replace := _float(m, "_MainHueShiftReplace", 1.0) != 0.0
	var gamma: float = at.call("_MainGamma")
	var saturation: float = at.call("_Saturation")
	var brightness: float = at.call("_MainBrightness")
	if not shifted and gamma == 1.0 and saturation == 0.0 and brightness == 0.0:
		return
	var masks := _over(m, _slot_image(m, "_MainColorAdjustTexture"), "_MainColorAdjustTexture", img.get_size(), 0)
	masks.convert(Image.FORMAT_RGBA8)
	var mask := masks.get_data()
	var data := img.get_data()
	for i in range(0, data.size(), 4):
		var c := Color8(data[i], data[i + 1], data[i + 2]).srgb_to_linear()
		if shifted:
			var cover := mask[i] / 255.0
			c = c.lerp(hue_shift(c, shift, space, select), cover) if replace else hue_shift(c, fposmod(shift - (1.0 - cover), 1.0), space, select)
		var gammaed := Color(pow(absf(c.r), gamma), pow(absf(c.g), gamma), pow(absf(c.b), gamma))
		c = c.lerp(gammaed, mask[i + 3] / 255.0)
		var grey := 0.3 * c.r + 0.59 * c.g + 0.11 * c.b
		c = c.lerp(Color(grey, grey, grey), -saturation * mask[i + 2] / 255.0)
		c = c.lerp(c * (brightness + 1.0), mask[i + 1] / 255.0).clamp().linear_to_srgb()
		data[i] = roundi(c.r * 255.0)
		data[i + 1] = roundi(c.g * 255.0)
		data[i + 2] = roundi(c.b * 255.0)
	img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)


static func _cell_image(m: Dictionary, cell: Rect2i) -> Image:
	var img: Image
	if m.image == null:
		img = Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
	else:
		img = (m.image as Image).duplicate()
	img.resize(cell.size.x, cell.size.y, RESAMPLE)
	return img


## The PAD holds `img` stretched, so filtering at the cell's edge samples it.
static func _blit_padded(into: Image, img: Image, cell: Rect2i) -> void:
	var outer := img.duplicate() as Image
	outer.resize(cell.size.x + 2 * PAD, cell.size.y + 2 * PAD, RESAMPLE)
	into.blit_rect(outer, Rect2i(Vector2i.ZERO, outer.get_size()), cell.position - Vector2i(PAD, PAD))
	into.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), cell.position)


func packed(key: String) -> String:
	var m: Dictionary = materials[key]
	var source := "none" if m.image == null else "%dx%d" % [(m.image as Image).get_width(), (m.image as Image).get_height()]
	return "%s: source %s, shown %s, packed %dx%d" % [m.name, source, m.get("shown", 0) if m.get("shown", 0) > 0 else "as source", (m.cell as Rect2i).size.x, (m.cell as Rect2i).size.y]


## Laid at the albedo's size, since nothing animates it: widening a cell to the detail's took a corpus avatar's atlas
## from 2048 to 4864 wide. lilToon layers a clip fades are the renderer's (Liltoon.faded).
func _detail(key: String, img: Image) -> void:
	var m: Dictionary = materials[key]
	if Liltoon.is_liltoon(m):
		Liltoon.lay(self, m, img, Liltoon.faded(m, animated.get(key, {})))
		return
	var layer := _detail_layer(m, img.get_size(), 0)
	if layer == null:
		return
	var detail := layer.get_data()
	var multiply := _number(m, "_DetailMode", DETAIL_BLEND) == DETAIL_MULTIPLY
	var data := img.get_data()
	for i in range(0, data.size(), 4):
		var a := detail[i + 3] / 255.0
		if a <= 0.0:
			continue
		for c in 3:
			var under := _LINEAR[data[i + c]]
			var over: float = under * _LINEAR[detail[i + c]] if multiply else _LINEAR[detail[i + c]]
			data[i + c] = _ENCODED[clampi(roundi(lerpf(under, over, a) * 4095.0), 0, 4095)]
	img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)


func _adjust_main(key: String, img: Image) -> void:
	if Liltoon.is_liltoon(materials[key]):
		Liltoon.adjust(self, materials[key], img, animated.get(key, {}))


## Toon Standard's _DetailMode values; the atlas holds no others.
const DETAIL_BLEND := 0.0
const DETAIL_MULTIPLY := 2.0


## Alpha is how far it covers the albedo; null where the atlas cannot hold it (`_lays_detail`).
func _detail_layer(m: Dictionary, size: Vector2i, pad: int) -> Image:
	var source := _slot_image(m, "_DetailAlbedoMap") if _lays_detail(m) else null
	if source == null:
		return null
	var mode := _number(m, "_DetailMode", DETAIL_BLEND)
	var layer := _over(m, source, "_DetailAlbedoMap", size, pad)
	var cover := _over(m, _slot_image(m, "_DetailMask"), "_DetailMask", size, pad).get_data()
	var channel := clampi(int(_number(m, "_DetailMaskChannel", 3.0)), 0, 3)
	var data := layer.get_data()
	for i in range(0, data.size(), 4):
		data[i + 3] = cover[i + channel] if mode == DETAIL_MULTIPLY else roundi(data[i + 3] * cover[i + channel] / 255.0)
	layer.set_data(layer.get_width(), layer.get_height(), false, Image.FORMAT_RGBA8, data)
	return layer


static func _lays_detail(m: Dictionary) -> bool:
	var keywords: Array = m.get("keywords", [])
	if not toon_standard(m) or "USE_DETAIL_MAPS" not in keywords or _texture_guid(m, "_DetailAlbedoMap") == "":
		return false
	if _number(m, "_DetailUV", 0.0) != 0.0 or _number(m, "_DetailMode", DETAIL_BLEND) not in [DETAIL_BLEND, DETAIL_MULTIPLY]:
		return false
	return "USE_HUE_SHIFT" not in keywords or _number(m, "_DetailHueShift", 0.0) == 0.0


static func _number(m: Dictionary, name: String, otherwise: float) -> float:
	return str((m.get("ints", {}) as Dictionary).get(name, (m.get("floats", {}) as Dictionary).get(name, otherwise))).to_float()


## Each [Alpha Blend Mode, texel alphas at `size`]; `decal` admits only decals spanning the whole cell.
func _alpha_overrides(key: String, size: Vector2i) -> Array:
	if Liltoon.is_liltoon(materials[key]):
		return Liltoon.alpha_overrides(self, materials[key], size)
	var floats: Dictionary = materials[key].get("floats", {})
	var out := []
	for slot in 4:
		var mode := str(floats.get("_DecalOverrideAlpha" + ("" if slot == 0 else str(slot)), "0")).to_int()
		if mode == 0:
			continue
		var d := decal(key, slot)
		if d.is_empty():
			continue
		var layer := (decal_images[d.image] as Image).duplicate() as Image
		layer.resize(size.x, size.y, RESAMPLE)
		var blend := clampf(d.alpha, 0.0, 1.0)
		var data := layer.get_data()
		var alphas := PackedFloat32Array()
		alphas.resize(size.x * size.y)
		for i in alphas.size():
			alphas[i] = data[4 * i + 3] / 255.0 * blend
		out.append([mode, alphas])
	return out


static func _float(m: Dictionary, name: String, otherwise := 0.0) -> float:
	return str((m.get("floats", {}) as Dictionary).get(name, otherwise)).to_float()


static func _tint(img: Image, colour: Color, alpha: Alpha, cutoff: float, mod: float, overrides: Array) -> void:
	var data := img.get_data()
	var mul := [colour.r, colour.g, colour.b, colour.a]
	for i in range(0, data.size(), 4):
		for c in 3:
			data[i + c] = int(data[i + c] * mul[c])
		var a: float = clampf(data[i + 3] * float(mul[3]) / 255.0 + mod, 0.0, 1.0)
		for over: Array in overrides:
			var by: float = over[1][i / 4]
			a = clampf([by, a * by, a + by, a - by, minf(a, by), maxf(a, by)][over[0] - 1], 0.0, 1.0)
		data[i + 3] = 255 if alpha == Alpha.OPAQUE or (alpha == Alpha.CUTOUT and a >= cutoff) else 0 if alpha == Alpha.CUTOUT else int(a * 255.0)
	img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)


static func _shelves(keys: Array, sizes: Dictionary, factor: float, side: int) -> Dictionary:
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
		if x + w > side:
			x = 0
			y += row
			row = 0
		if y + h > side:
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
	return [(Vector2(cell.position) + Vector2(u.x, 1.0 - u.y) * Vector2(cell.size)) / atlas_side, not inside]


func moved(from: String, to: String) -> Array:
	var affine := func(key: String) -> Array:
		var m: Dictionary = materials[key]
		var cell: Rect2 = Rect2(m.cell)
		var scale: Vector2 = m.scale
		var offset: Vector2 = m.offset
		return [Vector2(scale.x * cell.size.x, scale.y * cell.size.y) / atlas_side, Vector2(cell.position.x + offset.x * cell.size.x, cell.position.y + cell.size.y * (1.0 - scale.y - offset.y)) / atlas_side]
	var a: Array = affine.call(from)
	var b: Array = affine.call(to)
	var s: Vector2 = Vector2(b[0].x / a[0].x if a[0].x != 0.0 else 1.0, b[0].y / a[0].y if a[0].y != 0.0 else 1.0)
	return [s, (b[1] as Vector2) - (a[1] as Vector2) * s]


static func pass_of(m: Dictionary) -> Pass:
	return Pass.SOLID if m.alpha != Alpha.BLEND else Pass.BLENDED_DEPTH if m.depth else Pass.BLENDED


## Indexed as `face_material` computes. glTF has no word for blended depth writes or outlines: extras carry them.
func atlas_materials() -> Array[StandardMaterial3D]:
	atlas.generate_mipmaps()
	var texture := ImageTexture.create_from_image(atlas)
	var cut := materials.values().any(func(m: Dictionary) -> bool: return m.has("cell") and m.alpha == Alpha.CUTOUT)
	var out: Array[StandardMaterial3D] = []
	for outlined: bool in [false, true]:
		for drawn_as in PASSES:
			for two_sided: bool in [false, true]:
				var drawn := StandardMaterial3D.new()
				# The glTF export numbers a repeated name, so the extras, not the name, mark an outlined pass.
				drawn.resource_name = "atlas" + (", two-sided" if two_sided else "") + ["", ", blended", ", blended, depth written"][drawn_as]
				drawn.albedo_texture = texture
				drawn.cull_mode = BaseMaterial3D.CULL_DISABLED if two_sided else BaseMaterial3D.CULL_BACK
				var extras := {}
				if drawn_as != Pass.SOLID:
					drawn.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					drawn.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS if drawn_as == Pass.BLENDED_DEPTH else BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
					extras.depthWrite = drawn_as == Pass.BLENDED_DEPTH
				elif cut:
					drawn.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					drawn.alpha_scissor_threshold = 0.5
				if outlined:
					extras.outline = true
				if not extras.is_empty():
					drawn.set_meta("extras", extras)
				out.append(drawn)
	return out


func face_material(key: String, choices: Array = []) -> int:
	var m: Dictionary = materials[key]
	var outlined := ([key] + choices).any(func(k: String) -> bool: return _outline_metres(materials[k]) > 0.0)
	return int(m.cull == Cull.OFF) + 2 * pass_of(m) + 2 * PASSES * int(outlined)


func hue_mask() -> Image:
	var keys := hue_masks.keys()
	keys.append_array(materials.keys().filter(func(key: String) -> bool: return not hue_masks.has(key) and not emission(key).is_empty() and emission(key).shiftsHue))
	var out: Image
	for key: String in keys:
		var m: Dictionary = materials[key]
		var mask := Liltoon.hue_mask(self, m, Liltoon.faded(m, animated.get(key, {}))) if Liltoon.is_liltoon(m) else _adjust_mask(key)
		if mask == null:
			continue
		if out == null:
			out = Image.create_empty(atlas_side, atlas_side, false, Image.FORMAT_RGBA8)
			out.fill(Color.WHITE)
		out.blit_rect(mask, Rect2i(Vector2i.ZERO, mask.get_size()), (m.cell as Rect2i).position - Vector2i(PAD, PAD))
	return null if out == null else _layer(out, RESAMPLE)


## Over its padded cell, or null where it covers it all. A blended detail is spared, as the shader shifts the albedo
## before laying it; a multiplied one shows the shifted albedo through.
func _adjust_mask(key: String) -> Image:
	var m: Dictionary = materials[key]
	var mobile := toon_standard(m)
	var property := "_HueShiftMask" if mobile else "_MainColorAdjustTexture"
	var source := image(_texture_guid(m, property)) if _texture_guid(m, property) != "" else null
	var detail := _detail_layer(m, (m.cell as Rect2i).size, PAD) if hue_masks.has(key) and _number(m, "_DetailMode", DETAIL_BLEND) == DETAIL_BLEND else null
	if source == null and detail == null:
		return null
	var mask := _over_cell(m, source, property)
	if mobile:
		var channel := clampi(str(m.floats.get("_HueShiftMaskChannel", "1")).to_int(), 0, 3)
		var data := mask.get_data()
		var cover := PackedByteArray() if detail == null else detail.get_data()
		for i in range(0, data.size(), 4):
			data[i] = data[i + channel] if cover.is_empty() else roundi(data[i + channel] * (255 - cover[i + 3]) / 255.0)
			data[i + 1] = data[i]
			data[i + 2] = data[i]
			data[i + 3] = 255
		mask.set_data(mask.get_width(), mask.get_height(), false, Image.FORMAT_RGBA8, data)
	return mask


## {} where no menu recolours; else "image", the recoloured materials' untinted padded cells on shelves, cropped, and
## "cells", each [atlas x0, y0, x1, y1, image x0, y0, x1, y1] in UV. Only these cells travel, not a second albedo.
func untinted() -> Dictionary:
	if color_regions.is_empty():
		return {}
	var keys := color_regions.keys()
	var sizes := {}
	var area := 0
	var side := 1
	for key: String in keys:
		var size: Vector2i = (materials[key].cell as Rect2i).size
		sizes[key] = size
		area += (size.x + 2 * PAD) * (size.y + 2 * PAD)
		side = maxi(side, maxi(size.x, size.y) + 2 * PAD)
	side = mini(maxi(side, ceili(sqrt(area))), atlas_side)
	var laid := _shelves(keys, sizes, 1.0, side)
	while laid.is_empty() and side < atlas_side:
		side = mini(side + STEP, atlas_side)
		laid = _shelves(keys, sizes, 1.0, side)
	if laid.is_empty():
		for key: String in keys:
			laid[key] = materials[key].cell
	var covered := Vector2i.ONE
	for key: String in keys:
		covered = covered.max((laid[key] as Rect2i).end + Vector2i(PAD, PAD))
	var out := Image.create_empty(covered.x, covered.y, false, Image.FORMAT_RGBA8)
	out.fill(Color.WHITE)
	var uv := func(r: Rect2i, size: Vector2) -> Array:
		var g := Rect2(r.grow(PAD))
		return [g.position.x / size.x, g.position.y / size.y, g.end.x / size.x, g.end.y / size.y]
	var cells := []
	for key: String in keys:
		var m: Dictionary = materials[key]
		var img := _cell_image(m, m.cell)
		_adjust_main(key, img)
		_detail(key, img)
		_blit_padded(out, img, laid[key])
		cells.append(uv.call(m.cell, Vector2(atlas_side, atlas_side)) + uv.call(laid[key], Vector2(covered)))
	return {"image": out, "cells": cells}


## Poiyomi decal `slot` at rest as {"alpha", "intensity", "colorBlend" (ExpressionDefinition.DECAL_BLENDS), "image"
## (into `decal_images`), "hue"}, or {} unless it covers the whole UV0 square untiled and unrotated, any hue fixed.
func decal(key: String, slot: int) -> Dictionary:
	var m: Dictionary = materials[key]
	if Liltoon.is_liltoon(m):
		return _layer_decal(key, slot)
	var colours: Dictionary = m.get("colours", {})
	var n := "" if slot == 0 else str(slot)
	var vector := func(name: String) -> Color: return _colour(colours.get(name), Color(0, 0, 0, 0))
	if not m.has("cell") or not poiyomi(m) or _float(m, "_DecalEnabled" + n) == 0.0:
		return {}
	var blend: float = _float(m, "_DecalBlendType" + n)
	var position: Color = vector.call("_DecalPosition" + n)
	var scale: Color = vector.call("_DecalScale" + n)
	var still := ["_DecalTexture%sUV" % n, "_DecalRotation" + n, "_DecalRotationSpeed" + n, "_DecalTiled" + n, "_DecalSymmetryMode" + n, "_DecalMirroredUVMode" + n, "_Decal%sGlobalMask" % slot, "_DecalFaceMask" + n, "_DecalDepth" + n]
	if int(blend) not in ExpressionDefinition.DECAL_BLENDS or still.any(func(name: String) -> bool: return _float(m, name) != 0.0):
		return {}
	if _float(m, "_DecalOverrideAlpha" + n) not in [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0]:
		return {}
	if _float(m, "_DecalOverrideAlpha" + n) != 0.0 and _float(m, "_Decal%sOverrideAlphaMode" % slot) in [2.0, 3.0]:
		return {}
	if _float(m, "_DecalHueShiftEnabled" + n) != 0.0 and (_float(m, "_DecalHueShiftSpeed" + n) != 0.0 or _float(m, "_DecalHueAngleStrength" + n) != 0.0):
		return {}
	if not position.is_equal_approx(Color(0.5, 0.5, 0, 0)) or not is_equal_approx(scale.r, 1.0) or not is_equal_approx(scale.g, 1.0) or vector.call("_DecalSideOffset" + n) != Color(0, 0, 0, 0) or vector.call("_DecalTexture%sPan" % n) != Color(0, 0, 0, 0):
		return {}
	var hue: Variant = null
	if _turned(m, n):
		hue = {"shift": _saved(m, "_DecalHueShift" + n, 0.0), "space": _float(m, "_DecalHueShiftColorSpace" + n), "select": _float(m, "_DecalHueShiftSelectOrShift" + n, 1.0)}
	return {"alpha": _saved(m, "_DecalBlendAlpha" + n, 1.0), "intensity": _saved(m, "_DecalAlphaIntensity" + n, 1.0), "colorBlend": int(blend), "image": _decal_image(key, slot), "hue": hue}


## lilToon's 2nd (`slot` 0) or 3rd (1) main texture in `decal`'s form, where the renderer lays it (Liltoon.faded).
func _layer_decal(key: String, slot: int) -> Dictionary:
	var m: Dictionary = materials[key]
	if not m.has("cell") or slot >= Liltoon.LAYERS.size() or Liltoon.LAYERS[slot] not in Liltoon.faded(m, animated.get(key, {})):
		return {}
	var n := Liltoon.LAYERS[slot]
	if not _layer_decals.has([key, n]):
		var laid := Liltoon.layer_decal(self, m, n, Liltoon.layer(m, n), (m.cell as Rect2i).size)
		_layer_decals[[key, n]] = {"alpha": laid.alpha, "intensity": 1.0, "colorBlend": laid.colorBlend, "image": _baked_decal(laid.image), "hue": null}
	return _layer_decals[[key, n]]


## Whether a clip can move decal `n`'s hue, so its image holds it unturned: a locked Poiyomi shader declares an
## animated property with the material's suffix.
static func _turned(m: Dictionary, n: String) -> bool:
	if _float(m, "_DecalHueShiftEnabled" + n) == 0.0:
		return false
	return (m.get("properties", {}) as Dictionary).keys().any(func(declared: String) -> bool: return declared.begins_with("_DecalHueShift" + n + "_"))


func _decal_image(key: String, slot: int) -> int:
	var m: Dictionary = materials[key]
	var settings := [key, slot, hash(m.get("floats", {})), hash(m.get("colours", {}))]
	if _decal_of.has(settings):
		return _decal_of[settings]
	var n := "" if slot == 0 else str(slot)
	var property := "_DecalTexture" + n
	var source := _slot_image(m, property)
	var mask := _slot_image(m, "_DecalMask")
	var size := Vector2i.ZERO
	for pair: Array in [[source, property], [mask, "_DecalMask"]]:
		if pair[0] != null:
			var own: Vector2i = (pair[0] as Image).get_size()
			var big := maxi(own.x, own.y)
			var imported := shown(_texture_guid(m, pair[1]))
			var side := mini(mini(big, imported if imported > 0 else big), widest)
			if side > maxi(size.x, size.y):
				size = Vector2i(maxi(1, own.x * side / big), maxi(1, own.y * side / big))
	if size == Vector2i.ZERO:
		size = Vector2i(1, 1)
	var tint := _colour((m.get("colours", {}) as Dictionary).get("_DecalColor" + n), Color.WHITE)
	var colour := _over(m, source, property, size, 0)
	var shift := _float(m, "_DecalHueShiftEnabled" + n) != 0.0 and not _turned(m, n)
	if mask != null or tint != Color.WHITE or shift:
		var cover := _over(m, mask, "_DecalMask", size, 0).get_data()
		var channel := clampi(str(m.floats.get("_Decal%sMaskChannel" % slot, "0")).to_int(), 0, 3) if mask != null else 3
		var data := colour.get_data()
		for i in range(0, data.size(), 4):
			data[i] = mini(int(data[i] * tint.r), 255)
			data[i + 1] = mini(int(data[i + 1] * tint.g), 255)
			data[i + 2] = mini(int(data[i + 2] * tint.b), 255)
			data[i + 3] = mini(int(data[i + 3] * tint.a * cover[i + channel] / 255.0), 255)
		if shift:
			var by := _saved(m, "_DecalHueShift" + n, 0.0)
			var space := _float(m, "_DecalHueShiftColorSpace" + n)
			var select := _float(m, "_DecalHueShiftSelectOrShift" + n, 1.0)
			for i in range(0, data.size(), 4):
				var shifted := hue_shift(Color8(data[i], data[i + 1], data[i + 2]).srgb_to_linear(), by, space, select).clamp().linear_to_srgb()
				data[i] = shifted.r8
				data[i + 1] = shifted.g8
				data[i + 2] = shifted.b8
		colour.set_data(size.x, size.y, false, Image.FORMAT_RGBA8, data)
	_decal_of[settings] = _baked_decal(colour)
	return _decal_of[settings]


func _baked_decal(image: Image) -> int:
	var baked := image.get_data()
	var alike: Array = _decal_index.get_or_add([image.get_size(), hash(baked)], [])
	var found: int = alike.reduce(func(at: int, k: int) -> int: return k if at < 0 and decal_images[k].get_data() == baked else at, -1)
	if found < 0:
		found = decal_images.size()
		alike.append(found)
		decal_images.append(image)
	return found


## By `shift` turns, in OKLab blending to HSV as `space` nears 1; `select` 0 replaces the hue by the shift.
static func hue_shift(c: Color, shift: float, space: float, select: float) -> Color:
	var l := pow(maxf(0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b, 0.0), 1.0 / 3.0)
	var m := pow(maxf(0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b, 0.0), 1.0 / 3.0)
	var s := pow(maxf(0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b, 0.0), 1.0 / 3.0)
	var lightness := 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
	var ab := Vector2(1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s, 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
	if select <= 0.5:
		ab = Vector2(ab.length(), 0.0)
	ab = ab.rotated(shift * TAU)
	var cube := func(x: float) -> float: return x * x * x
	var l3: float = cube.call(lightness + 0.3963377774 * ab.x + 0.2158037573 * ab.y)
	var m3: float = cube.call(lightness - 0.1055613458 * ab.x - 0.0638541728 * ab.y)
	var s3: float = cube.call(lightness - 0.0894841775 * ab.x - 1.2914855480 * ab.y)
	var oklab := Color(4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3, -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3, -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3)
	var hsv := Color.from_hsv(fposmod(c.h * select + shift, 1.0), c.s, c.v)
	return oklab.lerp(hsv, clampf(space, 0.0, 1.0))


## Under its declared name: a locked shader suffixes an animated property's name with the material's.
static func _saved(m: Dictionary, name: String, otherwise: float) -> float:
	var floats: Dictionary = m.get("floats", {})
	for declared: String in m.get("properties", {}):
		if declared.begins_with(name + "_") and floats.has(declared):
			return str(floats[declared]).to_float()
	return _float(m, name, otherwise)


## Poiyomi matcap `slot` (0 to 3), or lilToon's; {} where off, rotated, panned, or in a UV mode other than normal (0,
## which a headset draws as 1) or reflection (2). "texture" is a GUID, "" for white; "theme" a `_theme` slot.
func matcap(key: String, slot: int) -> Dictionary:
	var m: Dictionary = materials[key]
	if m.has("cell") and Liltoon.is_liltoon(m):
		return Liltoon.matcap(m, slot)
	var colours: Dictionary = m.get("colours", {})
	var p: String = MATCAPS[slot]
	if not m.has("cell") or not poiyomi(m) or _float(m, p + "Enable") == 0.0:
		return {}
	var mode: float = _float(m, p + "UVMode", 1.0)
	if mode not in [0.0, 1.0, 2.0] or _float(m, p + "Rotation") != 0.0 or _colour(colours.get(p + "Pan"), Color(0, 0, 0, 0)) != Color(0, 0, 0, 0):
		return {}
	if global_mask(m, int(_float(m, p + "MaskGlobalMask"))) is bool:
		return {}
	var colour := shader_colour(m, p + "Color", Color.WHITE)
	var index := int(_float(m, p + "ColorThemeIndex")) - 1
	var theme := _theme(m, index) if index >= 0 and index <= 3 else {}
	if not theme.is_empty():
		var themed := ExpressionPlayer.theme_colour(theme, 0.0)
		colour = Color(themed.r, themed.g, themed.b, colour.a)
	var hue: Variant = null
	if _float(m, p + "HueShiftEnabled") != 0.0:
		hue = {"shift": _saved(m, p + "HueShift", 0.0), "space": _float(m, p + "HueShiftColorSpace"), "select": _float(m, p + "HueSelectOrShift", 1.0)}
	var circle: Variant = null
	if slot == 0 and _float(m, "_Matcap0CircleMaskEnabled") != 0.0:
		circle = {"border": _float(m, "_Matcap0CircleMaskBorder", 0.5), "blur": _float(m, "_Matcap0CircleMaskBlur")}
	return {
		"texture": _texture_guid(m, p),
		"mode": "reflection" if mode == 2.0 else "normal",
		"border": _float(m, p + "Border", 0.43),
		"color": [colour.r, colour.g, colour.b, colour.a],
		"intensity": _saved(m, p + "Intensity", 1.0),
		"baseMix": _float(m, p + "BaseColorMix"),
		"replace": _saved(m, p + "Replace", 1.0),
		"multiply": _saved(m, p + "Multiply", 0.0),
		"add": _saved(m, p + "Add", 0.0),
		"screen": _saved(m, p + "Screen", 0.0),
		"mixed": _saved(m, p + "Mixed", 0.0),
		"lightAdd": _float(m, p + "AddToLight"),
		"emission": _float(m, p + "EmissionStrength"),
		"lightMask": _float(m, p + "LightMask"),
		"hue": hue,
		"circle": circle,
		"theme": null if theme.is_empty() else theme.slot,
	}


## {} where off, globally masked, or its maps panned or not read by a UV channel. "st" is [scale x, scale y, offset x,
## offset y]; "texture" "" reads white, as does channel 4; "gsaa" [variance, threshold], zero where off;
## "fresnelStrength" null before Poiyomi 9.2; "fallbackTexture" "" for Unity's grey default.
func clearcoat(key: String) -> Dictionary:
	var m: Dictionary = materials[key]
	var floats: Dictionary = m.get("floats", {})
	var colours: Dictionary = m.get("colours", {})
	var number := func(name: String, otherwise: float) -> float: return str(floats.get(name, otherwise)).to_float()
	if not poiyomi(m) or _saved(m, "_ClearCoatBRDF", 0.0) == 0.0:
		return {}
	if COAT_GLOBAL_MASKS.any(func(p: String) -> bool: return number.call(p, 0.0) != 0.0):
		return {}
	var map := _texture_guid(m, "_ClearCoatMaps")
	var uv := int(number.call("_ClearCoatMapsUV", 0.0))
	if map != "" and (uv > 3 or _colour(colours.get("_ClearCoatMapsPan"), Color(0, 0, 0, 0)) != Color(0, 0, 0, 0)):
		return {}
	var entry: Dictionary = (m.get("textures", {}) as Dictionary).get("_ClearCoatMaps", {})
	var pair := func(v: Variant, otherwise: float) -> Array: return [str(v.get("x", otherwise)).to_float(), str(v.get("y", otherwise)).to_float()] if v is Dictionary else [otherwise, otherwise]
	var recent := (m.properties as Dictionary).has("_ClearcoatFresnelStrength")
	var tint := func(property: String) -> Array:
		var theme := int(number.call(property + "ThemeIndex", 0.0))
		var c: Color = ExpressionPlayer.theme_colour(_theme(m, theme - 1), 0.0) if theme >= 1 and theme <= 4 else shader_colour(m, property, Color.WHITE)
		return [c.r, c.g, c.b]
	return {
		"strength": _saved(m, "_ClearCoatStrength", 1.0),
		"smoothness": _saved(m, "_ClearCoatSmoothness", 1.0),
		"reflection": _saved(m, "_ClearCoatReflectionStrength", 1.0),
		"specular": _saved(m, "_ClearCoatSpecularStrength", 1.0),
		"specularTint": tint.call("_ClearCoatSpecularTint"),
		"reflectionTint": tint.call("_ClearCoatReflectionTint"),
		"fresnel": 1.0 if recent else _saved(m, "_ClearcoatFresnel", 1.0),
		"fresnelStrength": _saved(m, "_ClearcoatFresnelStrength", 0.5) if recent else null,
		"exposureOcclusion": _saved(m, "_ClearcoatExposureOcclusion", 0.0) if recent else 0.0,
		"gsaa": [number.call("_ClearCoatGSAAVariance", 0.15), number.call("_ClearCoatGSAAThreshold", 0.1)] if number.call("_ClearCoatGSAAEnabled", 1.0) != 0.0 else [0.0, 0.0],
		"texture": map,
		"uv": uv,
		"st": pair.call(entry.get("m_Scale"), 1.0) + pair.call(entry.get("m_Offset"), 0.0),
		"channels": COAT_CHANNELS.map(func(c: Array) -> int: return int(number.call(c[0], c[1]))),
		"inverts": COAT_INVERTS.map(func(p: String) -> bool: return number.call(p, 0.0) != 0.0),
		"fallbackTexture": _texture_guid(m, "_ClearCoatFallback"),
		"litFallback": number.call("_ClearCoatLitFallback", 1.0) != 0.0,
		"forceFallback": number.call("_ClearCoatForceFallback", 0.0) != 0.0,
	}


## Per level in `coat_map`'s channel order; COAT_CHANNELS as [property, Poiyomi's default].
const COAT_GLOBAL_MASKS := ["_ClearCoatGlobalMask", "_ClearCoatSmoothnessGlobalMask", "_ClearCoatReflectionStrengthGlobalMask", "_ClearCoatSpecularStrengthGlobalMask"]
const COAT_CHANNELS := [["_ClearCoatMapsClearCoatMaskChannel", 0.0], ["_ClearCoatMapsRoughnessChannel", 1.0], ["_ClearCoatMapsReflectionMaskChannel", 2.0], ["_ClearCoatMapsSpecularMaskChannel", 3.0]]
const COAT_INVERTS := ["_ClearCoatMaskInvert", "_ClearCoatSmoothnessMapInvert", "_ClearCoatReflectionMaskInvert", "_ClearCoatSpecularMaskInvert"]
## The packed maps mask a highlight and a reflection, not a colour.
const COAT_MAP := 512


## Bands Avatar.FALLBACK_SIDE / 2 high: band k is Unity's specular-convolved cube mip k (Poiyomi reads roughness * 6),
## RGBM over Avatar.FALLBACK_RANGE, azimuth as Unity's panoramic skybox. Null, and reported, where absent, undecodable,
## or not a cube from a 2:1 panorama at least Avatar.FALLBACK_SIDE wide.
func coat_fallback(guid: String) -> Image:
	if not assets.by_guid.has(guid):
		absent[guid] = true
		return null
	var importer: Dictionary = assets.meta(guid).get("TextureImporter", {})
	var panorama := str(importer.get("textureShape", "")) == "2" and str(importer.get("generateCubemap", "")) in ["2", "6"]
	var source: Image = _hdr_image(guid) if panorama else null
	if source == null or source.get_width() != 2 * source.get_height() or source.get_width() < Avatar.FALLBACK_SIDE:
		undecoded[assets.by_guid[guid].path] = true
		return null
	source.decompress()
	source.convert(Image.FORMAT_RGBF)
	var side := Avatar.FALLBACK_SIDE
	var out := Image.create_empty(side, side / 2 * Avatar.FALLBACK_LEVELS, false, Image.FORMAT_RGBA8)
	var panoramas := {}
	for level in Avatar.FALLBACK_LEVELS:
		# The lobe widens faster than Unity's mips halve: each level integrates at a size that samples its lobe.
		var w: int = [side, side, side / 2, side / 4, side / 4, side / 4, side / 4][level]
		var from_w: int = w if level < 4 else w / 2
		for width: int in [w, from_w]:
			if not panoramas.has(width):
				panoramas[width] = _panorama(source, width)
		var at: Dictionary = panoramas[w]
		var from: Dictionary = panoramas[from_w]
		var h := w / 2
		var from_h := from_w / 2
		var rough := level / (Avatar.FALLBACK_LEVELS - 1.0)
		var perceptual := (1.7 - sqrt(2.89 - 2.8 * rough)) / 1.4
		var a2 := pow(perceptual, 4.0)
		# Past this angle the lobe has fallen to a thousandth of its peak.
		var reach := acos(clampf(1.0 - 61.2 * a2 / (1.0 - a2 + 1e-9), -1.0, 1.0)) if level > 0 else 0.0
		var rows := ceili(reach / PI * from_h)
		var toward: PackedVector3Array = from.toward
		var light: PackedVector3Array = from.light
		var angle: PackedFloat32Array = from.angle
		var drawn := Image.create_empty(w, h, false, Image.FORMAT_RGBF)
		for i in w * h:
			var c: Vector3 = at.light[i]
			if level > 0:
				var n: Vector3 = at.toward[i]
				var row := (i / w) * from_h / h
				var column := (i % w) * from_w / w
				var nearest := minf(sin(PI * (clampi(row - rows, 0, from_h - 1) + 0.5) / from_h), sin(PI * (clampi(row + rows, 0, from_h - 1) + 0.5) / from_h))
				var columns := from_w / 2 if row - rows < 0 or row + rows >= from_h else mini(from_w / 2, ceili(reach / (TAU * nearest) * from_w))
				var sum := Vector3.ZERO
				var weight := 0.0
				for y in range(maxi(row - rows, 0), mini(row + rows, from_h - 1) + 1):
					for dx in range(-columns, columns + (0 if 2 * columns == from_w else 1)):
						var k := y * from_w + posmod(column + dx, from_w)
						var nl := n.dot(toward[k])
						if nl <= 0.0:
							continue
						var d := (1.0 + nl) * 0.5 * (a2 - 1.0) + 1.0
						var share := nl * angle[k] / (d * d)
						sum += light[k] * share
						weight += share
				c = sum / maxf(weight, 1e-12)
			drawn.set_pixel(i % w, i / w, Color(c.x, c.y, c.z))
		drawn.resize(side, side / 2, Image.INTERPOLATE_BILINEAR)
		for y in side / 2:
			for x in side:
				var c := drawn.get_pixel(x, y)
				var m := ceilf(clampf(maxf(c.r, maxf(c.g, c.b)) / Avatar.FALLBACK_RANGE, 1.0 / 255.0, 1.0) * 255.0) / 255.0
				var scale := 1.0 / (m * Avatar.FALLBACK_RANGE)
				out.set_pixel(x, level * side / 2 + y, Color(minf(c.r * scale, 1.0), minf(c.g * scale, 1.0), minf(c.b * scale, 1.0), m))
	return out


## Only Image.load_from_file decodes .exr and .hdr, by extension, which an unpacked .unitypackage's `asset` lacks.
func _hdr_image(guid: String) -> Image:
	var file: String = assets.by_guid[guid].file
	var kind := assets.extension(guid)
	if kind not in ["exr", "hdr"]:
		return null
	if file.get_extension().to_lower() == kind:
		return Assets.quietly(func() -> Image: return Image.load_from_file(file))
	var named := OS.get_temp_dir().path_join("unity_avatar_%d_%s.%s" % [OS.get_process_id(), guid, kind])
	if DirAccess.copy_absolute(file, named) != OK:
		return null
	var img: Image = Assets.quietly(func() -> Image: return Image.load_from_file(named))
	DirAccess.remove_absolute(named)
	return img


## Per texel of `w` by `w` / 2: "toward" in Unity's axes as its panoramic skybox reads it (u = 0.5 - atan2(z, x) / 2π,
## top row up), "light", and relative solid "angle".
static func _panorama(source: Image, w: int) -> Dictionary:
	var h := w / 2
	var light := PackedVector3Array()
	light.resize(w * h)
	var counts := PackedInt32Array()
	counts.resize(w * h)
	for y in source.get_height():
		for x in source.get_width():
			var c := source.get_pixel(x, y)
			var i := (y * h / source.get_height()) * w + x * w / source.get_width()
			light[i] += Vector3(c.r, c.g, c.b)
			counts[i] += 1
	var toward := PackedVector3Array()
	var angle := PackedFloat32Array()
	for i in w * h:
		light[i] /= counts[i]
		var azimuth := (0.5 - (i % w + 0.5) / w) * TAU
		var polar := PI * (i / w + 0.5) / h
		toward.append(Vector3(sin(polar) * cos(azimuth), cos(polar), sin(polar) * sin(azimuth)))
		angle.append(sin(polar))
	return {"toward": toward, "light": light, "angle": angle}


## r mask, g smoothness, b reflection, a specular, in linear light, at most COAT_MAP wide; null where undecodable.
func coat_map(coat: Dictionary) -> Image:
	var source := _sampled(coat.texture)
	if source == null:
		return null
	var side := mini(COAT_MAP, shown(coat.texture)) if shown(coat.texture) > 0 else COAT_MAP
	if source.get_width() > side or source.get_height() > side:
		var big := maxi(source.get_width(), source.get_height())
		source.resize(maxi(1, source.get_width() * side / big), maxi(1, source.get_height() * side / big), RESAMPLE)
	var data := source.get_data()
	var out := PackedByteArray()
	out.resize(data.size())
	var channels := PackedInt32Array(coat.channels)
	for i in data.size() / 4:
		for level in 4:
			var c := channels[level]
			var byte: int = 255 if c > 3 else data[4 * i + c]
			out[4 * i + level] = byte
	return Image.create_from_data(source.get_width(), source.get_height(), false, Image.FORMAT_RGBA8, out)


## Poiyomi global mask `index` (one-based, 0 none): {} for none; {"property", "channel"}, "property" "" for
## Poiyomi's whole 1; false where more than one UV0 sample draws it.
static func global_mask(m: Dictionary, index: int) -> Variant:
	if index <= 0:
		return {}
	if _float(m, "_GlobalMaskOptionsEnable") != 0.0 or ["Backface", "Camera", "Distance", "Mirror"].any(func(kind: String) -> bool: return _float(m, "_GlobalMaskModifiers%sEnable" % kind) != 0.0):
		return false
	var property := "_GlobalMaskTexture%d" % ((index - 1) / 4)
	if _float(m, "_GlobalMaskTexturesEnable") == 0.0 or _texture_guid(m, property) == "":
		return {"property": "", "channel": 0}
	if _float(m, property + "UV") != 0.0 or _float(m, property + "Split") != 0.0 or _colour((m.get("colours", {}) as Dictionary).get(property + "Pan"), Color(0, 0, 0, 0)) != Color(0, 0, 0, 0):
		return false
	return {"property": property, "channel": (index - 1) % 4}


static func mask_blend(mask: float, value: float, type: int) -> float:
	var blended: float = [value, mask - value, mask * value, mask / maxf(value, 0.0001), minf(mask, value), maxf(mask, value), (mask + value) * 0.5, mask + value][clampi(type, 0, 7)]
	return clampf(blended, 0.0, 1.0)


## "flat" for a shader lighting by the light's colour whichever way it faces, at most "cap" under Poiyomi's Max
## Brightness; else "lit", Toon Standard's with its "ramp" and "shadowTint", capped at 1 under Limit Brightness.
func lighting(key: String) -> Dictionary:
	var m: Dictionary = materials[key]
	if Liltoon.is_liltoon(m):
		return Liltoon.lighting(m)
	if poiyomi(m) and _flat_poiyomi(m):
		var flat := {"model": "flat"}
		if _capped(m):
			flat.cap = _saved(m, "_LightingCap", 1.0)
		return flat
	if m.get("shader", "") == "VRChat/Mobile/Toon Lit":
		return {"model": "flat"}
	if toon_standard(m):
		var ramped := {"model": "lit", "ramp": _ramp(m), "shadowTint": _saved(m, "_ShadowAlbedo", 0.5)}
		if _saved(m, "_LimitBrightness", 1.0) != 0.0:
			ramped.cap = 1.0
		return ramped
	return {"model": "lit"}


static func _capped(m: Dictionary) -> bool:
	return _saved(m, "_LightingCapEnabled", 1.0) != 0.0


## Flat, or Multilayer Math or Skin where Shadow Strength is 0 or their shade keeps the direct light whole.
static func _flat_poiyomi(m: Dictionary) -> bool:
	var mode := _float(m, "_LightingMode")
	if mode == 5.0:
		return true
	if mode != 1.0 and mode != 3.0:
		return false
	if _saved(m, "_ShadowStrength", 1.0) == 0.0:
		return true
	return _untinted(m) if mode == 1.0 else _skin_shade_covers_light(m)


## Skin's shade is a floor of its own, not a fraction of the light (the lesser of the light and Shadow Tint, times
## indirect light, less occlusion), so it keeps the light whole only under a Max Brightness it reaches.
static func _skin_shade_covers_light(m: Dictionary) -> bool:
	if _saved(m, "_LightingIgnoreAmbientColor", 1.0) != 1.0 or not _capped(m):
		return false
	if _texture_guid(m, "_LightingAOMaps") != "" or _float(m, "_LightDataAOGlobalMaskR") != 0.0:
		return false
	var cap := _saved(m, "_LightingCap", 1.0)
	var tint := _colour((m.get("colours", {}) as Dictionary).get("_LightingShadowColor"), Color.WHITE)
	return tint.r >= cap and tint.g >= cap and tint.b >= cap


## Multilayer Math's shadow side is the direct light times a tint, white where it ignores the ambient colour, mixes
## in no base colour and each drawn layer is untextured white.
static func _untinted(m: Dictionary) -> bool:
	if _saved(m, "_LightingIgnoreAmbientColor", 1.0) != 1.0 or _saved(m, "_ShadowMainStrength", 0.0) != 0.0:
		return false
	var colours: Dictionary = m.get("colours", {})
	for layer: String in ["", "2nd", "3rd"]:
		var tint := _colour(colours.get("_Shadow%sColor" % layer), Color(0.7, 0.75, 0.85, 1.0) if layer == "" else Color(0, 0, 0, 0))
		if tint.a > 0.0 and (tint.r != 1.0 or tint.g != 1.0 or tint.b != 1.0 or _texture_guid(m, "_Shadow%sColorTex" % layer) != ""):
			return false
	return true


const RAMP := 16


## At RAMP even points of the half-Lambert term 0 to 1: the middle row's channel mean in linear light plus Shadow
## Boost, at most 1, so a coloured ramp shades grey; white, the shader's default, without a texture.
func _ramp(m: Dictionary) -> Array:
	var guid := _texture_guid(m, "_Ramp")
	var img := image(guid) if guid != "" else null
	var linear := img == null or not _srgb(guid)
	var boost := _saved(m, "_ShadowBoost", 0.0)
	var out := []
	for i in RAMP:
		var c := Color.WHITE
		if img != null:
			c = img.get_pixel(roundi(i * (img.get_width() - 1) / (RAMP - 1.0)), img.get_height() / 2)
			if not linear:
				c = c.srgb_to_linear()
		out.append(minf((c.r + c.g + c.b) / 3.0 + boost, 1.0))
	return out


## At rest, "color" linear, "replace" Poiyomi's Override Base Color, "theme" a `_theme` slot; or {}. Poiyomi adds
## its four emissions up, so those alike fold into the drawn one's map (`_folded`).
func emission(key: String) -> Dictionary:
	var m: Dictionary = materials[key]
	if not m.has("cell"):
		return {}
	if Liltoon.is_liltoon(m):
		return Liltoon.emission(m)
	if toon_standard(m):
		if _float(m, "_EmissionUV") != 0.0:
			return {}
		var colour := _colour((m.get("colours", {}) as Dictionary).get("_EmissionColor"), Color.BLACK).srgb_to_linear()
		if colour.r + colour.g + colour.b == 0.0:
			return {}
		return {"color": [colour.r, colour.g, colour.b], "strength": _saved(m, "_EmissionStrength", 1.0), "hue": _saved(m, "_EmissionHueShift", 0.0), "shiftsHue": "USE_HUE_SHIFT" in m.get("keywords", []), "replace": 0.0}
	var drawn := _drawn(key)
	if drawn.is_empty():
		return {}
	var colour: Color = ExpressionPlayer.theme_colour(drawn.theme, 0.0) if not drawn.theme.is_empty() else drawn.colour
	if colour.r + colour.g + colour.b == 0.0 and drawn.theme.is_empty():
		return {}
	var out := {"color": [colour.r, colour.g, colour.b], "strength": drawn.strength * _peak(key), "hue": 0.0, "shiftsHue": false, "replace": drawn.replace}
	if not drawn.theme.is_empty():
		out.theme = drawn.theme.slot
	return out


func _drawn(key: String) -> Dictionary:
	var glows := _poiyomi_glows(key)
	var lit := glows.filter(func(g: Dictionary) -> bool: return g.strength > 0.0)
	if not glows.is_empty() and glows[0].slot == 0 and (glows[0].strength > 0.0 or strength_driven.has(key) or lit.is_empty()):
		return glows[0]
	return lit.reduce(func(strongest: Dictionary, g: Dictionary) -> Dictionary: return g if g.strength > strongest.strength else strongest, lit[0]) if not lit.is_empty() else {}


## Each {"slot", "strength", "replace", "theme" ({} for none), "colour" (linear)}, in slot order. Those the base
## colour tints are out: decals and hue shifts change it after the atlas.
func _poiyomi_glows(key: String) -> Array[Dictionary]:
	if _glow_lists.has(key):
		return _glow_lists[key]
	var m: Dictionary = materials[key]
	var out: Array[Dictionary] = []
	_glow_lists[key] = out
	if not poiyomi(m):
		return out
	for slot in 4:
		var n := "" if slot == 0 else str(slot)
		if _saved(m, "_EnableEmission" + n, 0.0) == 0.0:
			continue
		var still := ["_EmissionMap%sUV" % n, "_EmissionMask%sUV" % n, "_EmissionBaseColorAsMap" + n, "_EmissionCenterOutEnabled" + n, "_ScrollingEmission" + n, "_EmissionBlinkingEnabled" + n, "_EmissionHueShiftEnabled" + n, "_EnableGITDEmission" + n]
		if not still.all(func(name: String) -> bool: return _float(m, name) == 0.0) or not global_mask(m, int(_float(m, "_EmissionMask%dGlobalMask" % slot))) is Dictionary:
			continue
		var index := int(_float(m, "_EmissionColor%sThemeIndex" % n)) - 1
		var theme := _theme(m, index) if index >= 0 and index <= 3 else {}
		var colour := shader_colour(m, "_EmissionColor" + n, Color.WHITE)
		var strength := _saved(m, "_EmissionStrength" + n, 0.0)
		out.append({"slot": slot, "strength": strength if slot == 0 and strength_driven.has(key) else _audio_link_strength(m, slot, strength), "replace": _saved(m, "_EmissionReplace%d" % slot, 0.0), "theme": theme, "colour": colour})
	return out


## As Poiyomi leaves it where no world sends AudioLink: only Band Overrides count, at their sliders (volume band 0),
## and the center-out add reads an empty history, so adds its minimum.
static func _audio_link_strength(m: Dictionary, slot: int, strength: float) -> float:
	if _float(m, "_EnableAudioLink") == 0.0 or _saved(m, "_AudioLinkAnimToggle", 1.0) == 0.0 or _float(m, "_AudioLinkBandOverridesEnabled") == 0.0 or _float(m, "_EmissionAL%dEnabled" % slot) == 0.0:
		return strength
	var colours: Dictionary = m.get("colours", {})
	var sliders := _colour(colours.get("_AudioLinkBandOverrideSliders"), Color(0, 0, 0, 0))
	var level := func(band: String) -> float: return [sliders.r, sliders.g, sliders.b, sliders.a, 0.0][clampi(int(_float(m, band)), 0, 4)]
	var range_of := func(name: String, otherwise: Color) -> Color: return _colour(colours.get(name), otherwise)
	var add: Color = range_of.call("_EmissionAL%dStrengthMod" % slot, Color(0, 0, 0, 0))
	var times: Color = range_of.call("_EmissionAL%dMultipliers" % slot, Color(1, 1, 0, 0))
	strength += lerpf(add.r, add.g, level.call("_EmissionAL%dStrengthBand" % slot))
	strength *= lerpf(times.r, times.g, level.call("_EmissionAL%dMultipliersBand" % slot))
	return strength + range_of.call("_AudioLinkEmission%dCenterOut" % slot, Color(0, 0, 0, 0)).r


## Emissions folding into `_drawn`'s, as [slot, strength over the drawn one's].
func _folded(key: String) -> Array:
	var drawn := _drawn(key)
	if drawn.is_empty() or drawn.strength == 0.0 or drawn.slot == 0 and strength_driven.has(key):
		return [] if drawn.is_empty() else [[drawn.slot, 1.0]]
	var alike := func(g: Dictionary) -> bool: return g.replace == drawn.replace and g.strength > 0.0 and (g.theme.get("slot") == drawn.theme.slot if not drawn.theme.is_empty() else g.theme.is_empty() and g.colour.is_equal_approx(drawn.colour))
	return _poiyomi_glows(key).filter(alike).map(func(g: Dictionary) -> Array: return [g.slot, g.strength / drawn.strength])


## In linear light, as VRChat's projects are: Unity converts each colour it hands a shader, but a locked (Thry's)
## shader inlines an unanimated colour declared [HDR] or [Gamma], not both, as saved.
static func shader_colour(m: Dictionary, name: String, otherwise: Color) -> Color:
	var colour := _colour((m.get("colours", {}) as Dictionary).get(name), otherwise)
	var flags: Dictionary = (m.get("colour_attributes", {}) as Dictionary).get(name, {})
	var inlined := str(m.get("shader", "")).begins_with("Hidden/Locked/") and not (m.get("animated", {}) as Dictionary).has(name)
	return colour if inlined and flags.get("hdr", false) != flags.get("gamma", false) else colour.srgb_to_linear()


## "hsv" is the HDR colour over "exposure", linear; the rest are offsets ExpressionPlayer.theme_colour applies.
static func _theme(m: Dictionary, index: int) -> Dictionary:
	var colour := shader_colour(m, "_GlobalThemeColor%d" % index, Color.WHITE)
	var exposure := maxf(maxf(colour.r, maxf(colour.g, colour.b)), 1.0)
	colour = colour / exposure
	var offset := func(name: String) -> float: return _saved(m, "_GlobalTheme%s%d" % [name, index], 0.0)
	return {"slot": index, "hsv": [colour.h, colour.s, colour.v], "exposure": exposure, "hue": offset.call("Hue"), "saturation": offset.call("Saturation"), "value": offset.call("Value"), "speed": offset.call("HueSpeed")}


## [map over the padded cell, the strength its peak stands for].
func _glow_and_peak(key: String) -> Array:
	if _folded_maps.has(key):
		return _folded_maps[key]
	var m: Dictionary = materials[key]
	if Liltoon.is_liltoon(m):
		return [Liltoon.glow(self, m, _albedo(m)), 1.0]
	var folded := _folded(key) if poiyomi(m) else []
	if folded.size() <= 1:
		return [_glow_of(m, "" if folded.is_empty() or folded[0][0] == 0 else str(folded[0][0])), 1.0]
	var sum := PackedFloat32Array()
	var map: Image
	var peak := 1.0
	for fold: Array in folded:
		var own := _glow_of(m, "" if fold[0] == 0 else str(fold[0]))
		var data := own.get_data()
		if map == null:
			map = own
			sum.resize(data.size())
		for i in data.size():
			if i % 4 != 3:
				sum[i] += _LINEAR[data[i]] * fold[1]
				peak = maxf(peak, sum[i])
	var out := map.get_data()
	for i in out.size():
		if i % 4 != 3:
			out[i] = _ENCODED[int(clampf(sum[i] / peak, 0.0, 1.0) * 4095.0)]
	map.set_data(map.get_width(), map.get_height(), false, Image.FORMAT_RGBA8, out)
	_folded_maps[key] = [map, peak]
	return _folded_maps[key]


func drive_strength(key: String) -> void:
	strength_driven[key] = true
	_glow_lists.erase(key)
	_folded_maps.erase(key)


func _peak(key: String) -> float:
	return _glow_and_peak(key)[1] if _folded(key).size() > 1 else 1.0


func _glow_of(m: Dictionary, n: String) -> Image:
	var map := _over_cell(m, _slot_image(m, "_EmissionMap" + n), "_EmissionMap" + n)
	var p := "_EmissionMask" + n
	var global := "_EmissionMask%dGlobalMask" % (0 if n == "" else n.to_int())
	if not poiyomi(m) or not _masked(m, p, "_EmissionMaskInvert" + n, global):
		return map
	var cover := _mask(m, p, "_EmissionMask%sChannel" % n, "_EmissionMaskInvert" + n, global, global + "BlendType")
	var data := map.get_data()
	for i in cover.size():
		for c in 3:
			data[4 * i + c] = _ENCODED[int(_LINEAR[data[4 * i + c]] * cover[i] * 4095.0 / 255.0)]
	map.set_data(map.get_width(), map.get_height(), false, Image.FORMAT_RGBA8, data)
	return map


func _albedo(m: Dictionary) -> Image:
	var region := atlas.get_region(_padded(m))
	region.clear_mipmaps()
	return region


static func _padded(m: Dictionary) -> Rect2i:
	return (m.cell as Rect2i).grow(PAD)


func _masked(m: Dictionary, property: String, invert: String, global: String) -> bool:
	return _texture_guid(m, property) != "" or int(_float(m, invert)) != 0 or not (global_mask(m, int(_float(m, global))) as Dictionary).is_empty()


## One byte a texel over the padded cell, as Poiyomi masks a matcap or an emission.
func _mask(m: Dictionary, property: String, channel: String, invert: String, global: String, blend: String) -> PackedByteArray:
	var source := _over_cell(m, _slot_image(m, property), property).get_data()
	var pick := clampi(int(_float(m, channel)), 0, 3)
	var inverted := int(_float(m, invert)) != 0
	var over_mask: Dictionary = global_mask(m, int(_float(m, global)))
	var over := PackedByteArray() if over_mask.is_empty() else _over_cell(m, _slot_image(m, over_mask.property) if over_mask.property != "" else null, over_mask.property).get_data()
	var type := int(_float(m, blend, 2.0))
	var out := PackedByteArray()
	out.resize(source.size() / 4)
	for i in out.size():
		var own := 255 - source[4 * i + pick] if inverted else source[4 * i + pick]
		out[i] = own if over.is_empty() else roundi(255.0 * mask_blend(own / 255.0, over[4 * i + over_mask.channel] / 255.0, type))
	return out


static var _LINEAR := PackedFloat32Array(range(256).map(func(v: int) -> float: return Color(v / 255.0, 0, 0).srgb_to_linear().r))
static var _ENCODED := PackedByteArray(range(4096).map(func(v: int) -> int: return roundi(Color(v / 4095.0, 0, 0).linear_to_srgb().r * 255.0)))


func glows_in(key: String, slot: int) -> bool:
	return emission(key).get("theme", -1) == slot


func draws(key: String, look: Dictionary, property: String) -> bool:
	match look.field:
		"decal", "decalIntensity":
			return not decal(key, look.slot).is_empty()
		"decalHue":
			return decal(key, look.slot).get("hue") != null
		"emission":
			if emission(key).is_empty():
				return false
			if poiyomi(materials[key]):
				return _drawn(key).slot == 0
			return not Liltoon.is_liltoon(materials[key]) or Liltoon.blended_by(materials[key]) == property
		"emissionHue":
			return not emission(key).is_empty() and emission(key).shiftsHue
		"themeHue", "themeSaturation", "themeValue", "themeSpeed":
			return glows_in(key, look.slot) or range(MATCAPS.size()).any(func(k: int) -> bool: return matcap(key, k).get("theme") == look.slot)
		"matcapHueShift":
			return matcap(key, look.slot).get("hue") != null
		"clearcoatST":
			return coat_uv(key) >= 0
	return not matcap(key, look.slot).is_empty()


func coat_uv(key: String) -> int:
	var coat := clearcoat(key)
	return coat.uv if not coat.is_empty() and coat.texture != "" else -1


## {"field", "slot"} of the look an animated property drives, or {}; a clear coat ST component's slot is 0 to 3 for xyzw.
static func field(property: String) -> Dictionary:
	if property.begins_with(COAT_ST) and property.length() == COAT_ST.length() + 1:
		var component := "xyzw".find(property.right(1))
		if component >= 0:
			return {"field": "clearcoatST", "slot": component}
	if property in LAYER_ALPHAS:
		return {"field": "decal", "slot": LAYER_ALPHAS.find(property)}
	var decal := _DECAL_FIELD.search(property)
	if decal != null:
		return {"field": {"BlendAlpha": "decal", "AlphaIntensity": "decalIntensity", "HueShift": "decalHue"}[decal.get_string(1)], "slot": decal.get_string(2).to_int()}
	var matcap := _MATCAP_FIELD.search(property)
	if matcap != null:
		return {"field": "matcap" + matcap.get_string(2), "slot": maxi(matcap.get_string(1).to_int() - 1, 0)}
	var blend := _MATCAP_BLEND_FIELD.search(property)
	if blend != null:
		return {"field": "matcapIntensity", "slot": int(blend.get_string(1) != "")}
	var glow := _EMISSION_FIELD.search(property)
	if glow != null:
		return {"field": "emissionHue" if glow.get_string(1) == "HueShift" else "emission", "slot": 0}
	var theme := _THEME_FIELD.search(property)
	if theme != null:
		return {"field": "theme" + {"HueSpeed": "Speed"}.get(theme.get_string(1), theme.get_string(1)), "slot": theme.get_string(2).to_int()}
	return {}


const COAT_ST := "_ClearCoatMaps_ST."
static var LAYER_ALPHAS: Array = Liltoon.LAYERS.map(func(n: String) -> String: return "_Color%s.a" % n)
static var _DECAL_FIELD := RegEx.create_from_string("^_Decal(BlendAlpha|AlphaIntensity|HueShift)([1-3]?)(_|$)")
static var _MATCAP_FIELD := RegEx.create_from_string("^_Matcap([2-4]?)(HueShift|Intensity|Replace|Multiply|Add|Mixed)(_|$)")
static var _MATCAP_BLEND_FIELD := RegEx.create_from_string("^_MatCap(2nd)?Blend$")
static var _EMISSION_FIELD := RegEx.create_from_string("^_Emission(Strength|HueShift|Blend|2ndBlend)(_|$)")
static var _THEME_FIELD := RegEx.create_from_string("^_GlobalTheme(HueSpeed|Hue|Saturation|Value)([0-3])(_|$)")


## By shader: a material switched off Poiyomi keeps Poiyomi's saved values.
static func poiyomi(m: Dictionary) -> bool:
	return str(m.get("shader", "")).containsn("poiyomi")


static func toon_standard(m: Dictionary) -> bool:
	return m.get("shader", "") == "VRChat/Mobile/Toon Standard"


static func _texture_guid(m: Dictionary, property: String) -> String:
	var entry: Variant = (m.get("textures", {}) as Dictionary).get(property)
	return Yaml.guid((entry as Dictionary).get("m_Texture")) if entry is Dictionary else ""


## Only `outline_layer`'s keys where every material is lit by angle with no looks. Else, per atlas texel: "index" (each
## texel one plus its material's entry in "materials", 0 none); entries' "rect" (atlas UV), looks at rest and
## "themes" by slot; atlas-sized "matcapMasks" (channel k matcap slot k's), "emission", "shade" and "shade2"
## (albedo elsewhere), "rimTint" (white elsewhere); "matcaps", "decals", "clearcoatMaps", "clearcoatFallbacks",
## each indexed by the entries.
func looks() -> Dictionary:
	var entries := []
	var index := Image.create_empty(atlas_side, atlas_side, false, Image.FORMAT_L8)
	var matcap_textures := {}
	var matcap_masks: Image
	var glow: Image
	var rim_tints: Image
	var coat_maps := {}
	var coat_images: Array[Image] = []
	var shaded := []
	var second_shaded := false
	var fallbacks := {}
	var fallback_images: Array[Image] = []
	for key: String in materials:
		var m: Dictionary = materials[key]
		if not m.has("cell"):
			continue
		var decals := range(4).map(func(slot: int) -> Dictionary: return decal(key, slot))
		var matcaps := range(4).map(func(slot: int) -> Dictionary: return matcap(key, slot))
		var glows := emission(key)
		if not glows.is_empty() and glows.strength == 0.0 and not glow_regions.has(key):
			glows = {}
		var light := lighting(key)
		var coat := clearcoat(key)
		if decals.all(func(d: Dictionary) -> bool: return d.is_empty()) and matcaps.all(func(c: Dictionary) -> bool: return c.is_empty()) and glows.is_empty() and light == {"model": "lit"} and coat.is_empty():
			continue
		if entries.size() == 255:
			push_error("unity_avatar: over 255 materials with looks; the rest draw lit by angle without decals, matcaps or emission")
			break
		var padded := _padded(m)
		index.fill_rect(padded, Color8(entries.size() + 1, entries.size() + 1, entries.size() + 1))
		var drawn_matcaps := []
		for slot in 4:
			var c: Dictionary = matcaps[slot]
			if c.is_empty():
				drawn_matcaps.append(null)
				continue
			var drawn := c.duplicate()
			drawn.texture = null
			if c.texture != "" and not matcap_textures.has(c.texture):
				var decoded := _decoded(c.texture)
				if decoded != null:
					decoded.resize(MATCAP, MATCAP, RESAMPLE)
					matcap_textures[c.texture] = decoded
			if matcap_textures.has(c.texture):
				drawn.texture = matcap_textures.keys().find(c.texture)
			drawn_matcaps.append(drawn)
			var cover := _matcap_cover(m, slot)
			if cover.is_empty():
				continue
			if matcap_masks == null:
				matcap_masks = Image.create_empty(atlas_side, atlas_side, false, Image.FORMAT_RGBA8)
				matcap_masks.fill(Color.WHITE)
			var region := matcap_masks.get_region(padded)
			var data := region.get_data()
			for i in cover.size():
				data[4 * i + slot] = cover[i]
			region.set_data(padded.size.x, padded.size.y, false, Image.FORMAT_RGBA8, data)
			matcap_masks.blit_rect(region, Rect2i(Vector2i.ZERO, padded.size), padded.position)
		if not glows.is_empty():
			if glow == null:
				glow = Image.create_empty(atlas_side, atlas_side, false, Image.FORMAT_RGBA8)
				glow.fill(Color.BLACK)
			glow.blit_rect(_glow_and_peak(key)[0], Rect2i(Vector2i.ZERO, padded.size), padded.position)
			if _folded_maps.has(key):
				_folded_maps[key][0] = null
		if light.get("shadow") != null:
			shaded.append(m)
			second_shaded = second_shaded or light.shadow.second != null
		var cell := Rect2(m.cell)
		var entry := {"rect": [cell.position.x / atlas_side, cell.position.y / atlas_side, cell.end.x / atlas_side, cell.end.y / atlas_side], "decals": decals.map(func(d: Dictionary) -> Variant: return null if d.is_empty() else d), "matcaps": drawn_matcaps, "emission": null if glows.is_empty() else glows, "lighting": light}
		var themed: Array = drawn_matcaps.filter(func(c: Variant) -> bool: return c is Dictionary and c.theme != null).map(func(c: Dictionary) -> int: return c.theme)
		if glows.get("theme") != null:
			themed.append(glows.theme)
		if not themed.is_empty():
			entry.themes = range(4).map(func(slot: int) -> Variant: return _theme(m, slot) if slot in themed else null)
		if not coat.is_empty():
			var drawn_coat := coat.duplicate()
			drawn_coat.erase("channels")
			drawn_coat.erase("uv")
			drawn_coat.erase("texture")
			var packing := "%s|%s" % [coat.texture, coat.channels]
			if coat.texture != "" and not coat_maps.has(packing):
				var packed_map := coat_map(coat)
				coat_maps[packing] = coat_images.size() if packed_map != null else -1
				if packed_map != null:
					coat_images.append(packed_map)
			drawn_coat.map = coat_maps.get(packing, -1)
			drawn_coat.erase("fallbackTexture")
			if coat.fallbackTexture != "" and not fallbacks.has(coat.fallbackTexture):
				var reflected := coat_fallback(coat.fallbackTexture)
				fallbacks[coat.fallbackTexture] = fallback_images.size() if reflected != null else -1
				if reflected != null:
					fallback_images.append(reflected)
			drawn_coat.fallback = fallbacks.get(coat.fallbackTexture, -1)
			entry.clearcoat = drawn_coat
		var rim := Liltoon.rim(m) if Liltoon.is_liltoon(m) else {}
		if not rim.is_empty():
			entry.rim = rim
			var tint := Liltoon.rim_tint(self, m)
			if tint != null:
				if rim_tints == null:
					rim_tints = Image.create_empty(atlas_side, atlas_side, false, Image.FORMAT_RGBA8)
					rim_tints.fill(Color.WHITE)
				rim_tints.blit_rect(tint, Rect2i(Vector2i.ZERO, padded.size), padded.position)
		var rim_shade := Liltoon.rim_shade(m) if Liltoon.is_liltoon(m) else {}
		if not rim_shade.is_empty():
			entry.rimShade = rim_shade
		entries.append(entry)
	var outlines := outline_layer()
	if entries.is_empty():
		return outlines
	var out := {"index": _layer(index, Image.INTERPOLATE_NEAREST), "materials": entries, "decals": decal_images.duplicate(), "matcaps": matcap_textures.values()}
	out.merge(outlines)
	if matcap_masks != null:
		out.matcapMasks = _layer(matcap_masks, RESAMPLE)
	if glow != null:
		out.emission = _layer(glow, RESAMPLE, GLOW_LAYER)
	if rim_tints != null:
		out.rimTint = _layer(rim_tints, RESAMPLE, GLOW_LAYER)
	if not coat_images.is_empty():
		out.clearcoatMaps = coat_images
	for second: bool in [false, true].slice(0, 0 if shaded.is_empty() else 2 if second_shaded else 1):
		var shade := atlas.duplicate() as Image
		shade.clear_mipmaps()
		var data := shade.get_data()
		for i in range(3, data.size(), 4):
			data[i] = 255
		shade.set_data(atlas_side, atlas_side, false, Image.FORMAT_RGBA8, data)
		for m: Dictionary in shaded:
			shade.blit_rect(Liltoon.shade(self, m, _albedo(m), second), Rect2i(Vector2i.ZERO, _padded(m).size), _padded(m).position)
		out["shade2" if second else "shade"] = _layer(shade, RESAMPLE, GLOW_LAYER)
	if not fallback_images.is_empty():
		out.clearcoatFallbacks = fallback_images
	return out


func _matcap_cover(m: Dictionary, slot: int) -> PackedByteArray:
	if Liltoon.is_liltoon(m):
		return Liltoon.matcap_cover(self, m, slot)
	var p: String = MATCAPS[slot] + "Mask"
	if not _masked(m, p, p + "Invert", p + "GlobalMask"):
		return PackedByteArray()
	return _mask(m, p, p + "Channel", p + "Invert", p + "GlobalMask", p + "GlobalMaskBlendType")


static func _layer(img: Image, resample: Image.Interpolation, widest := LAYER) -> Image:
	if img.get_width() > widest:
		img.resize(widest, widest * img.get_height() / img.get_width(), resample)
	return img


## Decoded afresh: holding every looks texture would outgrow an avatar's memory budget.
func _slot_image(m: Dictionary, property: String) -> Image:
	var guid := _texture_guid(m, property)
	return _decoded(guid) if guid != "" else null


func _slot_sampled(m: Dictionary, property: String) -> Image:
	var guid := _texture_guid(m, property)
	return _sampled(guid) if guid != "" else null


## Decoded afresh, so linearising changes no cached image.
func _sampled(guid: String) -> Image:
	var source := _decoded(guid)
	if source != null and _srgb(guid):
		source.srgb_to_linear()
	return source


func _over_cell(m: Dictionary, source: Image, property: String) -> Image:
	return _over(m, source, property, (m.cell as Rect2i).size, PAD)


## White where `source` is null. The material's texture fills the cell, so another UV0 slot reads through both tilings.
func _over(m: Dictionary, source: Image, property: String, size: Vector2i, pad: int) -> Image:
	var entry: Dictionary = (m.get("textures", {}) as Dictionary).get(property, {})
	return _tiled(m, source, _vector2(entry.get("m_Scale"), Vector2.ONE), _vector2(entry.get("m_Offset"), Vector2.ZERO), size, pad)


func _tiled(m: Dictionary, source: Image, scale: Vector2, offset: Vector2, size: Vector2i, pad: int) -> Image:
	var out := Image.create_empty(size.x + 2 * pad, size.y + 2 * pad, false, Image.FORMAT_RGBA8)
	if source == null:
		out.fill(Color.WHITE)
		return out
	if scale == m.scale and offset == m.offset:
		var inner := source.duplicate() as Image
		inner.resize(size.x, size.y, RESAMPLE)
		if pad == 0:
			return inner
		var outer := source.duplicate() as Image
		outer.resize(out.get_width(), out.get_height(), RESAMPLE)
		out.blit_rect(outer, Rect2i(Vector2i.ZERO, outer.get_size()), Vector2i.ZERO)
		out.blit_rect(inner, Rect2i(Vector2i.ZERO, inner.get_size()), Vector2i(pad, pad))
		return out
	for y in range(-pad, size.y + pad):
		for x in range(-pad, size.x + pad):
			var uv := Vector2((clampi(x, 0, size.x - 1) + 0.5) / size.x, 1.0 - (clampi(y, 0, size.y - 1) + 0.5) / size.y)
			uv = (uv - (m.offset as Vector2)) / (m.scale as Vector2) * scale + offset
			out.set_pixel(x + pad, y + pad, _sample(source, uv))
	return out


static func value(m: Dictionary, property: String) -> Variant:
	for kind: String in ["floats", "ints"]:
		if (m.get(kind, {}) as Dictionary).has(property):
			return str(m[kind][property]).to_float()
	var axis := property.get_slice(".", 1) if property.contains(".") else ""
	var component := maxi("xyzw".find(axis), "rgba".find(axis)) if axis.length() == 1 else -1
	var vector: Variant = (m.get("colours", {}) as Dictionary).get(property.get_slice(".", 0))
	if not vector is Dictionary or component < 0:
		return null
	return str((vector as Dictionary).get("rgba"[component], "0")).to_float()


func losses() -> Array[String]:
	var out: Array[String] = []
	for m: Dictionary in materials.values():
		if m.has("cell") and Liltoon.is_liltoon(m):
			for feature: String in Liltoon.losses(m):
				out.append("%s: %s" % [m.name, feature])
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


static var OUTLINE_PASS := RegEx.create_from_string("(?i)\\bName\\s+\"(?:FORWARD_)?OUTLINE\"|\\bUsePass\\s+\"[^\"]*/FORWARD_OUTLINE\"")
## An outline is millimetres wide, so its colour and width change only across many atlas texels.
const OUTLINE_LAYER := 1024


func outline(key: String) -> Dictionary:
	return materials[key].outline


## {} for none, else "width" (metres), "world" (else the renderer's transform scales it), "colour" (linear),
## "texture" (property it multiplies by), "tint" (how far times the albedo; "squared": twice), "toward" (how far
## replaced by the albedo), "mask" (property whose "channel", -1 its brightest, scales the width) read through UV0
## by "scale" and "offset". Distance scaling is left out: within a metre or two it changes the width a few percent.
## Every outline is lit flat up to white, as each family's clamped, angle-blind light does; VRChat's unlit one too.
func _outline(m: Dictionary) -> Dictionary:
	if not m.outline_pass:
		return {}
	var colours: Dictionary = m.get("colours", {})
	var shader: String = m.shader
	var out := {"texture": "", "tint": 0.0, "squared": false, "toward": 0.0, "mask": "", "channel": 0, "world": false}
	if poiyomi(m):
		var old := shader.begins_with(".poiyomi/Toon/")
		out.width = _saved(m, "_LineWidth", 0.0 if old else 1.0) / 100.0 * (_saved(m, "_EnableOutlines", 0.0) if m.properties.has("_EnableOutlines") else 1.0)
		out.world = old or _float(m, "_OutlineSpace") != 0.0
		out.colour = _colour(colours.get("_LineColor"), Color.WHITE)
		out.texture = "_OutlineTexture"
		out.tint = 0.0 if old else _saved(m, "_OutlineTintMix", 0.0)
		out.mask = "_OutlineMask"
		out.channel = -1 if old or shader.begins_with(".poiyomi/Poiyomi 8.0/") else int(_float(m, "_OutlineMaskChannel"))
		if _float(m, "_OutlineMaskUV") != 0.0 or _float(m, "_OutlineTextureUV") != 0.0:
			return {}
	elif shader.containsn("lilToon"):
		out.width = _float(m, "_OutlineWidth", 0.08) / 100.0
		out.colour = _colour(colours.get("_OutlineColor"), Color(0.6, 0.56, 0.73))
		out.texture = "_OutlineTex"
		out.mask = "_OutlineWidthMask"
		out.scale = m.scale
		out.offset = m.offset
	elif shader.begins_with("UnityChanToonShader/") or shader.begins_with("Toon/Toon"):
		if "_DISABLE_OUTLINE" in m.get("keywords", []) or "_OUTLINE_POS" in m.get("keywords", []):
			return {}
		out.width = _float(m, "_Outline_Width") / 1000.0
		out.colour = _colour(colours.get("_Outline_Color"), Color(0.5, 0.5, 0.5))
		if _float(m, "_Is_OutlineTex") != 0.0:
			out.texture = "_OutlineTex"
		elif _float(m, "_Is_BlendBaseColor") != 0.0:
			out.tint = 1.0
			out.squared = true
		out.mask = "_Outline_Sampler"
	elif shader == "VRChat/Mobile/Toon Standard (Outline)":
		out.width = _float(m, "_OutlineThickness", 0.05) / 100.0
		out.world = true
		out.colour = _colour(colours.get("_OutlineColor"), Color.BLACK)
		out.toward = clampf(_float(m, "_OutlineFromAlbedo"), 0.0, 1.0)
		out.mask = "_OutlineMask"
		out.channel = int(_float(m, "_OutlineMaskChannel"))
		out.scale = Vector2.ONE
		out.offset = Vector2.ZERO
	else:
		return {}
	if out.width <= 0.0:
		return {}
	if not out.has("scale"):
		var entry: Dictionary = (m.get("textures", {}) as Dictionary).get(out.mask, {})
		out.scale = _vector2(entry.get("m_Scale"), Vector2.ONE)
		out.offset = _vector2(entry.get("m_Offset"), Vector2.ZERO)
	out.colour = (out.colour as Color).srgb_to_linear()
	return out


## {} where none draws one; else "outline", each outlined texel its colour (sRGB) and in alpha its width over
## "outlineWidth" (the widest, metres), mask included, clear elsewhere. Object-space widths scale by `outline_scale`,
## the largest where several renderers draw it, as Unity scales its offset.
func outline_layer() -> Dictionary:
	var drawn := {}
	var widest_metres := 0.0
	for key: String in materials:
		var m: Dictionary = materials[key]
		if _outline_metres(m) > 0.0 and m.has("cell"):
			drawn[key] = _outline_metres(m)
			widest_metres = maxf(widest_metres, drawn[key])
	if drawn.is_empty():
		return {}
	var out := Image.create_empty(atlas_side, atlas_side, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	for key: String in drawn:
		var m: Dictionary = materials[key]
		var o: Dictionary = m.outline
		var padded := _padded(m)
		var albedo := _albedo(m).get_data()
		var texture := _over_cell(m, _slot_image(m, o.texture) if o.texture != "" else null, o.texture).get_data()
		var mask := _outline_mask(m, o)
		var data := PackedByteArray()
		data.resize(albedo.size())
		var colour: Color = o.colour
		var share: float = drawn[key] / widest_metres
		for i in range(0, data.size(), 4):
			for c in 3:
				var base := _LINEAR[albedo[i + c]]
				var tinted: float = colour[c] * _LINEAR[texture[i + c]] * lerpf(1.0, base * base if o.squared else base, o.tint)
				data[i + c] = _ENCODED[clampi(roundi(lerpf(tinted, base, o.toward) * 4095.0), 0, 4095)]
			data[i + 3] = roundi(share * mask[i / 4])
		out.blit_rect(Image.create_from_data(padded.size.x, padded.size.y, false, Image.FORMAT_RGBA8, data), Rect2i(Vector2i.ZERO, padded.size), padded.position)
	return {"outline": _layer(out, RESAMPLE, OUTLINE_LAYER), "outlineWidth": widest_metres}


static func _outline_metres(m: Dictionary) -> float:
	return 0.0 if m.outline.is_empty() else m.outline.width * (1.0 if m.outline.world else m.outline_scale)


func _outline_mask(m: Dictionary, o: Dictionary) -> PackedByteArray:
	var texels := _tiled(m, _slot_sampled(m, o.mask), o.scale, o.offset, (m.cell as Rect2i).size, PAD).get_data()
	var out := PackedByteArray()
	out.resize(texels.size() / 4)
	for i in out.size():
		out[i] = maxi(texels[4 * i], maxi(texels[4 * i + 1], texels[4 * i + 2])) if o.channel < 0 else texels[4 * i + clampi(o.channel, 0, 3)]
	return out


## A GPU decodes sRGB before filtering, so a mask or map is decoded before it is resized.
func _srgb(guid: String) -> bool:
	return str(((assets.meta(guid).get("TextureImporter", {}) as Dictionary).get("mipmaps", {}) as Dictionary).get("sRGBTexture", "1")) != "0"
