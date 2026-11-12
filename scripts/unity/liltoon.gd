extends RefCounted

## lilToon (1.3.1 through 2.4.1) as the importer reads a material it draws: the properties its shaders declare, since
## VCC installs lilToon and an avatar package never carries it, its render mode, and what of its look the atlas and the
## looks (Materials.looks) hold. Its Multi shader compiles a feature only under its keyword; the others compile every
## feature, each drawn as its toggle says. Lite's features follow other formulas, which nothing here reads.

const Materials = preload("res://../scripts/unity/materials.gd")

## The properties lilToon's shaders declare: the union of 1.3.1's and 2.4.1's, and Lite's.
const PROPERTIES := ["_AAStrength", "_AlphaBoostFA", "_AlphaMask", "_AlphaMaskMode", "_AlphaMaskScale", "_AlphaMaskValue", "_AlphaToMask", "_Anisotropy2MatCap", "_Anisotropy2MatCap2nd", "_Anisotropy2Reflection", "_Anisotropy2ndBitangentWidth", "_Anisotropy2ndShift", "_Anisotropy2ndShiftNoiseScale", "_Anisotropy2ndSpecularStrength", "_Anisotropy2ndTangentWidth", "_AnisotropyBitangentWidth", "_AnisotropyScale", "_AnisotropyScaleMask", "_AnisotropyShift", "_AnisotropyShiftNoiseMask", "_AnisotropyShiftNoiseScale", "_AnisotropySpecularStrength", "_AnisotropyTangentMap", "_AnisotropyTangentWidth", "_ApplyReflection", "_ApplySpecular", "_ApplySpecularFA", "_AsOverlay", "_AsUnlit", "_AudioLink2Emission", "_AudioLink2Emission2nd", "_AudioLink2Emission2ndGrad", "_AudioLink2EmissionGrad", "_AudioLink2Main2nd", "_AudioLink2Main3rd", "_AudioLink2Vertex", "_AudioLinkAsLocal", "_AudioLinkDefaultValue", "_AudioLinkLocalMap", "_AudioLinkLocalMapParams", "_AudioLinkMask", "_AudioLinkMask_ScrollRotate", "_AudioLinkMask_UVMode", "_AudioLinkStart", "_AudioLinkUVMode", "_AudioLinkUVParams", "_AudioLinkVertexStart", "_AudioLinkVertexStrength", "_AudioLinkVertexUVMode", "_AudioLinkVertexUVParams", "_BackfaceColor", "_BackfaceForceShadow", "_BacklightBackfaceMask", "_BacklightBlur", "_BacklightBorder", "_BacklightColor", "_BacklightColorTex", "_BacklightDirectivity", "_BacklightMainStrength", "_BacklightNormalStrength", "_BacklightReceiveShadow", "_BacklightViewStrength", "_BaseColor", "_BaseColorMap", "_BaseMap", "_BeforeExposureLimit", "_BlendOp", "_BlendOpAlpha", "_BlendOpAlphaFA", "_BlendOpFA", "_Bump2ndMap", "_Bump2ndMap_UVMode", "_Bump2ndScale", "_Bump2ndScaleMask", "_BumpMap", "_BumpScale", "_Color", "_Color2nd", "_Color3rd", "_ColorMask", "_Cull", "_Cutoff", "_DissolveColor", "_DissolveMask", "_DissolveNoiseMask", "_DissolveNoiseMask_ScrollRotate", "_DissolveNoiseStrength", "_DissolveParams", "_DissolvePos", "_DistanceFade", "_DistanceFadeColor", "_DistanceFadeMode", "_DistanceFadeRimColor", "_DistanceFadeRimFresnelPower", "_DitherMaxValue", "_DitherTex", "_DstBlend", "_DstBlendAlpha", "_DstBlendAlphaFA", "_DstBlendFA", "_DummyProperty", "_Emission2ndBlend", "_Emission2ndBlendMask", "_Emission2ndBlendMask_ScrollRotate", "_Emission2ndBlendMode", "_Emission2ndBlink", "_Emission2ndColor", "_Emission2ndFluorescence", "_Emission2ndGradSpeed", "_Emission2ndGradTex", "_Emission2ndMainStrength", "_Emission2ndMap", "_Emission2ndMap_ScrollRotate", "_Emission2ndMap_UVMode", "_Emission2ndParallaxDepth", "_Emission2ndUseGrad", "_EmissionBlend", "_EmissionBlendMask", "_EmissionBlendMask_ScrollRotate", "_EmissionBlendMode", "_EmissionBlink", "_EmissionColor", "_EmissionFluorescence", "_EmissionGradSpeed", "_EmissionGradTex", "_EmissionMainStrength", "_EmissionMap", "_EmissionMap_ScrollRotate", "_EmissionMap_UVMode", "_EmissionParallaxDepth", "_EmissionUseGrad", "_EnvRimBlur", "_EnvRimBorder", "_FlipNormal", "_GSAAStrength", "_GlitterAngleRandomize", "_GlitterApplyShape", "_GlitterApplyTransparency", "_GlitterAtras", "_GlitterBackfaceMask", "_GlitterColor", "_GlitterColorTex", "_GlitterColorTex_UVMode", "_GlitterEnableLighting", "_GlitterMainStrength", "_GlitterNormalStrength", "_GlitterParams1", "_GlitterParams2", "_GlitterPostContrast", "_GlitterScaleRandomize", "_GlitterSensitivity", "_GlitterShadowMask", "_GlitterShapeTex", "_GlitterUVMode", "_GlitterVRParallaxStrength", "_IDMask1", "_IDMask2", "_IDMask3", "_IDMask4", "_IDMask5", "_IDMask6", "_IDMask7", "_IDMask8", "_IDMaskCompile", "_IDMaskControlsDissolve", "_IDMaskFrom", "_IDMaskIndex1", "_IDMaskIndex2", "_IDMaskIndex3", "_IDMaskIndex4", "_IDMaskIndex5", "_IDMaskIndex6", "_IDMaskIndex7", "_IDMaskIndex8", "_IDMaskIsBitmap", "_IDMaskPrior1", "_IDMaskPrior2", "_IDMaskPrior3", "_IDMaskPrior4", "_IDMaskPrior5", "_IDMaskPrior6", "_IDMaskPrior7", "_IDMaskPrior8", "_IgnoreEncryption", "_Invisible", "_Keys", "_LightDirectionOverride", "_LightMaxLimit", "_LightMinLimit", "_Main2ndBlendMask", "_Main2ndDissolveColor", "_Main2ndDissolveMask", "_Main2ndDissolveNoiseMask", "_Main2ndDissolveNoiseMask_ScrollRotate", "_Main2ndDissolveNoiseStrength", "_Main2ndDissolveParams", "_Main2ndDissolvePos", "_Main2ndDistanceFade", "_Main2ndEnableLighting", "_Main2ndTex", "_Main2ndTexAlphaMode", "_Main2ndTexAngle", "_Main2ndTexBlendMode", "_Main2ndTexDecalAnimation", "_Main2ndTexDecalSubParam", "_Main2ndTexIsDecal", "_Main2ndTexIsLeftOnly", "_Main2ndTexIsMSDF", "_Main2ndTexIsRightOnly", "_Main2ndTexShouldCopy", "_Main2ndTexShouldFlipCopy", "_Main2ndTexShouldFlipMirror", "_Main2ndTex_Cull", "_Main2ndTex_ScrollRotate", "_Main2ndTex_UVMode", "_Main3rdBlendMask", "_Main3rdDissolveColor", "_Main3rdDissolveMask", "_Main3rdDissolveNoiseMask", "_Main3rdDissolveNoiseMask_ScrollRotate", "_Main3rdDissolveNoiseStrength", "_Main3rdDissolveParams", "_Main3rdDissolvePos", "_Main3rdDistanceFade", "_Main3rdEnableLighting", "_Main3rdTex", "_Main3rdTexAlphaMode", "_Main3rdTexAngle", "_Main3rdTexBlendMode", "_Main3rdTexDecalAnimation", "_Main3rdTexDecalSubParam", "_Main3rdTexIsDecal", "_Main3rdTexIsLeftOnly", "_Main3rdTexIsMSDF", "_Main3rdTexIsRightOnly", "_Main3rdTexShouldCopy", "_Main3rdTexShouldFlipCopy", "_Main3rdTexShouldFlipMirror", "_Main3rdTex_Cull", "_Main3rdTex_ScrollRotate", "_Main3rdTex_UVMode", "_MainColorAdjustMask", "_MainGradationStrength", "_MainGradationTex", "_MainTex", "_MainTexHSVG", "_MainTex_ScrollRotate", "_MatCap2ndApplyTransparency", "_MatCap2ndBackfaceMask", "_MatCap2ndBlend", "_MatCap2ndBlendMask", "_MatCap2ndBlendMode", "_MatCap2ndBlendUV1", "_MatCap2ndBumpMap", "_MatCap2ndBumpScale", "_MatCap2ndColor", "_MatCap2ndCustomNormal", "_MatCap2ndEnableLighting", "_MatCap2ndLod", "_MatCap2ndMainStrength", "_MatCap2ndNormalStrength", "_MatCap2ndPerspective", "_MatCap2ndShadowMask", "_MatCap2ndTex", "_MatCap2ndVRParallaxStrength", "_MatCap2ndZRotCancel", "_MatCapApplyTransparency", "_MatCapBackfaceMask", "_MatCapBlend", "_MatCapBlendMask", "_MatCapBlendMode", "_MatCapBlendUV1", "_MatCapBumpMap", "_MatCapBumpScale", "_MatCapColor", "_MatCapCustomNormal", "_MatCapEnableLighting", "_MatCapLod", "_MatCapMainStrength", "_MatCapNormalStrength", "_MatCapPerspective", "_MatCapShadowMask", "_MatCapTex", "_MatCapVRParallaxStrength", "_MatCapZRotCancel", "_Metallic", "_MetallicGlossMap", "_MonochromeLighting", "_OffsetFactor", "_OffsetUnits", "_OutlineAlphaToMask", "_OutlineBlendOp", "_OutlineBlendOpAlpha", "_OutlineBlendOpAlphaFA", "_OutlineBlendOpFA", "_OutlineColor", "_OutlineColorMask", "_OutlineCull", "_OutlineDeleteMesh", "_OutlineDisableInVR", "_OutlineDstBlend", "_OutlineDstBlendAlpha", "_OutlineDstBlendAlphaFA", "_OutlineDstBlendFA", "_OutlineEnableLighting", "_OutlineFixWidth", "_OutlineLitApplyTex", "_OutlineLitColor", "_OutlineLitOffset", "_OutlineLitScale", "_OutlineLitShadowReceive", "_OutlineOffsetFactor", "_OutlineOffsetUnits", "_OutlineSrcBlend", "_OutlineSrcBlendAlpha", "_OutlineSrcBlendAlphaFA", "_OutlineSrcBlendFA", "_OutlineStencilComp", "_OutlineStencilFail", "_OutlineStencilPass", "_OutlineStencilReadMask", "_OutlineStencilRef", "_OutlineStencilWriteMask", "_OutlineStencilZFail", "_OutlineTex", "_OutlineTexHSVG", "_OutlineTex_ScrollRotate", "_OutlineVectorScale", "_OutlineVectorTex", "_OutlineVectorUVMode", "_OutlineVertexR2Width", "_OutlineWidth", "_OutlineWidthMask", "_OutlineZBias", "_OutlineZClip", "_OutlineZTest", "_OutlineZWrite", "_Parallax", "_ParallaxMap", "_ParallaxOffset", "_PreAlphaToMask", "_PreBlendOp", "_PreBlendOpAlpha", "_PreBlendOpAlphaFA", "_PreBlendOpFA", "_PreColor", "_PreColorMask", "_PreCull", "_PreCutoff", "_PreDstBlend", "_PreDstBlendAlpha", "_PreDstBlendAlphaFA", "_PreDstBlendFA", "_PreOffsetFactor", "_PreOffsetUnits", "_PreOutType", "_PreSrcBlend", "_PreSrcBlendAlpha", "_PreSrcBlendAlphaFA", "_PreSrcBlendFA", "_PreStencilComp", "_PreStencilFail", "_PreStencilPass", "_PreStencilReadMask", "_PreStencilRef", "_PreStencilWriteMask", "_PreStencilZFail", "_PreZClip", "_PreZTest", "_PreZWrite", "_Ramp", "_Reflectance", "_ReflectionApplyTransparency", "_ReflectionBlendMode", "_ReflectionColor", "_ReflectionColorTex", "_ReflectionCubeColor", "_ReflectionCubeEnableLighting", "_ReflectionCubeOverride", "_ReflectionCubeTex", "_ReflectionNormalStrength", "_RimApplyTransparency", "_RimBackfaceMask", "_RimBlendMode", "_RimBlur", "_RimBorder", "_RimColor", "_RimColorTex", "_RimDirRange", "_RimDirStrength", "_RimEnableLighting", "_RimFresnelPower", "_RimIndirBlur", "_RimIndirBorder", "_RimIndirColor", "_RimIndirRange", "_RimMainStrength", "_RimNormalStrength", "_RimShadeBlur", "_RimShadeBorder", "_RimShadeColor", "_RimShadeFresnelPower", "_RimShadeMask", "_RimShadeNormalStrength", "_RimShadowMask", "_RimVRParallaxStrength", "_Shadow2ndBlur", "_Shadow2ndBorder", "_Shadow2ndColor", "_Shadow2ndColorTex", "_Shadow2ndNormalStrength", "_Shadow2ndReceive", "_Shadow3rdBlur", "_Shadow3rdBorder", "_Shadow3rdColor", "_Shadow3rdColorTex", "_Shadow3rdNormalStrength", "_Shadow3rdReceive", "_ShadowAOShift", "_ShadowAOShift2", "_ShadowBlur", "_ShadowBlurMask", "_ShadowBlurMaskLOD", "_ShadowBorder", "_ShadowBorderColor", "_ShadowBorderMask", "_ShadowBorderMaskLOD", "_ShadowBorderRange", "_ShadowColor", "_ShadowColorTex", "_ShadowColorType", "_ShadowEnvStrength", "_ShadowFlatBlur", "_ShadowFlatBorder", "_ShadowMainStrength", "_ShadowMaskType", "_ShadowNormalStrength", "_ShadowPostAO", "_ShadowReceive", "_ShadowStrength", "_ShadowStrengthMask", "_ShadowStrengthMaskLOD", "_ShiftBackfaceUV", "_Smoothness", "_SmoothnessTex", "_SpecularBlur", "_SpecularBorder", "_SpecularNormalStrength", "_SpecularToon", "_SrcBlend", "_SrcBlendAlpha", "_SrcBlendAlphaFA", "_SrcBlendFA", "_StencilComp", "_StencilFail", "_StencilPass", "_StencilReadMask", "_StencilRef", "_StencilWriteMask", "_StencilZFail", "_SubpassCutoff", "_TessEdge", "_TessFactorMax", "_TessShrink", "_TessStrength", "_TransparentMode", "_UDIMDiscardCompile", "_UDIMDiscardMode", "_UDIMDiscardRow0_0", "_UDIMDiscardRow0_1", "_UDIMDiscardRow0_2", "_UDIMDiscardRow0_3", "_UDIMDiscardRow1_0", "_UDIMDiscardRow1_1", "_UDIMDiscardRow1_2", "_UDIMDiscardRow1_3", "_UDIMDiscardRow2_0", "_UDIMDiscardRow2_1", "_UDIMDiscardRow2_2", "_UDIMDiscardRow2_3", "_UDIMDiscardRow3_0", "_UDIMDiscardRow3_1", "_UDIMDiscardRow3_2", "_UDIMDiscardRow3_3", "_UDIMDiscardUV", "_UseAnisotropy", "_UseAudioLink", "_UseBacklight", "_UseBump2ndMap", "_UseBumpMap", "_UseClippingCanceller", "_UseDither", "_UseEmission", "_UseEmission2nd", "_UseGlitter", "_UseMain2ndTex", "_UseMain3rdTex", "_UseMatCap", "_UseMatCap2nd", "_UseOutline", "_UsePOM", "_UseParallax", "_UseReflection", "_UseRim", "_UseRimShade", "_UseShadow", "_VertexLightStrength", "_ZClip", "_ZTest", "_ZWrite", "_e2ga0", "_e2ga1", "_e2ga2", "_e2ga3", "_e2ga4", "_e2ga5", "_e2ga6", "_e2ga7", "_e2gai", "_e2gc0", "_e2gc1", "_e2gc2", "_e2gc3", "_e2gc4", "_e2gc5", "_e2gc6", "_e2gc7", "_e2gci", "_ega0", "_ega1", "_ega2", "_ega3", "_ega4", "_ega5", "_ega6", "_ega7", "_egai", "_egc0", "_egc1", "_egc2", "_egc3", "_egc4", "_egc5", "_egc6", "_egc7", "_egci", "_lilDirectionalLightStrength", "_lilShadowCasterBias", "_lilToonVersion"]
const LITE_PROPERTIES := ["_AAStrength", "_AlphaBoostFA", "_AlphaToMask", "_AsUnlit", "_BackfaceForceShadow", "_BaseColor", "_BaseColorMap", "_BaseMap", "_BeforeExposureLimit", "_BlendOp", "_BlendOpAlpha", "_BlendOpAlphaFA", "_BlendOpFA", "_Color", "_ColorMask", "_Cull", "_Cutoff", "_DstBlend", "_DstBlendAlpha", "_DstBlendAlphaFA", "_DstBlendFA", "_EmissionBlink", "_EmissionColor", "_EmissionMap", "_EmissionMap_ScrollRotate", "_EmissionMap_UVMode", "_FlipNormal", "_Invisible", "_LightDirectionOverride", "_LightMaxLimit", "_LightMinLimit", "_MainTex", "_MainTex_ScrollRotate", "_MatCapBlendUV1", "_MatCapMul", "_MatCapPerspective", "_MatCapTex", "_MatCapVRParallaxStrength", "_MatCapZRotCancel", "_MonochromeLighting", "_OffsetFactor", "_OffsetUnits", "_OutlineAlphaToMask", "_OutlineBlendOp", "_OutlineBlendOpAlpha", "_OutlineBlendOpAlphaFA", "_OutlineBlendOpFA", "_OutlineColor", "_OutlineColorMask", "_OutlineCull", "_OutlineDeleteMesh", "_OutlineDstBlend", "_OutlineDstBlendAlpha", "_OutlineDstBlendAlphaFA", "_OutlineDstBlendFA", "_OutlineEnableLighting", "_OutlineFixWidth", "_OutlineOffsetFactor", "_OutlineOffsetUnits", "_OutlineSrcBlend", "_OutlineSrcBlendAlpha", "_OutlineSrcBlendAlphaFA", "_OutlineSrcBlendFA", "_OutlineStencilComp", "_OutlineStencilFail", "_OutlineStencilPass", "_OutlineStencilReadMask", "_OutlineStencilRef", "_OutlineStencilWriteMask", "_OutlineStencilZFail", "_OutlineTex", "_OutlineTex_ScrollRotate", "_OutlineVertexR2Width", "_OutlineWidth", "_OutlineWidthMask", "_OutlineZBias", "_OutlineZClip", "_OutlineZTest", "_OutlineZWrite", "_PreAlphaToMask", "_PreBlendOp", "_PreBlendOpAlpha", "_PreBlendOpAlphaFA", "_PreBlendOpFA", "_PreColor", "_PreColorMask", "_PreCull", "_PreCutoff", "_PreDstBlend", "_PreDstBlendAlpha", "_PreDstBlendAlphaFA", "_PreDstBlendFA", "_PreOffsetFactor", "_PreOffsetUnits", "_PreOutType", "_PreSrcBlend", "_PreSrcBlendAlpha", "_PreSrcBlendAlphaFA", "_PreSrcBlendFA", "_PreStencilComp", "_PreStencilFail", "_PreStencilPass", "_PreStencilReadMask", "_PreStencilRef", "_PreStencilWriteMask", "_PreStencilZFail", "_PreZClip", "_PreZTest", "_PreZWrite", "_RimBlur", "_RimBorder", "_RimColor", "_RimFresnelPower", "_RimShadowMask", "_Shadow2ndBlur", "_Shadow2ndBorder", "_Shadow2ndColorTex", "_ShadowBlur", "_ShadowBorder", "_ShadowBorderColor", "_ShadowBorderRange", "_ShadowColorTex", "_ShadowEnvStrength", "_ShiftBackfaceUV", "_SrcBlend", "_SrcBlendAlpha", "_SrcBlendAlphaFA", "_SrcBlendFA", "_StencilComp", "_StencilFail", "_StencilPass", "_StencilReadMask", "_StencilRef", "_StencilWriteMask", "_StencilZFail", "_SubpassCutoff", "_TriMask", "_UseEmission", "_UseMatCap", "_UseRim", "_UseShadow", "_VertexLightStrength", "_ZClip", "_ZTest", "_ZWrite", "_lilDirectionalLightStrength", "_lilShadowCasterBias", "_lilToonVersion"]
## The vector component a clip turns the main texture's hue by.
const HUE := "_MainTexHSVG.x"
## The keyword lilToon Multi compiles each feature under.
const KEYWORDS := {
	"colour adjustment": "EFFECT_HUE_VARIATION",
	"2nd main texture": "_COLORADDSUBDIFF_ON",
	"3rd main texture": "_COLORCOLOR_ON",
	"decal animation": "_SUNDISK_NONE",
	"layer dissolve": "GEOM_TYPE_FROND",
	"alpha mask": "_COLOROVERLAY_ON",
	"shadow": "_REQUIRE_UV2",
	"emission": "_EMISSION",
	"2nd emission": "GEOM_TYPE_BRANCH",
	"emission masks": "_SUNDISK_SIMPLE",
	"matcap": "_SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A",
	"2nd matcap": "_SPECULARHIGHLIGHTS_OFF",
	"matcap normal map": "GEOM_TYPE_MESH",
	"rim": "_METALLICGLOSSMAP",
	"rim direction": "GEOM_TYPE_LEAF",
	"backlight": "ANTI_FLICKER",
	"rim shade": "AUTO_KEY_VALUE",
	"glitter": "_SPECGLOSSMAP",
	"reflection": "_GLOSSYREFLECTIONS_OFF",
	"anisotropy": "SOURCE_GBUFFER",
	"parallax": "_PARALLAXMAP",
	"AudioLink": "_MAPPING_6_FRAMES_LAYOUT",
	"dither": "ETC1_EXTERNAL_ALPHA",
	"dissolve": "GEOM_TYPE_BRANCH_DETAIL",
}
## The features the looks carry nothing of, by the toggle that draws each.
const UNDRAWN := {"backlight": "_UseBacklight", "rim shade": "_UseRimShade", "glitter": "_UseGlitter", "reflection": "_UseReflection", "anisotropy": "_UseAnisotropy", "parallax": "_UseParallax", "AudioLink": "_UseAudioLink", "dither": "_UseDither"}
## Lite's features, by the toggle that draws each.
const LITE_FEATURES := {"shadow": "_UseShadow", "matcap": "_UseMatCap", "rim": "_UseRim", "emission": "_UseEmission"}
const NONE := Color(0, 0, 0, 0)


