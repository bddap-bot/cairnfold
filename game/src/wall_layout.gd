class_name WallLayout
extends RefCounted

## Lays out the stones of a dry-stone wall along a ground curve, or around a closed loop (a tower or a
## house) standing level on its lowest ground, with its windows, doors, lanterns and flags; or, with the
## fence profile, the posts and rails of a wooden fence. Pure data: no nodes, so tests run headless.

enum Top { CRENEL, CAP, COPE }
## What rests on a closed wall's top: nothing, a pitched roof (the top stops flush under it) or a flat deck
## (the top rises round it as a rim, a cap top as a low parapet).
enum Cover { OPEN, ROOF, DECK }
## How a house's end walls rise under a gable roof: as the wall below, carried up under the slopes; boarded in
## upright planks under barge boards; or stepped up past the slopes in crow steps.
enum GableEnd { WALL, BOARDS, STEPS }

const COURSE := 0.3
const HEIGHTS := Vector2(0.9, 9.0)
## How far a house or tower on the ground may stand raised above its lowest ground, on a plinth of its own courses:
## as high as a build runs long. The budget charges the plinth as stone wall.
const RISE := Vector2(0.0, Commands.MAX_LENGTH)
## The courses under a wall's foot, its plinth, stand this far proud of each face, in stone this much darker, so a
## raised house reads as standing on them.
const PLINTH := Vector2(0.05, 0.86)
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
const MORTAR := Color(0.32, 0.29, 0.25)
## How far mortar stands back from the stones' faces, ends and tops wherever it would show.
const JOINT := 0.07
## How far a plaster wall's face stands back from its stones'.
const PLASTER_INSET := 0.02
## The stones up a gable's rakes: through the wall, and tall.
const VERGE := Vector2(THICKNESS + 0.06, 0.24)
## A boarded gable's planks: how wide, and the gap between them.
const BOARD := Vector2(0.2, 0.012)
## Courses to a crow step at the least, the least a step's tread, and the narrowest the top step stands.
const STEP_COURSES := 2
const TREAD := 0.2
const TOP_STEP := 0.35
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
## How far a loop on the ground stands raised above its lowest ground; the courses under its foot reach down to
## the ground as its plinth.
var rise := 0.0
var arches: Array[float] = []
var seed := 1
## A closed loop runs through its points and back to the first, straight between them.
var closed := false
var top := Top.CRENEL
var cover := Cover.OPEN
## Posts and rails instead of stone; a path through a fence opens a wooden arch.
var fence := false
var plaster := false
var gable_end := GableEnd.WALL
var timber_style := 0
## The gable roof a house's end walls rise under, course by course, as stone walls do; null for any other.
var gable: RoofLayout
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

## The points and plinth the stones were laid along: `points` and `rise` may have moved on while a worker lays them.
var laid_points: Array[Vector3] = []
var laid_rise := 0.0
var samples: Array[Vector3] = []
var lengths: Array[float] = []
## Per sample, how far the ground lies below the foot: a wall over a pond stands at the water and reaches down to its bed.
var depths := PackedFloat32Array()
## Per sample, the ground's height under it.
var grounds := PackedFloat32Array()
## Per sample, how far the plinth reaches below the foot to what the wall stands on: the ground, a pond's surface or a
## build's top. A wall's ivy roots there.
var plinths := PackedFloat32Array()
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
	laid_rise = rise
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
	var faces := _face_spans()
	var course_h := course_height()
	openings = openings_for(windows)
	var bays := pillars()
	var pillar_top := 0.0
	var bands := []
	var sink := 0.0
	for d in depths:
		sink = maxf(sink, d)
	for k in range(-ceili(sink / course_h), courses()):
		var y0 := k * course_h
		var h := minf(course_h, height - y0)
		var yc := y0 + h * 0.5
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
		stream.seed = hash([seed, "course", k])
		var offset := (0.5 if posmod(k, 2) == 1 else 0.0) * stream.randf_range(0.3, 0.6)
		if not plaster or k <= 0:
			for i in spans.size():
				var span: Array = spans[i]
				for face in faces.size():
					var a: float = maxf(span[0], faces[face].x)
					var b: float = minf(span[1], faces[face].y)
					stream.seed = hash([seed, "course", k, i, face])
					_lay_course(a, b, y0, h, offset, stream)
		bands.append([y0, h, spans, breaks[maxi(k, 0)]])
	_lay_mortar(bands)
	for i in live_arches.size():
		rng.seed = hash([seed, "arch", i])
		_lay_ring(live_arches[i], rng)
	for i in bays.size():
		rng.seed = hash([seed, "pillar", i])
		_lay_pillar(bays[i].s, bays[i].half, pillar_top, rng, wet)
	for i in openings.size():
		rng.seed = hash([seed, "opening", i])
		_lay_opening(openings[i], rng)
	rng.seed = hash([seed, "top"])
	if not TimberFrame.applies(self):
		_lay_top(rng)
	_lay_gables()
	TimberFrame.lay(self)
	var turns := corners()
	for i in turns.size():
		var s := turns[i]
		rng.seed = hash([seed, "pier", i])
		if not TimberFrame.applies(self) and not broken(s, PIER * 0.5):
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


