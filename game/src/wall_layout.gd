class_name WallLayout
extends RefCounted

## Lays out the stones of a dry-stone wall along a ground curve, or around a closed loop (a tower or a
## house) standing level on its lowest ground. Pure data: no nodes, so tests run headless.

enum Top { CRENEL, CAP, COPE }

const COURSE := 0.3
const THICKNESS := 0.62
const CAP := 0.14
const SAMPLE := 0.2
const ARCH_HALF := 0.75
const RING := 0.32
## The nearest an arch's centre stands to a wall's end.
const ARCH_END := ARCH_HALF + RING + 0.3
const MIN_ARCH_SPAN := 2.4
const CORNER_TURN := deg_to_rad(35.0)
const PIER := THICKNESS + 0.28
## A stroke at least this long whose end comes back within LOOP_CLOSE of its start is a loop.
const LOOP_MIN_RUN := 4.0
const LOOP_CLOSE := 1.2
const TOWER_RADIUS := Vector2(1.2, 4.0)

var points: Array[Vector3] = []
var height := 2.6
var arches: Array[float] = []
var seed := 1
## A closed loop runs through its points and back to the first, straight between them.
var closed := false
var top := Top.CRENEL
## A roof rests on the cap, so piers stop flush with it.
var roofed := false

var samples: Array[Vector3] = []
var lengths: Array[float] = []
var bounds := Rect2()
var stones: Array[Dictionary] = []
## Stones shorten on a round loop so their outer ends stay closed.
var _stone_scale := 1.0
## The arches `build` could open, after dropping those too near an end or on a wall too low.
var live_arches: Array[float] = []


func length() -> float:
	return lengths[-1] if lengths.size() > 0 else 0.0


## The ground point at arc length `s`.
func point_at(s: float) -> Vector3:
	var i := clampi(lengths.bsearch(s), 0, samples.size() - 1)
	return samples[i]


func spring() -> float:
	return minf(1.5, height - ARCH_HALF - RING - 0.3)


func can_arch() -> bool:
	return spring() >= 0.9


## Arch opening half-width at height `y` above the ground, or -1 where the arch does not reach.
func opening(y: float, ring: bool) -> float:
	var r := ARCH_HALF + (RING if ring else 0.0)
	var s := spring()
	if y < s:
		return ARCH_HALF
	var dy := y - s
	return sqrt(r * r - dy * dy) if dy < r else -1.0


func build(ground: Callable) -> void:
	resample(ground)
	stones.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	live_arches.clear()
	var total := length()
	if total < 0.3:
		return
	if can_arch():
		var piers: Array = corners() if closed else []
		for a in arches:
			if a > ARCH_END and a < total - ARCH_END and piers.all(func(c): return absf(c - a) > ARCH_HALF + RING + PIER * 0.5):
				live_arches.append(a)
	_stone_scale = 1.0
	if closed and corners().is_empty():
		_stone_scale = clampf(total / TAU / 3.0, 0.45, 1.0)
	var courses := maxi(1, int(round(height / COURSE)))
	var course_h := height / courses
	for k in courses:
		var y0 := k * course_h
		var yc := y0 + course_h * 0.5
		var spans := [[0.0, total]]
		for a in live_arches:
			var w := opening(yc, true)
			if w > 0.0:
				spans = _cut(spans, a - w, a + w)
		var offset := (0.5 if k % 2 == 1 else 0.0) * rng.randf_range(0.3, 0.6)
		for span in spans:
			_lay_course(span[0], span[1], y0, course_h, offset, rng)
			_lay_mortar(span[0], span[1], y0, course_h)
	for a in live_arches:
		_lay_ring(a, rng)
	_lay_top(rng)
	for s in corners():
		_lay_pier(s, rng)


func _cut(spans: Array, lo: float, hi: float) -> Array:
	var out := []
	for s in spans:
		if hi <= s[0] or lo >= s[1]:
			out.append(s)
			continue
		if lo > s[0]:
			out.append([s[0], lo])
		if hi < s[1]:
			out.append([hi, s[1]])
	return out


func _lay_course(a: float, b: float, y0: float, h: float, offset: float, rng: RandomNumberGenerator) -> void:
	var s := a
	var first := true
	while b - s > 0.08:
		var want := rng.randf_range(0.42, 0.85) * _stone_scale
		if first:
			want = maxf(0.2, want * (1.0 - offset))
			first = false
		var l := minf(want, b - s)
		if b - s - l < 0.25:
			l = b - s
		var hj := h * rng.randf_range(0.9, 1.04)
		var depth := THICKNESS * rng.randf_range(0.92, 1.05)
		_add(s + l * 0.5, y0 + h * 0.5, Vector3(l, hj, depth), rng, "block", 1.0, 0.035)
		s += l


