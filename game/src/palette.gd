class_name Palette
extends RefCounted

## The glade's colours: the garden's season, and the swatches each build is painted in (a wall's `paint`, one
## swatch per material). Laid parts keep their own colour variation around the material's first swatch; a
## build's paint scales its parts onto the chosen swatches as they are packed (Wall), so recolouring one build
## lays no stones. Pure data apart from `apply`, so tests run headless.

## Each material's value is also its code in the parts' custom data, which tells a repaint what to scale; the
## meadow's 0 doubles as "kept as laid".
## GLOW is the colour a room's windows shine at night, LANTERN its lanterns' colour and brightness.
enum Element { MEADOW = 0, STONE = 1, ROOF = 2, WOOD = 3, PLASTER = 4, TIMBER = 5, THATCH = 6, GLOW = 7, LANTERN = 8 }

## The meadow's swatches are the seasons, each a preset for the meadow (grass and ground) and foliage
## (trees, bushes, ivy): the colour plants turn toward (rgb) and how far (a); and the share of flowers in bloom.
const SEASONS := [
	{"name": "spring", "swatch": Color(0.50, 0.74, 0.30), "meadow": Color(0.46, 0.72, 0.22, 0.35), "foliage": Color(0.42, 0.66, 0.2, 0.4), "bloom": 1.0, "fireflies": true},
	{"name": "summer", "swatch": Color(0.40, 0.60, 0.18), "meadow": Color(0, 0, 0, 0), "foliage": Color(0, 0, 0, 0), "bloom": 1.0, "fireflies": true},
	{"name": "late summer", "swatch": Color(0.70, 0.66, 0.26), "meadow": Color(0.66, 0.6, 0.24, 0.5), "foliage": Color(0.42, 0.44, 0.16, 0.3), "bloom": 0.55, "fireflies": true},
	{"name": "autumn", "swatch": Color(0.80, 0.42, 0.14), "meadow": Color(0.6, 0.48, 0.2, 0.6), "foliage": Color(0.82, 0.36, 0.1, 0.85), "bloom": 0.15, "fireflies": false},
	{"name": "winter", "swatch": Color(0.86, 0.89, 0.93), "meadow": Color(0.84, 0.87, 0.92, 0.85), "foliage": Color(0.86, 0.88, 0.92, 0.7), "bloom": 0.0, "fireflies": false},
]
const SUMMER := 1

## The colours a window or a lantern glows in.
const GLOWS: Array[Color] = [Color(1.0, 0.62, 0.26), Color(1.0, 0.84, 0.56), Color(1.0, 0.42, 0.4), Color(0.95, 0.28, 0.14), Color(0.56, 0.92, 0.42), Color(0.36, 0.86, 0.8), Color(0.44, 0.6, 1.0), Color(0.78, 0.5, 1.0)]

## Each material's swatches; the first is the colour its parts are laid in. A lantern's are each glow colour lit, bright
## and dim in turn (Lamps.STRENGTHS), as its flame burns.
const SWATCHES := {
	Element.STONE: [WallLayout.STONE, Color(0.84, 0.81, 0.74), Color(0.78, 0.64, 0.42), Color(0.70, 0.46, 0.37), Color(0.48, 0.50, 0.55), Color(0.40, 0.38, 0.36), Color(0.56, 0.59, 0.48)],
	Element.ROOF: [RoofLayout.CLAY, Color(0.33, 0.38, 0.46), Color(0.38, 0.48, 0.30), Color(0.66, 0.22, 0.19), Color(0.78, 0.58, 0.30), Color(0.24, 0.24, 0.26), Color(0.24, 0.47, 0.50), Color(0.45, 0.28, 0.38)],
	Element.WOOD: [WallLayout.WOOD, Color(0.55, 0.53, 0.48), Color(0.44, 0.55, 0.44), Color(0.27, 0.40, 0.56), Color(0.56, 0.20, 0.16), Color(0.2, 0.2, 0.22), Color(0.86, 0.82, 0.70)],
	Element.TIMBER: [TimberFrame.OAK, Color(0.16, 0.105, 0.075), Color(0.30, 0.20, 0.12), Color(0.25, 0.22, 0.18), Color(0.19, 0.16, 0.13), Color(0.22, 0.12, 0.07)],
	Element.PLASTER: [WallLayout.PLASTER, Color(0.93, 0.92, 0.89), Color(0.91, 0.72, 0.68), Color(0.89, 0.73, 0.45), Color(0.72, 0.81, 0.87), Color(0.75, 0.81, 0.67)],
	Element.THATCH: [RoofLayout.STRAW, Color(0.72, 0.56, 0.3), Color(0.78, 0.68, 0.45), Color(0.5, 0.38, 0.24), Color(0.5, 0.48, 0.43), Color(0.34, 0.29, 0.22)],
	Element.GLOW: GLOWS,
	Element.LANTERN: [
		GLOWS[0], GLOWS[0] * 0.55 + Color(0.45, 0.45, 0.45), GLOWS[0] * 0.6,
		GLOWS[1], GLOWS[1] * 0.55 + Color(0.45, 0.45, 0.45), GLOWS[1] * 0.6,
		GLOWS[2], GLOWS[2] * 0.55 + Color(0.45, 0.45, 0.45), GLOWS[2] * 0.6,
		GLOWS[3], GLOWS[3] * 0.55 + Color(0.45, 0.45, 0.45), GLOWS[3] * 0.6,
		GLOWS[4], GLOWS[4] * 0.55 + Color(0.45, 0.45, 0.45), GLOWS[4] * 0.6,
		GLOWS[5], GLOWS[5] * 0.55 + Color(0.45, 0.45, 0.45), GLOWS[5] * 0.6,
		GLOWS[6], GLOWS[6] * 0.55 + Color(0.45, 0.45, 0.45), GLOWS[6] * 0.6,
		GLOWS[7], GLOWS[7] * 0.55 + Color(0.45, 0.45, 0.45), GLOWS[7] * 0.6,
	],
}

