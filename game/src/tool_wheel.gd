class_name ToolWheel
extends RefCounted

## A slot is a leaf, a subtree (an Array) or empty (null). Positions are metres in the wheel's plane, x to the
## player's right, y the player's up as seen along the line to the wheel.

const SLOTS := 8
const RADIUS := 0.12
## So the wheel opens with nothing hot.
const DEAD := 0.04
const ENTER := RADIUS * 0.85
const SPACING := TAU / SLOTS

## Per open level {centre, items, dirs, hot}; [0] is the wheel itself.
var levels: Array[Dictionary] = []


func _init(tree: Array) -> void:
	levels.append(_level(Vector2.ZERO, tree, ring_dirs()))


## z toward the head; the top tips away under the head and toward the player over it, as the view's top does.
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


## Clockwise from the top as the player sees it.
static func ring_dirs() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in SLOTS:
		out.append(Vector2(sin(SPACING * i), cos(SPACING * i)))
	return out


## From a sideways `dir`: a column bowed out away from it, top first. From a vertical one, two items go left
## then right.
static func fan_dirs(count: int, dir: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if absf(dir.x) < 0.01 and count == 2:
		out.append(Vector2.LEFT)
		out.append(Vector2.RIGHT)
		return out
	var side := -signf(dir.x) if absf(dir.x) >= 0.01 else 1.0
	for j in count:
		var a := (j - (count - 1) * 0.5) * SPACING
		out.append(Vector2(side * cos(a), -sin(a)))
	return out


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


func chosen() -> Variant:
	var top: Dictionary = levels[-1]
	if top.hot < 0 or top.items[top.hot] is Array:
		return null
	return top.items[top.hot]


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
