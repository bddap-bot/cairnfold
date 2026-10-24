class_name Daylight
extends RefCounted

## The sun's path and the light of each hour. Time runs once round the day: 0 and 1 are midnight, 0.25
## sunrise, 0.5 noon, 0.75 sunset. The sun goes round one tilted circle, rising on the left of the starting
## view, high in front of it at noon, setting on its right, so the meadow stays backlit. The moon rides the same
## circle MOON_LAG behind the sun, high at dusk and set soon after midnight, so the night before dawn is dark.
## Pure data: no nodes, so tests run headless.

## How far the arc leans from straight overhead toward the front; the noon sun stands 90° less this high.
const TILT := deg_to_rad(40.0)
## The arc turned about the vertical so the default hour's sun stands where the meadow was tuned under it.
const YAW := deg_to_rad(-25.5)
const RISE := Vector3(-cos(YAW), 0.0, sin(YAW))
const ARC_UP := Vector3(-sin(TILT) * sin(YAW), cos(TILT), -sin(TILT) * cos(YAW))
## Late morning, the look the meadow was tuned under.
const DEFAULT := 0.3805
## How far round the arc the moon trails the sun.
const MOON_LAG := deg_to_rad(100.0)
## The sun's elevation where the light passes from sun to moon; the sun is dark there and the moon not yet lit,
## so the swap is unseen.
const HANDOVER := -8.0
## The sun's elevation by which the night is dark enough for moonlight to take the garden whole.
const NIGHT := -18.0
## The moon's elevations between which it rises from lighting nothing to lighting the garden whole.
const MOONRISE := Vector2(-2.0, 12.0)
## The sun's elevations between which a room's windows come on, from dark to glowing whole.
const LIT := Vector2(6.0, -4.0)
## How near the sun or moon, in degrees, a pointing hand takes the sky by it, under the ground too.
const REACH := 7.0

## Each key holds at a sun elevation in degrees; between keys every value blends. `sun` is the colour of
## whichever of sun and moon lights the garden, `moon` the moon's own glow, `stars` how many show. Below the
## horizon the keys are a night with no moon up; MOONLIT is what a risen moon lifts it to.
const KEYS := [
	{"at": -40.0, "sun": Color(0.60, 0.72, 1.00), "energy": 0.0, "zenith": Color(0.008, 0.012, 0.03), "horizon": Color(0.022, 0.028, 0.05), "glow": Color(0.0, 0.0, 0.0), "fog": Color(0.02, 0.025, 0.04), "clouds": Color(0.04, 0.045, 0.07), "ambient": 0.35, "moon": Color(0.62, 0.68, 0.85), "stars": 1.0, "exposure": 1.2, "saturation": 0.6},
	{"at": NIGHT, "sun": Color(0.58, 0.68, 0.98), "energy": 0.0, "zenith": Color(0.012, 0.018, 0.045), "horizon": Color(0.03, 0.038, 0.065), "glow": Color(0.0, 0.0, 0.0), "fog": Color(0.028, 0.034, 0.055), "clouds": Color(0.055, 0.06, 0.09), "ambient": 0.4, "moon": Color(0.60, 0.64, 0.80), "stars": 0.8, "exposure": 1.2, "saturation": 0.65},
	{"at": HANDOVER, "sun": Color(0.40, 0.45, 0.70), "energy": 0.0, "zenith": Color(0.08, 0.11, 0.26), "horizon": Color(0.28, 0.28, 0.42), "glow": Color(0.45, 0.28, 0.40), "fog": Color(0.22, 0.24, 0.36), "clouds": Color(0.30, 0.31, 0.44), "ambient": 0.45, "moon": Color(0.55, 0.52, 0.62), "stars": 0.2, "exposure": 1.25, "saturation": 0.95},
	{"at": -1.0, "sun": Color(1.00, 0.42, 0.20), "energy": 0.2, "zenith": Color(0.22, 0.30, 0.56), "horizon": Color(0.88, 0.64, 0.56), "glow": Color(1.00, 0.50, 0.28), "fog": Color(0.72, 0.60, 0.58), "clouds": Color(0.98, 0.66, 0.58), "ambient": 0.5, "moon": Color(0.45, 0.40, 0.45), "stars": 0.0, "exposure": 1.05, "saturation": 1.12},
	{"at": 5.0, "sun": Color(1.00, 0.64, 0.36), "energy": 0.95, "zenith": Color(0.25, 0.40, 0.72), "horizon": Color(0.94, 0.80, 0.66), "glow": Color(1.00, 0.60, 0.30), "fog": Color(0.86, 0.78, 0.70), "clouds": Color(1.00, 0.84, 0.70), "ambient": 0.62, "moon": Color(0.0, 0.0, 0.0), "stars": 0.0, "exposure": 1.05, "saturation": 1.12},
	{"at": 14.0, "sun": Color(1.00, 0.84, 0.64), "energy": 1.45, "zenith": Color(0.28, 0.48, 0.82), "horizon": Color(0.92, 0.86, 0.76), "glow": Color(1.00, 0.75, 0.50), "fog": Color(0.82, 0.84, 0.86), "clouds": Color(1.00, 0.97, 0.92), "ambient": 0.7, "moon": Color(0.0, 0.0, 0.0), "stars": 0.0, "exposure": 1.05, "saturation": 1.12},
	{"at": 34.0, "sun": Color(1.00, 0.93, 0.80), "energy": 1.7, "zenith": Color(0.30, 0.52, 0.85), "horizon": Color(0.86, 0.88, 0.84), "glow": Color(1.00, 0.82, 0.55), "fog": Color(0.80, 0.85, 0.90), "clouds": Color(1.00, 1.00, 1.00), "ambient": 0.75, "moon": Color(0.0, 0.0, 0.0), "stars": 0.0, "exposure": 1.05, "saturation": 1.12},
	{"at": 50.0, "sun": Color(1.00, 0.96, 0.90), "energy": 1.8, "zenith": Color(0.28, 0.52, 0.88), "horizon": Color(0.84, 0.89, 0.90), "glow": Color(1.00, 0.86, 0.65), "fog": Color(0.80, 0.86, 0.92), "clouds": Color(1.00, 1.00, 1.00), "ambient": 0.8, "moon": Color(0.0, 0.0, 0.0), "stars": 0.0, "exposure": 1.05, "saturation": 1.12},
]