## The material each kind of laid part is painted with; kinds not listed (iron, flags, curtains, flowers) keep their
## colour. Glass carries the colour it glows at night.
const KINDS := {
	"block": Element.STONE, "mortar": Element.STONE, "voussoir": Element.STONE, "keystone": Element.STONE,
	"pillar": Element.STONE, "cope": Element.STONE, "cap": Element.STONE, "merlon": Element.STONE,
	"pier": Element.STONE, "lintel": Element.STONE, "sill": Element.STONE, "mullion": Element.STONE,
	"chimney": Element.STONE, "rubble": Element.STONE, "deck": Element.STONE, "flagstone": Element.STONE, "bed": Element.STONE,
	"tile": Element.ROOF, "ridge": Element.ROOF, "thatch": Element.THATCH,
	"post": Element.WOOD, "beam": Element.WOOD, "rail": Element.WOOD, "board": Element.WOOD, "gate": Element.WOOD, "frame": Element.WOOD,
	"door": Element.WOOD, "pole": Element.WOOD, "plank": Element.WOOD, "planter": Element.WOOD, "hatch": Element.WOOD,
	"glass": Element.GLOW,
	"plaster": Element.PLASTER, "timber": Element.TIMBER,
}

var season := SUMMER


static func count(element: Element) -> int:
	return SEASONS.size() if element == Element.MEADOW else SWATCHES[element].size()


static func swatch(element: Element, index: int) -> Color:
	return SEASONS[index].swatch if element == Element.MEADOW else SWATCHES[element][index]


## What a laid part's custom data carries so its shader finds its material's tint: 0 for none.
static func code(kind: String) -> float:
	return KINDS[kind] if KINDS.has(kind) else 0.0


## A build's paint as laid: every material on its first swatch. Indexed by Element; the meadow's entry stays 0.
static func plain() -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(Element.size())
	return out


## Whether `paint` is a build's paint: a swatch of each material, the meadow's entry 0.
static func valid(paint: Variant) -> bool:
	if typeof(paint) != TYPE_PACKED_INT32_ARRAY or paint.size() != Element.size() or paint[Element.MEADOW] != 0:
		return false
	for e: Element in SWATCHES:
		if paint[e] < 0 or paint[e] >= count(e):
			return false
	return true


## What scales a part laid in `element`'s first swatch onto its swatch `index`.
static func tint(element: Element, index: int) -> Color:
	var base: Color = SWATCHES[element][0]
	var c: Color = SWATCHES[element][index]
	return Color(c.r / base.r, c.g / base.g, c.b / base.b)


## The shader globals season `index` sets, by name.
static func globals(index: int) -> Dictionary:
	var out := {}
	for key in ["meadow", "foliage"]:
		var t: Color = SEASONS[index][key]
		out["season_" + key] = Vector4(t.r, t.g, t.b, t.a)
	out["season_bloom"] = SEASONS[index].bloom
	return out


## The share of flowers in bloom this season.
func bloom() -> float:
	return SEASONS[season].bloom


func fireflies() -> bool:
	return SEASONS[season].fireflies


func apply() -> void:
	preview(season)


## Shows season `index`, leaving the garden's as it is.
static func preview(index: int) -> void:
	var g := globals(index)
	for name in g:
		RenderingServer.global_shader_parameter_set(name, g[name])