static func is_liltoon(m: Dictionary) -> bool:
	return str(m.get("shader", "")).containsn("liltoon")


## The properties the lilToon shader named `shader` declares, or none for another shader.
static func properties(shader: String) -> Array:
	if not shader.containsn("liltoon"):
		return []
	return LITE_PROPERTIES if _lite(shader) else PROPERTIES


static func _lite(shader: String) -> bool:
	return shader.contains("Lite") or shader.contains("lite")


static func _multi(m: Dictionary) -> bool:
	return str(m.shader).contains("Multi")


## Whether the material's shader compiles `feature`: Multi under its keyword, every other shader always.
static func compiled(m: Dictionary, feature: String) -> bool:
	return not _multi(m) or KEYWORDS[feature] in m.get("keywords", [])


## Whether the material draws `feature`, which its `toggle` turns on: never for Lite, whose features this does not read.
static func _on(m: Dictionary, toggle: String, feature: String) -> bool:
	return not _lite(m.shader) and Materials._float(m, toggle) != 0.0 and compiled(m, feature)


## The material's colour `name` as its shader reads it in a linear project: rgb in linear light, alpha as saved.
static func _colour(m: Dictionary, name: String, otherwise: Color) -> Color:
	var saved := Materials._colour((m.get("colours", {}) as Dictionary).get(name), otherwise)
	var linear := saved.srgb_to_linear()
	return Color(linear.r, linear.g, linear.b, saved.a)