func _lay_mortar(a: float, b: float, y0: float, h: float) -> void:
	var s := a
	while b - s > 0.02:
		var l := minf(_stone_scale, b - s)
		var frame := frame_at(s + l * 0.5)
		var basis := Basis(frame.tangent, Vector3.UP, frame.tangent.cross(Vector3.UP))
		var size := Vector3(l, h + 0.02, THICKNESS - 0.14)
		stones.append({"xform": Transform3D(basis.scaled_local(size), frame.point + Vector3.UP * (y0 + h * 0.5)), "color": Color(0.32, 0.29, 0.25), "kind": "mortar", "s": s + l * 0.5, "y": y0 + h * 0.5, "size": size, "ao": 0.8, "variant": 0})
		s += l


func _lay_ring(a: float, rng: RandomNumberGenerator) -> void:
	var n := 11
	var r := ARCH_HALF + RING * 0.5
	for i in n:
		var t := (i + 0.5) / n * PI
		var along := a - cos(t) * r
		var up := spring() + sin(t) * r
		var size := Vector3(PI * r / n * 0.98, RING, THICKNESS * 1.04)
		stones.append(_stone(along, up, size, rng, "voussoir", 1.0, 0.0, PI * 0.5 - t))
	var top := spring() + r
	_add(a, top, Vector3(0.34, RING * 1.15, THICKNESS * 1.1), rng, "keystone", 1.05, 0.0)


## Where piers stand: the two ends of an open wall, the sharp corners of a loop.
func corners() -> Array[float]:
	var out: Array[float] = []
	if not closed:
		if length() > 0.0:
			out.assign([0.0, length()])
		return out
	var n := points.size()
	var s := 0.0
	for i in n:
		var a := points[(i + n - 1) % n]
		var b := points[i]
		var c := points[(i + 1) % n]
		var into := Vector2(b.x - a.x, b.z - a.z)
		var out_of := Vector2(c.x - b.x, c.z - b.z)
		if into.length() > 1e-4 and out_of.length() > 1e-4 and absf(into.angle_to(out_of)) > CORNER_TURN:
			out.append(s)
		s += out_of.length()
	return out


func _lay_top(rng: RandomNumberGenerator) -> void:
	var total := length()
	if top == Top.COPE:
		var s := 0.0
		var tall := true
		while total - s > 0.08:
			var l := minf(rng.randf_range(0.11, 0.17), total - s)
			var h := rng.randf_range(0.34, 0.42) if tall else rng.randf_range(0.22, 0.28)
			_add(s + l * 0.5, height + h * 0.5, Vector3(l, h, THICKNESS * 0.86), rng, "cope", 0.97, 0.06)
			tall = not tall
			s += l + 0.012
		return
	var s := 0.0
	while total - s > 0.05:
		var l := minf(rng.randf_range(0.5, 0.95), total - s)
		if total - s - l < 0.3:
			l = total - s
		_add(s + l * 0.5, height + CAP * 0.5, Vector3(l, CAP, THICKNESS + 0.16), rng, "cap", 0.95, 0.02)
		s += l
	if top != Top.CRENEL:
		return
	var m := 0.55
	while m < total - 0.4:
		_add(m, height + CAP + 0.24, Vector3(0.5, 0.48, THICKNESS * 0.8), rng, "merlon", 1.0, 0.03)
		m += 1.15


func _lay_pier(s: float, rng: RandomNumberGenerator) -> void:
	var y := 0.0
	var top_y := height + CAP + (0.0 if roofed else 0.35)
	while y < top_y - 0.05:
		var h := minf(rng.randf_range(0.36, 0.5), top_y - y)
		_add(s, y + h * 0.5, Vector3(PIER, h, PIER) * rng.randf_range(0.97, 1.03), rng, "pier", 0.97, 0.03)
		y += h
	if not roofed:
		_add(s, top_y + 0.09, Vector3(PIER + 0.14, 0.18, PIER + 0.14), rng, "pier", 0.92, 0.0)


func _add(s: float, y: float, size: Vector3, rng: RandomNumberGenerator, kind: String, shade: float, wobble: float) -> void:
	stones.append(_stone(s, y, size, rng, kind, shade, wobble))


func _stone(s: float, y: float, size: Vector3, rng: RandomNumberGenerator, kind: String, shade: float, wobble: float, roll := 0.0) -> Dictionary:
	var frame := frame_at(s)
	var basis := Basis(frame.tangent, Vector3.UP, frame.tangent.cross(Vector3.UP)) * Basis(Vector3.BACK, roll)
	basis = basis * Basis.from_euler(Vector3(rng.randf_range(-wobble, wobble), rng.randf_range(-wobble, wobble) * 2.0, rng.randf_range(-wobble, wobble)))
	var origin: Vector3 = frame.point + Vector3.UP * y
	origin += basis.z * rng.randf_range(-0.015, 0.015)
	var warm := rng.randf_range(-0.05, 0.05)
	var v := rng.randf_range(0.82, 1.08) * shade
	var color := Color(0.66 + warm, 0.61, 0.53 - warm * 1.5) * v
	return {"xform": Transform3D(basis.scaled_local(size), origin), "color": color, "kind": kind, "s": s, "y": y, "size": size, "ao": clampf(0.6 + y * 0.25, 0.6, 1.0), "variant": rng.randi() % 3}


