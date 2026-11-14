class_name Brushwork
extends RefCounted

## A stroke is plain data every machine reads alike; `Stroker` turns its samples into the dabs paint.glsl lays, the same
## on every machine and every replay of a kept painting. Colours are optical densities (absorbance per channel,
## Beer-Lambert), so paint mixes and glazes subtractively: blue and yellow make green, layers darken.

enum Medium { WATER, OIL, CHARCOAL, SMEAR }
enum Brush { SMALL, BIG, FLAT, STICK, THIN_STICK, THICK_STICK }

## The canvas in texels and in metres: about a millimetre a texel, finer than the Frame resolves at arm's length.
const SIZE := Vector2i(1536, 1152)
const METRES := Vector2(1.5, 1.125)
## Simulation ticks a second; each tick is two flow steps.
const TICK_HZ := 60.0
## A wash is dry this many ticks after the brush last wet it.
const DRY_TICKS := 360
## Wetness is tracked per square tile of this many texels.
const TILE := 64
## How far past the brush water may run, in texels: sideways and up, then down the tilted canvas.
const MARGIN := 40
const RUN := 160
## Each brush's radius in texels, from a touch to full pressure (`radii`).
const RADII := {Brush.SMALL: Vector2(1.5, 8.0), Brush.BIG: Vector2(6.0, 40.0), Brush.FLAT: Vector2(10.0, 42.0)}
## The charcoal sticks, long and thin to short and thick, by their radius and length in metres; the radius sets the
## mark's width and the length how far a stick on its side reaches.
const STICKS := {Brush.THIN_STICK: Vector2(0.0035, 0.24), Brush.STICK: Vector2(0.0065, 0.15), Brush.THICK_STICK: Vector2(0.011, 0.08)}
## Metres past the surface at which a tool presses fully.
const PRESS_DEPTH := 0.02
## Dabs are laid this fraction of their radius apart.
const SPACING := 0.2
## Speed, in texels a tick, at which a stroke skips over the paper's dips (dry-brush), and how much it does per medium:
## a wet brush skims most, thick oil little, charcoal not at all.
const SKIM := 60.0
const SKIMS := {Medium.WATER: 0.7, Medium.OIL: 0.25, Medium.CHARCOAL: 0.0, Medium.SMEAR: 0.0}
## The palette's wells, as display colours: white, lemon, ochre, vermilion, rose, ultramarine, sap green, umber,
## phthalo blue, black. A demo script or test may name a well by its index, so new wells go on the end.
const PIGMENTS := [
	Color(0.97, 0.96, 0.93), Color(0.98, 0.86, 0.18), Color(0.82, 0.6, 0.25), Color(0.9, 0.3, 0.14),
	Color(0.78, 0.16, 0.36), Color(0.16, 0.24, 0.72), Color(0.28, 0.5, 0.2), Color(0.38, 0.24, 0.16),
	Color(0.0, 0.45, 0.66), Color(0.08, 0.08, 0.09),
]
const CHARCOAL := Vector3(2.3, 2.25, 2.1)
const MAX_DENSITY := 8.0
const MAX_SAMPLES := 512
## Most dabs one stroke lays on a canvas (`dabs`), what laying it costs every machine that replays it; a board's
## stroke counts as on a canvas. The longest stroke in the recorded sessions laid 15561; the easel tool ends a stroke
## here as it does at MAX_SAMPLES, so none it paints is refused.
const MAX_DABS := 32768
## Most samples one canvas holds across its strokes; past it the canvas takes no more until a fresh sheet.
const MAX_TOTAL := 120000
## Most dabs one canvas lays across its strokes: MAX_TOTAL samples at the densest recorded canvas's 32 dabs a sample.
const MAX_TOTAL_DABS := MAX_TOTAL * 32
const MAX_STROKES := 4000
## Floats per dab: x, y, major radius, pressure; heading (charcoal minor radius), load, dryness, footprint angle.
const DAB := 8


static func absorbance(c: Color) -> Vector3:
	var l := c.srgb_to_linear()
	return Vector3(-log(maxf(l.r, 0.004)), -log(maxf(l.g, 0.004)), -log(maxf(l.b, 0.004)))


static func colour(density: Vector3) -> Color:
	return Color(exp(-density.x), exp(-density.y), exp(-density.z)).linear_to_srgb()


static func is_stick(brush: Brush) -> bool:
	return STICKS.has(brush)


