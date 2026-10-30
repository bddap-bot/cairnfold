extends RefCounted


const Yaml = preload("res://../scripts/unity/yaml.gd")
const Assets = preload("res://../scripts/unity/assets.gd")
const Sdk = preload("res://../scripts/unity/sdk_shaders.gd")

const ATLAS := 2048
const PAD := 4
const TEXTURES := ["_MainTex", "_BaseMap", "_BaseColorMap", "_MainTexture", "_Albedo"]
const COLOURS := ["_Color", "_BaseColor", "_MainColor"]
enum Alpha { OPAQUE, CUTOUT, BLEND }
## How a material's faces draw: whole or cut out, blended over what is behind, or blended and writing depth as Unity's
## ZWrite On does. The atlas holds one material for each pass on each side, PASSES * 2.
enum Pass { SOLID, BLENDED, BLENDED_DEPTH }
const PASSES := 3
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
const MATCAPS := ["_Matcap", "_Matcap2", "_Matcap3", "_Matcap4"]
const MATCAP := 256

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
	var m := {"name": str(ref.get("name", key)), "shader": "", "texture": "", "colour": fallback, "scale": Vector2.ONE, "offset": Vector2.ZERO, "alpha": Alpha.OPAQUE, "cutoff": 0.5, "alpha_mod": 0.0, "depth": false, "cull": Cull.BACK, "image": null}
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
	elif Sdk.SHADERS.has(shader_guid):
		for name: String in Sdk.SHADERS[shader_guid].properties:
			m.properties[name] = true
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
		if _texture_guid(m, k) != "":
			m.texture = _texture_guid(m, k)
			m.scale = _vector2(textures[k].get("m_Scale"), Vector2.ONE)
			m.offset = _vector2(textures[k].get("m_Offset"), Vector2.ZERO)
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
	var number := func(name: String, otherwise: float) -> float: return str(ints.get(name, floats.get(name, otherwise))).to_float()
	var declared := func(name: String) -> bool: return m.properties.has(name) and (ints.has(name) or floats.has(name))
	# A shader drawing `Blend [_SrcBlend] [_DstBlend]` blends exactly when its destination factor is not Zero, whatever
	# queue or preset name the material carries; only without one are those the evidence.
	var blended: bool = number.call("_DstBlend", 0.0) != 0.0 if declared.call("_DstBlend") else queue >= 3000 or render_type == "Transparent" or m.shader.contains("Transparent") or mode >= 2
	if blended:
		m.alpha = Alpha.BLEND
		m.depth = declared.call("_ZWrite") and number.call("_ZWrite", 0.0) != 0.0
	elif queue >= 2450 or render_type == "TransparentCutout" or m.shader.contains("Cutout") or mode == 1:
		m.alpha = Alpha.CUTOUT
		m.cutoff = str(floats.get("_Cutoff", "0.5")).to_float()
	if declared.call("_AlphaMod"):
		m.alpha_mod = number.call("_AlphaMod", 0.0)
	m.cull = clampi(str(ints.get(cull, floats.get(cull, Cull.BACK))).to_int(), Cull.OFF, Cull.BACK) if cull is String else cull


func _shader_name(ref: Dictionary) -> String:
	var guid := str(ref.get("guid", ""))
	if assets.by_guid.has(guid):
		for line in assets.text(guid).split("\n", false, 8):
			if line.strip_edges().begins_with("Shader \""):
				return line.strip_edges().get_slice("\"", 1)
		return assets.name(guid)
	if Sdk.SHADERS.has(guid):
		return Sdk.SHADERS[guid].name
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
		_tint(img, m.colour, m.alpha, m.cutoff, m.alpha_mod)
		var outer := img.duplicate() as Image
		outer.resize(cell.size.x + 2 * PAD, cell.size.y + 2 * PAD, Image.INTERPOLATE_BILINEAR)
		atlas.blit_rect(outer, Rect2i(Vector2i.ZERO, outer.get_size()), cell.position - Vector2i(PAD, PAD))
		atlas.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), cell.position)