## A stone's corners, before its transform.
const BOX: Array[Vector3] = [Vector3(-0.5, -0.5, -0.5), Vector3(0.5, -0.5, -0.5), Vector3(-0.5, 0.5, -0.5), Vector3(0.5, 0.5, -0.5),
	Vector3(-0.5, -0.5, 0.5), Vector3(0.5, -0.5, 0.5), Vector3(-0.5, 0.5, 0.5), Vector3(0.5, 0.5, 0.5)]
## How far under a roof's tiles `fit_under` leaves a cut stone's top, and the thinnest stone it leaves.
const FIT_CLEAR := 0.005
const MIN_FIT := 0.06


## Lowers the tops of the stones up to the wall's top that `r`'s tiles would cut, keeping their feet, and takes away
## those left too thin: a steep slope falls fast past the faces, below a proud stone's outer edge. A gable end, carried
## up under the slopes to its verge, is left as laid.
func fit_under(r: RoofLayout) -> void:
	if r.flat():
		return
	var kept: Array[Dictionary] = []
	for st in stones:
		var fitted := st
		if st.y + st.size.y * 0.5 <= height + CAP + FIT_CLEAR:
			for i in 4:
				var cut := _cut_under(r, fitted.xform)
				if cut <= 0.0:
					break
				var k := 1.0 - cut
				if k * fitted.size.y < MIN_FIT:
					fitted = {}
					break
				var x: Transform3D = fitted.xform
				fitted = fitted.duplicate()
				fitted.xform = Transform3D(Basis(x.basis.x, x.basis.y * k, x.basis.z), x.origin - x.basis.y * (1.0 - k) * 0.5)
				fitted.y -= fitted.size.y * (1.0 - k) * 0.5
				fitted.size = Vector3(fitted.size.x, fitted.size.y * k, fitted.size.z)
		if not fitted.is_empty():
			kept.append(fitted)
	stones = kept


## The share of a stone's height to take off its top to bring it under `r`, or 1 where its foot already pokes through.
static func _cut_under(r: RoofLayout, x: Transform3D) -> float:
	var cut := 0.0
	for c in BOX:
		var p := x * c
		var over := p.y - r.height_at(p.x, p.z) + FIT_CLEAR
		if over > 0.0:
			cut = maxf(cut, 1.0 if c.y < 0.0 else over / x.basis.y.y)
	return cut


## Takes away the tiles, coat, flag, gable ends and torching of the roof on this wall that lie where a build it meets lays nothing.
func hide_roof(r: RoofLayout) -> void:
	if joined.is_empty() and resting.is_empty():
		return
	r.tiles.assign(r.tiles.filter(func(t: Dictionary) -> bool: return not hides(t.xform.origin)))
	r.cloths.assign(r.cloths.filter(func(c: Dictionary) -> bool: return not hides(c.xform.origin)))
	r.keep_coat(func(p: Vector3) -> bool: return not hides(p))
	r.gable_faces = _unhidden(r.gable_faces)
	r.torching_faces = _unhidden(r.torching_faces)


