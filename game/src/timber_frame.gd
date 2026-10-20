class_name TimberFrame
extends RefCounted

const WIDTH := 0.16
const DEPTH := 0.10
## How far a roofed wall's top rail sits under its eaves, so its square edge stays under the tiles.
const EAVE_DROP := 0.04
const OAK := Color(0.12, 0.075, 0.045)
const SPACING := 1.8
const BRACES := [Vector4(0, 0, 1, 1), Vector4(1, 0, 0, 1)]

static func applies(w: WallLayout) -> bool:
	return w.timber_style >= 0 and w.plaster and w.closed and not w.fence and w.corners().size() == 4


static func generate(w: WallLayout) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not applies(w):
		return out
	var corners := w.corners()
	corners.append(w.length())
	for side in 4:
		var lo := corners[side]
		var hi := corners[side + 1]
		var mid := (lo + hi) * 0.5
		var foot := w.course_height()
		var eaves := w.height + WallLayout.CAP * 0.5
		var corner := (WallLayout.THICKNESS - WIDTH) * 0.5
		var xs: Array[float] = [lo - corner, hi + corner]
		var holes: Array[Rect2] = []
		var clearance := WIDTH * 0.72 + 0.01
		var frames: Array[Rect2] = []
		for o in w.apertures:
			if o.s > lo and o.s < hi:
				frames.append(Rect2(o.s - o.half, o.sill, o.half * 2.0, o.head - o.sill))
		for f in frames:
			holes.append(f.grow(clearance))
			xs.append(f.position.x - clearance)
			xs.append(f.end.x + clearance)
		var count := ceili((hi - lo) / SPACING)
		for i in range(1, count):
			var x := lerpf(lo, hi, float(i) / count)
			if xs.all(func(v: float) -> bool: return absf(v - x) > SPACING * 0.45):
				xs.append(x)
		xs.sort()
		var ys: Array[float] = [foot, lerpf(foot, eaves, 0.5), eaves]
		for y in ys:
			var rail := y - EAVE_DROP if y == eaves and side % 2 == 0 and w.cover == WallLayout.Cover.ROOF else y
			_emit(out, Vector2(lo - corner, rail), Vector2(hi + corner, rail), mid, holes)
		for x in xs:
			_emit(out, Vector2(x, foot), Vector2(x, eaves), mid, holes)
		for f in frames:
			for y: float in [f.position.y - clearance, f.end.y + clearance]:
				if y >= foot:
					_emit(out, Vector2(f.position.x - clearance, y), Vector2(f.end.x + clearance, y), mid, holes)
		for row in 2:
			for i in xs.size() - 1:
				var panel := Rect2(Vector2(xs[i], ys[row]), Vector2(xs[i + 1] - xs[i], ys[row + 1] - ys[row]))
				if panel.size.x < 0.5 or holes.any(func(h: Rect2) -> bool: return panel.intersects(h)):
					continue
				for brace: Vector4 in BRACES:
					_emit(out, panel.position + panel.size * Vector2(brace.x, brace.y), panel.position + panel.size * Vector2(brace.z, brace.w), mid, holes)
		if side % 2 == 0 or w.gable == null or w.gable.kind != RoofLayout.Kind.GABLE or w.gable.flat() or w.cover != WallLayout.Cover.ROOF or w.gable_end == WallLayout.GableEnd.BOARDS:
			continue
		var hs := (hi - lo + WallLayout.THICKNESS) * 0.5
		var base := w.height + WallLayout.CAP
		if not xs.any(func(x: float) -> bool: return absf(x - mid) < WIDTH):
			xs.append(mid)
			xs.sort()
		for x in xs:
			_emit(out, Vector2(x, eaves), Vector2(x, base + rake(w, hs, absf(x - mid) + WIDTH * 0.5)), mid, [])
		var y := w.gable.rise(1.0) * 0.5
		var reach := 0.0
		var past := hs
		for i in 20:
			if rake(w, hs, (reach + past) * 0.5) > y:
				reach = (reach + past) * 0.5
			else:
				past = (reach + past) * 0.5
		_emit(out, Vector2(mid - reach, base + y), Vector2(mid + reach, base + y), mid, [])
		for sign_x in [-1.0, 1.0]:
			var last := Vector2(mid + sign_x * hs, base + rake(w, hs, hs))
			var segments := maxi(1, ceili(absf(w.gable.curve) * 12.0))
			for i in range(1, segments + 1):
				var x := hs * (1.0 - float(i) / segments)
				var next := Vector2(mid + sign_x * x, base + rake(w, hs, x))
				_emit(out, last, next, mid, [])
				last = next
		for i in xs.size() - 1:
			var top := base + rake(w, hs, maxf(absf(xs[i] - mid), absf(xs[i + 1] - mid)) + WIDTH)
			if top - eaves < 0.35 or xs[i + 1] - xs[i] < 0.5:
				continue
			var panel := Rect2(Vector2(xs[i], eaves), Vector2(xs[i + 1] - xs[i], top - eaves))
			for brace: Vector4 in BRACES:
				_emit(out, panel.position + panel.size * Vector2(brace.x, brace.y), panel.position + panel.size * Vector2(brace.z, brace.w), mid, [])
	return out