## `mod` is Poiyomi's Alpha Mod, added to the alpha before it cuts or blends.
static func _tint(img: Image, colour: Color, alpha: Alpha, cutoff: float, mod: float) -> void:
	var data := img.get_data()
	var mul := [colour.r, colour.g, colour.b, colour.a]
	for i in range(0, data.size(), 4):
		for c in 3:
			data[i + c] = int(data[i + c] * mul[c])
		var a: float = clampf(data[i + 3] * float(mul[3]) / 255.0 + mod, 0.0, 1.0)
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


static func pass_of(m: Dictionary) -> Pass:
	return Pass.SOLID if m.alpha != Alpha.BLEND else Pass.BLENDED_DEPTH if m.depth else Pass.BLENDED


## The atlas as the material of the faces of each pass (Pass), drawing one side and then both: index `two_sided + 2 *
## pass`. Depth written while blending goes as the material's glTF extras, since glTF has no word for it.
func atlas_materials() -> Array[StandardMaterial3D]:
	atlas.generate_mipmaps()
	var texture := ImageTexture.create_from_image(atlas)
	var cut := materials.values().any(func(m: Dictionary) -> bool: return m.has("cell") and m.alpha == Alpha.CUTOUT)
	var out: Array[StandardMaterial3D] = []
	for drawn_as in PASSES:
		for two_sided: bool in [false, true]:
			var drawn := StandardMaterial3D.new()
			drawn.resource_name = "atlas" + (", two-sided" if two_sided else "") + ["", ", blended", ", blended, depth written"][drawn_as]
			drawn.albedo_texture = texture
			drawn.cull_mode = BaseMaterial3D.CULL_DISABLED if two_sided else BaseMaterial3D.CULL_BACK
			if drawn_as != Pass.SOLID:
				drawn.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				drawn.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS if drawn_as == Pass.BLENDED_DEPTH else BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
				drawn.set_meta("extras", {"depthWrite": drawn_as == Pass.BLENDED_DEPTH})
			elif cut:
				drawn.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				drawn.alpha_scissor_threshold = 0.5
			out.append(drawn)
	return out


func hue_mask() -> String:
	var keys := hue_masks.keys()
	keys.append_array(materials.keys().filter(func(key: String) -> bool: return not hue_masks.has(key) and not emission(key).is_empty() and emission(key).shiftsHue))
	var out: Image
	for key: String in keys:
		var m: Dictionary = materials[key]
		var mobile := toon_standard(m)
		var property := "_HueShiftMask" if mobile else "_MainColorAdjustTexture"
		var source := image(_texture_guid(m, property)) if _texture_guid(m, property) != "" else null
		if source == null:
			continue
		if out == null:
			out = Image.create_empty(ATLAS, ATLAS, false, Image.FORMAT_RGBA8)
			out.fill(Color.WHITE)
		var mask := _over_cell(m, source, property, Color.WHITE)
		if mobile:
			var channel := clampi(str(m.floats.get("_HueShiftMaskChannel", "1")).to_int(), 0, 3)
			var data := mask.get_data()
			for i in range(0, data.size(), 4):
				data[i] = data[i + channel]
				data[i + 1] = data[i]
				data[i + 2] = data[i]
				data[i + 3] = 255
			mask.set_data(mask.get_width(), mask.get_height(), false, Image.FORMAT_RGBA8, data)
		out.blit_rect(mask, Rect2i(Vector2i.ZERO, mask.get_size()), (m.cell as Rect2i).position - Vector2i(PAD, PAD))
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