func _unhidden(tris: PackedVector3Array) -> PackedVector3Array:
	var kept := PackedVector3Array()
	for i in range(0, tris.size(), 3):
		var tri := tris.slice(i, i + 3)
		if not hides((tri[0] + tri[1] + tri[2]) / 3.0):
			kept.append_array(tri)
	return kept


## Takes away what lies where a build this one meets lays nothing.
func _hide() -> void:
	if joined.is_empty() and resting.is_empty():
		return
	stones.assign(stones.filter(func(st: Dictionary) -> bool: return not hides(st.xform.origin)))
	flames.assign(flames.filter(func(x: Transform3D) -> bool: return not hides(x.origin)))
	cloths.assign(cloths.filter(func(c: Dictionary) -> bool: return not hides(c.xform.origin)))


func courses() -> int:
	return maxi(1, ceili(height / COURSE - 0.00001))


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


func course_height() -> float:
	return COURSE


## The face normal at arc length `s`, pointing to the side ivy and lanterns call +1.
func _normal(s: float) -> Vector3:
	return frame_at(s).tangent.cross(Vector3.UP)


## The face (+1 or -1, as `_normal` calls it) that looks into a roofed loop, or 0 where both look out.
func inner_side() -> float:
	if not closed or cover == Cover.OPEN:
		return 0.0
	var area := 0.0
	for i in samples.size():
		var a := samples[i]
		var b := samples[(i + 1) % samples.size()]
		area += a.x * b.z - b.x * a.z
	return signf(area)


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


## Whether a window placed at `at` among the windows `placed` would open without closing any they open.
func window_fits(at: Vector2, placed: Array[Vector2]) -> bool:
	var before := openings_for(placed)
	var after := placed.duplicate()
	after.append(at)
	var now := openings_for(after)
	return not _opening_in(now, at.x, at.y).is_empty() and placed.all(func(e): return _opening_in(before, e.x, e.y).is_empty() or not _opening_in(now, e.x, e.y).is_empty())


## The window among `placed` nearest `click` in the opening they make there, or -1 where they make none.
func window_at(click: Vector2, placed: Array[Vector2]) -> int:
	var made := openings_for(placed)
	var o := _opening_in(made, click.x, click.y)
	var near := -1
	if o.is_empty():
		return near
	for i in placed.size():
		var e := placed[i]
		if _opening_in(made, e.x, e.y) == o and (near < 0 or absf(offset(e.x, click.x)) < absf(offset(placed[near].x, click.x))):
			near = i
	return near


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
	while b - s > 0.001:
		var want := rng.randf_range(0.42, 0.85) * _stone_scale
		if first:
			want = maxf(0.2, want * (1.0 - offset))
			first = false
		var l := minf(want, b - s)
		var hj := h * rng.randf_range(0.9, 1.04)
		var depth := THICKNESS * rng.randf_range(0.92, 1.05) + (PLINTH.x * 2.0 if y0 < 0.0 else 0.0)
		_add(s + l * 0.5, y0 + h * 0.5, Vector3(l, hj, depth), rng, "block", PLINTH.y if y0 < 0.0 else 1.0, 0.035)
		s += l


