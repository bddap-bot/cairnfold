class_name WallPlan
extends RefCounted

## Pure data, so the drawing preview and the walls left on release come from one call. Within REACH of a
## standing wall a stroke merges into it, so a new wall meets an old one at a junction or stands a walkway off.

## Centre to centre: less a wall's thickness, a 1.2 m walkway between parallel walls.
const REACH := 1.8
## A merged stretch ends only this far out, so a hand wavering near REACH does not flicker in and out.
const LEAVE := REACH + 0.4
## Cosine of ~55° off straight at the wall: a shallower stretch ends free, so a stroke drifting near a wall
## grows no spur onto it.
const APPROACH := 0.57
const MIN_LENGTH := 1.0
const OBSTACLE_REACH := 0.6

var standing: Array[WallLayout]
var obstacles: PackedVector3Array
var seed: int
var fence := false
var finish := WallLayout.Finish.BARE
var wear := 0.0
var planks := false
var supports: Array[Massing] = []
## Per stroke point, `_nearest`'s result, recomputed only when the point moves (only the newest does).
var _hits: Array[Dictionary] = []
var _merged: Array[bool] = []
var _along := PackedFloat64Array()
var _starts := PackedInt32Array()


func _init(walls: Array[WallLayout], plants: PackedVector3Array, first_seed: int) -> void:
	standing = walls
	obstacles = plants
	seed = first_seed


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


func tail(stroke: Array[Vector3]) -> float:
	_mark(stroke, mini(_merged.size(), stroke.size()) - 2)
	var end := stroke.size() - 1
	var joined := false
	if _merged[end]:
		if end == 0 or _merged[end - 1]:
			return 0.0
		joined = _heads_at_wall(stroke, end, 1)
		end -= 1
	var i := _starts[end]
	var length := _along[end] - _along[i] + (_flat(_hits[end + 1].point - stroke[end]) if joined else 0.0)
	if i > 0 and _heads_at_wall(stroke, i - 1, -1):
		length += _flat(stroke[i] - _hits[i - 1].point)
	return length


static func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


func _mark(stroke: Array[Vector3], from: int) -> void:
	_hits.resize(stroke.size())
	_merged.resize(stroke.size())
	_along.resize(stroke.size())
	_starts.resize(stroke.size())
	for i in range(maxi(from, 0), stroke.size()):
		if _hits[i].is_empty() or not _hits[i].at.is_equal_approx(stroke[i]):
			_hits[i] = _nearest(stroke[i])
		_merged[i] = _hits[i].distance < (LEAVE if i > 0 and _merged[i - 1] else REACH)
		_along[i] = _along[i - 1] + _flat(stroke[i] - stroke[i - 1]) if i > 0 else 0.0
		_starts[i] = _starts[i - 1] if i > 0 and not _merged[i - 1] else i


func _runs(stroke: Array[Vector3]) -> Array[Array]:
	_mark(stroke, 0)
	var out: Array[Array] = []
	var run: Array[Vector3] = []
	for i in stroke.size():
		if _merged[i]:
			if not run.is_empty():
				if _heads_at_wall(stroke, i, 1):
					run.append(_hits[i].point)
				out.append(run)
				run = []
			continue
		if run.is_empty() and i > 0 and _heads_at_wall(stroke, i - 1, -1):
			run.append(_hits[i - 1].point)
		run.append(stroke[i])
	if not run.is_empty():
		out.append(run)
	return out


func _heads_at_wall(stroke: Array[Vector3], i: int, step: int) -> bool:
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
		if out.is_empty() or s - out[-1] >= WallLayout.ARCADE_GAP:
			out.append(s)
	return out


## Slid clear of the wall's arches so a junction's pier never stands in an opening.
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


## Where arches stand too close to clear them all, the spot farthest from any.
static func _clear_of_arches(w: WallLayout, s: float) -> float:
	var arched := w.apertures.filter(func(o): return o.style == WallLayout.Family.ARCHWAY)
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
		# Spots at an arch's clearance land within rounding of it and count as clear.
		var key := Vector2(minf(room + 0.001, 0.0), -absf(c - s))
		if key > best_key:
			best_key = key
			best = c
	return best


static func _clear(arch: Dictionary) -> float:
	return arch.half + WallLayout.RING * arch.size + WallLayout.PIER * 0.5