## Poiyomi decal `slot` of the material at `key` as {"alpha", "intensity", "multiply"} at rest, or {} where the decal
## draws in a way the atlas layers cannot hold: anything but the whole UV0 square, untiled, unrotated, at its saved hue,
## replacing or multiplying the albedo.
func decal(key: String, slot: int) -> Dictionary:
	var m: Dictionary = materials[key]
	var floats: Dictionary = m.get("floats", {})
	var colours: Dictionary = m.get("colours", {})
	var n := "" if slot == 0 else str(slot)
	var number := func(name: String) -> float: return str(floats.get(name, "0")).to_float()
	var vector := func(name: String) -> Color: return _colour(colours.get(name), Color(0, 0, 0, 0))
	if not m.has("cell") or not poiyomi(m) or number.call("_DecalEnabled" + n) == 0.0:
		return {}
	var blend: float = number.call("_DecalBlendType" + n)
	var position: Color = vector.call("_DecalPosition" + n)
	var scale: Color = vector.call("_DecalScale" + n)
	var still := ["_DecalTexture%sUV" % n, "_DecalRotation" + n, "_DecalRotationSpeed" + n, "_DecalTiled" + n, "_DecalSymmetryMode" + n, "_DecalMirroredUVMode" + n, "_DecalOverrideAlpha" + n, "_Decal%sGlobalMask" % slot, "_DecalFaceMask" + n, "_DecalDepth" + n]
	if blend not in [0.0, 2.0] or still.any(func(name: String) -> bool: return number.call(name) != 0.0):
		return {}
	if number.call("_DecalHueShiftEnabled" + n) != 0.0 and floats.keys().any(func(name: String) -> bool: return (name == "_DecalHueShift" + n or name.begins_with("_DecalHueShift%s_" % n)) and number.call(name) != 0.0):
		return {}
	if not position.is_equal_approx(Color(0.5, 0.5, 0, 0)) or not is_equal_approx(scale.r, 1.0) or not is_equal_approx(scale.g, 1.0) or vector.call("_DecalSideOffset" + n) != Color(0, 0, 0, 0) or vector.call("_DecalTexture%sPan" % n) != Color(0, 0, 0, 0):
		return {}
	return {"alpha": _saved(m, "_DecalBlendAlpha" + n, 1.0), "intensity": _saved(m, "_DecalAlphaIntensity" + n, 1.0), "multiply": blend == 2.0}


## The material's saved value of the shader property `name`, under the name its shader declares it by: a locked shader
## renames an animated property with the material's suffix.
static func _saved(m: Dictionary, name: String, otherwise: float) -> float:
	var floats: Dictionary = m.get("floats", {})
	for declared: String in m.get("properties", {}):
		if declared.begins_with(name + "_") and floats.has(declared):
			return str(floats[declared]).to_float()
	return str(floats.get(name, otherwise)).to_float()


## Poiyomi matcap `slot` (0 to 3) of the material at `key` at rest, or {} where it is off or maps its matcap by a view
## the renderer does not draw: those other than the normal's (0, which a headset draws as 1) and the reflection's (2),
## or rotated or panned. Its "texture" is the matcap texture's GUID, "" for plain white.
func matcap(key: String, slot: int) -> Dictionary:
	var m: Dictionary = materials[key]
	var floats: Dictionary = m.get("floats", {})
	var colours: Dictionary = m.get("colours", {})
	var p: String = MATCAPS[slot]
	var number := func(name: String, otherwise: float) -> float: return str(floats.get(name, otherwise)).to_float()
	if not m.has("cell") or not poiyomi(m) or number.call(p + "Enable", 0.0) == 0.0:
		return {}
	var mode: float = number.call(p + "UVMode", 1.0)
	if mode not in [0.0, 1.0, 2.0] or number.call(p + "Rotation", 0.0) != 0.0 or _colour(colours.get(p + "Pan"), Color(0, 0, 0, 0)) != Color(0, 0, 0, 0):
		return {}
	var colour := _colour(colours.get(p + "Color"), Color.WHITE).srgb_to_linear()
	var hue: Variant = null
	if number.call(p + "HueShiftEnabled", 0.0) != 0.0:
		hue = {"shift": _saved(m, p + "HueShift", 0.0), "space": number.call(p + "HueShiftColorSpace", 0.0), "select": number.call(p + "HueSelectOrShift", 1.0)}
	var circle: Variant = null
	if slot == 0 and number.call("_Matcap0CircleMaskEnabled", 0.0) != 0.0:
		circle = {"border": number.call("_Matcap0CircleMaskBorder", 0.5), "blur": number.call("_Matcap0CircleMaskBlur", 0.0)}
	return {
		"texture": _texture_guid(m, p),
		"mode": "reflection" if mode == 2.0 else "normal",
		"border": number.call(p + "Border", 0.43),
		"color": [colour.r, colour.g, colour.b, colour.a],
		"intensity": _saved(m, p + "Intensity", 1.0),
		"baseMix": number.call(p + "BaseColorMix", 0.0),
		"replace": _saved(m, p + "Replace", 1.0),
		"multiply": _saved(m, p + "Multiply", 0.0),
		"add": _saved(m, p + "Add", 0.0),
		"screen": _saved(m, p + "Screen", 0.0),
		"mixed": _saved(m, p + "Mixed", 0.0),
		"lightAdd": number.call(p + "AddToLight", 0.0),
		"emission": number.call(p + "EmissionStrength", 0.0),
		"lightMask": number.call(p + "LightMask", 0.0),
		"hue": hue,
		"circle": circle,
	}


