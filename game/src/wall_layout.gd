class_name WallLayout
extends RefCounted

## Lays out the stones of a dry-stone wall along a ground curve, or around a closed loop (a tower or a
## house) standing level on its lowest ground, with its windows, doors, lanterns and flags; or, with the
## fence profile, the posts and rails of a wooden fence. Pure data: no nodes, so tests run headless.

enum Top { CRENEL, CAP, COPE }
## What rests on a closed wall's top: nothing, a pitched roof (the top stops flush under it) or a flat deck
## (the top rises round it as a rim, a cap top as a low parapet).
enum Cover { OPEN, ROOF, DECK }

const COURSE := 0.3
const HEIGHTS := Vector2(0.9, 9.0)
const THICKNESS := 0.62
const CAP := 0.14
const PARAPET := 0.34
const SAMPLE := 0.2
## How far the stones sink below the ground, or into the top of what they stand on.
const SINK := 0.12
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
## Arches whose rings would touch cannot both open; arches nearer than ARCADE_GAP share a pillar.
const ARCH_SPACING := (ARCH_HALF + RING) * 2.0
const ARCADE_GAP := ARCH_SPACING + 0.4
const ARCADE_PITCH := 2.3
## Water under the foot deeper than this opens arches over it.
const WADE_UNDER := 0.1
## How far a paddling duck keeps from the sides of an arch it swims under.
const SWIM_CLEAR := 0.25
const FENCE_HEIGHT := 1.1
const POST_SPACING := 1.6
const GATE_POST := 2.1
const WINDOW_HALF := 0.3
const WINDOW_TALL := 0.9
const DOOR_HALF := 0.5
const DOOR_TALL := 2.0
## A window whose sill would stand lower than this reaches down to the ground as a door.
const DOOR_SILL := 0.6
const MULLION := 0.14
## Windows (or doors) on one course whose centres stand this near fuse into one opening.
const FUSE := WINDOW_HALF * 2.0 + 0.5
const LINTEL_EAR := 0.16
const LANTERN_OUT := 0.34
const FLAG_POLE := 1.7
const FLAG_COLORS := [Color(0.62, 0.12, 0.1), Color(0.14, 0.24, 0.5), Color(0.82, 0.62, 0.18), Color(0.2, 0.38, 0.2)]
const POLE := Color(0.37, 0.26, 0.17)
const FINIAL := Color(0.7, 0.58, 0.3)
const WOOD := Color(0.46, 0.33, 0.21)
const IRON := Color(0.16, 0.15, 0.14)
const GLASS := Color(0.12, 0.17, 0.22)
const PLASTER := Color(0.86, 0.8, 0.68)
## The stone walls are laid in, before each stone's variation.
const STONE := Color(0.66, 0.61, 0.53)
## A ruin's broken ends lean back by up to this much a course, out to at most RUIN_LEAN, ragged by RUIN_JAG.
const RUIN_STEP := Vector2(0.03, 0.22)
const RUIN_LEAN := 1.6
const RUIN_JAG := 0.18
## Fallen stones per metre of ruin.
const RUBBLE := 1.5
## The narrowest stretch an eraser breaks away, and the shortest stub it leaves standing.
const MIN_GAP := 1.0
const MIN_STUB := 0.8
## The spacing of the points a bird may stand on along a wall's top.
const PERCH_STEP := 0.16

var points: Array[Vector3] = []
var height := 2.6
var arches: Array[float] = []
var seed := 1
## A closed loop runs through its points and back to the first, straight between them.
var closed := false
var top := Top.CRENEL
var cover := Cover.OPEN
## Posts and rails instead of stone; a path through a fence opens a wooden arch.
var fence := false
var plaster := false
## Where windows were placed: arc length and the height of the click above the foot.
var windows: Array[Vector2] = []
## Lanterns: arc length, height above the foot, and the face they hang from (+1 or -1).
var lanterns: Array[Vector3] = []
## Flags on the wall's top, by arc length.
var flags: Array[float] = []
## Stretches broken away to the ground, by arc length from and to, each within the wall's length.
var ruins: Array[Vector2] = []
## The builds this one stands on, the builds standing on it and the houses and towers it joins
## (docs/design.md, "Buildings on buildings").
var supports: Array[Massing] = []
var resting: Array[Massing] = []
var joined: Array[Massing] = []
# The fields above are what `build` reads (see `inputs`); those below are what it lays (see `adopt`).

## The points the stones were laid along: `points` may have moved on while a worker lays them.
var laid_points: Array[Vector3] = []
var samples: Array[Vector3] = []
var lengths: Array[float] = []
## Per sample, how far the ground lies below the foot: a wall over a pond stands at the water and reaches down to its bed.
var depths := PackedFloat32Array()
var bounds := Rect2()
var stones: Array[Dictionary] = []
## Stones shorten on a round loop so their outer ends stay closed.
var _stone_scale := 1.0
## The arches `build` could open, after dropping those too near an end or on a wall too low.
var live_arches: Array[float] = []
## The openings `build` cut for the windows that fit, fused where they stand together: arc length `s`,
## half-width `half`, `sill` and `head` heights, `door`, and `lights`, the panes side by side.
var openings: Array[Dictionary] = []
## Lantern flames and flag cloths, laid with the stones; flames are unit boxes, cloths unit quads off the pole.
var flames: Array[Transform3D] = []
var cloths: Array[Dictionary] = []
## Per course from the foot up, the stretches broken away there: each ruin, wider every course up.
var breaks: Array[PackedVector2Array] = []
## Counts the times stones were laid in any layout, by `build` or `adopt`, so what is worked out from a wall's
## stones knows when it is stale, even after the wall takes a new layout.
static var _laid_count := 0
var laid := 0


func length() -> float:
	return lengths[-1] if lengths.size() > 0 else 0.0


## The ground point at arc length `s`.
func point_at(s: float) -> Vector3:
	var i := clampi(lengths.bsearch(s), 0, samples.size() - 1)
	return samples[i]


func spring() -> float:
	return minf(1.5, height - ARCH_HALF - RING - 0.3)


func can_arch() -> bool:
	return fence or spring() >= 0.9


