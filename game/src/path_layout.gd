class_name PathLayout
extends RefCounted

## Path strokes wear the ground to their surface and open arches, or doors into houses, where they cross walls; across
## water they lay stepping stones, and a garden bed sprouts rows of vegetables. Pure data.

const CELL := 1.0
const ROW := 0.42
const HALF_WIDTH := Vector2(0.45, 3.0)
## A crossing at least this long along the wall opens an arcade instead of a single arch.
const ARCADE_SPAN := 2.8
## Soft edge beyond the stroke.
const VERGE := 0.3
## How far neighbouring treads overlap, so no seam between their stones shows the ground beneath.
const TREAD_LAP := 0.06
## Width and depth of the timbers carrying a flight of treads at either edge.
const STRINGER := Vector2(0.16, 0.34)
## How far a stringer's top stands above the treads it carries.
const STRINGER_PROUD := 0.06
## Water at least this deep over the spine lays stepping stones instead of treads.
const WET := 0.04
## Stepping stones' spacing along the spine, their size across, along and down, and how high they stand out of the water.
const STRIDE := 0.7
const STEPPING_STONE := Vector3(0.55, 0.16, 0.46)
const STEPPING_PROUD := 0.05
## A bed's rows lie this far apart across it, at least this far in from its edge, with a plant this often along each.
const CROP_ROWS := 0.4
const CROP_MARGIN := 0.12
const CROP_EVERY := 0.32

## What a path lays: dirt, sand, cobbles or flagstones, or a garden bed of tilled earth.
enum Surface { DIRT, SAND, COBBLES, FLAGS, BED }
enum Crop { CABBAGE, LETTUCE, CARROT, LEEK }

var points: Array[Vector3] = []
var half_widths: Array[float] = []
var seed := 1
var surface := Surface.DIRT
## The small things gathered beside it (ClutterLayout).
var clutter: Array[Vector4] = []
## What this path wears into Ground's mask, as Ground's marks are read.
var kind: Ground.Kind:
	get:
		return wears(surface)

var samples: Array[Vector3] = []
var sample_half_widths: Array[float] = []
var lengths: Array[float] = []
var point_lengths: Array[float] = []
## Where each point's samples start in `samples`, and how many points the last `_resample` read.
var _point_samples := PackedInt32Array()
var _resampled := 0
## The grid cells the last `_resample` took segments from or laid them in, or null where it laid them all again.
var moved: Variant = null
## Each wear row fills the band of arc length from the previous row's end to its own.
var row_ends: Array[float] = []
## Bounds for skipping walls that cannot cross.
var area := Rect2()
## Grid cell → indices of the sample segments whose boxes reach into it, made when first asked for.
var _segment_cells := {}
## A stroke still being drawn: its segments before `settled` stand, so `meetings` keeps each wall's along them and tests
## only the moving end again. A path not growing keeps each wall's whole until it is planned again.
var growing := false:
	set(v):
		growing = v
		_met.clear()
## Wall instance id → [its segment grid, the segments kept (-1 for all), and the crossings found and met along them].
var _met := {}
## Each crop's pieces (`crop`), made as the class loads so workers laying beds only read them.
static var _crop_pieces: Array = _made_crops()


## What a path of surface `what` wears into Ground's mask.
static func wears(what: Surface) -> Ground.Kind:
	return {Surface.SAND: Ground.Kind.SAND, Surface.COBBLES: Ground.Kind.STONE, Surface.FLAGS: Ground.Kind.STONE}.get(what, Ground.Kind.EARTH)


## The look a path of surface `what` lays in Ground's mask: a stone style, or Ground.TILLED for a bed.
static func look(what: Surface) -> int:
	match what:
		Surface.COBBLES:
			return StoneStyles.RIVER_COBBLE
		Surface.FLAGS:
			return StoneStyles.MOSSY
		Surface.BED:
			return Ground.TILLED
	return 0


