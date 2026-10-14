class_name PathLayout
extends RefCounted

## Flat stones laid in rows along a brush stroke, and the arches the stroke opens where it crosses a wall.
## Stones lie flat at heights counted from the ground under their centres; the paving shader sets them on
## the ground. Pure data.

const ROW := 0.42
const HALF_WIDTH := Vector2(0.45, 3.0)
## A crossing at least this long along the wall opens an arcade instead of a single arch.
const ARCADE_SPAN := 2.8
const SINK := 0.035

var points: Array[Vector3] = []
var half_widths: Array[float] = []
var seed := 1

var samples: Array[Vector3] = []
var sample_half_widths: Array[float] = []
var lengths: Array[float] = []
var point_lengths: Array[float] = []
var stones: Array[Dictionary] = []
var row_lengths: Array[float] = []
## Where each row's stones start in `stones`.
var row_starts: Array[int] = []
var _next_row := ROW * 0.5


func add(p: Vector3, half_width: float) -> void:
	points.append(p)
	half_widths.append(clampf(half_width, HALF_WIDTH.x, HALF_WIDTH.y))


func length() -> float:
	return lengths[-1] if lengths.size() > 0 else 0.0


## The arc length before which the spine has not moved since the last build, as long as only the last point
## moved or points were added: smoothing reaches two points back from the one that moved.
func settled() -> float:
	return point_lengths[-3] if point_lengths.size() >= 3 else 0.0


## Lays the stones, keeping the rows laid before `keep_before`: each row draws from its own stream, so a
## growing stroke relays only its tail and ends with the stones a single build would lay.
func build(keep_before := 0.0) -> void:
	_resample()
	var k := row_lengths.bsearch(keep_before)
	if k < row_lengths.size():
		_next_row = row_lengths[k]
		stones.resize(row_starts[k])
		row_lengths.resize(k)
		row_starts.resize(k)
	var rng := RandomNumberGenerator.new()
	while _next_row < length():
		rng.seed = hash([seed, row_lengths.size()])
		row_starts.append(stones.size())
		row_lengths.append(_next_row)
		_lay_row(_next_row, rng)
		_next_row += ROW * rng.randf_range(0.9, 1.1)


## The spine point, half-width and unit direction at arc length `s`.
func frame_at(s: float) -> Dictionary:
	var i := clampi(lengths.bsearch(s), 1, samples.size() - 1)
	var t := clampf((s - lengths[i - 1]) / maxf(lengths[i] - lengths[i - 1], 1e-5), 0.0, 1.0)
	var along := samples[i] - samples[i - 1]
	along.y = 0.0
	return {"point": samples[i - 1].lerp(samples[i], t), "half": lerpf(sample_half_widths[i - 1], sample_half_widths[i], t), "along": along.normalized() if along.length() > 1e-5 else Vector3.FORWARD}


func _lay_row(s: float, rng: RandomNumberGenerator) -> void:
	var f := frame_at(s)
	var half: float = f.half
	var across: Vector3 = f.along.cross(Vector3.UP)
	var x := -half + rng.randf_range(0.0, 0.12)
	while half - x > 0.14:
		var w := minf(rng.randf_range(0.3, 0.56), half - x)
		var edge := absf(x + w * 0.5) / half
		if rng.randf() < 0.95 - edge * edge * 0.35:
			var p: Vector3 = f.point + across * (x + w * 0.5) + f.along * rng.randf_range(-0.05, 0.05)
			var size := Vector3(w - 0.06, rng.randf_range(0.09, 0.13), ROW * rng.randf_range(0.72, 0.92))
			stones.append(_stone(p, across, size, rng))
		x += w


func _stone(p: Vector3, across: Vector3, size: Vector3, rng: RandomNumberGenerator) -> Dictionary:
	var basis := Basis(across, Vector3.UP, across.cross(Vector3.UP)) * Basis(Vector3.UP, rng.randf_range(-0.18, 0.18))
	var origin := Vector3(p.x, size.y * 0.5 - SINK, p.z)
	var warm := rng.randf_range(-0.04, 0.04)
	var color := Color(0.6 + warm, 0.56, 0.49 - warm * 1.5) * rng.randf_range(0.78, 1.04)
	return {"xform": Transform3D(basis.scaled_local(size), origin), "color": color, "ao": 0.85, "variant": rng.randi() % 3}


func _resample() -> void:
	samples.clear()
	sample_half_widths.clear()
	lengths.clear()
	point_lengths.clear()
	WallLayout.smooth(points, func(q: Vector3, i: int, t: float):
		lengths.append(lengths[-1] + Vector2(q.x - samples[-1].x, q.z - samples[-1].z).length() if samples.size() > 0 else 0.0)
		samples.append(q)
		sample_half_widths.append(lerpf(half_widths[i], half_widths[mini(i + 1, half_widths.size() - 1)], t))
		if t == 0.0:
			point_lengths.append(lengths[-1]))


## Arc lengths along `wall` where this path opens arches: one where it crosses, or an arcade where the
## crossing runs long along the wall (a wide path, or one meeting the wall at a slant).
func crossings(wall: WallLayout) -> Array[float]:
	var out: Array[float] = []
	if samples.size() < 2 or wall.samples.size() < 2:
		return out
	var found: Array[float] = []
	var bounds := Rect2(_flat(wall.samples[0]), Vector2.ZERO)
	for q in wall.samples:
		bounds = bounds.expand(_flat(q))
	for i in samples.size() - 1:
		var a := _flat(samples[i])
		var b := _flat(samples[i + 1])
		if not bounds.grow(0.01).intersects(Rect2(a, Vector2.ZERO).expand(b), true):
			continue
		for j in wall.samples.size() - 1:
			var c := _flat(wall.samples[j])
			var d := _flat(wall.samples[j + 1])
			var hit: Variant = Geometry2D.segment_intersects_segment(a, b, c, d)
			if hit == null or (c - d).length() < 1e-5:
				continue
			var s: float = wall.lengths[j] + c.distance_to(hit)
			# A crossing exactly on a sample joint hits both segments that meet there.
			if found.any(func(f): return absf(f - s) < WallLayout.SAMPLE):
				continue
			found.append(s)
			var slant := absf((b - a).normalized().cross((d - c).normalized()))
			var span := 2.0 * lerpf(sample_half_widths[i], sample_half_widths[i + 1], a.distance_to(hit) / maxf(a.distance_to(b), 1e-5)) / maxf(slant, 0.4)
			var n := 1 if span < ARCADE_SPAN else ceili((span - WallLayout.ARCH_HALF * 2.0) / WallLayout.ARCADE_PITCH) + 1
			for k in n:
				out.append(s + (k - (n - 1) * 0.5) * WallLayout.ARCADE_PITCH)
	return out


static func _flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)