## Arch opening half-width at height `y` above the ground, or -1 where the arch does not reach.
func opening(y: float, ring: bool) -> float:
	var r := ARCH_HALF + (RING if ring else 0.0)
	var s := spring()
	if y < s:
		return ARCH_HALF
	var dy := y - s
	return sqrt(r * r - dy * dy) if dy < r else -1.0


## `water` gives the pond surface at (x, z), below the ground where there is none; without it the ground is dry.
func build(ground: Callable, water := Callable()) -> void:
	resample(ground, water)
	laid_points = points.duplicate()
	_laid_count += 1
	laid = _laid_count
	stones.clear()
	flames.clear()
	cloths.clear()
	openings.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	# Stones under the foot draw from their own stream, so water coming or going leaves the dry stones as they were.
	var wet := RandomNumberGenerator.new()
	wet.seed = hash([seed, "wet"])
	live_arches.clear()
	var total := length()
	if total < 0.3:
		return
	if can_arch():
		var sorted := arches.duplicate()
		sorted.sort()
		for a in sorted + _water_arches():
			if fits_arch(a, live_arches):
				live_arches.append(a)
		live_arches.sort()
	if fence:
		_build_fence(rng)
		_hide()
		return
	_stone_scale = 1.0
	if closed and corners().is_empty():
		_stone_scale = clampf(total / TAU / 3.0, 0.45, 1.0)
	var course_h := course_height()
	openings = openings_for(windows)
	var bays := pillars()
	var pillar_top := 0.0
	var sink := 0.0
	for d in depths:
		sink = maxf(sink, d)
	for k in range(-ceili(sink / course_h), courses()):
		var y0 := k * course_h
		var yc := y0 + course_h * 0.5
		var spans := [[0.0, total]] if k >= 0 else _over_bed(-y0 - course_h)
		for a in live_arches:
			var w := opening(yc, true)
			if w > 0.0:
				spans = _cut(spans, a - w, a + w)
		for o in openings:
			if yc > o.sill and yc < o.head:
				spans = _cut(spans, o.s - o.half, o.s + o.half)
			elif yc > o.head and yc < o.head + course_h:
				spans = _cut(spans, o.s - o.half - LINTEL_EAR, o.s + o.half + LINTEL_EAR)
		if yc < spring():
			pillar_top = y0 + course_h
			for b in bays:
				spans = _cut(spans, b.s - b.half, b.s + b.half)
		for b in breaks[maxi(k, 0)]:
			spans = _cut(spans, b.x, b.y)
		var stream := rng if k >= 0 else wet
		var offset := (0.5 if posmod(k, 2) == 1 else 0.0) * stream.randf_range(0.3, 0.6)
		for span in spans:
			if not plaster or k == 0:
				_lay_course(span[0], span[1], y0, course_h, offset, stream)
			_lay_mortar(span[0], span[1], y0, course_h)
	for a in live_arches:
		_lay_ring(a, rng)
	for p in pillars():
		_lay_pillar(p.s, p.half, pillar_top, rng, wet)
	for o in openings:
		_lay_opening(o, rng)
	_lay_top(rng)
	for s in corners():
		if not broken(s, PIER * 0.5):
			_lay_pier(s, rng, wet)
	_lay_rubble()
	for l in lanterns:
		if lantern_fits(l.x, l.y):
			_lay_lantern(l.x, frame_at(l.x).point + Vector3.UP * l.y, _normal(l.x) * l.z, rng)
	for f in flags:
		if flag_fits(f) and not broken(f, 0.3):
			var parts := flag(frame_at(f).point + Vector3.UP * (height + CAP), frame_at(f).tangent, flag_color(seed, f))
			_world(parts.pole, POLE, "pole", f)
			_world(parts.finial, FINIAL, "finial", f)
			cloths.append(parts.cloth)
	_hide()


## Takes away the tiles, flag and gable ends of the roof on this wall that lie where a build it meets lays nothing.
func hide_roof(r: RoofLayout) -> void:
	if joined.is_empty() and resting.is_empty():
		return
	r.tiles.assign(r.tiles.filter(func(t: Dictionary) -> bool: return not hides(t.xform.origin)))
	r.cloths.assign(r.cloths.filter(func(c: Dictionary) -> bool: return not hides(c.xform.origin)))
	var kept := PackedVector3Array()
	for i in range(0, r.gable_faces.size(), 3):
		var tri := r.gable_faces.slice(i, i + 3)
		if not hides((tri[0] + tri[1] + tri[2]) / 3.0):
			kept.append_array(tri)
	r.gable_faces = kept


## Takes away what lies where a build this one meets lays nothing.
func _hide() -> void:
	if joined.is_empty() and resting.is_empty():
		return
	stones.assign(stones.filter(func(st: Dictionary) -> bool: return not hides(st.xform.origin)))
	flames.assign(flames.filter(func(x: Transform3D) -> bool: return not hides(x.origin)))
	cloths.assign(cloths.filter(func(c: Dictionary) -> bool: return not hides(c.xform.origin)))


func courses() -> int:
	return maxi(1, int(round(height / COURSE)))


## Each ruin's stretch per course, leaning back further every course up so its ends stand as ragged steps.
## A ruin draws from its own stream, so breaking one stretch leaves another's steps as they were.
func _break() -> void:
	var n := courses()
	breaks.resize(n)
	for k in n:
		breaks[k] = PackedVector2Array()
	for r in ruins:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([seed, snappedf(r.x, 0.01)])
		var lean := Vector2.ZERO
		var edge := r
		for k in n:
			edge = Vector2(minf(edge.x, r.x - lean.x - rng.randf() * RUIN_JAG), maxf(edge.y, r.y + lean.y + rng.randf() * RUIN_JAG))
			breaks[k].append(edge)
			lean = (lean + Vector2(rng.randf_range(RUIN_STEP.x, RUIN_STEP.y), rng.randf_range(RUIN_STEP.x, RUIN_STEP.y))).min(Vector2.ONE * RUIN_LEAN)


## Whether arc length `s` lies within `margin` of a stretch broken away at the top, where a ruin is widest.
func broken(s: float, margin := 0.0) -> bool:
	if breaks.is_empty():
		return false
	for b in breaks[-1]:
		if absf(offset(s, (b.x + b.y) * 0.5)) < (b.y - b.x) * 0.5 + margin:
			return true
	return false