## The emission of a VRChat Toon Standard material at `key` at rest as {"color", "strength", "hue", "shiftsHue"}, its
## map in the emission atlas, or {} for a material that glows by another shader's emission or not at all.
func emission(key: String) -> Dictionary:
	var m: Dictionary = materials[key]
	if not m.has("cell") or not toon_standard(m) or str((m.get("floats", {}) as Dictionary).get("_EmissionUV", "0")).to_int() != 0:
		return {}
	var colour := _colour((m.get("colours", {}) as Dictionary).get("_EmissionColor"), Color.BLACK)
	if colour.r + colour.g + colour.b == 0.0:
		return {}
	colour = colour.srgb_to_linear()
	return {"color": [colour.r, colour.g, colour.b], "strength": _saved(m, "_EmissionStrength", 1.0), "hue": _saved(m, "_EmissionHueShift", 0.0), "shiftsHue": "USE_HUE_SHIFT" in m.get("keywords", [])}


## Whether the material at `key` draws the look `field` that an animated property drives in `slot`.
func draws(key: String, look: Dictionary) -> bool:
	match look.field:
		"decal", "decalIntensity":
			return not decal(key, look.slot).is_empty()
		"emission":
			return not emission(key).is_empty()
		"emissionHue":
			return not emission(key).is_empty() and emission(key).shiftsHue
		"matcapHueShift":
			return matcap(key, look.slot).get("hue") != null
	return not matcap(key, look.slot).is_empty()


## The look field an animated shader property drives as {"field", "slot"}, or {} where it drives none: a decal's alpha
## or alpha intensity, a matcap's hue shift or strengths, or emission's strength or hue.
static func field(property: String) -> Dictionary:
	var decal := _DECAL_FIELD.search(property)
	if decal != null:
		return {"field": "decal" if decal.get_string(1) == "BlendAlpha" else "decalIntensity", "slot": decal.get_string(2).to_int()}
	var matcap := _MATCAP_FIELD.search(property)
	if matcap != null:
		return {"field": "matcap" + matcap.get_string(2), "slot": maxi(matcap.get_string(1).to_int() - 1, 0)}
	var glow := _EMISSION_FIELD.search(property)
	if glow != null:
		return {"field": "emission" if glow.get_string(1) == "Strength" else "emissionHue", "slot": 0}
	return {}


static var _DECAL_FIELD := RegEx.create_from_string("^_Decal(BlendAlpha|AlphaIntensity)([1-3]?)(_|$)")
static var _MATCAP_FIELD := RegEx.create_from_string("^_Matcap([2-4]?)(HueShift|Intensity|Replace|Multiply|Add|Mixed)(_|$)")
static var _EMISSION_FIELD := RegEx.create_from_string("^_Emission(Strength|HueShift)(_|$)")


## Whether the material draws by a Poiyomi shader: a material switched to another shader keeps Poiyomi's saved decal and
## matcap values, which that shader never draws.
static func poiyomi(m: Dictionary) -> bool:
	return str(m.get("shader", "")).containsn("poiyomi")


static func toon_standard(m: Dictionary) -> bool:
	return m.get("shader", "") == "VRChat/Mobile/Toon Standard"