static func of(data: Dictionary) -> PathLayout:
	var path := PathLayout.new()
	path.seed = data.seed
	path.surface = data.surface
	path.clutter.assign(Array(data.get("clutter", PackedVector4Array())))
	for i in data.points.size():
		path.add(data.points[i], data.half_widths[i])
	return path


## What a build command carries to lay this path again.
func data() -> Dictionary:
	return {"points": PackedVector3Array(points), "half_widths": PackedFloat32Array(half_widths), "seed": seed, "surface": surface, "clutter": PackedVector4Array(clutter)}


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


## Wears rows `from_row` up to `to_row` (all of them by default) into the ground mask `onto`; a Ground mark. Cobbles and
## flagstones lie on worn earth under their full stone, so stone painted back to meadow over them leaves the path's way
## showing, and their soft edge frays into the meadow as painted stone does, with no earth along it.
func wear(onto: Image, from_row := 0, to_row := -1) -> void:
	for k in range(from_row, row_ends.size() if to_row < 0 else to_row):
		var d := disc(k)
		if kind == Ground.Kind.STONE:
			Ground.stamp(onto, d.x, d.y, d.z - Ground.TEXEL, Ground.TEXEL, Ground.Kind.EARTH)
		Ground.stamp(onto, d.x, d.y, d.z, d.w, kind, look(surface))


## Row `k`'s disc on the ground mask: x, z, full radius and the width of the fade past it, as Ground.stamp takes them.
func disc(k: int) -> Vector4:
	var f := frame_at(((row_ends[k - 1] if k > 0 else 0.0) + row_ends[k]) * 0.5)
	return Vector4(f.point.x, f.point.z, f.half - 0.1, VERGE + 0.1)


## The spine point, half-width and unit direction at arc length `s`.
func frame_at(s: float) -> Dictionary:
	var i := clampi(lengths.bsearch(s), 1, samples.size() - 1)
	var t := clampf((s - lengths[i - 1]) / maxf(lengths[i] - lengths[i - 1], 1e-5), 0.0, 1.0)
	var along := samples[i] - samples[i - 1]
	along.y = 0.0
	return {"point": samples[i - 1].lerp(samples[i], t), "half": lerpf(sample_half_widths[i - 1], sample_half_widths[i], t), "along": along.normalized() if along.length() > 1e-5 else Vector3.FORWARD}


func _resample() -> void:
	# While `growing`, only the points the last resample read may have moved: its last, which `extend` moves, and the
	# new ones. A sample segment reads the point before and the two after it, so those from three before stand.
	var first := maxi(_resampled - 3, 0) if growing else 0
	var keep := _point_samples[first] if first > 0 and first < _point_samples.size() else 0
	moved = null
	if keep == 0 or _segment_cells.is_empty():
		first = 0 if keep == 0 else first
		_segment_cells = {}
		_met.clear()
	else:
		moved = {}
		for i in range(keep - 1, samples.size() - 1):
			for c in cells_along(_flat(samples[i]), _flat(samples[i + 1])):
				moved[c] = true
				_segment_cells[c].erase(i)
				if _segment_cells[c].is_empty():
					_segment_cells.erase(c)
	samples.resize(keep)
	sample_half_widths.resize(keep)
	lengths.resize(keep)
	point_lengths.resize(first)
	_point_samples.resize(first)
	WallLayout.smooth(points, func(q: Vector3, i: int, t: float):
		lengths.append(lengths[-1] + Vector2(q.x - samples[-1].x, q.z - samples[-1].z).length() if samples.size() > 0 else 0.0)
		samples.append(q)
		sample_half_widths.append(lerpf(half_widths[i], half_widths[mini(i + 1, half_widths.size() - 1)], t))
		if t == 0.0:
			point_lengths.append(lengths[-1])
			_point_samples.append(samples.size() - 1), first)
	_resampled = points.size()
	area = Rect2(_flat(samples[0]), Vector2.ZERO) if samples.size() > 0 else Rect2()
	for q in samples:
		area = area.expand(_flat(q))
	area = area.grow(HALF_WIDTH.y)
	if moved != null:
		for i in range(maxi(keep - 1, 0), samples.size() - 1):
			for c in cells_along(_flat(samples[i]), _flat(samples[i + 1])):
				moved[c] = true
				if not _segment_cells.has(c):
					_segment_cells[c] = []
				_segment_cells[c].append(i)