## The material's vector `name`, as saved.
static func _vector(m: Dictionary, name: String, otherwise := NONE) -> Color:
	return Materials._colour((m.get("colours", {}) as Dictionary).get(name), otherwise)


## A texture slot's tiling and offset of UV0 where lilToon reads it through the main texture's UV: the main texture's,
## then the slot's own.
static func _through_main(m: Dictionary, property: String) -> Array:
	var entry: Dictionary = (m.get("textures", {}) as Dictionary).get(property, {})
	var scale := Materials._vector2(entry.get("m_Scale"), Vector2.ONE)
	return [(m.scale as Vector2) * scale, (m.offset as Vector2) * scale + Materials._vector2(entry.get("m_Offset"), Vector2.ZERO)]


## Multi's render mode, which its _TransparentMode keys rather than its shader: refraction and gem blend, fur draws as
## its own pass's mode.
static func read(m: Dictionary) -> void:
	if not _multi(m):
		return
	var mode := clampi(int(Materials._float(m, "_TransparentMode")), 0, 6)
	m.alpha = [Materials.Alpha.OPAQUE, Materials.Alpha.CUTOUT, Materials.Alpha.BLEND, Materials.Alpha.BLEND, Materials.Alpha.BLEND, Materials.Alpha.CUTOUT, Materials.Alpha.BLEND][mode]
	m.depth = m.alpha == Materials.Alpha.BLEND and Materials._number(m, "_ZWrite", 1.0) != 0.0
	m.cutoff = Materials._float(m, "_Cutoff", 0.5)


