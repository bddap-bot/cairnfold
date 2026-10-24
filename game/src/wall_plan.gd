class_name WallPlan
extends RefCounted

## Turns a hand-drawn stroke into the walls it builds among those already standing. Pure data, so the
## preview while drawing and the walls left on release come from the same call.
##
## Where the stroke comes within REACH of a standing wall it merges into that wall: the stretch is dropped,
## and a stretch heading into the wall is extended onto its centre line, so a new wall meets an old one at a
## junction or stands at least a walkway from it, never crowded alongside it.

## Centre line to centre line; less a wall's thickness this leaves a 1.2 m walkway between parallel walls.
const REACH := 1.8
## A merged stretch ends only this far out, so a hand wavering near REACH does not flicker in and out.
const LEAVE := REACH + 0.4
## A stretch meets the wall it runs into only when heading at it more steeply than this (cosine of ~55°
## off straight at it); a shallower one ends free, so a stroke drifting near a wall grows no spur onto it.
const APPROACH := 0.57
const MIN_LENGTH := 1.0
## A plant this near the centre line stands in the wall's way, so the wall arches over it.
const OBSTACLE_REACH := 0.6

var standing: Array[WallLayout]
var obstacles: PackedVector3Array
var seed: int
## The stroke draws a fence: low posts and rails, with no arches over plants.
var fence := false
## What the stroke's faces are, and how worn its plaster.
var finish := WallLayout.Finish.BARE
var wear := 0.0
var planks := false
## The builds the stroke is drawn on top of.
var supports: Array[Massing] = []
## Each stroke point's nearest standing wall, kept while the point stays put: only the newest point moves.
var _hits: Array[Dictionary] = []


func _init(walls: Array[WallLayout], plants: PackedVector3Array, first_seed: int) -> void:
	standing = walls
	obstacles = plants
	seed = first_seed


## The walls `stroke` builds, traced on the ground with their arches set; `build` lays their stones.
func pieces(stroke: Array[Vector3], ground: Callable, commit := false) -> Array[WallLayout]:
	var out: Array[WallLayout] = []
	for run in _runs(stroke):
		var w := WallLayout.new()
		w.seed = seed + out.size()
		w.points = run
		w.fence = fence
		w.finish = finish
		w.wear = wear
		w.planks = planks
		if fence:
			w.height = WallLayout.FENCE_HEIGHT
		w.supports = supports.duplicate()
		w.resample(ground)
		if commit:
			w.finish_stroke()
			w.resample(ground)
		if w.length() < MIN_LENGTH:
			continue
		w.openings.assign(arches_for(w).map(WallLayout.archway))
		out.append(w)
	return out


func _runs(stroke: Array[Vector3]) -> Array[Array]:
	_hits.resize(stroke.size())
	for i in stroke.size():
		if _hits[i].is_empty() or not _hits[i].at.is_equal_approx(stroke[i]):
			_hits[i] = _nearest(stroke[i])
	var merged: Array[bool] = []
	for i in stroke.size():
		var limit := LEAVE if i > 0 and merged[-1] else REACH
		merged.append(_hits[i].distance < limit)
	var out: Array[Array] = []
	var run: Array[Vector3] = []
	for i in stroke.size():
		if merged[i]:
			if not run.is_empty():
				if _steep(stroke, i, 1):
					run.append(_hits[i].point)
				out.append(run)
				run = []
			continue
		if run.is_empty() and i > 0 and _steep(stroke, i - 1, -1):
			run.append(_hits[i - 1].point)
		run.append(stroke[i])
	if not run.is_empty():
		out.append(run)
	return out


## Whether the stroke reaching point `i` from the point `step` behind it heads at its nearest wall.
func _steep(stroke: Array[Vector3], i: int, step: int) -> bool:
	var a := stroke[clampi(i - step, 0, stroke.size() - 1)]
	var b := stroke[i]
	var to: Vector3 = _hits[i].point - b
	var dir := Vector2(b.x - a.x, b.z - a.z)
	var at := Vector2(to.x, to.z)
	if dir.length() < 1e-4 or at.length() < 1e-4:
		return false
	return dir.normalized().dot(at.normalized()) > APPROACH


func arches_for(w: WallLayout) -> Array[float]:
	var out: Array[float] = []
	if w.fence or not w.can_arch():
		return out
	var hi := w.length() - WallLayout.ARCH_END
	var spacing := WallLayout.ARCADE_GAP
	var box := w.bounds.grow(OBSTACLE_REACH)
	var found: Array[float] = []
	for o in obstacles:
		if not box.has_point(Vector2(o.x, o.z)):
			continue
		var s := w.closest_s(o)
		var c := w.point_at(s)
		if Vector2(c.x - o.x, c.z - o.z).length() < OBSTACLE_REACH and s >= WallLayout.ARCH_END and s <= hi:
			found.append(s)
	found.sort()
	for s in found:
		if out.is_empty() or s - out[-1] >= spacing:
			out.append(s)
	return out


## The nearest point on any standing wall's centre line, moved clear of the wall's arches so a junction's
## pier never stands in an opening.
func _nearest(p: Vector3) -> Dictionary:
	var best := {"at": p, "distance": INF, "point": p}
	var at := Vector2(p.x, p.z)
	var best_wall: WallLayout
	var best_s := 0.0
	for w in standing:
		if not w.bounds.grow(LEAVE).has_point(at):
			continue
		var s := w.samples
		for k in s.size() - 1:
			var a := Vector2(s[k].x, s[k].z)
			var q := Geometry2D.get_closest_point_to_segment(at, a, Vector2(s[k + 1].x, s[k + 1].z))
			var d := q.distance_to(at)
			if d < best.distance:
				best.distance = d
				best_wall = w
				best_s = w.lengths[k] + q.distance_to(a)
	if best_wall == null:
		return best
	var q: Vector3 = best_wall.frame_at(_clear_of_arches(best_wall, best_s)).point
	best.point = Vector3(q.x, p.y, q.z)
	return best


## The nearest arc length to `s` where a junction's pier stands clear of every arch opening; where arches
## stand too close for that, the spot farthest from any of them.
static func _clear_of_arches(w: WallLayout, s: float) -> float:
	var arched := w.apertures.filter(func(o): return o.style == WallLayout.DoorStyle.ARCHWAY)
	if arched.is_empty():
		return s
	var spots: Array[float] = [s, 0.0, w.length()]
	for o in arched:
		spots.append_array([o.s - _clear(o), o.s + _clear(o)])
	var best := s
	var best_key := Vector2(-INF, 0.0)
	for c in spots:
		if c < 0.0 or c > w.length():
			continue
		var room := INF
		for o in arched:
			room = minf(room, absf(c - o.s) - _clear(o))
		# The spots at an arch's clearance land within rounding of it, and count as clear.
		var key := Vector2(minf(room + 0.001, 0.0), -absf(c - s))
		if key > best_key:
			best_key = key
			best = c
	return best


static func _clear(arch: Dictionary) -> float:
	return arch.half + WallLayout.RING * arch.size + WallLayout.PIER * 0.5