## Arc lengths along `wall` where this path opens arches: one where it crosses, or an arcade where the
## crossing runs long along the wall (a wide path, or one meeting the wall at a slant). Looks only in `cells` of
## `segment_cells`, by default all of them.
func crossings(wall: WallLayout, cells: Array = []) -> Array[float]:
	return arches(meetings(wall, cells))


## The arc lengths of the arches `met`, a path's `meetings` with a wall, open: an arcade where one runs long along it.
static func arches(met: Array[Dictionary]) -> Array[float]:
	var out: Array[float] = []
	for m in met:
		var n := 1 if m.span < ARCADE_SPAN else ceili((m.span - WallLayout.ARCH_HALF * 2.0) / WallLayout.ARCADE_PITCH) + 1
		for k in n:
			out.append(m.s + (k - (n - 1) * 0.5) * WallLayout.ARCADE_PITCH)
	return out


## Where this path crosses `wall`: the arc length along it of each crossing (`s`), and how far along it the path's width
## runs there (`span`), its width or more where it meets the wall at a slant. Looks only in `cells` of `segment_cells`, by
## default all of them; a cell the wall does not reach holds no crossing.
func meetings(wall: WallLayout, cells: Array = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if samples.size() < 2 or wall.samples.size() < 2:
		return out
	if not wall.bounds.grow(0.01).intersects(area, true):
		return out
	var theirs := wall.segment_cells()
	var found: Array[float] = []
	var from := 0
	var fixed := lengths.bsearch(settled(), false) - 1 if growing else 0
	var kept: Array = _met.get(wall.get_instance_id(), [])
	if not growing and not kept.is_empty() and is_same(kept[0], theirs) and kept[1] < 0:
		out.assign(kept[3])
		return out
	if growing and not kept.is_empty() and is_same(kept[0], theirs) and kept[1] <= fixed:
		from = kept[1]
		found.assign(kept[2])
		out.assign(kept[3])
	var meets := {}
	for c in cells if not cells.is_empty() else segment_cells().keys():
		var js: Variant = theirs.get(c)
		if js == null:
			continue
		for i: int in segment_cells()[c]:
			if i < from:
				continue
			if not meets.has(i):
				meets[i] = {}
			for j: int in js:
				meets[i][j] = true
	var near := meets.keys()
	near.sort()
	near.append(samples.size())
	for i: int in near:
		if growing and i >= fixed and fixed > from:
			_met[wall.get_instance_id()] = [theirs, fixed, found.duplicate(), out.duplicate()]
			from = fixed
		if i == samples.size():
			break
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
			out.append({"s": s, "span": 2.0 * lerpf(sample_half_widths[i], sample_half_widths[i + 1], a.distance_to(hit) / maxf(a.distance_to(b), 1e-5)) / maxf(slant, 0.4)})
	if not growing:
		_met[wall.get_instance_id()] = [theirs, -1, [], out.duplicate()]
	return out


func segment_cells() -> Dictionary:
	if _segment_cells.is_empty() and samples.size() > 1:
		_segment_cells = segment_grid(samples)
	return _segment_cells


## The cells of `segment_cells` that `wall`'s reach too.
func shared_cells(wall: WallLayout) -> Array:
	var mine := segment_cells()
	return wall.segment_cells().keys().filter(func(c: Vector2i) -> bool: return mine.has(c))


## Takes the meetings `other`, the same path laid again, has found and will find.
func share_meetings(other: PathLayout) -> void:
	_met = other._met


## Grid cell → indices of the segments between consecutive `points` whose boxes reach into it.
static func segment_grid(points: Array[Vector3]) -> Dictionary:
	var grid := {}
	for i in points.size() - 1:
		for c in cells_along(_flat(points[i]), _flat(points[i + 1])):
			if not grid.has(c):
				grid[c] = []
			grid[c].append(i)
	return grid


## The grid cells the box around segment a–b reaches, padded so a crossing on a cell edge is found from both sides.
static func cells_along(a: Vector2, b: Vector2) -> Array[Vector2i]:
	var lo := Vector2i(((a.min(b) - Vector2.ONE * 0.01) / CELL).floor())
	var hi := Vector2i(((a.max(b) + Vector2.ONE * 0.01) / CELL).floor())
	var out: Array[Vector2i] = []
	for i in range(lo.x, hi.x + 1):
		for j in range(lo.y, hi.y + 1):
			out.append(Vector2i(i, j))
	return out


static func _flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


## What the path lays besides its wear: horizontal treads on steep dry rows, each flight carried by a timber stringer
## along either edge (a bed's rows grow crops instead), stepping stones where it crosses water, and a bed's vegetables.
## The ground's height and the water's surface are supplied (`water` none for dry ground) so the layout stays pure data.
func pieces(height: Callable, water := Callable()) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var wet := func(p: Vector3) -> bool: return water.is_valid() and water.call(p.x, p.z) > height.call(p.x, p.z) + WET
	if surface != Surface.BED:
		_treads(height, wet, out)
	_stepping_stones(height, water, wet, out)
	if surface == Surface.BED:
		_crops(height, wet, out)
	for v in clutter:
		var x: Variant = clutter_frame(v, height)
		if x != null:
			out.append_array(ClutterLayout.parts(v, x, seed))
	return out


## Where piece `v` of the path's clutter stands on ground of `height`, its middle facing out from the path, or null past
## either end.
func clutter_frame(v: Vector4, height: Callable) -> Variant:
	if v.x < 0.0 or v.x > length():
		return null
	var f := frame_at(v.x)
	var x := ClutterLayout.facing(f.point, f.along, v.y, absf(v.y), v.z)
	x.origin.y = height.call(x.origin.x, x.origin.z)
	return x


func _treads(height: Callable, wet: Callable, pieces: Array[Dictionary]) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var flight: Array[Dictionary] = []
	for row in row_ends.size():
		var start := row_ends[row - 1] if row > 0 else 0.0
		var end := minf(row_ends[row], length())
		var a := frame_at(start).point as Vector3
		var b := frame_at(end).point as Vector3
		var run := Vector2(b.x - a.x, b.z - a.z).length()
		var rise: float = height.call(b.x, b.z) - height.call(a.x, a.z) if run >= 0.001 else 0.0
		if run < 0.001 or absf(rise) / run <= 0.5 or wet.call(frame_at((start + end) * 0.5).point):
			_stringers(flight, height, pieces, rng)
			flight.clear()
			continue
		var count := Budget.PATH_TREADS_PER_ROW
		for i in count:
			var from := lerpf(start, end, float(i) / count)
			var to := lerpf(start, end, float(i + 1) / count)
			var f := frame_at((from + to) * 0.5)
			var along := Vector3(f.along.x, 0, f.along.z).normalized()
			var side := along.cross(Vector3.UP)
			var columns := maxi(1, ceili(f.half * 2.0 / 0.5))
			var depth := to - from + TREAD_LAP
			var top := -INF
			var low := INF
			for k in columns + 1:
				for edge in [-1.0, 1.0]:
					var at: Vector3 = f.point + side * (float(k) / columns - 0.5) * f.half * 2.0 + along * depth * edge * 0.5
					var y: float = height.call(at.x, at.z)
					top = maxf(top, y)
					low = minf(low, y)
			var thick := maxf(0.12, top - low + 0.04)
			for col in columns:
				var at: Vector3 = f.point + side * ((col + 0.5) / columns - 0.5) * f.half * 2.0
				at.y = top + 0.025 - thick * 0.5
				var size := Vector3(f.half * 2.0 / columns + TREAD_LAP, thick, depth)
				pieces.append({"xform": Transform3D(Basis(side, Vector3.UP, -along).scaled_local(size), at), "color": Color(0.62, 0.58, 0.5) * rng.randf_range(0.88, 1.05), "ao": 0.9, "variant": 0, "kind": "block"})
			flight.append({"point": Vector3(f.point.x, top + 0.025, f.point.z), "half": f.half, "along": along, "depth": depth})
	_stringers(flight, height, pieces, rng)


## A flat stone every STRIDE along the spine where it runs over water, its top a little out of the water and its foot on
## the bed, stepping a little to either side in turn.
func _stepping_stones(height: Callable, water: Callable, wet: Callable, pieces: Array[Dictionary]) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, "stepping"])
	var k := 0
	var s := STRIDE * 0.5
	while s < length():
		var f := frame_at(s)
		s += STRIDE
		k += 1
		if not wet.call(f.point):
			continue
		var side: Vector3 = f.along.cross(Vector3.UP)
		var at: Vector3 = f.point + side * minf(0.12, f.half * 0.3) * (1.0 if k % 2 == 0 else -1.0)
		var top: float = water.call(at.x, at.z) + STEPPING_PROUD
		var foot: float = height.call(at.x, at.z) - 0.05
		var size := Vector3(STEPPING_STONE.x * rng.randf_range(0.85, 1.15), maxf(STEPPING_STONE.y, top - foot), STEPPING_STONE.z * rng.randf_range(0.85, 1.15))
		var turn := Basis(Vector3.UP, rng.randf_range(-0.4, 0.4)) * Basis(side, Vector3.UP, -f.along)
		pieces.append({"xform": Transform3D(turn.scaled_local(size), Vector3(at.x, top - size.y * 0.5, at.z)), "color": Color(0.46, 0.44, 0.4) * rng.randf_range(0.85, 1.08), "ao": 0.9, "variant": k % 3, "kind": "block"})