## 0..1 for `depth` in metres; every tool's one curve, eased so a graze stays faint and narrow; a touch at the surface
## still marks.
static func pressure(depth: float) -> float:
	return lerpf(0.05, 1.0, smoothstep(0.0, PRESS_DEPTH, depth))


## Texels, (touch, full pressure); a stick's mark is a little wider than the stick.
static func radii(brush: Brush) -> Vector2:
	if is_stick(brush):
		return Vector2(0.4, 1.4) * STICKS[brush].x * SIZE.x / METRES.x
	return RADII[brush]


## Texels either way from the contact's middle, `side` 0..1: half a stick's length laid flat, 0 for a brush.
static func side_reach(brush: Brush, side: float) -> float:
	return side * STICKS[brush].y * 0.5 * SIZE.x / METRES.x if is_stick(brush) else 0.0


## Within a quarter turn either way: a stick's or a flat brush's footprint looks the same turned half a turn.
static func turn(from: float, to: float) -> float:
	return wrapf(to - from, -PI * 0.5, PI * 0.5)


## Texels; a stick on its side is a line `side_reach` either way of its middle. Returns (farthest any point goes, mean
## distance its points go).
static func sweep(brush: Brush, from: Vector2, from_angle: float, to: Vector2, to_angle: float, side: float) -> Vector2:
	var moved := to - from
	var end := side_reach(brush, side) * (Vector2.from_angle(from_angle + turn(from_angle, to_angle)) - Vector2.from_angle(from_angle))
	var mean := 0.0
	for k in 8:
		var along := (k + 0.5) / 4.0 - 1.0
		mean += (moved + end * along).length() / 8.0
	return Vector2(maxf((moved + end).length(), (moved - end).length()), mean)


static func medium_of(brush: Brush, medium: Medium) -> Medium:
	return Medium.CHARCOAL if is_stick(brush) else (Medium.WATER if medium == Medium.CHARCOAL else medium)


## Two ints: uv (0..1, to 1/65535), pressure (0..1), footprint angle (0..PI), ticks since the previous sample (0..2047),
## charcoal side contact (0..1).
static func pack(uv: Vector2, pressure: float, angle: float, ticks: int, side := 0.0) -> PackedInt32Array:
	var u := clampi(roundi(clampf(uv.x, 0.0, 1.0) * 65535.0), 0, 65535)
	var v := clampi(roundi(clampf(uv.y, 0.0, 1.0) * 65535.0), 0, 65535)
	var p := clampi(roundi(clampf(pressure, 0.0, 1.0) * 255.0), 0, 255)
	var a := clampi(roundi(fposmod(angle, PI) / PI * 255.0), 0, 255)
	var t := clampi(ticks, 0, 2047)
	var side_bits := clampi(roundi(side * 31.0), 0, 31)
	return PackedInt32Array([u | (v << 16), p | (a << 8) | (t << 16) | (side_bits << 27)])


## [uv, pressure, angle, ticks, charcoal side contact].
static func unpack(samples: PackedInt32Array, i: int) -> Array:
	var a := samples[i * 2]
	var b := samples[i * 2 + 1]
	return [Vector2((a & 0xffff) / 65535.0, ((a >> 16) & 0xffff) / 65535.0), (b & 0xff) / 255.0, ((b >> 8) & 0xff) / 255.0 * PI, (b >> 16) & 0x7ff, ((b >> 27) & 31) / 31.0]


static func count(stroke: Dictionary) -> int:
	return stroke.samples.size() / 2


## `more`, `samples` and `dabs`: what is to be added besides `strokes`.
static func holds(strokes: Array, more := 0, samples := 0, dabs := 0) -> bool:
	for s: Dictionary in strokes:
		samples += count(s)
		dabs += s.dabs
	return strokes.size() + more <= MAX_STROKES and samples <= MAX_TOTAL and dabs <= MAX_TOTAL_DABS


static func radius(brush: Brush, pressure: float) -> float:
	var r := radii(brush)
	return lerpf(r.x, r.y, pow(pressure, 0.7))


## `prev` ([] for the first sample) and `s` as `unpack` gives them. Returns [dabs laid (one for the first sample, none
## for a stick that only lifts or lowers), mean distance its points go, dab spacing].
static func span(stroke: Dictionary, prev: Array, s: Array, texels := Vector2(SIZE)) -> Array:
	if prev.is_empty():
		return [1, 0.0, 0.0]
	var swept := sweep(stroke.brush, prev[0] * texels, prev[2], s[0] * texels, s[2], maxf(prev[4], s[4]))
	var spacing := maxf(minf(radius(stroke.brush, prev[1]), radius(stroke.brush, s[1])) * SPACING, 0.5)
	return [0 if stroke.medium == Medium.CHARCOAL and swept.y < 1e-5 else maxi(ceili(swept.x / spacing), 1), swept.y, spacing]