## How high the wall stands at arc length `s`: its height, or lower where a ruin's end steps down.
func standing(s: float) -> float:
	for k in breaks.size():
		for b in breaks[k]:
			if absf(offset(s, (b.x + b.y) * 0.5)) < (b.y - b.x) * 0.5:
				return k * course_height()
	return height


## Stones fallen from each ruin, lying in and beside its gap.
func _lay_rubble() -> void:
	for r in ruins:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([seed, snappedf(r.x, 0.01), 1])
		for i in mini(int((r.y - r.x) * RUBBLE * minf(height, 3.0) / 3.0) + 2, 40):
			var s := rng.randf_range(r.x, r.y)
			var size := Vector3(rng.randf_range(0.3, 0.6), rng.randf_range(0.16, 0.28), rng.randf_range(0.24, 0.42))
			var st := _stone(s, size.y * 0.4 - depth_at(s), size, rng, "rubble", 0.92, 0.45, rng.randf_range(-0.5, 0.5))
			st.xform.origin += _normal(s) * rng.randf_range(-0.8, 0.8)
			stones.append(st)


## A wall's `ruins` after the stretch `lo` to `hi` (lo <= hi, unwrapped round a `closed` loop) of its
## `total` length is broken away too: at least MIN_GAP wide, merged with those standing, and no stub
## shorter than MIN_STUB left. Nothing standing is [Vector2(0, total)].
static func ruins_after(ruins: Array[Vector2], total: float, closed: bool, lo: float, hi: float) -> Array[Vector2]:
	if hi - lo < MIN_GAP:
		var mid := (lo + hi) * 0.5
		lo = mid - MIN_GAP * 0.5
		hi = mid + MIN_GAP * 0.5
	var out: Array[Vector2] = []
	var spans: Array[Vector2] = ruins.duplicate()
	if closed:
		if hi - lo >= total:
			out.append(Vector2(0.0, total))
			return out
		var a := fposmod(lo, total)
		var b := a + hi - lo
		spans.append(Vector2(a, minf(b, total)))
		if b > total:
			spans.append(Vector2(0.0, b - total))
	else:
		spans.append(Vector2(maxf(lo, 0.0), minf(hi, total)))
	spans.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.x < q.x)
	var start := 0.0
	for sp in spans:
		if sp.x - start < MIN_STUB and not out.is_empty():
			out[-1].y = maxf(out[-1].y, sp.y)
		elif sp.x - start < MIN_STUB and not closed:
			out.append(Vector2(0.0, sp.y))
		else:
			out.append(sp)
		start = out[-1].y
	if out.is_empty():
		return out
	if not closed and total - out[-1].y < MIN_STUB:
		out[-1].y = total
	if closed and out.size() > 1 and total - out[-1].y + out[0].x < MIN_STUB:
		out[0].x = 0.0
		out[-1].y = total
	var left := total
	for sp in out:
		left -= sp.y - sp.x
	if left < MIN_STUB:
		out.assign([Vector2(0.0, total)])
	return out


## Whole courses fill the wall's height.
func course_height() -> float:
	return height / courses()


## The face normal at arc length `s`, pointing to the side ivy and lanterns call +1.
func _normal(s: float) -> Vector3:
	return frame_at(s).tangent.cross(Vector3.UP)


## The opening a placed window makes on its own, before fusing: a door if its sill would be near the ground.
func opening_for(w: Vector2) -> Dictionary:
	var c := course_height()
	if w.y - WINDOW_TALL * 0.5 < DOOR_SILL:
		return {"s": w.x, "half": DOOR_HALF, "sill": 0.0, "head": roundf(DOOR_TALL / c) * c, "door": true, "lights": 1}
	var sill := roundf((w.y - WINDOW_TALL * 0.5) / c) * c
	return {"s": w.x, "half": WINDOW_HALF, "sill": sill, "head": sill + roundf(WINDOW_TALL / c) * c, "door": false, "lights": 1}


## The openings `placed` windows make on the built wall: neighbours on one course (doors beside doors) fuse,
## round a loop's seam too, and those that fit are kept: under the top with a course left for the lintel,
## clear of the ends, corner piers, arches and each other.
func openings_for(placed: Array[Vector2]) -> Array[Dictionary]:
	var courses_of := {}
	for w in placed:
		var o := opening_for(w)
		var key := roundi(o.sill * 100.0)
		if not courses_of.has(key):
			courses_of[key] = []
		courses_of[key].append(o)
	var fused: Array[Dictionary] = []
	for row in courses_of.values():
		fused.append_array(_fuse(row))
	fused.sort_custom(func(a, b): return a.s < b.s)
	var out: Array[Dictionary] = []
	for o in fused:
		if _opening_fits(o, out):
			out.append(o)
	return out


## Fuses the openings of one course that stand within FUSE of each other into wider ones.
func _fuse(row: Array) -> Array[Dictionary]:
	row.sort_custom(func(a, b): return a.s < b.s)
	if closed and row.size() > 1:
		# Round a loop, the row is read from just past its widest gap, so no run of windows straddles the seam.
		var n := row.size()
		var cut := 0
		var widest := -1.0
		for i in n:
			var gap := fposmod(row[(i + 1) % n].s - row[i].s, length())
			if gap > widest:
				widest = gap
				cut = (i + 1) % n
		row = row.slice(cut) + row.slice(0, cut)
	var out: Array[Dictionary] = []
	var first := 0.0
	var last := 0.0
	for o in row:
		var u: float = row[0].s + fposmod(o.s - row[0].s, length()) if closed else o.s
		if out.is_empty() or u - last >= FUSE:
			out.append(o)
			first = u
		else:
			var into: Dictionary = out[-1]
			into.lights += 1
			into.s = self.wrap((first + u) * 0.5)
			into.half = into.lights * (DOOR_HALF if o.door else WINDOW_HALF) + (into.lights - 1) * MULLION * 0.5
		last = u
	return out