## Rows of vegetables along a bed, one kind a row: as many rows as its width holds CROP_ROWS apart, a plant every
## CROP_EVERY along each, none where it runs over water. Each plant is its crop's pieces turned a way of its own.
func _crops(height: Callable, wet: Callable, pieces: Array[Dictionary]) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, "crops"])
	for spot in crop_spots():
		var at: Vector3 = spot.at
		if wet.call(at):
			continue
		at.y = height.call(at.x, at.z)
		var root := Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)), at)
		var tone := rng.randf_range(0.88, 1.1)
		for piece: Array in crop(spot.crop):
			pieces.append({"xform": root * piece[0], "color": piece[1] * tone, "ao": 1.0, "variant": pieces.size() % 3, "kind": "crop"})


## Where a bed's plants stand on flat ground and which crop each is: its rows run along the spine, the row through the
## middle, or the two either side of it, then outward, each row's crop chosen by the bed's seed and how far out it lies.
func crop_spots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var s := CROP_EVERY * 0.5
	while s < length():
		var f := frame_at(s)
		var side: Vector3 = f.along.cross(Vector3.UP)
		var rows := maxi(1, floori((f.half - CROP_MARGIN) * 2.0 / CROP_ROWS) + 1)
		for r in rows:
			var across := (r - (rows - 1) * 0.5) * CROP_ROWS
			var crop := posmod(hash([seed, roundi(across / CROP_ROWS * 2.0)]), Crop.size()) as Crop
			# Neighbouring rows stand staggered, as rows sown by hand do.
			var stagger := CROP_EVERY * 0.5 * (r % 2) - CROP_EVERY * 0.25
			out.append({"at": f.point + side * across + f.along * stagger, "crop": crop})
		s += CROP_EVERY
	return out