## Mortar, or plaster above the footing, fills each band's spans `[y0, h, spans, broken]` as panels on cells every band
## shares. Mortar stands JOINT back from the stones at every end a span leaves open, a ruin's, a doorway's or the wall's
## own, and on the broken tops under the next band's.
## A panel runs straight between its cell's ends on the ground, so it climbs a slope rather than stepping, and is
## mitred into the next cell (`Masonry.Kind.write`'s `ends`), so a curved face stays closed and shades round. A panel
## with the same ends as the one below grows up instead of stacking on it.
func _lay_mortar(bands: Array, thick := THICKNESS) -> void:
	var cells := _cells()
	var turns := PackedFloat32Array()
	turns.resize(cells.size() + 1)
	for i in range(1, cells.size()):
		turns[i] = cells[i - 1].tangent.signed_angle_to(cells[i].tangent, Vector3.UP) * 0.5
	if closed and cells.size() > 1:
		turns[0] = cells[-1].tangent.signed_angle_to(cells[0].tangent, Vector3.UP) * 0.5
		turns[-1] = turns[0]
	var total := length()
	var panels := []
	var below := {}
	for j in bands.size():
		var y0: float = bands[j][0]
		var face := plaster and y0 > 0.0
		var spans: Array = bands[j][2]
		var bare := _round(bands[j + 1][3] if j + 1 < bands.size() and bands[j + 1].size() > 3 and not face else PackedVector2Array())
		if not face:
			spans = spans.map(func(sp): return [sp[0] + (0.0 if closed and sp[0] < 0.001 else JOINT), sp[1] - (0.0 if closed and sp[1] > total - 0.001 else JOINT)])
		var wraps: bool = closed and spans.any(func(sp): return sp[0] < 0.001) and spans.any(func(sp): return sp[1] > total - 0.001)
		var here := {}
		for span in spans:
			for i in cells.size():
				var c: Dictionary = cells[i]
				var a := maxf(span[0], c.a)
				var b := minf(span[1], c.b)
				if b - a < 0.02:
					continue
				var left: bool = a - c.a < 0.001 and (a - span[0] > 0.001 or wraps and a < 0.001)
				var right: bool = c.b - b < 0.001 and (span[1] - b > 0.001 or wraps and b > total - 0.001)
				var ends := Vector2(clampf(-turns[i], -1.0, 1.0) if left else 0.0, clampf(turns[i + 1], -1.0, 1.0) if right else 0.0)
				for piece in _pieces(a, b, bare):
					var key := "%d %.3f %.3f %s" % [i, piece[0], piece[1], face]
					var p: Dictionary = below.get(key, {})
					var e := Vector2(ends.x if piece[0] == a else 0.0, ends.y if piece[1] == b else 0.0)
					if p.is_empty() or p.ends != e:
						p = {"cell": c, "a": piece[0], "b": piece[1], "y0": y0, "face": face, "ends": e}
						panels.append(p)
					p.top = y0 + bands[j][1] + (-JOINT if piece[2] else 0.02)
					here[key] = p
		below = here
	for p in panels:
		var c: Dictionary = p.cell
		var from: Vector3 = c.from.lerp(c.to, (p.a - c.a) / (c.b - c.a))
		var to: Vector3 = c.from.lerp(c.to, (p.b - c.a) / (c.b - c.a))
		var h: float = p.top - p.y0
		var size := Vector3(p.b - p.a, h, thick - (PLASTER_INSET if p.face else JOINT) * 2.0)
		var basis := Basis(to - from, Vector3.UP * h, c.tangent.cross(Vector3.UP) * size.z)
		var y: float = p.y0 + h * 0.5
		stones.append({"xform": Transform3D(basis, (from + to) * 0.5 + Vector3.UP * y), "color": PLASTER if p.face else MORTAR, "kind": "plaster" if p.face else "mortar", "s": (p.a + p.b) * 0.5, "y": y, "size": size, "ao": 1.0 if plaster else 0.8, "variant": 0, "ends": p.ends})


## The stretches, and round a loop each one a lap either way too, in order.
func _round(stretches: PackedVector2Array) -> Array:
	var out := []
	for b in stretches:
		for lap in ([-1.0, 0.0, 1.0] if closed else [0.0]):
			out.append(b + Vector2.ONE * lap * length())
	out.sort()
	return out