func _opening_fits(o: Dictionary, others: Array[Dictionary]) -> bool:
	if o.head + course_height() > height + 0.01:
		return false
	var side: float = o.half + LINTEL_EAR + PIER * 0.5
	if broken(o.s, side) or (not closed and (o.s < side or o.s > length() - side)):
		return false
	if not corners().all(func(c): return absf(offset(o.s, c)) > side):
		return false
	if not live_arches.all(func(a): return absf(offset(o.s, a)) > o.half + LINTEL_EAR + ARCH_HALF + RING):
		return false
	return others.all(func(e): return absf(offset(o.s, e.s)) > o.half + e.half + LINTEL_EAR * 2.0 or o.sill > e.head + course_height() * 0.5 or e.sill > o.head + course_height() * 0.5)


## The opening at a face point, or empty.
func opening_at(s: float, y: float) -> Dictionary:
	return _opening_in(openings, s, y)


func _opening_in(list: Array[Dictionary], s: float, y: float) -> Dictionary:
	for o in list:
		if absf(offset(s, o.s)) < o.half + 0.05 and y > o.sill - 0.05 and y < o.head + 0.05:
			return o
	return {}


## Whether a window placed at `at` would open without closing any window open now.
func window_fits(at: Vector2) -> bool:
	var after := windows.duplicate()
	after.append(at)
	var now := openings_for(after)
	return not _opening_in(now, at.x, at.y).is_empty() and windows.all(func(e): return opening_at(e.x, e.y).is_empty() or not _opening_in(now, e.x, e.y).is_empty())


## Whether a lantern hangs at face point `s`, `y`: on a stone face clear of every opening, or on a fence post.
func lantern_fits(s: float, y: float) -> bool:
	if fence:
		return true
	if broken(s, 0.3) or y < 0.9 or y > height - 0.2 or (not closed and (s < PIER or s > length() - PIER)):
		return false
	if live_arches.any(func(a): return absf(offset(s, a)) < ARCH_HALF + RING + 0.2):
		return false
	return openings.all(func(o): return absf(offset(s, o.s)) > o.half + LINTEL_EAR + 0.15 or y > o.head + course_height() + 0.3 or y < o.sill - 0.3)


func flag_fits(s: float) -> bool:
	return not fence and cover != Cover.ROOF and (closed or (s > PIER * 0.5 and s < length() - PIER * 0.5))


func _lay_opening(o: Dictionary, rng: RandomNumberGenerator) -> void:
	var s: float = o.s
	var half: float = o.half
	var tall: float = o.head - o.sill
	var c := course_height()
	_part(s, o.head + c * 0.5, Vector3(half * 2.0 + LINTEL_EAR * 2.0, c, THICKNESS * 1.04), stone_color(rng) * 1.05, rng, "lintel")
	if not o.door:
		_part(s, o.sill + 0.04, Vector3(half * 2.0 + 0.16, 0.08, THICKNESS + 0.1), stone_color(rng) * 1.05, rng, "sill")
	for face in [-1.0, 1.0]:
		for edge in [-1.0, 1.0]:
			_part(s + edge * (half + 0.09), o.sill + tall * 0.5, Vector3(0.18, tall, 0.03), PLASTER * rng.randf_range(0.94, 1.02), rng, "plaster", face * (THICKNESS * 0.5 + 0.01))
		if not o.door:
			_part(s, o.sill - 0.1, Vector3(half * 2.0 + 0.36, 0.14, 0.03), PLASTER * rng.randf_range(0.94, 1.02), rng, "plaster", face * (THICKNESS * 0.5 + 0.01))
	var n: int = o.lights
	var light := (half * 2.0 - (n - 1) * MULLION) / n
	for i in n:
		var at := s - half + light * (i + 0.5) + MULLION * i
		if i > 0:
			_part(at - light * 0.5 - MULLION * 0.5, o.sill + tall * 0.5, Vector3(MULLION, tall, THICKNESS * 0.9), stone_color(rng), rng, "mullion")
		if o.door:
			_lay_door(at, light, tall, rng)
		else:
			_lay_window(at, o.sill, light, tall, rng)


## A casement: a dark pane in a wooden frame with a cross of glazing bars, set back in the wall.
func _lay_window(s: float, sill: float, w: float, tall: float, rng: RandomNumberGenerator) -> void:
	var mid := sill + tall * 0.5
	var back := -THICKNESS * 0.12
	_part(s, mid, Vector3(w - 0.02, tall - 0.02, 0.02), GLASS * rng.randf_range(0.9, 1.1), rng, "glass", back)
	for edge in [-1.0, 1.0]:
		_part(s + edge * (w * 0.5 - 0.03), mid, Vector3(0.06, tall, 0.08), WOOD * rng.randf_range(0.85, 1.05), rng, "frame", back)
		_part(s, mid + edge * (tall * 0.5 - 0.03), Vector3(w, 0.06, 0.08), WOOD * rng.randf_range(0.85, 1.05), rng, "frame", back)
	_part(s, mid, Vector3(0.035, tall, 0.05), WOOD, rng, "frame", back)
	_part(s, mid + tall * 0.08, Vector3(w, 0.035, 0.05), WOOD, rng, "frame", back)


## A plank door with two iron straps, set back in the wall.
func _lay_door(s: float, w: float, tall: float, rng: RandomNumberGenerator) -> void:
	var planks := maxi(3, roundi(w / 0.2))
	var back := -THICKNESS * 0.15
	for i in planks:
		var at := s - w * 0.5 + w * (i + 0.5) / planks
		_part(at, tall * 0.5, Vector3(w / planks - 0.012, tall - 0.02, 0.06), WOOD * rng.randf_range(0.75, 1.1), rng, "door", back)
	for y: float in [0.4, tall - 0.45]:
		_part(s, y, Vector3(w - 0.08, 0.06, 0.08), IRON, rng, "iron", back)