## A crop's pieces about its root, as [transform, colour]: coloured stones for a cabbage's pale head in its spreading
## leaves, a lettuce's rosette, a carrot's fronds over its orange shoulder, a leek's pale stem under its fan.
static func crop(which: Crop) -> Array:
	return _crop_pieces[which]


static func _made_crops() -> Array:
	var leaves := func(n: int, out: float, up: float, tilt: float, size: Vector3, color: Color) -> Array:
		var ring := []
		for i in n:
			var turn := Basis(Vector3.UP, i * TAU / n)
			ring.append([Transform3D((turn * Basis(Vector3.BACK, tilt)).scaled_local(size), turn * Vector3(out, up, 0)), color])
		return ring
	var cabbage := [[Transform3D(Basis(Vector3.UP, PI / 4.0).scaled_local(Vector3(0.17, 0.15, 0.17)), Vector3(0, 0.08, 0)), Color(0.42, 0.6, 0.3)]]
	var carrot := [[Transform3D(Basis.from_scale(Vector3(0.05, 0.03, 0.05)), Vector3(0, 0.01, 0)), Color(0.9, 0.42, 0.08)]]
	var leek := [[Transform3D(Basis.from_scale(Vector3(0.045, 0.1, 0.045)), Vector3(0, 0.05, 0)), Color(0.62, 0.7, 0.46)]]
	return [
		cabbage + leaves.call(3, 0.1, 0.05, 0.35, Vector3(0.2, 0.04, 0.15), Color(0.2, 0.42, 0.22)),
		leaves.call(4, 0.05, 0.06, 0.6, Vector3(0.15, 0.05, 0.12), Color(0.38, 0.62, 0.12)),
		carrot + leaves.call(2, 0.025, 0.12, 0.3, Vector3(0.05, 0.22, 0.03), Color(0.2, 0.48, 0.1)),
		leek + leaves.call(2, 0.0, 0.22, 0.3, Vector3(0.07, 0.24, 0.02), Color(0.16, 0.36, 0.26)),
	]


