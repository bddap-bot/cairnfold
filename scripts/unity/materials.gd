extends RefCounted


const Yaml = preload("res://../scripts/unity/yaml.gd")
const Assets = preload("res://../scripts/unity/assets.gd")
const Sdk = preload("res://../scripts/unity/sdk_shaders.gd")

## The atlas starts this wide and widens by STEP, up to `widest`, until every material fits at the size its texture
## shows in Unity; past that every cell shrinks alike.
const ATLAS := 2048
const STEP := 256
## The widest atlas expression layers other than the untinted colours are carried at, the widest image a player's file
## carries: they mask or index the albedo, and at a widened atlas's side each would hold as much memory as it.
const LAYER := Avatar.MAX_IMAGE_SIDE
const PAD := 4
## A texture shrinks into its cell several times over; bilinear and cubic resizes read only 2x2 or 4x4 source texels
## per texel, so they alias, while Lanczos widens its kernel to the shrink.
const RESAMPLE := Image.INTERPOLATE_LANCZOS
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
var atlas_side := ATLAS
var widest: int
var undecoded := {}
var hue_masks := {}
var color_regions := {}
## Each decal a material draws (`decal`), at the size Unity imports its texture, once however many slots draw it.
var decal_images: Array[Image] = []
var _decal_of := {}
var _decal_index := {}


func _init(from: Assets, atlas_widest := Avatar.MAX_IMAGE_SIDE) -> void:
	assets = from
	widest = atlas_widest


func use(ref: Dictionary, fallback: Color) -> String:
	var guid := Yaml.guid(ref)
	var key := guid if assets.by_guid.has(guid) and assets.extension(guid) == "mat" else "missing:" + str(ref.get("name", guid))
	if materials.has(key):
		return key
	var m := {"name": str(ref.get("name", key)), "shader": "", "texture": "", "colour": fallback, "scale": Vector2.ONE, "offset": Vector2.ZERO, "alpha": Alpha.OPAQUE, "cutoff": 0.5, "alpha_mod": 0.0, "depth": false, "cull": Cull.BACK, "image": null}
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
	var shader_guid := Yaml.guid(shader)
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
	var guid := Yaml.guid(ref)
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


## The widest side Unity imports the texture at for a PC: its Standalone max size where that overrides, else the default
## platform's, else the legacy field (Unity's own import of a texture whose default is 1024 and legacy field 2048 is
## 1024 wide). 0 where its .meta names none.
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
		var img: Image
		if m.image == null:
			img = Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
			img.fill(Color.WHITE)
		else:
			img = (m.image as Image).duplicate()
		img.resize(cell.size.x, cell.size.y, RESAMPLE)
		_tint(img, m.colour, m.alpha, m.cutoff, m.alpha_mod)
		var outer := img.duplicate() as Image
		outer.resize(cell.size.x + 2 * PAD, cell.size.y + 2 * PAD, RESAMPLE)
		atlas.blit_rect(outer, Rect2i(Vector2i.ZERO, outer.get_size()), cell.position - Vector2i(PAD, PAD))
		atlas.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), cell.position)


## The material's texture as packed: its source size, the size Unity shows it at, and its cell's.
func packed(key: String) -> String:
	var m: Dictionary = materials[key]
	var source := "none" if m.image == null else "%dx%d" % [(m.image as Image).get_width(), (m.image as Image).get_height()]
	return "%s: source %s, shown %s, packed %dx%d" % [m.name, source, m.get("shown", 0) if m.get("shown", 0) > 0 else "as source", (m.cell as Rect2i).size.x, (m.cell as Rect2i).size.y]


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
			out = Image.create_empty(atlas_side, atlas_side, false, Image.FORMAT_RGBA8)
			out.fill(Color.WHITE)
		var mask := _over_cell(m, source, property)
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
	return "" if out == null else _layer(out, RESAMPLE)


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
		raw.resize(cell.size.x, cell.size.y, RESAMPLE)
		var outer := raw.duplicate() as Image
		outer.resize(cell.size.x + 2 * PAD, cell.size.y + 2 * PAD, RESAMPLE)
		out.blit_rect(outer, Rect2i(Vector2i.ZERO, outer.get_size()), cell.position - Vector2i(PAD, PAD))
		out.blit_rect(raw, Rect2i(Vector2i.ZERO, raw.get_size()), cell.position)
	var data := out.get_data()
	var original := atlas.get_data()
	for i in range(3, data.size(), 4):
		data[i] = original[i]
	out.set_data(atlas_side, atlas_side, false, Image.FORMAT_RGBA8, data)
	return Marshalls.raw_to_base64(out.save_png_to_buffer())