## A lantern hanging from an iron arm `out` of the face at `at`, or standing on a post where `out` is zero.
func _lay_lantern(s: float, at: Vector3, out: Vector3, rng: RandomNumberGenerator) -> void:
	var reach := THICKNESS * 0.5 + LANTERN_OUT
	var hang := at + out * reach
	if out.length() > 0.0:
		var arm := Basis(out, Vector3.UP, out.cross(Vector3.UP))
		_world(Transform3D(arm.scaled_local(Vector3(reach + 0.04, 0.04, 0.04)), at + out * reach * 0.5 + Vector3.UP * 0.32), IRON, "iron", s)
		_world(Transform3D(Basis().scaled(Vector3(0.02, 0.1, 0.02)), hang + Vector3.UP * 0.26), IRON, "iron", s)
	var turn := Basis(Vector3.UP, rng.randf() * TAU)
	_world(Transform3D(turn.scaled_local(Vector3(0.2, 0.05, 0.2)), hang + Vector3.UP * 0.19), IRON, "iron", s)
	_world(Transform3D(turn.scaled_local(Vector3(0.16, 0.035, 0.16)), hang - Vector3.UP * 0.07), IRON, "iron", s)
	flames.append(Transform3D(turn.scaled_local(Vector3(0.12, 0.22, 0.12)), hang + Vector3.UP * 0.055))


## A flag standing at `foot`: its `pole` and `finial` transforms, and its `cloth` streaming along `along`.
static func flag(foot: Vector3, along: Vector3, color: Color) -> Dictionary:
	var x := along.normalized()
	var cloth := Basis(x, Vector3.UP, x.cross(Vector3.UP)).scaled_local(Vector3(0.9, 0.55, 1.0))
	return {
		"pole": Transform3D(Basis().scaled(Vector3(0.05, FLAG_POLE, 0.05)), foot + Vector3.UP * FLAG_POLE * 0.5),
		"finial": Transform3D(Basis().scaled(Vector3.ONE * 0.09), foot + Vector3.UP * (FLAG_POLE + 0.04)),
		"cloth": {"xform": Transform3D(cloth, foot + Vector3.UP * (FLAG_POLE - 0.33) + x * 0.03), "color": color},
	}


## A flag keeps its colour through every other edit to its wall.
static func flag_color(wall_seed: int, s: float) -> Color:
	return FLAG_COLORS[posmod(hash([wall_seed, roundi(s * 100.0)]), FLAG_COLORS.size())]


## Where a fence's posts stand, clear of its gates.
func posts() -> Array[float]:
	var total := length()
	var n := maxi(1, ceili(total / POST_SPACING))
	var out: Array[float] = []
	for i in n + 1:
		var s := total * i / n
		if live_arches.all(func(a): return absf(s - a) > ARCH_HALF + 0.4):
			out.append(s)
	return out


## The fence post nearest `s`, where a lantern on the fence stands.
func nearest_post(s: float) -> float:
	var best := INF
	for p in posts():
		if absf(p - s) < absf(best - s):
			best = p
	return best if best != INF else s


## Posts along the ground with two rails between each pair; a gate where a path crosses: two tall posts
## under a bent wooden arch, the rails cut between them.
func _build_fence(rng: RandomNumberGenerator) -> void:
	var standing := posts()
	var gates: Array[float] = []
	for a in live_arches:
		gates.append_array([a - ARCH_HALF - 0.08, a + ARCH_HALF + 0.08])
	var all := standing + gates
	all.sort()
	for i in all.size():
		var s := all[i]
		var tall := FENCE_HEIGHT + (GATE_POST - FENCE_HEIGHT if gates.has(s) else 0.0)
		var d := depth_at(s)
		_part(s, (tall + 0.12 - d) * 0.5, Vector3(0.13, tall + 0.12 + d, 0.13) * rng.randf_range(0.92, 1.08), WOOD * rng.randf_range(0.8, 1.1), rng, "post", 0.0, 0.03)
		if i == 0:
			continue
		var prev := all[i - 1]
		if live_arches.any(func(a): return a > prev and a < s):
			continue
		for y: float in [0.45, 0.85]:
			var a: Vector3 = frame_at(prev).point + Vector3.UP * (y + 0.12)
			var b: Vector3 = frame_at(s).point + Vector3.UP * (y + 0.12)
			var x := (b - a).normalized()
			var z := x.cross(Vector3.UP).normalized()
			_world(Transform3D(Basis(x, z.cross(x), z).scaled_local(Vector3(a.distance_to(b) + 0.06, 0.08, 0.05)), (a + b) * 0.5), WOOD * rng.randf_range(0.8, 1.1), "rail", (prev + s) * 0.5)
	for a in live_arches:
		var r := ARCH_HALF + 0.08
		var squash := 0.5
		var k := 9
		for i in k:
			var t := (i + 0.5) / k * PI
			var size := Vector3(PI * r / k * 1.2, 0.11, 0.1)
			stones.append(_stone(a - cos(t) * r, GATE_POST + 0.04 + sin(t) * r * squash, size, rng, "gate", 1.0, 0.0, atan2(cos(t) * squash, sin(t))))
			stones[-1].color = WOOD * rng.randf_range(0.8, 1.05)
	if standing.is_empty():
		return
	var lit: Array[float] = []
	for l in lanterns:
		var s := nearest_post(l.x)
		if not lit.has(s):
			lit.append(s)
			_lay_lantern(s, frame_at(s).point + Vector3.UP * (FENCE_HEIGHT + 0.25), Vector3.ZERO, rng)


static func stone_color(rng: RandomNumberGenerator) -> Color:
	var warm := rng.randf_range(-0.05, 0.05)
	return Color(STONE.r + warm, STONE.g, STONE.b - warm * 1.5) * rng.randf_range(0.82, 1.08)


## A coloured part on the wall's frame at `s`, `y`, `out` metres off the centre plane toward face +1.
func _part(s: float, y: float, size: Vector3, color: Color, rng: RandomNumberGenerator, kind: String, out := 0.0, wobble := 0.0) -> void:
	var st := _stone(s, y, size, rng, kind, 1.0, wobble)
	st.xform.origin += _normal(s) * out
	st.color = color
	stones.append(st)


## A coloured part placed in world space, filed at arc length `s`.
func _world(xform: Transform3D, color: Color, kind: String, s: float) -> void:
	stones.append({"xform": xform, "color": color, "kind": kind, "s": s, "y": xform.origin.y - frame_at(s).point.y, "size": xform.basis.get_scale(), "ao": 1.0, "variant": stones.size() % 3})