static func _texture_guid(m: Dictionary, property: String) -> String:
	var entry: Variant = (m.get("textures", {}) as Dictionary).get(property)
	return str(((entry as Dictionary).get("m_Texture", {}) as Dictionary).get("guid", "")) if entry is Dictionary else ""


## What each packed material lays over its albedo and adds to its light, for the renderer to read by atlas texel: the
## material a texel shows decides it, so a material swapped in for another draws its own. Empty where no material has
## any; otherwise the "index" (a greyscale PNG, each texel one plus its material's entry in "materials", zero for none),
## each entry's decals, matcaps and emission at rest, and the atlas-sized "decals" layers, "matcapMasks" (channel k
## matcap slot k's) and "emission" map, with the "matcaps" textures their entries name by position.
func looks() -> Dictionary:
	var entries := []
	var index := Image.create_empty(ATLAS, ATLAS, false, Image.FORMAT_L8)
	var decal_layers := []
	var matcap_textures := {}
	var matcap_masks: Image
	var glow: Image
	for key: String in materials:
		var m: Dictionary = materials[key]
		if not m.has("cell"):
			continue
		var decals := range(4).map(func(slot: int) -> Dictionary: return decal(key, slot))
		var matcaps := range(4).map(func(slot: int) -> Dictionary: return matcap(key, slot))
		var glows := emission(key)
		if decals.all(func(d: Dictionary) -> bool: return d.is_empty()) and matcaps.all(func(c: Dictionary) -> bool: return c.is_empty()) and glows.is_empty():
			continue
		if entries.size() == 255:
			push_error("unity_avatar: over 255 materials with decals, matcaps or emission; the rest draw without them")
			break
		var padded := Rect2i((m.cell as Rect2i).position - Vector2i(PAD, PAD), (m.cell as Rect2i).size + 2 * Vector2i(PAD, PAD))
		index.fill_rect(padded, Color8(entries.size() + 1, entries.size() + 1, entries.size() + 1))
		for slot in 4:
			if decals[slot].is_empty():
				continue
			while decal_layers.size() <= slot:
				var layer := Image.create_empty(ATLAS, ATLAS, false, Image.FORMAT_RGBA8)
				layer.fill(Color(0, 0, 0, 0))
				decal_layers.append(layer)
			var n := "" if slot == 0 else str(slot)
			var tint := _colour((m.get("colours", {}) as Dictionary).get("_DecalColor" + n), Color.WHITE)
			var colour := _over_cell(m, _slot_image(m, "_DecalTexture" + n), "_DecalTexture" + n, Color.WHITE)
			var mask := _slot_image(m, "_DecalMask")
			var cover := _over_cell(m, mask, "_DecalMask", Color.WHITE).get_data()
			var channel := clampi(str(m.floats.get("_Decal%sMaskChannel" % slot, "0")).to_int(), 0, 3) if mask != null else 3
			var data := colour.get_data()
			for i in range(0, data.size(), 4):
				data[i] = mini(int(data[i] * tint.r), 255)
				data[i + 1] = mini(int(data[i + 1] * tint.g), 255)
				data[i + 2] = mini(int(data[i + 2] * tint.b), 255)
				data[i + 3] = mini(int(data[i + 3] * tint.a * cover[i + channel] / 255.0), 255)
			colour.set_data(padded.size.x, padded.size.y, false, Image.FORMAT_RGBA8, data)
			(decal_layers[slot] as Image).blit_rect(colour, Rect2i(Vector2i.ZERO, padded.size), padded.position)
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
					decoded.resize(MATCAP, MATCAP, Image.INTERPOLATE_BILINEAR)
					matcap_textures[c.texture] = decoded
			if matcap_textures.has(c.texture):
				drawn.texture = matcap_textures.keys().find(c.texture)
			drawn_matcaps.append(drawn)
			var mask := _slot_image(m, MATCAPS[slot] + "Mask")
			var invert := str(m.floats.get(MATCAPS[slot] + "MaskInvert", "0")).to_float() != 0.0
			if mask == null and not invert:
				continue
			if matcap_masks == null:
				matcap_masks = Image.create_empty(ATLAS, ATLAS, false, Image.FORMAT_RGBA8)
				matcap_masks.fill(Color.WHITE)
			var channel := clampi(str(m.floats.get(MATCAPS[slot] + "MaskChannel", "0")).to_int(), 0, 3)
			var source := _over_cell(m, mask, MATCAPS[slot] + "Mask", Color.WHITE).get_data()
			var region := matcap_masks.get_region(padded)
			var data := region.get_data()
			for i in range(0, data.size(), 4):
				data[i + slot] = 255 - source[i + channel] if invert else source[i + channel]
			region.set_data(padded.size.x, padded.size.y, false, Image.FORMAT_RGBA8, data)
			matcap_masks.blit_rect(region, Rect2i(Vector2i.ZERO, padded.size), padded.position)
		if not glows.is_empty():
			if glow == null:
				glow = Image.create_empty(ATLAS, ATLAS, false, Image.FORMAT_RGBA8)
				glow.fill(Color.BLACK)
			glow.blit_rect(_over_cell(m, _slot_image(m, "_EmissionMap"), "_EmissionMap", Color.WHITE), Rect2i(Vector2i.ZERO, padded.size), padded.position)
		entries.append({"decals": decals.map(func(d: Dictionary) -> Variant: return null if d.is_empty() else d), "matcaps": drawn_matcaps, "emission": null if glows.is_empty() else glows})
	if entries.is_empty():
		return {}
	var png := func(img: Image) -> String: return Marshalls.raw_to_base64(img.save_png_to_buffer())
	var out := {"index": png.call(index), "materials": entries, "decals": decal_layers.map(png), "matcaps": matcap_textures.values().map(png)}
	if matcap_masks != null:
		out.matcapMasks = png.call(matcap_masks)
	if glow != null:
		out.emission = png.call(glow)
	return out


