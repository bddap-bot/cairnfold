class_name Weather
extends RefCounted

## The garden's fog and snowfall, each 0 to 1; pure data, so tests run headless. `thick`: thin to thick, the depth fog
## and the ground layer alike. `high`: 0 no layer on the ground, then from clinging to the ground to standing high.
## `snow`: how hard it snows, in a winter only.

const CLEAR := {"thick": 0.25, "high": 0.0, "snow": 0.0}
const KEYS := ["thick", "high", "snow"]
## Each step of thickness from CLEAR brings the depth fog this many times nearer.
const NEARER := 16.0
## Metres: where the ground layer's top stands, from its lowest to its highest.
const LAYER := Vector2(0.4, 14.0)
## Of `high`: over its first stretch the layer gathers from nothing, so none and clinging are no step apart.
const SETTLE := 0.05
## Per metre under the layer's top, from the thinnest to the thickest.
const LAYER_DENSITY := Vector2(0.06, 0.6)
## The depth fog's density and how much of the sky it takes, from the thinnest to CLEAR to the thickest.
const DENSITY := Vector3(0.3, 0.55, 1.0)
const SKY_AFFECT := Vector3(0.05, 0.15, 0.85)


static func valid(w: Variant) -> bool:
	if not w is Dictionary or w.size() != KEYS.size():
		return false
	for k in KEYS:
		var v: Variant = w.get(k)
		if typeof(v) != TYPE_FLOAT or not (v >= 0.0 and v <= 1.0):
			return false
	return true


## 0 at CLEAR and thinner, 1 at the thickest: what the far hills and lake lose to the fog besides their own haze.
static func veil(w: Dictionary) -> float:
	return smoothstep(CLEAR.thick, 1.0, w.thick)


static func _by_thickness(w: Dictionary, span: Vector3) -> float:
	if w.thick < CLEAR.thick:
		return lerpf(span.x, span.y, w.thick / CLEAR.thick)
	return lerpf(span.y, span.z, veil(w))


## The Environment's fog for an eye `lift` metres over the ground (`Look.fog_at_height`) in weather `w`.
static func fog(w: Dictionary, lift_fog: Dictionary) -> Dictionary:
	var r := pow(NEARER, CLEAR.thick - w.thick)
	return {
		"fog_depth_begin": lift_fog.fog_depth_begin * r,
		"fog_depth_end": lift_fog.fog_depth_end * r,
		"fog_density": _by_thickness(w, DENSITY),
		"fog_sky_affect": _by_thickness(w, SKY_AFFECT),
		"fog_height": lerpf(LAYER.x, LAYER.y, w.high),
		"fog_height_density": lerpf(LAYER_DENSITY.x, LAYER_DENSITY.y, w.thick) * minf(w.high / SETTLE, 1.0),
	}