## `a` to `b` split where the stretches `bare` start and stop, each piece `[from, to, is_bare]`.
static func _pieces(a: float, b: float, bare: Array) -> Array:
	var out := []
	var s := a
	for sp in bare:
		var lo := clampf(sp.x, s, b)
		var hi := clampf(sp.y, s, b)
		if hi - lo < 0.001:
			continue
		if lo > s:
			out.append([s, lo, false])
		out.append([lo, hi, true])
		s = hi
	if b > s:
		out.append([s, b, false])
	return out


## The run cut into cells of about a stone's length between corners, each with its ends `a`, `b` in arc length,
## where they stand (`from`, `to`) and its level `tangent`.
func _cells() -> Array[Dictionary]:
	var total := length()
	var stops: Array[float] = [0.0, total]
	for s in corners():
		if s > 0.001 and s < total - 0.001:
			stops.append(s)
	stops.sort()
	var out: Array[Dictionary] = []
	for j in stops.size() - 1:
		var n := maxi(1, ceili((stops[j + 1] - stops[j]) / _stone_scale - 0.25))
		for m in n:
			var a := lerpf(stops[j], stops[j + 1], float(m) / n)
			var b := lerpf(stops[j], stops[j + 1], float(m + 1) / n)
			var from: Vector3 = frame_at(a).point
			var to: Vector3 = frame_at(minf(b, total - 0.0001) if closed else b).point
			var level := Vector3(to.x - from.x, 0.0, to.z - from.z)
			out.append({"a": a, "b": b, "from": from, "to": to, "tangent": level.normalized() if level.length() > 1e-5 else frame_at((a + b) * 0.5).tangent})
	return out


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


## Where piers stand: the two ends and the sharp bends of an open wall, the sharp corners of a loop.
func corners() -> Array[float]:
	var out: Array[float] = []
	if not closed:
		if length() > 0.0:
			out.assign([0.0] + _bends() + [length()])
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


## Where an open wall turns sharply, as a hand draws a corner: the sharpest turn over half a pier either side,
## clear of the ends and of each other by a pier.
func _bends() -> Array[float]:
	var out: Array[float] = []
	var reach := PIER * 0.5
	var turns := PackedFloat32Array()
	for s in lengths:
		var p: Vector3 = frame_at(s).point
		var into: Vector3 = p - frame_at(s - reach).point
		var out_of: Vector3 = frame_at(s + reach).point - p
		var ok := s > PIER and s < length() - PIER
		turns.append(absf(Vector2(into.x, into.z).angle_to(Vector2(out_of.x, out_of.z))) if ok else 0.0)
	for i in range(1, turns.size() - 1):
		if turns[i] > CORNER_TURN and turns[i] >= turns[i - 1] and turns[i] > turns[i + 1]:
			if out.is_empty() or lengths[i] - out[-1] > PIER:
				out.append(lengths[i])
	return out


func _face_spans() -> Array[Vector2]:
	var edges := corners()
	if edges.is_empty() or edges[0] > 0.0:
		edges.push_front(0.0)
	if edges[-1] < length():
		edges.append(length())
	var spans: Array[Vector2] = []
	for i in edges.size() - 1:
		spans.append(Vector2(edges[i], edges[i + 1]))
	return spans


func _lay_top(rng: RandomNumberGenerator) -> void:
	var faces := _face_spans()
	for face in faces.size():
		var spans := [[faces[face].x, faces[face].y]]
		if not breaks.is_empty():
			for b in breaks[-1]:
				spans = _cut(spans, b.x, b.y)
		for i in spans.size():
			rng.seed = hash([seed, "top", face, i])
			_lay_top_span(spans[i][0], spans[i][1], rng)


