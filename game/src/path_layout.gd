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
## The ground wears to earth this far past a path's stones.
const VERGE := 0.3
## Bare earth between neighbouring stones' footprints.
const GAP := 0.04
## The stone mesh's lumps reach this far from its centre, in units of its scale.
const REACH := 0.53
## A stone squeezed thinner than this either way is left out.
const SMALLEST := 0.12
const CELL := 1.0

var points: Array[Vector3] = []
var half_widths: Array[float] = []
var seed := 1
## The paths laid before this one, whose stones it paves around.
var others: Array[PathLayout] = []

var samples: Array[Vector3] = []
var sample_half_widths: Array[float] = []
var lengths: Array[float] = []
var point_lengths: Array[float] = []
var stones: Array[Dictionary] = []
## Each row of stones fills the band of arc length from the previous row's end to its own.
var row_ends: Array[float] = []
## Where each laid row's stones start in `stones`.
var row_starts: Array[int] = []
## The ground the stones can cover, for skipping paths that cannot touch.
var area := Rect2()
## Grid cell → indices of the stones whose footprints reach into it.
var _cells := {}


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


## Whether the stones or worn verge reach the ground point (x, z).
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


func build(keep_before := 0.0) -> void:
	plan()
	lay(keep_before)


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


## Lays the planned rows' stones, keeping the rows wholly before `keep_before`: each row draws from its own
## stream, so a growing stroke relays only its tail and ends with the stones a single build would lay.
func lay(keep_before := 0.0) -> void:
	var k := mini(rows_before(keep_before), row_starts.size())
	if k < row_starts.size():
		for i in range(row_starts[k], stones.size()):
			_index(i, false)
		stones.resize(row_starts[k])
		row_starts.resize(k)
	var near: Array[PathLayout] = [self]
	near.append_array(others.filter(func(o: PathLayout) -> bool: return o.area.intersects(area)))
	var rng := RandomNumberGenerator.new()
	while row_starts.size() < row_ends.size():
		k = row_starts.size()
		rng.seed = hash([seed, k, "stones"])
		row_starts.append(stones.size())
		_lay_row(row_ends[k - 1] if k > 0 else 0.0, minf(row_ends[k], length()), rng, near)


## Takes the stones `job`, a copy of this path, laid.
func adopt(job: PathLayout) -> void:
	stones = job.stones
	row_starts = job.row_starts
	_cells = job._cells


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


## Splits the band from arc length `a` to `b` across the path into cells, one stone to a cell. Neighbouring
## cells share edges, so stones kept inside their cells cannot touch; where a curve is too tight for the
## band's inner side the cells fold over and lay nothing.
func _lay_row(a: float, b: float, rng: RandomNumberGenerator, near: Array[PathLayout]) -> void:
	var fa := frame_at(a)
	var fb := frame_at(b)
	var fm := frame_at((a + b) * 0.5)
	var half: float = fm.half
	var x := -half + rng.randf_range(0.0, 0.12)
	while half - x > 0.14:
		var w := minf(rng.randf_range(0.3, 0.56), half - x)
		var edge := absf(x + w * 0.5) / half
		if rng.randf() < 0.95 - edge * edge * 0.35:
			var cell := PackedVector2Array([_across(fa, x), _across(fa, x + w), _across(fb, x + w), _across(fb, x)])
			_place(cell, fm, Vector2(w, b - a), rng, near)
		x += w


static func _across(f: Dictionary, x: float) -> Vector2:
	return _flat(f.point + f.along.cross(Vector3.UP) * x)


