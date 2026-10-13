class_name WallLayout
extends RefCounted

## Lays out the stones of a dry-stone wall along a ground curve. Pure data: no nodes, so tests run headless.

const COURSE := 0.3
const THICKNESS := 0.62
const CAP := 0.14
const SAMPLE := 0.2
const ARCH_HALF := 0.75
const RING := 0.32
const MIN_ARCH_SPAN := 2.4

var points: Array[Vector3] = []
var height := 2.6
var arches: Array[float] = []
var seed := 1

var samples: Array[Vector3] = []
var lengths: Array[float] = []
var stones: Array[Dictionary] = []


func length() -> float:
	return lengths[-1] if lengths.size() > 0 else 0.0


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
	_resample(ground)
	stones.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var total := length()
	if total < 0.3:
		return
	var live_arches: Array[float] = []
	if can_arch():
		for a in arches:
			if a > ARCH_HALF + RING + 0.3 and a < total - ARCH_HALF - RING - 0.3:
				live_arches.append(a)
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
	_lay_cap(rng)
	for s in [0.0, total]:
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
		var want := rng.randf_range(0.42, 0.85)
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
		var l := minf(1.0, b - s)
		var frame := frame_at(s + l * 0.5)
		var basis := Basis(frame.tangent, Vector3.UP, frame.tangent.cross(Vector3.UP))
		var size := Vector3(l + 0.04, h + 0.02, THICKNESS - 0.14)
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


func _lay_cap(rng: RandomNumberGenerator) -> void:
	var total := length()
	var s := 0.0
	while total - s > 0.05:
		var l := minf(rng.randf_range(0.5, 0.95), total - s)
		if total - s - l < 0.3:
			l = total - s
		_add(s + l * 0.5, height + CAP * 0.5, Vector3(l, CAP, THICKNESS + 0.16), rng, "cap", 0.95, 0.02)
		s += l
	var m := 0.55
	while m < total - 0.4:
		_add(m, height + CAP + 0.24, Vector3(0.5, 0.48, THICKNESS * 0.8), rng, "merlon", 1.0, 0.03)
		m += 1.15


func _lay_pier(s: float, rng: RandomNumberGenerator) -> void:
	var w := THICKNESS + 0.28
	var y := 0.0
	var top := height + CAP + 0.35
	while y < top - 0.05:
		var h := minf(rng.randf_range(0.36, 0.5), top - y)
		_add(s, y + h * 0.5, Vector3(w, h, w) * rng.randf_range(0.97, 1.03), rng, "pier", 0.97, 0.03)
		y += h
	_add(s, top + 0.09, Vector3(w + 0.14, 0.18, w + 0.14), rng, "pier", 0.92, 0.0)


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


func _resample(ground: Callable) -> void:
	samples.clear()
	lengths.clear()
	if points.size() == 0:
		return
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


static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
