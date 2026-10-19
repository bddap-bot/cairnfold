class_name ToolWheel
extends RefCounted

## The tool selector as pure data: a wheel of SLOTS facing the head where the hand opened it, each slot a
## leaf, a subtree (an Array) or empty (null). Sweeping the hand onto a slot makes it hot; reaching a
## subtree opens its items beside it (`fan_dirs`), so a deep pick zig-zags left and right. Positions are metres in the wheel's plane, x to the player's right,
## y the player's up as seen along the line to the wheel.

const SLOTS := 8
const RADIUS := 0.12
## Inside this the hand points at nothing, so the wheel opens with nothing hot.
const DEAD := 0.04
## How far toward a subtree the hand must reach before it opens.
const ENTER := RADIUS * 0.85
const SPACING := TAU / SLOTS

## One entry per open level: {centre, items, dirs, hot}. The first is the wheel itself.
var levels: Array[Dictionary] = []


func _init(tree: Array) -> void:
	levels.append(_level(Vector2.ZERO, tree, ring_dirs()))


## The wheel's frame for a hand at `hand` with the head at `head` facing `forward`: z toward the head, so
## the wheel lies flat with the hand under or over the head and stands upright level with it. Its top
## tips away from the player under the head and toward them over it, as the view's top does looking there.
static func facing(hand: Vector3, head: Vector3, forward: Vector3) -> Basis:
	var z := head - hand
	z = z.normalized() if z.length() > 1e-3 else Vector3.BACK
	var ahead := Vector3(forward.x, 0.0, forward.z)
	ahead = ahead.normalized() if ahead.length() > 1e-3 else Vector3.FORWARD
	var up := (Vector3.UP + ahead * z.y).slide(z)
	if up.length() < 1e-3:
		up = ahead.slide(z)
	var y := up.normalized()
	return Basis(y.cross(z), y, z)


## The wheel's slot directions, clockwise from the top as the player sees it.
static func ring_dirs() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in SLOTS:
		out.append(Vector2(sin(SPACING * i), cos(SPACING * i)))
	return out


## A subtree's item directions from the slot at `dir`. Reached by a sideways swing, they stand in a column bowed
## outward on the side away from that swing, top first; reached by an upward or downward one, they are two, one to
## each side, left first.
static func fan_dirs(count: int, dir: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if absf(dir.x) < 0.01:
		assert(count == 2, "a subtree reached by an upward or downward swing holds two")
		out.append(Vector2.LEFT)
		out.append(Vector2.RIGHT)
		return out
	var side := -signf(dir.x)
	for j in count:
		var a := (j - (count - 1) * 0.5) * SPACING
		out.append(Vector2(side * cos(a), -sin(a)))
	return out


## The hand at `p` in the wheel's plane: updates what is hot and opens any subtree it reaches.
func move(p: Vector2) -> void:
	while true:
		var top: Dictionary = levels[-1]
		var v: Vector2 = p - top.centre
		top.hot = -1
		if v.length() >= DEAD:
			var best := -1
			var best_dot := cos(SPACING * 0.5) - 1e-4
			for k in top.items.size():
				var d: float = v.normalized().dot(top.dirs[k])
				if d >= best_dot:
					best = k
					best_dot = d
			top.hot = best
		if top.hot < 0 or not top.items[top.hot] is Array or v.length() < ENTER:
			return
		var dir: Vector2 = top.dirs[top.hot]
		var items: Array = top.items[top.hot]
		levels.append(_level(top.centre + dir * RADIUS, items, fan_dirs(items.size(), dir)))


## The leaf the hand is on, or null.
func chosen() -> Variant:
	var top: Dictionary = levels[-1]
	if top.hot < 0 or top.items[top.hot] is Array:
		return null
	return top.items[top.hot]


## The slot-index path to every leaf of `tree`, keyed by leaf.
static func paths(tree: Array, prefix: Array[int] = []) -> Dictionary:
	var out := {}
	for k in tree.size():
		var path: Array[int] = prefix.duplicate()
		path.append(k)
		if tree[k] is Array:
			out.merge(paths(tree[k], path))
		elif tree[k] != null:
			out[tree[k]] = path
	return out


## The hand positions that sweep from the wheel's centre along `path` to its leaf, one per level.
static func sweep(tree: Array, path: Array[int]) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var centre := Vector2.ZERO
	var dirs := ring_dirs()
	var items := tree
	for k in path:
		var at := centre + dirs[k] * RADIUS
		out.append(at)
		if items[k] is Array:
			items = items[k]
			dirs = fan_dirs(items.size(), dirs[k])
			centre = at
	return out


func _level(centre: Vector2, items: Array, dirs: Array[Vector2]) -> Dictionary:
	assert(items.size() <= dirs.size())
	return {"centre": centre, "items": items, "dirs": dirs, "hot": -1}