## Two timbers along a flight's edges, from the ground at its foot to the ground at its head, their tops a little
## above the tread line so they read as holding the stones up.
func _stringers(flight: Array[Dictionary], height: Callable, pieces: Array[Dictionary], rng: RandomNumberGenerator) -> void:
	if flight.is_empty():
		return
	for edge in [-1.0, 1.0]:
		var line: Array[Vector3] = []
		for t in flight:
			line.append(t.point + t.along.cross(Vector3.UP) * edge * (t.half + STRINGER.x * 0.5))
		var first: Dictionary = flight[0]
		var last: Dictionary = flight[-1]
		var foot: Vector3 = line[0] - first.along * first.depth * 0.5
		var head: Vector3 = line[-1] + last.along * last.depth * 0.5
		foot.y = minf(foot.y, height.call(foot.x, foot.z))
		head.y = minf(head.y, height.call(head.x, head.z))
		line.push_front(foot)
		line.push_back(head)
		var color: Color = TimberFrame.OAK * rng.randf_range(0.88, 1.12)
		for i in line.size() - 1:
			var run := line[i + 1] - line[i]
			var z := run.normalized()
			var x := Vector3.UP.cross(z).normalized()
			var y := z.cross(x)
			var size := Vector3(STRINGER.x, STRINGER.y, run.length() + STRINGER.x)
			var at := (line[i] + line[i + 1]) * 0.5 - y * (STRINGER.y * 0.5 - STRINGER_PROUD)
			pieces.append({"xform": Transform3D(Basis(x, y, z).scaled_local(size), at), "color": color, "ao": 1.0, "variant": 0, "kind": "timber", "size": size})