## Poiyomi decal `slot` of the material at `key` as {"alpha", "intensity", "multiply", "image"} at rest, baking its
## image into `decal_images`, or {} where the decal draws in a way its image cannot hold: anything but the whole UV0 square, untiled, unrotated, its hue shifted
## by a fixed amount if at all, replacing or multiplying the albedo.
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
	if number.call("_DecalHueShiftEnabled" + n) != 0.0 and (number.call("_DecalHueShiftSpeed" + n) != 0.0 or number.call("_DecalHueAngleStrength" + n) != 0.0):
		return {}
	if not position.is_equal_approx(Color(0.5, 0.5, 0, 0)) or not is_equal_approx(scale.r, 1.0) or not is_equal_approx(scale.g, 1.0) or vector.call("_DecalSideOffset" + n) != Color(0, 0, 0, 0) or vector.call("_DecalTexture%sPan" % n) != Color(0, 0, 0, 0):
		return {}
	return {"alpha": _saved(m, "_DecalBlendAlpha" + n, 1.0), "intensity": _saved(m, "_DecalAlphaIntensity" + n, 1.0), "multiply": blend == 2.0, "image": _decal_image(key, slot)}


## The decal `slot` of the material at `key` as it lies over the material's texture, coloured, masked and hue shifted
## as it draws, at the size Unity imports the decal's texture: its index in `decal_images`.
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
	var shift := str(m.floats.get("_DecalHueShiftEnabled" + n, "0")).to_float() != 0.0
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
			var space := str(m.floats.get("_DecalHueShiftColorSpace" + n, "0")).to_float()
			var select := str(m.floats.get("_DecalHueShiftSelectOrShift" + n, "1")).to_float()
			for i in range(0, data.size(), 4):
				var shifted := hue_shift(Color8(data[i], data[i + 1], data[i + 2]).srgb_to_linear(), by, space, select).clamp().linear_to_srgb()
				data[i] = shifted.r8
				data[i + 1] = shifted.g8
				data[i + 2] = shifted.b8
		colour.set_data(size.x, size.y, false, Image.FORMAT_RGBA8, data)
	var baked := colour.get_data()
	var alike: Array = _decal_index.get_or_add([size, hash(baked)], [])
	var found: int = alike.reduce(func(at: int, k: int) -> int: return k if at < 0 and decal_images[k].get_data() == baked else at, -1)
	if found < 0:
		found = decal_images.size()
		alike.append(found)
		decal_images.append(colour)
	_decal_of[settings] = found
	return found


## Poiyomi's `hueShift` of the linear colour `c`: rotated by `shift` turns in OKLab, or in HSV as `space` nears 1, the
## hue kept (`select` 1) or replaced by the shift alone (`select` 0).
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
	if global_mask(m, int(number.call(p + "MaskGlobalMask", 0.0))) is bool:
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