## The built shape without its stones, safe to read on another thread while this one is edited.
func snapshot() -> WallLayout:
	var w := WallLayout.new()
	w.seed = seed
	w.height = height
	w.closed = closed
	w.samples = samples.duplicate()
	w.lengths = lengths.duplicate()
	w.bounds = bounds
	w.live_arches = live_arches.duplicate()
	return w


## Ground point and unit tangent at arc length `s`.
func frame_at(s: float) -> Dictionary:
	var i := lengths.bsearch(s)
	i = clampi(i, 1, samples.size() - 1)
	var l0 := lengths[i - 1]
	var l1 := lengths[i]
	var t := 0.0 if l1 <= l0 else clampf((s - l0) / (l1 - l0), 0.0, 1.0)
	var p := samples[i - 1].lerp(samples[i], t)
	var tan := samples[i] - samples[i - 1]
	tan.y = 0.0
	return {"point": p, "tangent": tan.normalized() if tan.length() > 1e-5 else Vector3.RIGHT}


## Closest arc length on the wall to a world point, measured on the ground plane.
func closest_s(p: Vector3) -> float:
	var best := INF
	var best_s := 0.0
	for i in samples.size():
		var d := Vector2(samples[i].x - p.x, samples[i].z - p.z).length()
		if d < best:
			best = d
			best_s = lengths[i]
	return best_s


func resample(ground: Callable) -> void:
	samples.clear()
	lengths.clear()
	bounds = Rect2()
	if points.size() == 0:
		return
	if closed:
		_resample_loop(ground)
	else:
		_resample_open(ground)
	bounds = Rect2(Vector2(samples[0].x, samples[0].z), Vector2.ZERO)
	for q in samples:
		bounds = bounds.expand(Vector2(q.x, q.z))


func _resample_open(ground: Callable) -> void:
	var dense: Array[Vector3] = []
	if points.size() == 1:
		dense.append(points[0])
	for i in points.size() - 1:
		var p0 := points[maxi(i - 1, 0)]
		var p1 := points[i]
		var p2 := points[i + 1]
		var p3 := points[mini(i + 2, points.size() - 1)]
		var seg := maxi(1, int(ceil(p1.distance_to(p2) / SAMPLE)))
		for j in seg:
			var t := float(j) / seg
			dense.append(_catmull(p0, p1, p2, p3, t))
	if points.size() > 1:
		dense.append(points[-1])
	var acc := 0.0
	for i in dense.size():
		var q := dense[i]
		q.y = ground.call(q.x, q.z) - 0.12
		if i > 0:
			acc += Vector2(q.x - samples[-1].x, q.z - samples[-1].z).length()
		samples.append(q)
		lengths.append(acc)


func _resample_loop(ground: Callable) -> void:
	var dense: Array[Vector3] = []
	var n := points.size()
	for i in n:
		var a := points[i]
		var b := points[(i + 1) % n]
		var seg := maxi(1, int(ceil(a.distance_to(b) / SAMPLE)))
		for j in seg:
			dense.append(a.lerp(b, float(j) / seg))
	dense.append(points[0])
	var foot := INF
	for q in dense:
		foot = minf(foot, ground.call(q.x, q.z))
	var acc := 0.0
	for i in dense.size():
		var q := Vector3(dense[i].x, foot - 0.12, dense[i].z)
		if i > 0:
			acc += Vector2(q.x - samples[-1].x, q.z - samples[-1].z).length()
		samples.append(q)
		lengths.append(acc)


## The centre and radius of the tower a held stroke snaps to, or empty while the stroke is not yet a loop.
static func fit_loop(stroke: Array[Vector3]) -> Dictionary:
	if stroke.size() < 6:
		return {}
	var run := 0.0
	var center := Vector3.ZERO
	for i in stroke.size():
		center += stroke[i]
		if i > 0:
			run += _flat_distance(stroke[i - 1], stroke[i])
	center /= stroke.size()
	if run < LOOP_MIN_RUN or _flat_distance(stroke[0], stroke[-1]) > LOOP_CLOSE:
		return {}
	var radius := 0.0
	for p in stroke:
		radius += _flat_distance(p, center)
	radius /= stroke.size()
	var spread := 0.0
	for p in stroke:
		spread += absf(_flat_distance(p, center) - radius)
	spread /= stroke.size()
	if radius < LOOP_CLOSE * 0.5 or radius > TOWER_RADIUS.y * 1.25 or spread > radius * 0.25:
		return {}
	return {"center": center, "radius": clampf(radius, TOWER_RADIUS.x, TOWER_RADIUS.y)}


static func circle(center: Vector3, radius: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var n := maxi(12, ceili(TAU * radius / 0.35))
	for i in n:
		var a := TAU * i / n
		out.append(center + Vector3(cos(a), 0.0, sin(a)) * radius)
	return out


## Corners of a house footprint whose long axis runs from `a` to `b`, `depth` across.
static func rectangle(a: Vector3, b: Vector3, depth: float) -> Array[Vector3]:
	var along := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var across := along.cross(Vector3.UP).normalized() * depth * 0.5
	return [a - across, b - across, b + across, a + across]


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
