class_name Palette
extends RefCounted

## The glade's colours: a season for the meadow, and a swatch for each built material. Laid parts keep
## their own colour variation around the material's first swatch; a pick scales them toward the chosen
## swatch through one shader global per material, so recolouring relays nothing. Pure data apart from
## `apply`, so tests run headless.

## Each material's value is also its code in the parts' custom data, read by `material_tint` in
## palette.gdshaderinc; the meadow's 0 doubles as "kept as laid".
enum Element { MEADOW = 0, STONE = 1, ROOF = 2, WOOD = 3, PLASTER = 4 }

## The meadow's swatches are the seasons, each a preset for the meadow (grass and ground) and foliage
## (trees, bushes, ivy): the colour plants turn toward (rgb) and how far (a); and the share of flowers in bloom.
const SEASONS := [
	{"name": "spring", "swatch": Color(0.50, 0.74, 0.30), "meadow": Color(0.46, 0.72, 0.22, 0.35), "foliage": Color(0.42, 0.66, 0.2, 0.4), "bloom": 1.0},
	{"name": "summer", "swatch": Color(0.40, 0.60, 0.18), "meadow": Color(0, 0, 0, 0), "foliage": Color(0, 0, 0, 0), "bloom": 1.0},
	{"name": "late summer", "swatch": Color(0.70, 0.66, 0.26), "meadow": Color(0.66, 0.6, 0.24, 0.5), "foliage": Color(0.42, 0.44, 0.16, 0.3), "bloom": 0.55},
	{"name": "autumn", "swatch": Color(0.80, 0.42, 0.14), "meadow": Color(0.6, 0.48, 0.2, 0.6), "foliage": Color(0.82, 0.36, 0.1, 0.85), "bloom": 0.15},
	{"name": "winter", "swatch": Color(0.86, 0.89, 0.93), "meadow": Color(0.84, 0.87, 0.92, 0.85), "foliage": Color(0.86, 0.88, 0.92, 0.7), "bloom": 0.0},
]
const SUMMER := 1

## Each material's swatches; the first is the colour its parts are laid in.
const SWATCHES := {
	Element.STONE: [WallLayout.STONE, Color(0.84, 0.81, 0.74), Color(0.78, 0.64, 0.42), Color(0.70, 0.46, 0.37), Color(0.48, 0.50, 0.55), Color(0.40, 0.38, 0.36), Color(0.56, 0.59, 0.48)],
	Element.ROOF: [RoofLayout.CLAY, Color(0.33, 0.38, 0.46), Color(0.38, 0.48, 0.30), Color(0.66, 0.22, 0.19), Color(0.78, 0.58, 0.30), Color(0.24, 0.24, 0.26), Color(0.24, 0.47, 0.50), Color(0.45, 0.28, 0.38)],
	Element.WOOD: [WallLayout.WOOD, Color(0.55, 0.53, 0.48), Color(0.44, 0.55, 0.44), Color(0.27, 0.40, 0.56), Color(0.56, 0.20, 0.16), Color(0.2, 0.2, 0.22), Color(0.86, 0.82, 0.70)],
	Element.PLASTER: [WallLayout.PLASTER, Color(0.93, 0.92, 0.89), Color(0.91, 0.72, 0.68), Color(0.89, 0.73, 0.45), Color(0.72, 0.81, 0.87), Color(0.75, 0.81, 0.67)],
}

## The material each kind of laid part is painted with; kinds not listed (glass, iron, flags) keep their colour.
const KINDS := {
	"block": Element.STONE, "mortar": Element.STONE, "voussoir": Element.STONE, "keystone": Element.STONE,
	"pillar": Element.STONE, "cope": Element.STONE, "cap": Element.STONE, "merlon": Element.STONE,
	"pier": Element.STONE, "lintel": Element.STONE, "sill": Element.STONE, "mullion": Element.STONE,
	"chimney": Element.STONE, "rubble": Element.STONE,
	"tile": Element.ROOF, "ridge": Element.ROOF,
	"post": Element.WOOD, "rail": Element.WOOD, "gate": Element.WOOD, "frame": Element.WOOD,
	"door": Element.WOOD, "pole": Element.WOOD,
	"plaster": Element.PLASTER,
}
const TWIST_STEP := 28.0

## The swatch picked for each element; for the meadow, the season.
var picks: Array[int] = []


func _init() -> void:
	picks.resize(Element.size())
	picks[Element.MEADOW] = SUMMER


static func count(element: Element) -> int:
	return SEASONS.size() if element == Element.MEADOW else SWATCHES[element].size()


static func swatch(element: Element, index: int) -> Color:
	return SEASONS[index].swatch if element == Element.MEADOW else SWATCHES[element][index]


## What a laid part's custom data carries so its shader finds its material's tint: 0 for none.
static func code(kind: String) -> float:
	return KINDS[kind] if KINDS.has(kind) else 0.0


## The swatch a twist of `degrees` (clockwise positive) from `start` lands on, wrapping round the wheel.
static func twisted(element: Element, start: int, degrees: float) -> int:
	return posmod(start + roundi(degrees / TWIST_STEP), count(element))


## The shader globals these picks set, by name.
func globals() -> Dictionary:
	var out := {}
	for e: Element in SWATCHES:
		var base: Color = SWATCHES[e][0]
		var c: Color = SWATCHES[e][picks[e]]
		out["tint_" + Element.keys()[e].to_lower()] = Vector3(c.r / base.r, c.g / base.g, c.b / base.b)
	var season: Dictionary = SEASONS[picks[Element.MEADOW]]
	for key in ["meadow", "foliage"]:
		var t: Color = season[key]
		out["season_" + key] = Vector4(t.r, t.g, t.b, t.a)
	out["season_bloom"] = season.bloom
	return out


func apply() -> void:
	_set_globals(globals())


## Shows these picks with `element` at `index` instead, leaving the picks as they are.
func preview(element: Element, index: int) -> void:
	var p := Palette.new()
	p.picks = picks.duplicate()
	p.picks[element] = index
	_set_globals(p.globals())


static func _set_globals(g: Dictionary) -> void:
	for name in g:
		RenderingServer.global_shader_parameter_set(name, g[name])