## The height over the wall top of a gable end's rake beam's centre line `x` out from the ridge, `hs` out at the faces:
## a beam's width square off the slope rather than straight under it, so its upper edge stays under a steep slope.
static func rake(w: WallLayout, hs: float, x: float) -> float:
	var slope := (w.gable.rise(1.0 - (x - 0.01) / hs) - w.gable.rise(1.0 - (x + 0.01) / hs)) / 0.02
	return w.gable.rise(1.0 - x / hs) - WIDTH * sqrt(1.0 + slope * slope)


static func _emit(out: Array[Dictionary], a: Vector2, b: Vector2, face: float, holes: Array[Rect2]) -> void:
	if a.distance_to(b) < WIDTH or b.y < a.y and is_equal_approx(a.x, b.x):
		return
	var intervals: Array[Vector2] = [Vector2(0, 1)]
	for h in holes:
		var cut := _inside(a, b, h)
		if cut.x >= cut.y:
			continue
		var next: Array[Vector2] = []
		for span in intervals:
			if cut.x > span.x:
				next.append(Vector2(span.x, minf(span.y, cut.x)))
			if cut.y < span.y:
				next.append(Vector2(maxf(span.x, cut.y), span.y))
		intervals = next
	for span in intervals:
		var start := a.lerp(b, span.x)
		var end := a.lerp(b, span.y)
		if start.distance_to(end) >= WIDTH:
			out.append({"a": start, "b": end, "face": face})


static func _inside(a: Vector2, b: Vector2, rect: Rect2) -> Vector2:
	var enter := 0.0
	var leave := 1.0
	for axis in 2:
		var delta := b[axis] - a[axis]
		if absf(delta) < 0.00001:
			if a[axis] <= rect.position[axis] + 0.00001 or a[axis] >= rect.end[axis] - 0.00001:
				return Vector2.ZERO
		else:
			var t0 := (rect.position[axis] - a[axis]) / delta
			var t1 := (rect.end[axis] - a[axis]) / delta
			enter = maxf(enter, minf(t0, t1))
			leave = minf(leave, maxf(t0, t1))
	return Vector2(enter, leave)


static func lay(w: WallLayout) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([w.seed, "timber"])
	for beam in generate(w):
		var center: Vector2 = (beam.a + beam.b) * 0.5
		var run: Vector2 = beam.b - beam.a
		var frame := w.frame_at(beam.face)
		var tangent: Vector3 = frame.tangent
		var normal := tangent.cross(Vector3.UP)
		var x := (tangent * run.x + Vector3.UP * run.y).normalized()
		var origin: Vector3 = frame.point + tangent * (center.x - beam.face) + Vector3.UP * center.y
		origin -= normal * w.inner_side() * (WallLayout.THICKNESS * 0.5 - WallLayout.PLASTER_INSET + DEPTH * 0.35)
		var size := Vector3(run.length() + 0.02, WIDTH, DEPTH)
		w.stones.append({"xform": Transform3D(Basis(x, normal.cross(x), normal).scaled_local(size), origin), "color": OAK * rng.randf_range(0.88, 1.12), "kind": "timber", "s": center.x, "y": center.y, "size": size, "ao": 1.0, "variant": 0, "beam": beam})


static func count(d: Dictionary) -> int:
	if not d.plaster or not d.closed or d.fence or d.points.size() != 4:
		return 0
	var w := WallLayout.new()
	w.points.assign(Array(d.points))
	w.closed = true
	w.plaster = true
	w.height = d.height
	w.timber_style = d.timber_style
	w.gable_end = d.gable_end
	w.resample(func(_x: float, _z: float) -> float: return 0.0)
	w.openings.assign(Array(d.openings))
	w.apertures = w.openings_for(w.openings)
	if d.has("roof"):
		w.cover = WallLayout.Cover.ROOF
		w.gable = RoofLayout.new()
		w.gable.kind = d.roof.kind
		w.gable.pitch = d.roof.pitch
		w.gable.curve = d.roof.curve
	for o in w.apertures:
		if o.style == WallLayout.DoorStyle.ARCHWAY:
			w._lay_arch(o.s, o.size, RandomNumberGenerator.new(), 0.0)
	return generate(w).size() + w.stones.filter(func(s: Dictionary) -> bool: return s.kind == "timber").size()
