class_name PathLayout
extends RefCounted

## Dirt strokes wear the ground and open arches where they cross walls. Pure data.

const CELL := 1.0
const ROW := 0.42
const HALF_WIDTH := Vector2(0.45, 3.0)
## A crossing at least this long along the wall opens an arcade instead of a single arch.
const ARCADE_SPAN := 2.8
## Soft edge beyond the stroke.
const VERGE := 0.3

var points: Array[Vector3] = []
var half_widths: Array[float] = []
var seed := 1

var samples: Array[Vector3] = []
var sample_half_widths: Array[float] = []
var lengths: Array[float] = []
var point_lengths: Array[float] = []
## Each wear row fills the band of arc length from the previous row's end to its own.
var row_ends: Array[float] = []
## Bounds for skipping walls that cannot cross.
var area := Rect2()
## Grid cell → indices of the sample segments whose boxes reach into it, made when first asked for.
var _segment_cells := {}


static func of(data: Dictionary) -> PathLayout:
	var path := PathLayout.new()
	path.seed = data.seed
	for i in data.points.size():
		path.add(data.points[i], data.half_widths[i])
	return path


## What a build command carries to lay this path again.
func data() -> Dictionary:
	return {"points": PackedVector3Array(points), "half_widths": PackedFloat32Array(half_widths), "seed": seed}


func add(p: Vector3, half_width: float) -> void:
	points.append(p)
	half_widths.append(clampf(half_width, HALF_WIDTH.x, HALF_WIDTH.y))


## Whether the worn stroke reaches the ground point (x, z).
func covers(x: float, z: float) -> bool:
	var p := Vector2(x, z)
	for i in samples.size() - 1:
		var a := _flat(samples[i])
		var b := _flat(samples[i + 1])
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		var t := q.distance_to(a) / maxf(a.distance_to(b), 1e-5)
		if p.distance_to(q) < lerpf(sample_half_widths[i], sample_half_widths[i + 1], t) + VERGE:
			return true
	return false


func length() -> float:
	return lengths[-1] if lengths.size() > 0 else 0.0


## The arc length before which the spine has not moved since the last build, as long as only the last point
## moved or points were added: smoothing reaches two points back from the one that moved.
func settled() -> float:
	return point_lengths[-3] if point_lengths.size() >= 3 else 0.0


## How many rows lie wholly before arc length `s`.
func rows_before(s: float) -> int:
	return row_ends.bsearch(s, false)


## Smooths the spine and marks out its rows, all the ground wear and arches need.
func plan() -> void:
	_resample()
	while row_ends.size() > 1 and row_ends[-2] >= length():
		row_ends.pop_back()
	var rng := RandomNumberGenerator.new()
	var s := row_ends[-1] if row_ends.size() > 0 else 0.0
	while s < length():
		rng.seed = hash([seed, row_ends.size()])
		s += ROW * rng.randf_range(0.9, 1.1)
		row_ends.append(s)


## Wears rows `from_row` up to `to_row` (all of them by default) into the ground mask `onto`; a Ground mark.
func wear(onto: Image, from_row := 0, to_row := -1) -> void:
	for k in range(from_row, row_ends.size() if to_row < 0 else to_row):
		var f := frame_at(((row_ends[k - 1] if k > 0 else 0.0) + row_ends[k]) * 0.5)
		Ground.stamp(onto, f.point.x, f.point.z, f.half - 0.1, VERGE + 0.1, Ground.Kind.EARTH)


## The spine point, half-width and unit direction at arc length `s`.
func frame_at(s: float) -> Dictionary:
	var i := clampi(lengths.bsearch(s), 1, samples.size() - 1)
	var t := clampf((s - lengths[i - 1]) / maxf(lengths[i] - lengths[i - 1], 1e-5), 0.0, 1.0)
	var along := samples[i] - samples[i - 1]
	along.y = 0.0
	return {"point": samples[i - 1].lerp(samples[i], t), "half": lerpf(sample_half_widths[i - 1], sample_half_widths[i], t), "along": along.normalized() if along.length() > 1e-5 else Vector3.FORWARD}


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
	area = Rect2(_flat(samples[0]), Vector2.ZERO) if samples.size() > 0 else Rect2()
	for q in samples:
		area = area.expand(_flat(q))
	area = area.grow(HALF_WIDTH.y)
	_segment_cells = {}


