class_name Brushwork
extends RefCounted

## What a painted stroke is, as plain data every machine reads alike: the medium, the brush, the paint on it, and
## its samples (where the tip touched the canvas, how hard, at which tick of the canvas's simulation). `Stroker`
## turns samples into the dabs the canvas's compute shader lays (paint.glsl), the same dabs on every machine and on
## every replay of a kept painting. Colours are optical densities (absorbance per channel, Beer-Lambert), so paint
## mixes on the brush and glazes on the canvas subtractively: blue and yellow make green, layers darken.

enum Medium { WATER, OIL, CHARCOAL }
enum Brush { SMALL, BIG, FLAT, STICK }

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
## Each brush's radius in texels, from a touch to full pressure, and how much paint it holds, in texels of area
## laid at full pressure before it is spent.
const RADII := {Brush.SMALL: Vector2(1.5, 8.0), Brush.BIG: Vector2(6.0, 40.0), Brush.FLAT: Vector2(10.0, 42.0), Brush.STICK: Vector2(2.5, 9.0)}
const HOLDS := {Brush.SMALL: 40000.0, Brush.BIG: 400000.0, Brush.FLAT: 400000.0, Brush.STICK: 1.0e12}
## Oil is spent a little sooner than a wet brush.
const OIL_HOLDS := 0.8
## Dabs overlap by this fraction of their radius.
const SPACING := 0.2
## Speed, in texels a tick, at which a stroke skips over the paper's dips (dry-brush), and how much it does per medium:
## a wet brush skims most, thick oil little, charcoal not at all.
const SKIM := 60.0
const SKIMS := {Medium.WATER: 0.7, Medium.OIL: 0.25, Medium.CHARCOAL: 0.0}
## The palette's wells, as display colours: white, lemon, ochre, vermilion, rose, ultramarine, sap green, umber.
const PIGMENTS := [
	Color(0.97, 0.96, 0.93), Color(0.98, 0.86, 0.18), Color(0.82, 0.6, 0.25), Color(0.9, 0.3, 0.14),
	Color(0.78, 0.16, 0.36), Color(0.16, 0.24, 0.72), Color(0.28, 0.5, 0.2), Color(0.38, 0.24, 0.16),
]
const CHARCOAL := Vector3(2.3, 2.25, 2.1)
const MAX_DENSITY := 8.0
const MAX_SAMPLES := 512
## Most samples one canvas holds across its strokes; past it the canvas takes no more until a fresh sheet.
const MAX_TOTAL := 120000
const MAX_STROKES := 4000
## Floats per dab, as the shader's Dab struct reads them: x, y, radius, pressure; heading, load, dryness, flat angle.
const DAB := 8


static func absorbance(c: Color) -> Vector3:
	var l := c.srgb_to_linear()
	return Vector3(-log(maxf(l.r, 0.004)), -log(maxf(l.g, 0.004)), -log(maxf(l.b, 0.004)))


## How paper looks under `density` of pigment.
static func colour(density: Vector3) -> Color:
	return Color(exp(-density.x), exp(-density.y), exp(-density.z)).linear_to_srgb()


static func medium_of(brush: Brush, medium: Medium) -> Medium:
	return Medium.CHARCOAL if brush == Brush.STICK else (Medium.WATER if medium == Medium.CHARCOAL else medium)


## One sample as the two ints a stroke keeps it in: where on the canvas (0..1 each way, to 1/65535), how hard
## (0..1), the flat brush's angle (0..PI), and the ticks since the stroke's previous sample.
static func pack(uv: Vector2, pressure: float, angle: float, ticks: int) -> PackedInt32Array:
	var u := clampi(roundi(clampf(uv.x, 0.0, 1.0) * 65535.0), 0, 65535)
	var v := clampi(roundi(clampf(uv.y, 0.0, 1.0) * 65535.0), 0, 65535)
	var p := clampi(roundi(clampf(pressure, 0.0, 1.0) * 255.0), 0, 255)
	var a := clampi(roundi(fposmod(angle, PI) / PI * 255.0), 0, 255)
	var t := clampi(ticks, 0, 32767)
	return PackedInt32Array([u | (v << 16), p | (a << 8) | (t << 16)])


## Sample `i` of `samples`: [uv, pressure, angle, ticks].
static func unpack(samples: PackedInt32Array, i: int) -> Array:
	var a := samples[i * 2]
	var b := samples[i * 2 + 1]
	return [Vector2((a & 0xffff) / 65535.0, ((a >> 16) & 0xffff) / 65535.0), (b & 0xff) / 255.0, ((b >> 8) & 0xff) / 255.0 * PI, (b >> 16) & 0x7fff]


static func count(stroke: Dictionary) -> int:
	return stroke.samples.size() / 2


## A stroke as a command carries it, or null: every field in range, so a peer cannot hand a canvas anything a brush
## could not paint.
static func clean(d: Variant) -> Variant:
	if not d is Dictionary:
		return null
	var medium: Variant = d.get("medium")
	var brush: Variant = d.get("brush")
	if typeof(medium) != TYPE_INT or medium < 0 or medium >= Medium.size() or typeof(brush) != TYPE_INT or brush < 0 or brush >= Brush.size():
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
	return {"medium": medium, "brush": brush, "colour": c, "strength": d.strength, "load": d.load, "gap": gap, "samples": s}


## Lays a stroke's dabs sample by sample: between each sample and the one before, dabs a fifth of a radius apart,
## the paint on the brush running down as it lays them. The first sample lays one dab.
class Stroker:
	var stroke: Dictionary
	var _hold: float
	var _spent := 0.0
	var _last: Array = []
	var _heading := 0.0

	func _init(of: Dictionary) -> void:
		stroke = of
		_hold = HOLDS[of.brush] * (OIL_HOLDS if of.medium == Medium.OIL else 1.0)

	## The paint left on the brush, 0..1 of what the stroke began with.
	func left() -> float:
		return exp(-_spent / _hold)

	## The dabs sample `s` ([uv, pressure, angle, ticks], as `unpack` gives) adds.
	func add(s: Array) -> PackedFloat32Array:
		var out := PackedFloat32Array()
		var to := Vector2(s[0].x * SIZE.x, s[0].y * SIZE.y)
		if _last.is_empty():
			_dab(out, to, s[1], s[2], 0.0)
			_last = [to, s[1], s[2]]
			return out
		var from: Vector2 = _last[0]
		var run := from.distance_to(to)
		if run > 0.01:
			_heading = (to - from).angle()
		var speed := run / maxf(float(s[3]), 1.0)
		var r := minf(_radius(_last[1]), _radius(s[1]))
		var n := clampi(ceili(run / maxf(r * SPACING, 0.5)), 1, 4096)
		for k in range(1, n + 1):
			var t := float(k) / n
			_dab(out, from.lerp(to, t), lerpf(_last[1], s[1], t), lerp_angle(_last[2], s[2], t), speed)
		_last = [to, s[1], s[2]]
		return out

	func _radius(pressure: float) -> float:
		var r: Vector2 = RADII[stroke.brush]
		return lerpf(r.x, r.y, pow(pressure, 0.7))

	func _dab(out: PackedFloat32Array, at: Vector2, pressure: float, angle: float, speed: float) -> void:
		var r := _radius(pressure)
		var load: float = stroke.load * left()
		var dryness: float = clampf(speed / SKIM, 0.0, 1.0) * SKIMS[stroke.medium] + (1.0 - load) * 0.45
		out.append_array([at.x, at.y, r, pressure, _heading, load, clampf(dryness, 0.0, 1.0), angle])
		_spent += PI * r * r * SPACING * (0.3 + pressure)