## Poiyomi global mask `index` (one-based; 0 for none) of the material: {} for none, {"property", "channel"} for a
## texture's channel, with "property" "" where no texture fills it and it stays Poiyomi's whole 1, or false where it is
## drawn by more than one UV0 texture sample (split, panned or other-UV sampling, or a modifier).
static func global_mask(m: Dictionary, index: int) -> Variant:
	var floats: Dictionary = m.get("floats", {})
	var number := func(name: String) -> float: return str(floats.get(name, "0")).to_float()
	if index <= 0:
		return {}
	if number.call("_GlobalMaskOptionsEnable") != 0.0 or ["Backface", "Camera", "Distance", "Mirror"].any(func(kind: String) -> bool: return number.call("_GlobalMaskModifiers%sEnable" % kind) != 0.0):
		return false
	var property := "_GlobalMaskTexture%d" % ((index - 1) / 4)
	if number.call("_GlobalMaskTexturesEnable") == 0.0 or _texture_guid(m, property) == "":
		return {"property": "", "channel": 0}
	if number.call(property + "UV") != 0.0 or number.call(property + "Split") != 0.0 or _colour((m.get("colours", {}) as Dictionary).get(property + "Pan"), Color(0, 0, 0, 0)) != Color(0, 0, 0, 0):
		return false
	return {"property": property, "channel": (index - 1) % 4}


## Poiyomi's `maskBlend` of `mask` by a global mask's `value`: replace, subtract, multiply, divide, min, max, average or
## add, as `type` counts from 0.
static func mask_blend(mask: float, value: float, type: int) -> float:
	var blended: float = [value, mask - value, mask * value, mask / maxf(value, 0.0001), minf(mask, value), maxf(mask, value), (mask + value) * 0.5, mask + value][clampi(type, 0, 7)]
	return clampf(blended, 0.0, 1.0)


## How the material at `key` takes the light: "flat" for a shader lighting a surface by the light's colour whichever way
## it faces (Poiyomi's Flat lighting, capped at its Max Brightness where that is on; VRChat's Toon Lit, uncapped),
## "lit" for a surface shaded by the angle of its light.
func lighting(key: String) -> Dictionary:
	var m: Dictionary = materials[key]
	var floats: Dictionary = m.get("floats", {})
	if poiyomi(m) and str(floats.get("_LightingMode", "")).to_float() == 5.0:
		var flat := {"model": "flat"}
		if str(floats.get("_LightingCapEnabled", "0")).to_float() != 0.0:
			flat.cap = _saved(m, "_LightingCap", 1.0)
		return flat
	if m.get("shader", "") == "VRChat/Mobile/Toon Lit":
		return {"model": "flat"}
	return {"model": "lit"}


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
	return Yaml.guid((entry as Dictionary).get("m_Texture")) if entry is Dictionary else ""