## Lays the biggest stone up to `room` that fits inside `cell` clear of every stone already laid.
func _place(cell: PackedVector2Array, f: Dictionary, room: Vector2, rng: RandomNumberGenerator, near: Array[PathLayout]) -> void:
	var across: Vector3 = f.along.cross(Vector3.UP)
	var basis := Basis(across, Vector3.UP, across.cross(Vector3.UP)) * Basis(Vector3.UP, rng.randf_range(-0.18, 0.18))
	var u := _flat(basis.x) * room.x * 0.5
	var v := _flat(basis.z) * room.y * 0.5
	var centre := (cell[0] + cell[1] + cell[2] + cell[3]) * 0.25
	var fit := rng.randf_range(0.88, 1.0)
	for i in 4:
		var p := cell[i]
		var q := cell[(i + 1) % 4]
		var r := cell[(i + 2) % 4]
		if (q - p).cross(r - q) > -1e-4:
			return
		var inward := (q - p).orthogonal().normalized()
		var clear := inward.dot(centre - p) - GAP * 0.5
		var reach := absf(inward.dot(u)) + absf(inward.dot(v))
		if clear <= 0.0:
			return
		fit = minf(fit, clear / reach)
	var foot := PackedVector2Array([centre, u * fit, v * fit])
	while _crowded(foot, near):
		foot[1] *= 0.85
		foot[2] *= 0.85
	if foot[1].length() * 2.0 < SMALLEST or foot[2].length() * 2.0 < SMALLEST:
		return
	var size := Vector3(foot[1].length() / REACH, rng.randf_range(0.09, 0.13), foot[2].length() / REACH)
	var warm := rng.randf_range(-0.04, 0.04)
	var color := Color(0.6 + warm, 0.56, 0.49 - warm * 1.5) * rng.randf_range(0.78, 1.04)
	var origin := Vector3(centre.x, size.y * 0.5 - SINK, centre.y)
	stones.append({"xform": Transform3D(basis.scaled_local(size), origin), "color": color, "ao": 0.85, "variant": rng.randi() % 3, "foot": foot})
	_index(stones.size() - 1, true)


## Whether footprint `foot` (centre, half-extent vectors) comes within GAP of a stone laid on a path of `near`.
## This row's and the last row's stones sit in cells sharing edges with its own, so cannot.
func _crowded(foot: PackedVector2Array, near: Array[PathLayout]) -> bool:
	if foot[1].length() * 2.0 < SMALLEST or foot[2].length() * 2.0 < SMALLEST:
		return false
	var cells := _cells_of(foot)
	for path in near:
		var upto := row_starts[maxi(row_starts.size() - 2, 0)] if path == self else path.stones.size()
		for c in cells:
			for i: int in path._cells.get(c, []):
				if i >= upto:
					break
				if not _apart(foot, path.stones[i].foot):
					return true
	return false


static func _apart(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	var d := b[0] - a[0]
	var ra := a[1].length() + a[2].length()
	var rb := b[1].length() + b[2].length()
	if d.length_squared() >= (ra + rb + GAP) * (ra + rb + GAP):
		return true
	return _apart_on(d, a[1], a, b) or _apart_on(d, a[2], a, b) or _apart_on(d, b[1], a, b) or _apart_on(d, b[2], a, b)


static func _apart_on(d: Vector2, axis: Vector2, a: PackedVector2Array, b: PackedVector2Array) -> bool:
	var n := axis.normalized()
	return absf(n.dot(d)) >= absf(n.dot(a[1])) + absf(n.dot(a[2])) + absf(n.dot(b[1])) + absf(n.dot(b[2])) + GAP * 0.5


static func _cells_of(foot: PackedVector2Array) -> Array[Vector2i]:
	var r := Vector2(absf(foot[1].x) + absf(foot[2].x), absf(foot[1].y) + absf(foot[2].y)) + Vector2.ONE * GAP
	var lo := Vector2i(((foot[0] - r) / CELL).floor())
	var hi := Vector2i(((foot[0] + r) / CELL).floor())
	var out: Array[Vector2i] = []
	for i in range(lo.x, hi.x + 1):
		for j in range(lo.y, hi.y + 1):
			out.append(Vector2i(i, j))
	return out


func _index(i: int, on: bool) -> void:
	for c in _cells_of(stones[i].foot):
		if on:
			if not _cells.has(c):
				_cells[c] = []
			_cells[c].append(i)
		else:
			_cells[c].erase(i)


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
	area = area.grow(HALF_WIDTH.y + GAP)


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
