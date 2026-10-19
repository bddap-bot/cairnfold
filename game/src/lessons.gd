class_name Lessons
extends RefCounted

## The picture book's pages, one per control a player would not guess from the tool in hand. Each page is a
## script of both hands in head space (metres; x right, y up, -z ahead, the eye at the origin) and of the actions
## held, read by two players: the page's live picture (LessonScene), where ghost controllers act it out, and
## tests/test_lessons.gd, which plays the same script through the real hands into a garden and checks that it
## does what the page shows. A changed control breaks the test until its page is redrawn.
##
## A key's hand pose is `at` and `aim` (the way the controller points) and `roll` (degrees about the aim);
## a hand missing from a key keeps its pose. `book` hands are posed in the held book's frame (Book.local),
## as a hand that touches the page must be. `press` holds an action (Controls.ACTIONS) over [from, to) seconds.
## `setup` is the garden the test plays it in, as Driver steps; `effect` names what the page shows and the test checks; `view` places the page's camera `back` metres behind the hands from what they act on, beside and
## under them for a trigger or grip (`side`) or over them for a button or stick (`top`), widened to hold it all, or from `eye`, with its
## meadow where the first press points or at `dish`, its ghost controllers `ghost` times life size; `tools` what
## each ghost holds at the start, as Hand.Tool names.

const HELD_BOOK := {"at": [-0.06, -0.3, -0.34], "aim": [0.15, -0.55, -1.0]}

const PAGES := [
	{"effect": "page", "length": 3.4, "setup": [{"op": "book", "do": "open", "seconds": 1.2}], "tools": {"left": "book", "right": "walls"}, "book": ["right"],
		"view": {"eye": [0.03, 0.02, 0.02], "ghost": 1.3},
		"keys": [
			{"t": 0.0, "left": HELD_BOOK, "right": {"at": [0.2, 0.09, 0.12], "aim": [-0.2, -1.0, -0.5]}},
			{"t": 0.7, "right": {"at": [0.125, 0.03, 0.07], "aim": [-0.2, -1.0, -0.5]}},
			{"t": 1.5, "right": {"at": [-0.05, 0.035, 0.07], "aim": [-0.3, -1.0, -0.5]}},
			{"t": 2.2, "right": {"at": [-0.06, 0.12, 0.12], "aim": [-0.2, -1.0, -0.5]}},
			{"t": 3.4, "right": {"at": [0.2, 0.09, 0.12], "aim": [-0.2, -1.0, -0.5]}},
		], "press": []},
	{"effect": "tool", "length": 3.2, "tools": {"right": "walls"}, "to": "delete",
		"view": {"look": "top", "back": 0.3},
		"keys": [
			{"t": 0.0, "right": {"at": [0.2, -0.3, -0.42], "aim": [0.0, -0.35, -1.0]}},
			{"t": 0.8, "right": {"at": [0.2, -0.3, -0.42], "aim": [0.0, -0.35, -1.0]}},
			{"t": 1.3, "right": {"at": [0.2, -0.44, -0.42], "aim": [0.0, -0.35, -1.0]}},
			{"t": 2.2, "right": {"at": [0.2, -0.44, -0.42], "aim": [0.0, -0.35, -1.0]}},
			{"t": 3.0, "right": {"at": [0.2, -0.3, -0.42], "aim": [0.0, -0.35, -1.0]}},
		], "press": [{"hand": "right", "action": "wheel", "from": 0.4, "to": 1.8}]},
	{"effect": "teleport", "length": 3.6, "tools": {"left": "hands"},
		"view": {"look": "top", "back": 0.55},
		"keys": [
			{"t": 0.0, "left": {"at": [-0.2, -0.35, -0.32], "aim": [0.0, -0.35, -1.0]}},
		], "press": [{"hand": "left", "action": "teleport", "from": 0.5, "to": 2.0}]},
	{"effect": "undo", "length": 3.8, "setup": [{"op": "wall", "points": [[-2, 3], [2, 3]], "relative": true, "seconds": 0.3}], "tools": {"left": "hands", "right": "hands"},
		"view": {"look": "top", "back": 0.36},
		"keys": [
			{"t": 0.0, "left": {"at": [-0.16, -0.32, -0.36], "aim": [0.1, -0.4, -1.0], "roll": 20.0}, "right": {"at": [0.16, -0.32, -0.36], "aim": [-0.1, -0.4, -1.0], "roll": -20.0}},
		], "press": [{"hand": "left", "action": "undo", "from": 0.8, "to": 1.0}, {"hand": "right", "action": "redo", "from": 2.3, "to": 2.5}]},
	{"effect": "hill", "length": 3.6, "tools": {"right": "walls"},
		"view": {"look": "side", "back": 0.4},
		"keys": [
			{"t": 0.0, "right": {"at": [0.2, -0.42, -0.36], "aim": [0.0, -0.5, -1.0]}},
			{"t": 0.8, "right": {"at": [0.2, -0.42, -0.36], "aim": [0.0, -0.5, -1.0]}},
			{"t": 2.0, "right": {"at": [0.2, -0.14, -0.36], "aim": [0.0, -0.4, -1.0]}},
		], "press": [{"hand": "right", "action": "grab", "from": 0.5, "to": 2.6}]},
	{"effect": "sky", "length": 3.8, "tools": {"right": "walls"},
		"view": {"look": "side", "back": 0.85},
		"keys": [
			{"t": 0.0, "right": {"at": [0.2, -0.25, -0.35], "aim": [-0.7, 1.0, -0.8]}},
			{"t": 0.8, "right": {"at": [0.2, -0.25, -0.35], "aim": [-0.7, 1.0, -0.8]}},
			{"t": 2.4, "right": {"at": [0.2, -0.25, -0.35], "aim": [0.7, 1.0, -0.8]}},
		], "press": [{"hand": "right", "action": "grab", "from": 0.5, "to": 2.8}]},
	{"effect": "colour", "length": 3.8, "setup": [{"op": "house", "at": [0, 5.5], "size": [4.5, 4.5], "relative": true, "seconds": 0.3}], "tools": {"right": "colour"},
		"view": {"look": "side", "back": 0.58},
		"keys": [
			{"t": 0.0, "right": {"at": [0.2, -0.32, -0.36], "aim": [-0.07, -0.3, -1.0]}},
			{"t": 0.9, "right": {"at": [0.2, -0.32, -0.36], "aim": [-0.07, -0.3, -1.0]}},
			{"t": 2.3, "right": {"at": [0.2, -0.32, -0.36], "aim": [-0.07, -0.3, -1.0], "roll": -75.0}},
		], "press": [{"hand": "right", "action": "tool", "from": 0.5, "to": 2.7}]},
	{"effect": "house", "length": 4.2, "tools": {"left": "hands", "right": "house"},
		"view": {"look": "top", "back": 0.42},
		"keys": [
			{"t": 0.0, "left": {"at": [-0.12, -0.36, -0.36], "aim": [0.0, -0.5, -1.0]}, "right": {"at": [0.12, -0.36, -0.36], "aim": [0.0, -0.5, -1.0]}},
			{"t": 1.4, "left": {"at": [-0.12, -0.36, -0.36], "aim": [0.0, -0.5, -1.0]}, "right": {"at": [0.12, -0.36, -0.36], "aim": [0.0, -0.5, -1.0]}},
			{"t": 2.5, "left": {"at": [-0.3, -0.36, -0.36], "aim": [0.0, -0.5, -1.0]}, "right": {"at": [0.3, -0.36, -0.36], "aim": [0.0, -0.5, -1.0]}},
		], "press": [{"hand": "right", "action": "tool", "from": 0.4, "to": 3.0}, {"hand": "left", "action": "grab", "from": 1.0, "to": 3.0}]},
	{"effect": "wipe", "length": 4.6, "setup": [{"op": "wall", "points": [[-3, 4], [3, 4]], "relative": true, "seconds": 0.3}, {"op": "tree", "x": 4, "z": 5, "relative": true}], "tools": {"right": "delete"},
		"view": {"look": "side", "back": 0.48, "dish": [0.1, -0.85, -0.75]},
		"keys": [
			{"t": 0.0, "right": {"at": [0.2, -0.32, -0.32], "aim": [0.0, -0.3, -1.0]}},
			{"t": 0.4, "right": {"at": [0.2, -0.32, -0.32], "aim": [0.0, -0.3, -1.0]}},
			{"t": 0.9, "right": {"at": [0.2, -0.24, -0.3], "aim": [0.0, 1.0, -0.45]}},
		], "press": [{"hand": "right", "action": "tool", "from": 1.0, "to": 1.0 + DeleteTool.WIPE_HOLD + 0.3, "timed": DeleteTool.WIPE_HOLD}]},
]