static func dabs(stroke: Dictionary) -> int:
	var n := 0
	var prev := []
	for i in count(stroke):
		var s := unpack(stroke.samples, i)
		n += span(stroke, prev, s)[0]
		prev = s
	return n


## Null unless every field is in range, so a peer cannot hand a canvas anything a brush could not paint.
static func clean(d: Variant) -> Variant:
	if not d is Dictionary:
		return null
	var medium: Variant = d.get("medium")
	var brush: Variant = d.get("brush")
	if typeof(medium) != TYPE_INT or medium < 0 or medium >= Medium.size() or typeof(brush) != TYPE_INT or brush < 0 or brush >= Brush.size():
		return null
	if medium == Medium.SMEAR and (brush != Brush.FLAT or d.get("colour") != Vector3.ZERO or d.get("strength") != 0.0 or d.get("load") != 1.0):
		return null
	if medium_of(brush, medium) != medium:
		return null
	var c: Variant = d.get("colour")
	if typeof(c) != TYPE_VECTOR3 or not c.is_finite() or c.x < 0.0 or c.y < 0.0 or c.z < 0.0 or c.x > MAX_DENSITY or c.y > MAX_DENSITY or c.z > MAX_DENSITY:
		return null
	for k in ["strength", "load"]:
		var x: Variant = d.get(k)
		if typeof(x) != TYPE_FLOAT or not (x >= 0.0 and x <= 1.0):
			return null
	var gap: Variant = d.get("gap")
	if typeof(gap) != TYPE_INT or gap < 0 or gap > DRY_TICKS:
		return null
	var s: Variant = d.get("samples")
	if typeof(s) != TYPE_PACKED_INT32_ARRAY or s.size() < 2 or s.size() % 2 != 0 or s.size() > MAX_SAMPLES * 2:
		return null
	var out := {"medium": medium, "brush": brush, "colour": c, "strength": d.strength, "load": d.load, "gap": gap, "samples": s}
	out.dabs = dabs(out)
	return out if out.dabs <= MAX_DABS else null


class Stroker:
	var stroke: Dictionary
	var _texels: Vector2
	var _last: Array = []
	var _heading := 0.0

	func _init(of: Dictionary, texels := SIZE) -> void:
		stroke = of
		_texels = Vector2(texels)

	## `s` as `unpack` gives it; returns DAB floats per dab. A stick on its side lays a line, so it lays by how far that
	## line sweeps, turning about its middle as much as moving it.
	func add(s: Array) -> PackedFloat32Array:
		var out := PackedFloat32Array()
		var last := _last
		_last = s
		var to: Vector2 = s[0] * _texels
		var charcoal: bool = stroke.medium == Medium.CHARCOAL
		if last.is_empty():
			_dab(out, to, s[1], s[2], 0.0, 0.015 if charcoal else 1.0, s[4])
			return out
		var from: Vector2 = last[0] * _texels
		var run := from.distance_to(to)
		if run > 0.01:
			_heading = (to - from).angle()
		var span := Brushwork.span(stroke, last, s, _texels)
		var n: int = span[0]
		var turned := Brushwork.turn(last[2], s[2])
		var speed := run / maxf(float(s[3]), 1.0)
		for k in range(1, n + 1):
			var t := float(k) / n
			_dab(out, from.lerp(to, t), lerpf(last[1], s[1], t), last[2] + turned * t, speed, span[1] / n / span[2] if charcoal else 1.0, lerpf(last[4], s[4], t))
		return out

	func _dab(out: PackedFloat32Array, at: Vector2, pressure: float, angle: float, speed: float, travel := 1.0, side := 0.0) -> void:
		var r := Brushwork.radius(stroke.brush, pressure)
		var load: float = stroke.load
		var dryness: float = clampf(speed / SKIM, 0.0, 1.0) * SKIMS[stroke.medium] + (1.0 - load) * 0.45
		var major := maxf(r, Brushwork.side_reach(stroke.brush, side)) if stroke.medium == Medium.CHARCOAL else r
		out.append_array([at.x, at.y, major, pressure, r if stroke.medium == Medium.CHARCOAL else _heading, load * travel, clampf(dryness, 0.0, 1.0), angle])