## The texture in the material's `property` slot, decoded afresh: looks read each once, and holding them all would
## outgrow an avatar's memory budget.
func _slot_image(m: Dictionary, property: String) -> Image:
	var guid := _texture_guid(m, property)
	return _decoded(guid) if guid != "" else null


## `source` (`blank` where null) as it lies over the material's cell, padded like the atlas: the material's own texture
## fills its cell, so another texture slot of the same UV0 is read through both slots' tilings.
func _over_cell(m: Dictionary, source: Image, property: String, blank: Color) -> Image:
	var cell: Rect2i = m.cell
	var out := Image.create_empty(cell.size.x + 2 * PAD, cell.size.y + 2 * PAD, false, Image.FORMAT_RGBA8)
	if source == null:
		out.fill(blank)
		return out
	var entry: Dictionary = (m.get("textures", {}) as Dictionary).get(property, {})
	var scale := _vector2(entry.get("m_Scale"), Vector2.ONE)
	var offset := _vector2(entry.get("m_Offset"), Vector2.ZERO)
	if scale == m.scale and offset == m.offset:
		var inner := source.duplicate() as Image
		inner.resize(cell.size.x, cell.size.y, Image.INTERPOLATE_BILINEAR)
		var outer := source.duplicate() as Image
		outer.resize(out.get_width(), out.get_height(), Image.INTERPOLATE_BILINEAR)
		out.blit_rect(outer, Rect2i(Vector2i.ZERO, outer.get_size()), Vector2i.ZERO)
		out.blit_rect(inner, Rect2i(Vector2i.ZERO, inner.get_size()), Vector2i(PAD, PAD))
		return out
	for y in range(-PAD, cell.size.y + PAD):
		for x in range(-PAD, cell.size.x + PAD):
			var uv := Vector2((clampi(x, 0, cell.size.x - 1) + 0.5) / cell.size.x, 1.0 - (clampi(y, 0, cell.size.y - 1) + 0.5) / cell.size.y)
			uv = (uv - (m.offset as Vector2)) / (m.scale as Vector2) * scale + offset
			out.set_pixel(x + PAD, y + PAD, _sample(source, uv))
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