## The night as a risen moon lights it, blended in by `moonlit`.
const MOONLIT := {"sun": Color(0.60, 0.72, 1.00), "energy": 0.42, "zenith": Color(0.035, 0.06, 0.15), "horizon": Color(0.10, 0.14, 0.25), "fog": Color(0.09, 0.12, 0.21), "clouds": Color(0.20, 0.24, 0.36), "ambient": 1.0, "exposure": 1.45, "saturation": 0.72}


static func angle(time: float) -> float:
	return (time - 0.25) * TAU


static func _on_arc(a: float) -> Vector3:
	return RISE * cos(a) + ARC_UP * sin(a)


static func toward_sun(time: float) -> Vector3:
	return _on_arc(angle(time))


static func toward_moon(time: float) -> Vector3:
	return _on_arc(angle(time) - MOON_LAG)


static func elevation(time: float) -> float:
	return rad_to_deg(asin(toward_sun(time).y))


static func moon_elevation(time: float) -> float:
	return rad_to_deg(asin(toward_moon(time).y))


## How fully the moon lights the garden at `time`: 0 while the sun lights it or the moon is down, 1 at full night
## with the moon well up.
static func moonlit(time: float) -> float:
	return smoothstep(HANDOVER, NIGHT, elevation(time)) * smoothstep(MOONRISE.x, MOONRISE.y, moon_elevation(time))


## How fully the rooms' windows glow at `time`: 0 by day, 1 once the sun is down.
static func lit(time: float) -> float:
	return smoothstep(LIT.x, LIT.y, elevation(time))


## Toward whichever of sun and moon lights the garden at `time`.
static func toward_light(time: float) -> Vector3:
	return toward_sun(time) if elevation(time) > HANDOVER else toward_moon(time)


## How far round the arc's axis `dir` stands, on the same scale as `angle`: the sky turns by its change.
static func turn_of(dir: Vector3) -> float:
	return atan2(dir.dot(ARC_UP), dir.dot(RISE))


## Whether `dir` points within REACH degrees of the sun or the moon at `time`, wherever they stand.
static func aims_at_body(dir: Vector3, time: float) -> bool:
	var d := dir.normalized()
	return maxf(d.dot(toward_sun(time)), d.dot(toward_moon(time))) > cos(deg_to_rad(REACH))


## The time whose `angle` is `a`, wrapped into one day.
static func time_at(a: float) -> float:
	return fposmod(a / TAU + 0.25, 1.0)


## Every light value for `time`, blended between the keys around the sun's elevation, then toward MOONLIT as far
## as the moon lights the garden.
static func light(time: float) -> Dictionary:
	var e := elevation(time)
	var hi := 1
	while hi < KEYS.size() - 1 and KEYS[hi].at < e:
		hi += 1
	var a: Dictionary = KEYS[hi - 1]
	var b: Dictionary = KEYS[hi]
	var k := smoothstep(a.at, b.at, e)
	var out := {}
	for key in a:
		if key != "at":
			out[key] = lerp(a[key], b[key], k)
	var m := moonlit(time)
	for key in MOONLIT:
		out[key] = lerp(out[key], MOONLIT[key], m)
	return out