## Under a pitched roof every top lies flat as a cap, flush with the faces, so the roof rests on its outer edges.
func _lay_top_span(a: float, total: float, rng: RandomNumberGenerator) -> void:
	var style := Top.CAP if cover == Cover.ROOF else top
	if style == Top.COPE:
		var s := a
		var tall := true
		while total - s > 0.001:
			var l := minf(rng.randf_range(0.11, 0.17), total - s)
			var h := rng.randf_range(0.34, 0.42) if tall else rng.randf_range(0.22, 0.28)
			_add(s + l * 0.5, height + h * 0.5, Vector3(l, h, THICKNESS * 0.86), rng, "cope", 0.97, 0.06)
			tall = not tall
			s += l + 0.012
		return
	var s := a
	while total - s > 0.001:
		var l := minf(rng.randf_range(0.5, 0.95), total - s)
		_add(s + l * 0.5, height + CAP * 0.5, Vector3(l, CAP, THICKNESS + (0.0 if cover == Cover.ROOF else 0.16)), rng, "cap", 0.95, 0.02)
		s += l
	if style == Top.CAP and cover == Cover.DECK:
		_lay_parapet(a, total, rng)
	if style != Top.CRENEL:
		return
	rng.seed = hash([rng.seed, "merlon"])
	var edge := a + 0.3
	while edge < total - 0.001:
		var width := minf(0.5, total - edge)
		_add(edge + width * 0.5, height + CAP + 0.24, Vector3(width, 0.48, THICKNESS * 0.8), rng, "merlon", 1.0, 0.03)
		edge += 1.15


func _lay_gables() -> void:
	if gable == null or gable.kind != RoofLayout.Kind.GABLE or gable.flat() or cover != Cover.ROOF:
		return
	var c := corners()
	if c.size() != 4:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, "gable"])
	var h := course_height()
	var base := height + CAP
	var ends := [[c[1], c[2]], [c[3], length()]]
	for i in ends.size():
		var end: Array = ends[i]
		rng.seed = hash([seed, "gable", i])
		var mid: float = (end[0] + end[1]) * 0.5
		var hs: float = (end[1] - end[0] + THICKNESS) * 0.5
		match gable_end:
			GableEnd.BOARDS:
				_lay_boards(mid, hs, base, rng)
				if not gable.thatch:
					_lay_verge(mid, hs, base, rng, "board")
			GableEnd.STEPS:
				_lay_crow_steps(mid, hs, base, h, rng)
			_:
				var rows: Array[Vector2] = []
				while not plaster and _under_slope((rows.size() + 1) * h, hs) >= 0.2:
					rows.append(Vector2(rows.size(), _under_slope((rows.size() + 1) * h, hs)))
				_lay_gable_rows(mid, hs, base, h, rows, rng)
				if not TimberFrame.applies(self) and not gable.thatch:
					_lay_verge(mid, hs, base, rng, "cope")


## Courses up a gable end `hs` out from the ridge each side, each Vector2(course, half-width) about its middle: stone
## laid in mortar, or plaster. Courses stop at the corners rather than turn down the side walls, one reaching out to
## the walls' outer faces on a block filling each corner; the mortar stops JOINT short of a course's ends, behind its stones.
func _lay_gable_rows(mid: float, hs: float, base: float, h: float, rows: Array[Vector2], rng: RandomNumberGenerator) -> void:
	var edge := hs - THICKNESS * 0.5
	var inset := 0.0 if plaster else JOINT
	for row in rows:
		var y := base + row.x * h
		var half := minf(row.y, edge)
		var offset := (0.5 if int(row.x) % 2 == 0 else 0.0) * rng.randf_range(0.3, 0.6)
		for span in _standing([[mid - half, mid + half]]):
			if not plaster:
				_lay_course(span[0], span[1], y, h, offset, rng)
			_lay_mortar([[y, h, [[span[0] + inset, span[1] - inset]]]])
		if row.y > hs - 0.01:
			for side in [-1.0, 1.0]:
				_part(mid + side * edge, y + h * 0.5, Vector3(THICKNESS, h, THICKNESS), PLASTER if plaster else stone_color(rng), rng, "plaster" if plaster else "block")