## What each packed material lays over its albedo and adds to its light, and how it takes the light, for the renderer
## to read by atlas texel: the material a texel shows decides it, so a material swapped in for another draws its own.
## Empty where every material is lit by angle and has none; otherwise the "index" (a greyscale PNG, each texel one plus
## its material's entry in "materials", zero for none), each entry's cell ("rect", in atlas UV), its decals, matcaps and
## emission at rest and its "lighting", the atlas-sized "matcapMasks" (channel k matcap slot k's, its global mask
## blended in) and "emission" map, the "matcaps" textures their entries name by position, and the "decals",
## `decal_images`, each over its material's cell, which its decals name by "image".
func looks() -> Dictionary:
	var entries := []
	var index := Image.create_empty(atlas_side, atlas_side, false, Image.FORMAT_L8)
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
		var light := lighting(key)
		if decals.all(func(d: Dictionary) -> bool: return d.is_empty()) and matcaps.all(func(c: Dictionary) -> bool: return c.is_empty()) and glows.is_empty() and light.model == "lit":
			continue
		if entries.size() == 255:
			push_error("unity_avatar: over 255 materials with looks; the rest draw lit by angle without decals, matcaps or emission")
			break
		var padded := Rect2i((m.cell as Rect2i).position - Vector2i(PAD, PAD), (m.cell as Rect2i).size + 2 * Vector2i(PAD, PAD))
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
			var mask := _slot_image(m, MATCAPS[slot] + "Mask")
			var invert := str(m.floats.get(MATCAPS[slot] + "MaskInvert", "0")).to_float() != 0.0
			var global: Dictionary = global_mask(m, str(m.floats.get(MATCAPS[slot] + "MaskGlobalMask", "0")).to_int())
			if mask == null and not invert and global.is_empty():
				continue
			if matcap_masks == null:
				matcap_masks = Image.create_empty(atlas_side, atlas_side, false, Image.FORMAT_RGBA8)
				matcap_masks.fill(Color.WHITE)
			var channel := clampi(str(m.floats.get(MATCAPS[slot] + "MaskChannel", "0")).to_int(), 0, 3)
			var source := _over_cell(m, mask, MATCAPS[slot] + "Mask").get_data()
			var over := PackedByteArray() if global.is_empty() else _over_cell(m, _slot_image(m, global.property) if global.property != "" else null, global.property).get_data()
			var blend := str(m.floats.get(MATCAPS[slot] + "MaskGlobalMaskBlendType", "2")).to_int()
			var region := matcap_masks.get_region(padded)
			var data := region.get_data()
			for i in range(0, data.size(), 4):
				var own := 255 - source[i + channel] if invert else source[i + channel]
				data[i + slot] = own if over.is_empty() else roundi(255.0 * mask_blend(own / 255.0, over[i + global.channel] / 255.0, blend))
			region.set_data(padded.size.x, padded.size.y, false, Image.FORMAT_RGBA8, data)
			matcap_masks.blit_rect(region, Rect2i(Vector2i.ZERO, padded.size), padded.position)
		if not glows.is_empty():
			if glow == null:
				glow = Image.create_empty(atlas_side, atlas_side, false, Image.FORMAT_RGBA8)
				glow.fill(Color.BLACK)
			glow.blit_rect(_over_cell(m, _slot_image(m, "_EmissionMap"), "_EmissionMap"), Rect2i(Vector2i.ZERO, padded.size), padded.position)
		var cell := Rect2(m.cell)
		entries.append({"rect": [cell.position.x / atlas_side, cell.position.y / atlas_side, cell.end.x / atlas_side, cell.end.y / atlas_side], "decals": decals.map(func(d: Dictionary) -> Variant: return null if d.is_empty() else d), "matcaps": drawn_matcaps, "emission": null if glows.is_empty() else glows, "lighting": light})
	if entries.is_empty():
		return {}
	var png := func(img: Image) -> String: return _layer(img, RESAMPLE)
	var out := {"index": _layer(index, Image.INTERPOLATE_NEAREST), "materials": entries, "decals": decal_images.duplicate(), "matcaps": matcap_textures.values().map(png)}
	if matcap_masks != null:
		out.matcapMasks = png.call(matcap_masks)
	if glow != null:
		out.emission = png.call(glow)
	return out


## The layer as the PNG an avatar file carries, at most LAYER wide.
static func _layer(img: Image, resample: Image.Interpolation) -> String:
	if img.get_width() > LAYER:
		img = img.duplicate() as Image
		img.resize(LAYER, LAYER * img.get_height() / img.get_width(), resample)
	return Marshalls.raw_to_base64(img.save_png_to_buffer())


## The texture in the material's `property` slot, decoded afresh: looks read each once, and holding them all would
## outgrow an avatar's memory budget.
func _slot_image(m: Dictionary, property: String) -> Image:
	var guid := _texture_guid(m, property)
	return _decoded(guid) if guid != "" else null


## `source` (white where null) as it lies over the material's cell, padded like the atlas.
func _over_cell(m: Dictionary, source: Image, property: String) -> Image:
	return _over(m, source, property, (m.cell as Rect2i).size, PAD)


## `source` (white where null) as it lies over the material's own texture, `size` texels and `pad` more each side: the
## material's own texture fills it, so another texture slot of the same UV0 is read through both slots' tilings.
func _over(m: Dictionary, source: Image, property: String, size: Vector2i, pad: int) -> Image:
	var out := Image.create_empty(size.x + 2 * pad, size.y + 2 * pad, false, Image.FORMAT_RGBA8)
	if source == null:
		out.fill(Color.WHITE)
		return out
	var entry: Dictionary = (m.get("textures", {}) as Dictionary).get(property, {})
	var scale := _vector2(entry.get("m_Scale"), Vector2.ONE)
	var offset := _vector2(entry.get("m_Offset"), Vector2.ZERO)
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