## Arc lengths along `wall` where this path opens arches: one where it crosses, or an arcade where the
## crossing runs long along the wall (a wide path, or one meeting the wall at a slant). Looks only in `cells` of
## `segment_cells`, by default all of them; a cell the wall does not reach holds no crossing.
func crossings(wall: WallLayout, cells: Array = []) -> Array[float]:
	var out: Array[float] = []
	if samples.size() < 2 or wall.samples.size() < 2:
		return out
	if not wall.bounds.grow(0.01).intersects(area, true):
		return out
	var theirs := wall.segment_cells()
	var meets := {}
	for c in cells if not cells.is_empty() else segment_cells().keys():
		var js: Variant = theirs.get(c)
		if js == null:
			continue
		for i: int in segment_cells()[c]:
			if not meets.has(i):
				meets[i] = {}
			for j: int in js:
				meets[i][j] = true
	var found: Array[float] = []
	var near := meets.keys()
	near.sort()
	for i: int in near:
		var a := _flat(samples[i])
		var b := _flat(samples[i + 1])
		var js: Array = meets[i].keys()
		js.sort()
		for j: int in js:
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


func segment_cells() -> Dictionary:
	if _segment_cells.is_empty() and samples.size() > 1:
		_segment_cells = segment_grid(samples)
	return _segment_cells


## The ends and half-widths of the segments in `cells` of `segment_cells`: all `crossings` reads of this path there.
func segments_in(cells: Array) -> Array:
	var ends := PackedVector3Array()
	var halves := PackedFloat32Array()
	for c in cells:
		for i: int in segment_cells()[c]:
			ends.append_array([samples[i], samples[i + 1]])
			halves.append_array([sample_half_widths[i], sample_half_widths[i + 1]])
	return [ends, halves]


## Grid cell → indices of the segments between consecutive `points` whose boxes reach into it.
static func segment_grid(points: Array[Vector3]) -> Dictionary:
	var grid := {}
	for i in points.size() - 1:
		for c in _cells_along(_flat(points[i]), _flat(points[i + 1])):
			if not grid.has(c):
				grid[c] = []
			grid[c].append(i)
	return grid


## The grid cells the box around segment a–b reaches, padded so a crossing on a cell edge is found from both sides.
static func _cells_along(a: Vector2, b: Vector2) -> Array[Vector2i]:
	var lo := Vector2i(((a.min(b) - Vector2.ONE * 0.01) / CELL).floor())
	var hi := Vector2i(((a.max(b) + Vector2.ONE * 0.01) / CELL).floor())
	var out: Array[Vector2i] = []
	for i in range(lo.x, hi.x + 1):
		for j in range(lo.y, hi.y + 1):
			out.append(Vector2i(i, j))
	return out


static func _flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


## Horizontal treads on steep rows; height is supplied so the layout stays pure data.
func steps(height: Callable) -> Array[Dictionary]:
	var pieces: Array[Dictionary] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for row in row_ends.size():
		var start := row_ends[row - 1] if row > 0 else 0.0
		var end := minf(row_ends[row], length())
		var a := frame_at(start).point as Vector3
		var b := frame_at(end).point as Vector3
		var run := Vector2(b.x - a.x, b.z - a.z).length()
		if run < 0.001:
			continue
		var rise: float = height.call(b.x, b.z) - height.call(a.x, a.z)
		if absf(rise) / run <= 0.5:
			continue
		var count := Budget.PATH_TREADS_PER_ROW
		for i in count:
			var from := lerpf(start, end, float(i) / count)
			var to := lerpf(start, end, float(i + 1) / count)
			var f := frame_at((from + to) * 0.5)
			var along := Vector3(f.along.x, 0, f.along.z).normalized()
			var side := along.cross(Vector3.UP)
			var columns := maxi(1, ceili(f.half * 2.0 / 0.5))
			var top := -INF
			var low := INF
			for k in columns + 1:
				for edge in [-1.0, 1.0]:
					var at: Vector3 = f.point + side * (float(k) / columns - 0.5) * f.half * 2.0 + along * (to - from + 0.02) * edge * 0.5
					var y: float = height.call(at.x, at.z)
					top = maxf(top, y)
					low = minf(low, y)
			var thick := maxf(0.12, top - low + 0.04)
			for col in columns:
				var at: Vector3 = f.point + side * ((col + 0.5) / columns - 0.5) * f.half * 2.0
				at.y = top + 0.025 - thick * 0.5
				var size := Vector3(f.half * 2.0 / columns - 0.015, thick, to - from + 0.02)
				pieces.append({"xform": Transform3D(Basis(side, Vector3.UP, -along).scaled_local(size), at), "color": Color(0.62, 0.58, 0.5) * rng.randf_range(0.88, 1.05), "ao": 0.9, "variant": 0, "kind": "block"})
	return pieces