## lilToon's colour adjustment of the main texture in `img` at its cell's size, in linear light as a linear project
## draws it: raised to its gamma, its hue turned (but where `hue_held`), saturation and value scaled, as far as
## _MainColorAdjustMask's red says.
static func adjust(materials: Materials, m: Dictionary, img: Image, hue_held: bool) -> void:
	if not compiled(m, "colour adjustment"):
		return
	var hsvg := _vector(m, "_MainTexHSVG", Color(0, 1, 1, 1))
	if hue_held:
		hsvg.r = 0.0
	if hsvg == Color(0, 1, 1, 1):
		return
	var cover := materials._tiled(m, materials._slot_image(m, "_MainColorAdjustMask"), m.scale, m.offset, img.get_size(), 0).get_data()
	var data := img.get_data()
	for i in range(0, data.size(), 4):
		var by := cover[i] / 255.0
		if by <= 0.0:
			continue
		var c := Color(Materials._LINEAR[data[i]], Materials._LINEAR[data[i + 1]], Materials._LINEAR[data[i + 2]])
		var raised := Color(pow(c.r, hsvg.a), pow(c.g, hsvg.a), pow(c.b, hsvg.a))
		var turned := Color.from_hsv(fposmod(raised.h + hsvg.r, 1.0), clampf(raised.s * hsvg.g, 0.0, 1.0), clampf(raised.v * hsvg.b, 0.0, 1.0))
		for k in 3:
			data[i + k] = _encoded(lerpf(c[k], turned[k], by))
	img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)


