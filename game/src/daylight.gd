class_name Daylight
extends RefCounted

## The sun's path and the light of each hour. Time runs from 0, the sun just under the horizon at dawn,
## to 1, just under it at dusk; the sun crosses the sky on one tilted arc, rising on the left of the
## starting view, high in front of it at noon, setting on its right, so the meadow stays backlit.
## Pure data: no nodes, so tests run headless.

const DAWN := deg_to_rad(-11.0)
const DUSK := deg_to_rad(191.0)
## How far the arc leans from straight overhead toward the front; the noon sun stands 90° less this high.
const TILT := deg_to_rad(40.0)
## The arc turned about the vertical so the default hour's sun stands where the meadow was tuned under it.
const YAW := deg_to_rad(-25.5)
const RISE := Vector3(-cos(YAW), 0.0, sin(YAW))
const ARC_UP := Vector3(-sin(TILT) * sin(YAW), cos(TILT), -sin(TILT) * cos(YAW))
## Late morning, the look the meadow was tuned under.
const DEFAULT := 0.287

## Each key holds at a sun elevation in degrees; between keys every value blends.
const KEYS := [
	{"at": -8.0, "sun": Color(0.40, 0.45, 0.70), "energy": 0.0, "zenith": Color(0.08, 0.11, 0.26), "horizon": Color(0.28, 0.28, 0.42), "glow": Color(0.45, 0.28, 0.40), "fog": Color(0.22, 0.24, 0.36), "clouds": Color(0.30, 0.31, 0.44), "ambient": 0.35},
	{"at": -1.0, "sun": Color(1.00, 0.42, 0.20), "energy": 0.2, "zenith": Color(0.22, 0.30, 0.56), "horizon": Color(0.88, 0.64, 0.56), "glow": Color(1.00, 0.50, 0.28), "fog": Color(0.72, 0.60, 0.58), "clouds": Color(0.98, 0.66, 0.58), "ambient": 0.5},
	{"at": 5.0, "sun": Color(1.00, 0.64, 0.36), "energy": 0.95, "zenith": Color(0.25, 0.40, 0.72), "horizon": Color(0.94, 0.80, 0.66), "glow": Color(1.00, 0.60, 0.30), "fog": Color(0.86, 0.78, 0.70), "clouds": Color(1.00, 0.84, 0.70), "ambient": 0.62},
	{"at": 14.0, "sun": Color(1.00, 0.84, 0.64), "energy": 1.45, "zenith": Color(0.28, 0.48, 0.82), "horizon": Color(0.92, 0.86, 0.76), "glow": Color(1.00, 0.75, 0.50), "fog": Color(0.82, 0.84, 0.86), "clouds": Color(1.00, 0.97, 0.92), "ambient": 0.7},
	{"at": 34.0, "sun": Color(1.00, 0.93, 0.80), "energy": 1.7, "zenith": Color(0.30, 0.52, 0.85), "horizon": Color(0.86, 0.88, 0.84), "glow": Color(1.00, 0.82, 0.55), "fog": Color(0.80, 0.85, 0.90), "clouds": Color(1.00, 1.00, 1.00), "ambient": 0.75},
	{"at": 50.0, "sun": Color(1.00, 0.96, 0.90), "energy": 1.8, "zenith": Color(0.28, 0.52, 0.88), "horizon": Color(0.84, 0.89, 0.90), "glow": Color(1.00, 0.86, 0.65), "fog": Color(0.80, 0.86, 0.92), "clouds": Color(1.00, 1.00, 1.00), "ambient": 0.8},
]


static func angle(time: float) -> float:
	return lerpf(DAWN, DUSK, clampf(time, 0.0, 1.0))


static func toward_sun(time: float) -> Vector3:
	var a := angle(time)
	return RISE * cos(a) + ARC_UP * sin(a)


static func elevation(time: float) -> float:
	return rad_to_deg(asin(toward_sun(time).y))


## The time whose sun lies nearest `dir` along the arc: where a ray pointed that way drags the sun.
static func time_toward(dir: Vector3) -> float:
	var a := atan2(dir.dot(ARC_UP), dir.dot(RISE))
	if a < (DAWN + DUSK) * 0.5 - PI:
		a += TAU
	return clampf(inverse_lerp(DAWN, DUSK, a), 0.0, 1.0)


## Every light value for `time`, blended between the keys around the sun's elevation.
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
	return out