## A stepped gable end `hs` out from the ridge each side, from the eaves up, as Vector3(half-width, first course,
## courses): each as wide as the slope at its foot and tall enough to leave a tread, the top one tall enough to stand
## over the ridge. Steps above the first stand inside the corners, so every cap lies along the end wall.
func crow_steps(hs: float) -> Array[Vector3]:
	var h := course_height()
	var steps: Array[Vector3] = []
	var k := 0
	var half := hs
	while half > TOP_STEP:
		var top := k + STEP_COURSES
		while _under_slope(top * h, hs) > minf(half, hs - THICKNESS) - TREAD:
			top += 1
		steps.append(Vector3(half, k, top - k))
		k = top
		half = _under_slope(k * h, hs)
	steps.append(Vector3(TOP_STEP, k, maxi(STEP_COURSES, ceili(gable.rise(1.0) / h) + 1 - k)))
	return steps


## The face one gable end `hs` out from the ridge each side stands: under the slopes, or the steps'.
func gable_face(hs: float) -> float:
	if gable_end != GableEnd.STEPS:
		return hs * gable.pitch * (1.0 + gable.curve / PI)
	var out := 0.0
	for st in crow_steps(hs):
		out += 2.0 * st.x * st.z * course_height()
	return out


## Crow steps, each capped where it shows.
func _lay_crow_steps(mid: float, hs: float, base: float, h: float, rng: RandomNumberGenerator) -> void:
	var steps := crow_steps(hs)
	var rows: Array[Vector2] = []
	for st in steps:
		for c in range(st.y, st.y + st.z):
			rows.append(Vector2(c, st.x))
	_lay_gable_rows(mid, hs, base, h, rows, rng)
	for i in steps.size():
		var top := base + (steps[i].y + steps[i].z) * h + CAP * 0.5
		var outer := steps[i].x + 0.06
		if i + 1 == steps.size():
			_add(mid, top, Vector3(outer * 2.0, CAP, THICKNESS + 0.12), rng, "cap", 0.95, 0.0)
			break
		for side in [-1.0, 1.0]:
			_add(mid + side * (steps[i + 1].x + outer) * 0.5, top, Vector3(outer - steps[i + 1].x, CAP, THICKNESS + 0.12), rng, "cap", 0.95, 0.0)


## Upright planks side by side across a gable end, each up to where the slope crosses its outer edge.
func _lay_boards(mid: float, hs: float, base: float, rng: RandomNumberGenerator) -> void:
	var x := -hs
	while x < hs - 0.05:
		var w := minf(BOARD.x, hs - x)
		var tall := gable.rise(1.0 - maxf(absf(x), absf(x + w)) / hs)
		if tall > 0.05 and not _standing([[mid + x, mid + x + w]]).is_empty():
			_part(mid + x + w * 0.5, base + tall * 0.5, Vector3(w - BOARD.y, tall, THICKNESS - PLASTER_INSET * 2.0), WOOD * rng.randf_range(0.85, 1.1), rng, "board")
		x += w


## Pieces of `kind` up each rake over the gable's stepped edge, as long as its curve allows.
func _lay_verge(mid: float, hs: float, base: float, rng: RandomNumberGenerator, kind: String) -> void:
	for side in [-1.0, 1.0]:
		var x := hs
		while x > 0.05:
			var x1 := maxf(x - rng.randf_range(0.42, 0.6), 0.0)
			if x1 < 0.25:
				x1 = 0.0
			var lo := Vector2(x, gable.rise(1.0 - x / hs))
			var hi := Vector2(x1, gable.rise(1.0 - x1 / hs))
			var run := hi - lo
			var at := (lo + hi) * 0.5 - run.orthogonal().normalized() * VERGE.y * 0.5
			if not _standing([[mid + side * at.x - 0.01, mid + side * at.x + 0.01]]).is_empty():
				var roll := atan(run.y / (run.x * side))
				var piece := _stone(mid + side * at.x, base + at.y, Vector3(run.length() + 0.02, VERGE.y, VERGE.x), rng, kind, 0.97, 0.02, roll)
				if kind == "board":
					piece.color = WOOD * rng.randf_range(0.8, 0.95)
				stones.append(piece)
			x = x1


func _standing(spans: Array) -> Array:
	if not breaks.is_empty():
		for b in breaks[-1]:
			spans = _cut(spans, b.x, b.y)
	return spans