## The sRGB byte of linear light `v`.
static func _encoded(v: float) -> int:
	return Materials._ENCODED[clampi(roundi(v * 4095.0), 0, 4095)]


## The 2nd or 3rd main texture (`n`) as the atlas lays it: {"colour", "mode", "angle", "decal", "copy", "flip"}, what of
## it the atlas cannot hold, or null where it is off. The atlas holds one drawn by UV0 into the albedo before light,
## still, on both sides and both halves of the model, its own alpha not written into the albedo's.
static func layer(m: Dictionary, n: String) -> Variant:
	var feature := n + " main texture"
	if not _on(m, "_UseMain%sTex" % n, feature):
		return null
	var p := "_Main%sTex" % n
	var uv := int(Materials._float(m, p + "_UVMode"))
	if uv != 0:
		return "matcap UV" if uv == 4 else "UV%d" % uv
	if Materials._float(m, "_Main%sEnableLighting" % n, 1.0) != 1.0:
		return "drawn unlit"
	var spin := _vector(m, p + "_ScrollRotate")
	if spin.r != 0.0 or spin.g != 0.0 or spin.a != 0.0:
		return "scrolling"
	if Materials._float(m, p + "_Cull") != 0.0:
		return "one side"
	if m.alpha != Materials.Alpha.OPAQUE and Materials._float(m, p + "AlphaMode") != 0.0:
		return "alpha mode"
	if ["IsLeftOnly", "IsRightOnly", "ShouldFlipMirror"].any(func(flag: String) -> bool: return Materials._float(m, p + flag) != 0.0):
		return "one half"
	if Materials._float(m, p + "IsMSDF") != 0.0:
		return "MSDF"
	if compiled(m, "decal animation") and (_vector(m, p + "DecalAnimation", Color(1, 1, 1, 30)) * Color(1, 1, 1, 0) != Color(1, 1, 1, 0) or _vector(m, p + "DecalSubParam", Color(1, 1, 0, 1)) * Color(1, 1, 1, 0) != Color(1, 1, 0, 0)):
		return "decal animation"
	if compiled(m, "layer dissolve") and _vector(m, "_Main%sDissolveParams" % n).r != 0.0:
		return "dissolve"
	if _vector(m, "_Main%sDistanceFade" % n).b != 0.0:
		return "distance fade"
	var mode := int(Materials._float(m, p + "BlendMode"))
	if mode < 0 or mode > 3:
		return "blend mode %d" % mode
	return {"colour": _colour(m, "_Color" + n, Color.WHITE), "mode": mode, "angle": Materials._float(m, p + "Angle"), "decal": Materials._float(m, p + "IsDecal") != 0.0, "copy": Materials._float(m, p + "ShouldCopy") != 0.0, "flip": Materials._float(m, p + "ShouldFlipCopy") != 0.0}


## The 2nd and 3rd main textures blended into `img`, the tinted albedo at its cell's size, in linear light by their
## blend modes (normal, add, screen, multiply), as lilToon blends them before light.
static func lay(materials: Materials, m: Dictionary, img: Image) -> void:
	for n: String in ["2nd", "3rd"]:
		var l: Variant = layer(m, n)
		if not l is Dictionary:
			continue
		var over := _layer_image(materials, m, n, l, img.get_size(), 0).get_data()
		var data := img.get_data()
		for i in range(0, data.size(), 4):
			var a := over[i + 3] / 255.0
			if a <= 0.0:
				continue
			for c in 3:
				var d: float = Materials._LINEAR[data[i + c]]
				var s: float = Materials._LINEAR[over[i + c]]
				data[i + c] = _encoded(lerpf(d, [s, d + s, maxf(d + s - d * s, d), d * s][l.mode], a))
		img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)


## Layer `l`, the main texture `n`, over the material's texture at `size` texels and `pad` more each side: its colour
## and texture's colour, sRGB-encoded, and in alpha how far it covers, its colour's and texture's alpha inside a decal's
## bounds times its blend mask's red.
static func _layer_image(materials: Materials, m: Dictionary, n: String, l: Dictionary, size: Vector2i, pad: int) -> Image:
	var p := "_Main%sTex" % n
	var source := materials._slot_image(m, p)
	var entry: Dictionary = (m.get("textures", {}) as Dictionary).get(p, {})
	var scale := Materials._vector2(entry.get("m_Scale"), Vector2.ONE)
	var offset := Materials._vector2(entry.get("m_Offset"), Vector2.ZERO)
	var straight: bool = l.angle == 0.0 and not l.copy and not l.flip
	var out := materials._tiled(m, source if straight else null, scale, offset, size, pad)
	var data := out.get_data()
	var mask := materials._tiled(m, materials._slot_image(m, "_Main%sBlendMask" % n), m.scale, m.offset, size, pad).get_data()
	var colour: Color = l.colour
	for y in size.y + 2 * pad:
		for x in size.x + 2 * pad:
			var uv := Vector2((clampi(x - pad, 0, size.x - 1) + 0.5) / size.x, 1.0 - (clampi(y - pad, 0, size.y - 1) + 0.5) / size.y)
			var at := _decal_uv((uv - (m.offset as Vector2)) / (m.scale as Vector2), l, scale, offset)
			var i := 4 * (y * out.get_width() + x)
			var s := Color8(data[i], data[i + 1], data[i + 2], data[i + 3]) if straight or source == null else Materials._sample(source, at)
			var inside: bool = not l.decal or (at.x >= 0.0 and at.x <= 1.0 and at.y >= 0.0 and at.y <= 1.0)
			var linear := s.srgb_to_linear()
			data[i] = _encoded(linear.r * colour.r)
			data[i + 1] = _encoded(linear.g * colour.g)
			data[i + 2] = _encoded(linear.b * colour.b)
			data[i + 3] = roundi(255.0 * s.a * colour.a * mask[i] / 255.0) if inside else 0
	out.set_data(out.get_width(), out.get_height(), false, Image.FORMAT_RGBA8, data)
	return out


## lilToon's decal UV of `uv` (UV0) for layer `l` read through `scale` and `offset`: copied across the middle, flipped
## on the copy's left, turned about the texture's centre by its angle.
static func _decal_uv(uv: Vector2, l: Dictionary, scale: Vector2, offset: Vector2) -> Vector2:
	var o := uv
	if l.copy:
		o.x = absf(o.x - 0.5) + 0.5
	o = o * scale + offset
	if l.flip and uv.x < 0.5:
		o.x = 1.0 - o.x
	return ((o - offset) / scale - Vector2(0.5, 0.5)).rotated(l.angle) * scale + Vector2(0.5, 0.5) * scale + offset