## `hand`'s pose on `page` at `t` seconds: {at, aim, roll}, eased between the keys that name it.
static func pose(page: Dictionary, hand: String, t: float) -> Dictionary:
	var before: Dictionary = {}
	var t0 := 0.0
	for k in page.keys:
		if not k.has(hand):
			continue
		if k.t <= t or before.is_empty():
			before = k[hand]
			t0 = k.t
			continue
		var w := smoothstep(0.0, 1.0, (t - t0) / maxf(k.t - t0, 1e-3))
		var to: Dictionary = k[hand]
		return {"at": _v(before.at).lerp(_v(to.at), w), "aim": _v(before.aim).normalized().slerp(_v(to.aim).normalized(), w),
			"roll": lerpf(before.get("roll", 0.0), to.get("roll", 0.0), w)}
	if before.is_empty():
		return {}
	return {"at": _v(before.at), "aim": _v(before.aim).normalized(), "roll": before.get("roll", 0.0)}


## The pose as a controller's transform: -z along the aim, rolled about it.
static func frame(p: Dictionary) -> Transform3D:
	var aim: Vector3 = p.aim
	var up := Vector3.UP if absf(aim.y) < 0.95 else Vector3.BACK
	var b := Basis.looking_at(aim, up) * Basis(Vector3.BACK, deg_to_rad(p.roll))
	return Transform3D(b, p.at)


## Whether `hand` holds `action` on `page` at `t`.
static func held(page: Dictionary, hand: String, action: String, t: float) -> bool:
	for p in page.press:
		if p.hand == hand and p.action == action and t >= p.from and t < p.to:
			return true
	return false


## When `hand` began holding `action` on `page`, if it holds it at `t`; else -1.
static func since(page: Dictionary, hand: String, action: String, t: float) -> float:
	for p in page.press:
		if p.hand == hand and p.action == action and t >= p.from and t < p.to:
			return t - p.from
	return -1.0


## Every hand a page poses.
static func hands(page: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for side in ["left", "right"]:
		if page.keys.any(func(k: Dictionary) -> bool: return k.has(side)):
			out.append(side)
	return out


static func tool(name: String) -> Hand.Tool:
	return Hand.Tool[name.to_upper()]


static func _v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])