## Removes [lo, hi] from the spans; on a closed loop an opening across the seam is cut at both ends.
func _cut(spans: Array, lo: float, hi: float) -> Array:
	if closed and (lo < 0.0 or hi > length()):
		var shift := length() if lo < 0.0 else -length()
		spans = _cut_span(spans, lo + shift, hi + shift)
	return _cut_span(spans, lo, hi)


func _cut_span(spans: Array, lo: float, hi: float) -> Array:
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
		var size := Vector3(l, h + 0.02, THICKNESS - (0.04 if plaster and y0 > 0.0 else 0.14))
		stones.append({"xform": Transform3D(basis.scaled_local(size), frame.point + Vector3.UP * (y0 + h * 0.5)), "color": PLASTER if plaster and y0 > 0.0 else Color(0.32, 0.29, 0.25), "kind": "plaster" if plaster and y0 > 0.0 else "mortar", "s": s + l * 0.5, "y": y0 + h * 0.5, "size": size, "ao": 1.0 if plaster else 0.8, "variant": 0})
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


## Whether an arch can open at `s` beside `others`: clear of an open wall's ends, a loop's corner piers,
## ruins and the others' rings, measured round a loop.
func fits_arch(s: float, others: Array[float]) -> bool:
	var reach := ARCH_HALF + RING
	if broken(s, reach) or (not closed and (s < ARCH_END or s > length() - ARCH_END)):
		return false
	if closed and not corners().all(func(c): return absf(offset(s, c)) > reach + PIER * 0.5):
		return false
	return others.all(func(o): return absf(offset(s, o)) >= ARCH_SPACING)


## How far along the wall `a` lies past `b`, the short way round a closed loop.
func offset(a: float, b: float) -> float:
	return fposmod(a - b + length() * 0.5, length()) - length() * 0.5 if closed else a - b


## An arc length on this wall: wrapped round a closed loop, clamped to an open wall.
func wrap(s: float) -> float:
	return fposmod(s, length()) if closed else clampf(s, 0.0, length())


## The pillars of the arcades: their arc length and half-width.
func pillars() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var n := live_arches.size()
	for i in range(0 if closed and n > 1 else 1, n):
		var prev := live_arches[(i + n - 1) % n]
		var gap := offset(live_arches[i], prev)
		if gap > 0.0 and gap < ARCADE_GAP:
			out.append({"s": prev + gap * 0.5, "half": gap * 0.5 - ARCH_HALF})
	return out


func _lay_pillar(s: float, half: float, top_y: float, rng: RandomNumberGenerator, wet: RandomNumberGenerator) -> void:
	var w := half * 2.0
	var bed := maxf(maxf(depth_at(s - half), depth_at(s)), depth_at(s + half))
	_lay_footing(s, bed, Vector3(w - 0.1, 0.0, THICKNESS - 0.06), "pillar", wet)
	_add(s, 0.1, Vector3(w + 0.08, 0.2, THICKNESS + 0.1), rng, "pillar", 0.95, 0.02)
	var y := 0.2
	while y < top_y - 0.25:
		var h := minf(rng.randf_range(0.34, 0.46), top_y - 0.18 - y)
		_add(s, y + h * 0.5, Vector3(w - 0.1, h, THICKNESS - 0.06), rng, "pillar", 1.0, 0.02)
		y += h
	_add(s, top_y - 0.09, Vector3(w + 0.1, 0.18, THICKNESS + 0.1), rng, "pillar", 0.95, 0.0)


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
	var spans := [[0.0, length()]]
	if not breaks.is_empty():
		for b in breaks[-1]:
			spans = _cut(spans, b.x, b.y)
	for span in spans:
		_lay_top_span(span[0], span[1], rng)


## Under a pitched roof every top lies flat as a cap.
func _lay_top_span(a: float, total: float, rng: RandomNumberGenerator) -> void:
	var style := Top.CAP if cover == Cover.ROOF else top
	if style == Top.COPE:
		var s := a
		var tall := true
		while total - s > 0.08:
			var l := minf(rng.randf_range(0.11, 0.17), total - s)
			var h := rng.randf_range(0.34, 0.42) if tall else rng.randf_range(0.22, 0.28)
			_add(s + l * 0.5, height + h * 0.5, Vector3(l, h, THICKNESS * 0.86), rng, "cope", 0.97, 0.06)
			tall = not tall
			s += l + 0.012
		return
	var s := a
	while total - s > 0.05:
		var l := minf(rng.randf_range(0.5, 0.95), total - s)
		if total - s - l < 0.3:
			l = total - s
		_add(s + l * 0.5, height + CAP * 0.5, Vector3(l, CAP, THICKNESS + 0.16), rng, "cap", 0.95, 0.02)
		s += l
	if style == Top.CAP and cover == Cover.DECK:
		_lay_parapet(a, total, rng)
	if style != Top.CRENEL:
		return
	var m := a + 0.55
	while m < total - 0.4:
		_add(m, height + CAP + 0.24, Vector3(0.5, 0.48, THICKNESS * 0.8), rng, "merlon", 1.0, 0.03)
		m += 1.15


func _lay_parapet(a: float, total: float, rng: RandomNumberGenerator) -> void:
	var y := height + CAP
	var s := a
	while total - s > 0.05:
		var l := minf(rng.randf_range(0.4, 0.75), total - s)
		if total - s - l < 0.2:
			l = total - s
		_add(s + l * 0.5, y + PARAPET * 0.5, Vector3(l, PARAPET, THICKNESS * 0.62), rng, "block", 1.0, 0.02)
		s += l
	s = a
	while total - s > 0.05:
		var l := minf(rng.randf_range(0.6, 1.0), total - s)
		if total - s - l < 0.3:
			l = total - s
		_add(s + l * 0.5, y + PARAPET + CAP * 0.4, Vector3(l, CAP * 0.8, THICKNESS * 0.74), rng, "cap", 0.95, 0.02)
		s += l