## The alpha mask's mode (replace, multiply, add, subtract as 1 to 4), what of it the atlas cannot hold, or null where
## it draws none: off, or the material opaque.
static func alpha_mask(m: Dictionary) -> Variant:
	if m.alpha == Materials.Alpha.OPAQUE or not compiled(m, "alpha mask"):
		return null
	var mode := int(Materials._float(m, "_AlphaMaskMode"))
	if mode == 0:
		return null
	return mode if mode <= 4 else "mode %d" % mode


## The alpha mask as Materials._tint overrides the albedo's alpha by it, before it cuts or blends: [mode, each
## texel's mask] at `size`, the cell's, its red scaled and offset.
static func alpha_overrides(materials: Materials, m: Dictionary, size: Vector2i) -> Array:
	var mode: Variant = alpha_mask(m)
	if not mode is int:
		return []
	var tiling := _through_main(m, "_AlphaMask")
	var cover := materials._tiled(m, materials._slot_image(m, "_AlphaMask"), tiling[0], tiling[1], size, 0).get_data()
	var scale := Materials._float(m, "_AlphaMaskScale", 1.0)
	var value := Materials._float(m, "_AlphaMaskValue")
	var alphas := PackedFloat32Array()
	alphas.resize(size.x * size.y)
	for i in alphas.size():
		alphas[i] = clampf(cover[4 * i] / 255.0 * scale + value, 0.0, 1.0)
	return [[mode, alphas]]


## The toon shadow as the looks carry it (ExpressionDefinition.looks_valid), what of it they cannot hold, or null where
## it is off: one shaded by the light's angle against a border, its strength masked, a second shade, an
## edge colour; not one masked flat or by a signed distance field, coloured by a lookup table, or its border or blur
## masked.
static func _shadow(m: Dictionary) -> Variant:
	if not _on(m, "_UseShadow", "shadow"):
		return null
	var masked := int(Materials._float(m, "_ShadowMaskType"))
	if masked != 0:
		return "flat mask" if masked == 1 else "signed distance field"
	if Materials._float(m, "_ShadowColorType") == 1.0:
		return "lookup table colours"
	var shift := _vector(m, "_ShadowAOShift", Color(1, 0, 1, 0))
	if Materials._texture_guid(m, "_ShadowBorderMask") != "" or shift.r + shift.g < 1.0:
		return "border mask"
	if Materials._texture_guid(m, "_ShadowBlurMask") != "":
		return "blur mask"
	var second := _colour(m, "_Shadow2ndColor", Color(0.68, 0.66, 0.79, 1))
	var edge := _colour(m, "_ShadowBorderColor", Color(1, 0.1, 0, 1))
	return {
		"border": Materials._float(m, "_ShadowBorder", 0.5),
		"blur": Materials._float(m, "_ShadowBlur", 0.1),
		"strength": Materials._float(m, "_ShadowStrength", 1.0),
		"second": null if second.a == 0.0 else {"border": Materials._float(m, "_Shadow2ndBorder", 0.15), "blur": Materials._float(m, "_Shadow2ndBlur", 0.1), "weight": second.a},
		"edge": null if edge.r + edge.g + edge.b == 0.0 else {"color": [edge.r, edge.g, edge.b], "range": Materials._float(m, "_ShadowBorderRange", 0.08)},
	}


## How the material takes the light: lilToon lights flat, capped at its _LightMaxLimit, its toon shadow (`_shadow`) or
## null.
static func lighting(m: Dictionary) -> Dictionary:
	var shadow: Variant = _shadow(m)
	return {"model": "flat", "cap": Materials._float(m, "_LightMaxLimit", 1.0), "shadow": shadow if shadow is Dictionary else null}


## The material's first (or `second`) shade colour over its padded cell, from `albedo`, its padded atlas region:
## the albedo laid under the shadow colour texture by its alpha, tinted by the shadow colour and by the albedo as far as
## _ShadowMainStrength says, sRGB-encoded, with _ShadowStrengthMask's red in the first's alpha and the second's whole.
## Neither is held below the albedo here: lilToon caps the shade after mixing the second into the first, as the renderer does.
static func shade(materials: Materials, m: Dictionary, albedo: Image, second: bool) -> Image:
	var n := "2nd" if second else ""
	var size: Vector2i = (m.cell as Rect2i).size
	var texture := materials._slot_image(m, "_Shadow%sColorTex" % n)
	var laid := PackedByteArray() if texture == null else materials._tiled(m, texture, m.scale, m.offset, size, Materials.PAD).get_data()
	var mask := materials._slot_image(m, "_ShadowStrengthMask")
	var strength := PackedByteArray() if second or mask == null else materials._tiled(m, mask, m.scale, m.offset, size, Materials.PAD).get_data()
	var colour := _colour(m, "_Shadow%sColor" % n, Color(0.68, 0.66, 0.79, 1) if second else Color(0.82, 0.76, 0.85, 1))
	var main := Materials._float(m, "_ShadowMainStrength")
	var data := albedo.get_data()
	for i in range(0, data.size(), 4):
		for c in 3:
			var a: float = Materials._LINEAR[data[i + c]]
			var x: float = (a if laid.is_empty() else lerpf(a, Materials._LINEAR[laid[i + c]], laid[i + 3] / 255.0)) * colour[c]
			x = lerpf(x, x * a, main)
			data[i + c] = _encoded(x)
		data[i + 3] = 255 if strength.is_empty() else strength[i]
	return Image.create_from_data(albedo.get_width(), albedo.get_height(), false, Image.FORMAT_RGBA8, data)


## The rim light as the looks carry it, what of it they cannot hold, or null where it is off: a fresnel rim added after
## light, on back faces too ("backface") only where _RimBackfaceMask is 0, as lilToon hides it there at any mask above,
## tinted by its colour texture in the looks' "rimTint" layer (`rim_tint`); not one shaped by the light's direction or
## blended other than by adding.
static func _rim(m: Dictionary) -> Variant:
	if not _on(m, "_UseRim", "rim"):
		return null
	if compiled(m, "rim direction") and Materials._float(m, "_RimDirStrength") != 0.0:
		return "light direction"
	var mode := int(Materials._float(m, "_RimBlendMode", 1.0))
	if mode != 1:
		return "blend mode %d" % mode
	var c := _colour(m, "_RimColor", Color(0.66, 0.5, 0.48, 1))
	return {"color": [c.r, c.g, c.b], "strength": c.a, "main": Materials._float(m, "_RimMainStrength"), "border": Materials._float(m, "_RimBorder", 0.5), "blur": Materials._float(m, "_RimBlur", 0.65), "power": Materials._float(m, "_RimFresnelPower", 3.5), "lit": Materials._float(m, "_RimEnableLighting", 1.0), "shadowMask": Materials._float(m, "_RimShadowMask", 0.5), "backface": Materials._float(m, "_RimBackfaceMask", 1.0) <= 0.0}