## How far out from the ridge the gable's slope stands `rise` above its foot, `hs` out at the faces.
func _under_slope(rise: float, hs: float) -> float:
	var lo := 0.0
	var hi := hs
	for i in 20:
		var x := (lo + hi) * 0.5
		if gable.rise(1.0 - x / hs) > rise:
			lo = x
		else:
			hi = x
	return lo


func _lay_parapet(a: float, total: float, rng: RandomNumberGenerator) -> void:
	rng.seed = hash([rng.seed, "parapet"])
	var y := height + CAP
	var s := a
	while total - s > 0.001:
		var l := minf(rng.randf_range(0.4, 0.75), total - s)
		_add(s + l * 0.5, y + PARAPET * 0.5, Vector3(l, PARAPET, THICKNESS * 0.62), rng, "block", 1.0, 0.02)
		s += l
	_lay_mortar([[y, PARAPET, [[a, total]]]], THICKNESS * 0.62)
	rng.seed = hash([rng.seed, "parapet-cap"])
	s = a
	while total - s > 0.001:
		var l := minf(rng.randf_range(0.6, 1.0), total - s)
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
	w.rise = rise
	w.arches = arches.duplicate()
	w.seed = seed
	w.closed = closed
	w.top = top
	w.cover = cover
	w.fence = fence
	w.plaster = plaster
	w.gable_end = gable_end
	w.timber_style = timber_style
	w.gable = gable
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
	return (points == other.points and height == other.height and rise == other.rise and arches == other.arches
		and seed == other.seed and closed == other.closed and top == other.top
		and cover == other.cover and fence == other.fence and plaster == other.plaster and gable_end == other.gable_end and timber_style == other.timber_style
		and windows == other.windows and lanterns == other.lanterns and flags == other.flags
		and ruins == other.ruins and supports == other.supports and resting == other.resting
		and joined == other.joined)


## Takes what `built` laid, as if `build` had run here.
func adopt(built: WallLayout) -> void:
	laid_points = built.laid_points
	laid_rise = built.laid_rise
	samples = built.samples
	lengths = built.lengths
	depths = built.depths
	plinths = built.plinths
	grounds = built.grounds
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
	w.plinths = plinths.duplicate()
	w.grounds = grounds.duplicate()
	w.bounds = bounds
	w.live_arches = live_arches.duplicate()
	w.openings = openings.duplicate(true)
	w.breaks = breaks.duplicate()
	w.fence = fence
	w.plaster = plaster
	w.cover = cover
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
	return _along(depths, s)


## The ground's height under arc length `s`.
func ground_at(s: float) -> float:
	return _along(grounds, s)


## How far the plinth reaches below the foot at arc length `s`.
func plinth_at(s: float) -> float:
	return _along(plinths, s)


func _along(per_sample: PackedFloat32Array, s: float) -> float:
	if per_sample.size() < 2:
		return 0.0
	if closed:
		s = fposmod(s, length())
	var i := clampi(lengths.bsearch(s), 1, samples.size() - 1)
	var l0 := lengths[i - 1]
	var l1 := lengths[i]
	return lerpf(per_sample[i - 1], per_sample[i], 0.0 if l1 <= l0 else clampf((s - l0) / (l1 - l0), 0.0, 1.0))


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
	plinths.clear()
	grounds.clear()
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
		grounds.append(ground.call(q.x, q.z))
		depths.append(maxf(q.y - grounds[-1], 0.0))
		plinths.append(maxf(q.y + SINK - maxf(footing.call(q.x, q.z), _rest(q.x, q.z)), 0.0))
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
	# On the ground a loop stands level on its lowest ground, raised by `rise`; on other builds, on the highest top under it.
	var foot := INF
	var held := -INF
	for q in dense:
		foot = minf(foot, ground.call(q.x, q.z))
		held = maxf(held, _rest(q.x, q.z))
	if held > -INF:
		foot = held
	else:
		foot += rise
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