func _lay_pier(s: float, rng: RandomNumberGenerator, wet: RandomNumberGenerator) -> void:
	_lay_footing(s, depth_at(s), Vector3(PIER, 0.0, PIER), "pier", wet)
	var y := 0.0
	var top_y := height + CAP + (0.0 if cover == Cover.ROOF else 0.35)
	while y < top_y - 0.05:
		var h := minf(rng.randf_range(0.36, 0.5), top_y - y)
		_add(s, y + h * 0.5, Vector3(PIER, h, PIER) * rng.randf_range(0.97, 1.03), rng, "pier", 0.97, 0.03)
		y += h
	if cover != Cover.ROOF:
		_add(s, top_y + 0.09, Vector3(PIER + 0.14, 0.18, PIER + 0.14), rng, "pier", 0.92, 0.0)


## Stones from the bed `depth` below the foot up to it, `size` across, under a pillar or pier standing in water.
func _lay_footing(s: float, depth: float, size: Vector3, kind: String, rng: RandomNumberGenerator) -> void:
	var y := -depth
	while y < -0.05:
		var h := minf(rng.randf_range(0.34, 0.46), -y)
		_add(s, y + h * 0.5, Vector3(size.x, h, size.z), rng, kind, 0.95, 0.02)
		y += h


func _add(s: float, y: float, size: Vector3, rng: RandomNumberGenerator, kind: String, shade: float, wobble: float) -> void:
	stones.append(_stone(s, y, size, rng, kind, shade, wobble))


func _stone(s: float, y: float, size: Vector3, rng: RandomNumberGenerator, kind: String, shade: float, wobble: float, roll := 0.0) -> Dictionary:
	var frame := frame_at(s)
	var basis := Basis(frame.tangent, Vector3.UP, frame.tangent.cross(Vector3.UP)) * Basis(Vector3.BACK, roll)
	basis = basis * Basis.from_euler(Vector3(rng.randf_range(-wobble, wobble), rng.randf_range(-wobble, wobble) * 2.0, rng.randf_range(-wobble, wobble)))
	var origin: Vector3 = frame.point + Vector3.UP * y
	origin += basis.z * rng.randf_range(-0.015, 0.015)
	var color := stone_color(rng) * shade
	return {"xform": Transform3D(basis.scaled_local(size), origin), "color": color, "kind": kind, "s": s, "y": y, "size": size, "ao": clampf(0.6 + y * 0.25, 0.6, 1.0), "variant": rng.randi() % 3}


## Where a small bird can stand on the wall's top, in world space: along the top of every cap, coping stone,
## merlon and pier, a fence's upper rails and its posts, a step apart, and only the highest where they
## overlap; none on a roofed wall, none beside a flag or a lantern.
func perches() -> PackedVector3Array:
	var out := PackedVector3Array()
	if cover == Cover.ROOF:
		return out
	var tops: Array[Vector3] = []
	var fittings: Array[Vector3] = []
	for st in stones:
		var kind: String = st.kind
		var x: Transform3D = st.xform
		if kind in ["pole", "iron", "finial"]:
			fittings.append(x.origin)
			continue
		if not (kind in ["cap", "cope", "merlon", "pier", "post"] or kind == "rail" and st.y > FENCE_HEIGHT * 0.6):
			continue
		var top := x.origin + x.basis.y * 0.5
		var run := x.basis.x
		var n := maxi(1, floori(run.length() / PERCH_STEP))
		for i in n:
			tops.append(top + run * ((i + 0.5) / n - 0.5))
	tops.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y > b.y)
	var taken := {}
	for p in tops:
		var cell := Vector2i(floori(p.x / PERCH_STEP), floori(p.z / PERCH_STEP))
		var clear := true
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				for q: Vector3 in taken.get(cell + Vector2i(dx, dz), []):
					if Vector2(q.x - p.x, q.z - p.z).length() < PERCH_STEP:
						clear = false
		if fittings.any(func(f: Vector3) -> bool: return Vector2(f.x - p.x, f.z - p.z).length() < 0.3):
			clear = false
		if clear:
			taken.get_or_add(cell, []).append(p)
			out.append(p)
	return out


## A copy of what `build` reads, to build on another thread while this one is edited.
func inputs() -> WallLayout:
	var w := WallLayout.new()
	w.points = points.duplicate()
	w.height = height
	w.arches = arches.duplicate()
	w.seed = seed
	w.closed = closed
	w.top = top
	w.cover = cover
	w.fence = fence
	w.plaster = plaster
	w.windows = windows.duplicate()
	w.lanterns = lanterns.duplicate()
	w.flags = flags.duplicate()
	w.ruins = ruins.duplicate()
	w.supports = supports.duplicate()
	w.resting = resting.duplicate()
	w.joined = joined.duplicate()
	return w


## Whether `other` would lay the same stones on the same ground.
func same_inputs(other: WallLayout) -> bool:
	var a := inputs()
	var b := other.inputs()
	for p in a.get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and a.get(p.name) != b.get(p.name):
			return false
	return true


## Takes what `built` laid, as if `build` had run here.
func adopt(built: WallLayout) -> void:
	laid_points = built.laid_points
	samples = built.samples
	lengths = built.lengths
	depths = built.depths
	bounds = built.bounds
	stones = built.stones
	_stone_scale = built._stone_scale
	live_arches = built.live_arches
	openings = built.openings
	flames = built.flames
	cloths = built.cloths
	breaks = built.breaks
	_laid_count += 1
	laid = _laid_count


## The built shape without its stones, safe to read on another thread while this one is edited.
func snapshot() -> WallLayout:
	var w := WallLayout.new()
	w.seed = seed
	w.height = height
	w.closed = closed
	w.samples = samples.duplicate()
	w.lengths = lengths.duplicate()
	w.depths = depths.duplicate()
	w.bounds = bounds
	w.live_arches = live_arches.duplicate()
	w.openings = openings.duplicate(true)
	w.breaks = breaks.duplicate()
	w.fence = fence
	w.plaster = plaster
	w.resting = resting.duplicate()
	w.joined = joined.duplicate()
	return w


## Ground point and unit tangent at arc length `s`.
func frame_at(s: float) -> Dictionary:
	if closed and lengths.size() > 1:
		s = fposmod(s, length())
	var i := lengths.bsearch(s)
	i = clampi(i, 1, samples.size() - 1)
	var l0 := lengths[i - 1]
	var l1 := lengths[i]
	var t := 0.0 if l1 <= l0 else clampf((s - l0) / (l1 - l0), 0.0, 1.0)
	var p := samples[i - 1].lerp(samples[i], t)
	var tan := samples[i] - samples[i - 1]
	tan.y = 0.0
	return {"point": p, "tangent": tan.normalized() if tan.length() > 1e-5 else Vector3.RIGHT}