static func rim(m: Dictionary) -> Dictionary:
	var drawn: Variant = _rim(m)
	return drawn if drawn is Dictionary else {}


## The rim's colour texture over the material's padded cell, sRGB-encoded, its colour times its alpha in linear light
## (the rim adds both as factors), read through the main texture's tiling and then its own, as lilToon samples it at the
## main UV; null where the rim draws none.
static func rim_tint(materials: Materials, m: Dictionary) -> Image:
	var source := materials._slot_image(m, "_RimColorTex") if _rim(m) is Dictionary else null
	if source == null:
		return null
	var srgb := materials._srgb(Materials._texture_guid(m, "_RimColorTex"))
	var tiling := _through_main(m, "_RimColorTex")
	var tint := materials._tiled(m, source, tiling[0], tiling[1], (m.cell as Rect2i).size, Materials.PAD)
	var data := tint.get_data()
	for i in range(0, data.size(), 4):
		var a := data[i + 3] / 255.0
		for c in 3:
			data[i + c] = _encoded((Materials._LINEAR[data[i + c]] if srgb else data[i + c] / 255.0) * a)
		data[i + 3] = 255
	tint.set_data(tint.get_width(), tint.get_height(), false, Image.FORMAT_RGBA8, data)
	return tint


## Matcap `slot` (0 the first, 1 the second) as {"scale", "mode"}, what of it the looks cannot hold, or null where it is
## off: one mapped by the surface's own normal, its texture tiled alike both ways and not offset.
static func _matcap(m: Dictionary, slot: int) -> Variant:
	if slot > 1:
		return null
	var p: String = "_MatCap" + ["", "2nd"][slot]
	if not _on(m, "_UseMatCap" + ["", "2nd"][slot], ["matcap", "2nd matcap"][slot]):
		return null
	if compiled(m, "matcap normal map") and Materials._float(m, p + "CustomNormal") != 0.0:
		return "own normal map"
	var uv1 := _vector(m, p + "BlendUV1")
	if uv1.r != 0.0 or uv1.g != 0.0:
		return "UV1 blend"
	var entry: Dictionary = (m.get("textures", {}) as Dictionary).get(p + "Tex", {})
	var scale := Materials._vector2(entry.get("m_Scale"), Vector2.ONE)
	if not is_equal_approx(scale.x, scale.y) or Materials._vector2(entry.get("m_Offset"), Vector2.ZERO) != Vector2.ZERO:
		return "offset tiling"
	var mode := int(Materials._float(m, p + "BlendMode", 1.0))
	if mode < 0 or mode > 3:
		return "blend mode %d" % mode
	return {"scale": scale.x, "mode": mode}


## Matcap `slot` as Materials.matcap gives Poiyomi's: its blend mode (normal, add, screen, multiply) as the strength of
## the like Poiyomi blend, an added one's lit share added and the rest glowing, masked by the shadow only where one is
## drawn (lilToon's shadow mix is one without its shadow); {} where `_matcap` draws none.
static func matcap(m: Dictionary, slot: int) -> Dictionary:
	var drawn: Variant = _matcap(m, slot)
	if not drawn is Dictionary:
		return {}
	var p: String = "_MatCap" + ["", "2nd"][slot]
	var c := _colour(m, p + "Color", Color.WHITE)
	var lit := Materials._float(m, p + "EnableLighting", 1.0)
	var mode: int = drawn.mode
	return {
		"texture": Materials._texture_guid(m, p + "Tex"),
		"mode": "normal",
		"border": 0.5 * drawn.scale,
		"color": [c.r, c.g, c.b, c.a],
		"intensity": Materials._float(m, p + "Blend", 1.0),
		"baseMix": Materials._float(m, p + "MainStrength"),
		"replace": float(mode == 0),
		"multiply": float(mode == 3),
		"add": lit if mode == 1 else 0.0,
		"screen": float(mode == 2),
		"mixed": 0.0,
		"lightAdd": 0.0,
		"emission": 1.0 - lit if mode == 1 else 0.0,
		"lightMask": Materials._float(m, p + "ShadowMask") if _shadow(m) is Dictionary else 0.0,
		"hue": null,
		"circle": null,
		"theme": null,
	}


## Matcap `slot`'s blend mask's red over the material's padded cell, one byte a texel, or empty where none masks it.
static func matcap_cover(materials: Materials, m: Dictionary, slot: int) -> PackedByteArray:
	var p := "_MatCap%sBlendMask" % ["", "2nd"][slot]
	var source := materials._slot_image(m, p)
	if source == null:
		return PackedByteArray()
	var tiling := _through_main(m, p)
	var data := materials._tiled(m, source, tiling[0], tiling[1], (m.cell as Rect2i).size, Materials.PAD).get_data()
	var out := PackedByteArray()
	out.resize(data.size() / 4)
	for i in out.size():
		out[i] = data[4 * i]
	return out


## Emission `n` ("" the first, "2nd" the second) as {"colour", "blend"}, what of it the looks cannot hold, or null where
## it is off: one added after light, its map read through UV0, still and steady.
static func _emission(m: Dictionary, n: String) -> Variant:
	var p := "_Emission" + n
	if not _on(m, "_UseEmission" + n, "emission" if n == "" else "2nd emission"):
		return null
	var uv := int(Materials._float(m, p + "Map_UVMode"))
	if uv != 0:
		return "rim UV" if uv == 4 else "UV%d" % uv
	var spin := _vector(m, p + "Map_ScrollRotate")
	if spin.r != 0.0 or spin.g != 0.0 or spin.a != 0.0:
		return "scrolling"
	if spin.b != 0.0:
		return "rotated"
	if compiled(m, "emission masks") and _vector(m, p + "BlendMask_ScrollRotate") != NONE:
		return "scrolling mask"
	if _vector(m, p + "Blink", Color(0, 0, PI, 0)).r != 0.0:
		return "blinking"
	if Materials._float(m, p + "UseGrad") != 0.0:
		return "gradient"
	if Materials._float(m, p + "ParallaxDepth") != 0.0:
		return "parallax"
	if Materials._float(m, p + "Fluorescence") != 0.0:
		return "fluorescence"
	var mode := int(Materials._float(m, p + "BlendMode", 1.0))
	if mode != 1:
		return "blend mode %d" % mode
	return {"colour": _colour(m, p + "Color", Color.WHITE), "blend": Materials._float(m, p + "Blend", 1.0)}


## The emissions drawn, as [n, `_emission`'s reading].
static func _emissions(m: Dictionary) -> Array:
	return ["", "2nd"].map(func(n: String) -> Array: return [n, _emission(m, n)]).filter(func(e: Array) -> bool: return e[1] is Dictionary)


## The emission entry Materials.emission gives: one emission's colour (its alpha in it) and blend as the strength, which
## an animated blend drives; two baked together into the map, the brighter one's peak the strength. {} where none glows.
static func emission(m: Dictionary) -> Dictionary:
	var drawn := _emissions(m)
	var peak := 0.0
	for e: Array in drawn:
		var c: Color = e[1].colour
		peak = maxf(peak, maxf(c.r, maxf(c.g, c.b)) * c.a * e[1].blend)
	var single := drawn.size() == 1
	var colour: Color = drawn[0][1].colour if single else Color.WHITE
	if drawn.is_empty() or (peak == 0.0 if not single else maxf(colour.r, maxf(colour.g, colour.b)) * colour.a == 0.0):
		return {}
	return {"color": [colour.r * colour.a, colour.g * colour.a, colour.b * colour.a] if single else [1.0, 1.0, 1.0], "strength": drawn[0][1].blend if single else peak, "hue": 0.0, "shiftsHue": false, "replace": 0.0}


## The blend property of the one emission the material's entry carries, which a clip moving it drives, or "".
static func blended_by(m: Dictionary) -> String:
	var drawn := _emissions(m)
	return "_Emission%sBlend" % drawn[0][0] if drawn.size() == 1 else ""


## The emission map over the material's padded cell, sRGB-encoded, from `albedo`, its padded atlas region: each
## emission's map times its blend mask (both by their alphas) and by the albedo as far as its main strength says; two
## each by its colour, alpha and blend over the entry's strength.
static func glow(materials: Materials, m: Dictionary, albedo: Image) -> Image:
	var drawn := _emissions(m)
	var strength: float = emission(m).get("strength", 1.0)
	var base := albedo.get_data()
	var sum := PackedFloat32Array()
	sum.resize(base.size())
	for e: Array in drawn:
		var p: String = "_Emission" + e[0]
		var c: Color = e[1].colour
		var by: Color = Color(1, 1, 1) if drawn.size() == 1 else Color(c.r, c.g, c.b) * (c.a * e[1].blend / strength)
		var map := materials._over_cell(m, materials._slot_image(m, p + "Map"), p + "Map").get_data()
		var mask := materials._over_cell(m, materials._slot_image(m, p + "BlendMask") if compiled(m, "emission masks") else null, p + "BlendMask").get_data()
		var main := Materials._float(m, p + "MainStrength")
		for i in range(0, base.size(), 4):
			var cover := map[i + 3] * mask[i + 3] / 65025.0
			for k in 3:
				sum[i + k] += Materials._LINEAR[map[i + k]] * mask[i + k] / 255.0 * cover * lerpf(1.0, Materials._LINEAR[base[i + k]], main) * by[k]
	var data := PackedByteArray()
	data.resize(base.size())
	for i in range(0, base.size(), 4):
		for k in 3:
			data[i + k] = _encoded(sum[i + k])
		data[i + 3] = 255
	return Image.create_from_data(albedo.get_width(), albedo.get_height(), false, Image.FORMAT_RGBA8, data)


## The material's colour adjustment mask over its padded cell, as hue_mask carries it: _MainColorAdjustMask's red,
## spared where a 2nd or 3rd main texture laid over the adjusted texture covers it normally; null where it covers all.
static func hue_mask(materials: Materials, m: Dictionary) -> Image:
	var source := materials._slot_image(m, "_MainColorAdjustMask")
	var over := ["2nd", "3rd"].filter(func(n: String) -> bool: return layer(m, n) is Dictionary and layer(m, n).mode == 0)
	if source == null and over.is_empty():
		return null
	var size: Vector2i = (m.cell as Rect2i).size
	var mask := materials._tiled(m, source, m.scale, m.offset, size, Materials.PAD)
	var data := mask.get_data()
	for n: String in over:
		var cover := _layer_image(materials, m, n, layer(m, n), size, Materials.PAD).get_data()
		for i in range(0, data.size(), 4):
			data[i] = roundi(data[i] * (255 - cover[i + 3]) / 255.0)
	for i in range(0, data.size(), 4):
		data[i + 1] = data[i]
		data[i + 2] = data[i]
		data[i + 3] = 255
	mask.set_data(mask.get_width(), mask.get_height(), false, Image.FORMAT_RGBA8, data)
	return mask


## What the material draws that the atlas and looks hold nothing of, each as "feature (why)" or the feature alone.
static func losses(m: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if _lite(m.shader):
		for feature: String in LITE_FEATURES:
			if Materials._float(m, LITE_FEATURES[feature]) != 0.0:
				out.append("%s (lilToon Lite)" % feature)
		return out
	var readings := {"2nd main texture": layer(m, "2nd"), "3rd main texture": layer(m, "3rd"), "alpha mask": alpha_mask(m), "shadow": _shadow(m), "matcap": _matcap(m, 0), "2nd matcap": _matcap(m, 1), "rim": _rim(m), "emission": _emission(m, ""), "2nd emission": _emission(m, "2nd")}
	for feature: String in readings:
		if readings[feature] is String:
			out.append("%s (%s)" % [feature, readings[feature]])
	if readings.shadow is Dictionary:
		if _colour(m, "_Shadow3rdColor", NONE).a != 0.0:
			out.append("shadow (3rd shade)")
		if ["_ShadowReceive", "_Shadow2ndReceive", "_Shadow3rdReceive"].any(func(name: String) -> bool: return Materials._float(m, name) != 0.0):
			out.append("shadow (received shadows)")
		if Materials._float(m, "_ShadowEnvStrength") != 0.0:
			out.append("shadow (environment light)")
		if Materials._float(m, "_BackfaceForceShadow") != 0.0:
			out.append("shadow (back faces shaded)")
	if compiled(m, "colour adjustment") and Materials._float(m, "_MainGradationStrength") != 0.0:
		out.append("colour adjustment (gradation)")
	var spin := _vector(m, "_MainTex_ScrollRotate")
	if spin.r != 0.0 or spin.g != 0.0 or spin.a != 0.0:
		out.append("main texture (scrolling)")
	elif spin.b != 0.0:
		out.append("main texture (rotated)")
	for feature: String in UNDRAWN:
		if _on(m, UNDRAWN[feature], feature):
			out.append(feature)
	if compiled(m, "dissolve") and _vector(m, "_DissolveParams").r != 0.0:
		out.append("dissolve")
	if Materials._float(m, "_AsUnlit") != 0.0:
		out.append("unlit share")
	if _multi(m) and (Materials._number(m, "_DstBlend", 0.0) != 0.0) != (m.alpha == Materials.Alpha.BLEND):
		out.append("render mode (_TransparentMode %d, but _DstBlend %d)" % [int(Materials._float(m, "_TransparentMode")), int(Materials._number(m, "_DstBlend", 0.0))])
	return out