## How far the ground lies below the foot at arc length `s`.
func depth_at(s: float) -> float:
	if depths.size() < 2:
		return 0.0
	if closed:
		s = fposmod(s, length())
	var i := clampi(lengths.bsearch(s), 1, samples.size() - 1)
	var l0 := lengths[i - 1]
	var l1 := lengths[i]
	return lerpf(depths[i - 1], depths[i], 0.0 if l1 <= l0 else clampf((s - l0) / (l1 - l0), 0.0, 1.0))


## The stretches where the ground lies deeper below the foot than `drop`, as spans of arc length.
func _over_bed(drop: float) -> Array:
	var out := []
	var from := -1.0
	for i in samples.size():
		if depths[i] > drop and from < 0.0:
			from = lengths[maxi(i - 1, 0)]
		elif depths[i] <= drop and from >= 0.0:
			out.append([from, lengths[i]])
			from = -1.0
	if from >= 0.0:
		out.append([from, length()])
	return out


## An open wall over water opens arches where it crosses: one over a narrow crossing, an arcade on pillars
## standing in the pond over a wider one.
func _water_arches() -> Array[float]:
	var out: Array[float] = []
	if closed or fence:
		return out
	for span in _over_bed(WADE_UNDER):
		var between: float = maxf(span[1] - span[0] - ARCH_HALF * 2.0, 0.0)
		var n := floori(between / ARCH_SPACING) + 1
		var pitch := minf(between / (n - 1), ARCADE_PITCH) if n > 1 else 0.0
		var first: float = (span[0] + span[1] - pitch * (n - 1)) * 0.5
		for i in n:
			out.append(first + pitch * i)
	return out


## Whether a duck paddling straight from `a` to `b` would meet this wall: anywhere along a stone wall but
## under an arch; a fence's rails stand clear over the water.
func blocks_swim(a: Vector2, b: Vector2) -> bool:
	if fence or not bounds.grow(THICKNESS).intersects(Rect2(a, Vector2.ZERO).expand(b).grow(0.01)):
		return false
	for i in samples.size() - 1:
		var p := Vector2(samples[i].x, samples[i].z)
		var q := Vector2(samples[i + 1].x, samples[i + 1].z)
		var hit: Variant = Geometry2D.segment_intersects_segment(a, b, p, q)
		if hit == null:
			continue
		if not _swims_through(lengths[i] + p.distance_to(hit)):
			return true
	var end := closest_s(Vector3(b.x, 0.0, b.y))
	var at: Vector3 = frame_at(end).point
	return Vector2(at.x, at.z).distance_to(b) < THICKNESS * 0.5 + SWIM_CLEAR and not _swims_through(end)


func _swims_through(s: float) -> bool:
	return broken(s, -SWIM_CLEAR) or live_arches.any(func(c): return absf(offset(s, c)) < ARCH_HALF - SWIM_CLEAR)


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


## The ground curve, and the ruins' breaks along it, for the inputs as they stand.
func resample(ground: Callable, water := Callable()) -> void:
	samples.clear()
	lengths.clear()
	depths.clear()
	breaks.clear()
	bounds = Rect2()
	if points.size() == 0:
		return
	if not fence:
		_break()
	var footing := ground
	if water.is_valid():
		footing = func(x: float, z: float) -> float: return maxf(ground.call(x, z), water.call(x, z))
	if closed:
		_resample_loop(footing)
	else:
		_resample_open(footing)
	for q in samples:
		depths.append(maxf(q.y - ground.call(q.x, q.z), 0.0))
	bounds = Rect2(Vector2(samples[0].x, samples[0].z), Vector2.ZERO)
	for q in samples:
		bounds = bounds.expand(Vector2(q.x, q.z))


func _resample_open(ground: Callable) -> void:
	var dense: Array[Vector3] = []
	smooth(points, func(q: Vector3, _i: int, _t: float): dense.append(q))
	var acc := 0.0
	for i in dense.size():
		var q := dense[i]
		q.y = maxf(ground.call(q.x, q.z), _rest(q.x, q.z)) - SINK
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
	# On the ground a loop stands level on its lowest ground; on other builds, on the highest top under it.
	var foot := INF
	var held := -INF
	for q in dense:
		foot = minf(foot, ground.call(q.x, q.z))
		held = maxf(held, _rest(q.x, q.z))
	if held > -INF:
		foot = held
	var acc := 0.0
	for i in dense.size():
		var q := Vector3(dense[i].x, foot - SINK, dense[i].z)
		if i > 0:
			acc += Vector2(q.x - samples[-1].x, q.z - samples[-1].z).length()
		samples.append(q)
		lengths.append(acc)


## The highest top of the builds under (x, z), or -INF.
func _rest(x: float, z: float) -> float:
	var best := -INF
	for s in supports:
		var h := s.rest(x, z)
		if not is_nan(h):
			best = maxf(best, h)
	return best


## Whether `p` lies where a build this one meets lays nothing: in a house or tower it joins, or under a build
## standing on it.
func hides(p: Vector3) -> bool:
	for s in joined:
		if s.holds(p):
			return true
	for s in resting:
		if s.covers(p):
			return true
	return false


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


## Visits Catmull-Rom samples through an open stroke, SAMPLE apart and ending on its last point, as
## `each(sample, i, t)`: `t` of the way from point `i` to the next.
static func smooth(stroke: Array[Vector3], each: Callable) -> void:
	for i in stroke.size() - 1:
		var p0 := stroke[maxi(i - 1, 0)]
		var p3 := stroke[mini(i + 2, stroke.size() - 1)]
		var seg := maxi(1, int(ceil(stroke[i].distance_to(stroke[i + 1]) / SAMPLE)))
		for j in seg:
			var t := float(j) / seg
			each.call(_catmull(p0, stroke[i], stroke[i + 1], p3, t), i, t)
	if stroke.size() > 0:
		each.call(stroke[-1], stroke.size() - 1, 0.0)


static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
