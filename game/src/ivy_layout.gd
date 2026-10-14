class_name IvyLayout
extends RefCounted

## Ivy climbing both faces of a wall: vines start at the foot, wander upward, branch, and
## steer around arch openings. Pure data: no nodes, so tests run headless.

const STEP := 0.1
const RATE := 0.15
const END := 0.6
const MARGIN := 0.1
const FACE := WallLayout.THICKNESS * 0.53 + 0.02
const GREENS := [Color(0.13, 0.27, 0.07), Color(0.17, 0.33, 0.08), Color(0.11, 0.24, 0.09)]
const YOUNG := Color(0.36, 0.52, 0.14)


## Leaves of a built wall in the order they grow, each with `t`, the seconds after the wall was finished it appears.
static func grow(wall: WallLayout) -> Array[Dictionary]:
	var leaves: Array[Dictionary] = []
	var total := wall.length()
	if total < END * 2.0 + 0.4:
		return leaves
	var rng := RandomNumberGenerator.new()
	rng.seed = wall.seed * 7919 + 13
	for side in [-1.0, 1.0]:
		var s := END + rng.randf_range(0.0, 1.4)
		while s < total - END:
			if rng.randf() < 0.85 and not blocked(wall, s, 0.05):
				_vine(wall, Vector2(s, 0.02), Vector2.UP, side, rng.randf_range(0.0, 3.0), 0, rng, leaves)
			s += rng.randf_range(0.8, 1.8)
	leaves.sort_custom(func(a, b): return a.t < b.t)
	return leaves


## Whether the face point `s` along the wall, `y` above its foot, lies in an arch opening or its ring.
static func blocked(wall: WallLayout, s: float, y: float) -> bool:
	for a in wall.live_arches:
		var w := wall.opening(y, true)
		if w > 0.0 and absf(s - a) < w + MARGIN:
			return true
	return false


static func _vine(wall: WallLayout, at: Vector2, dir: Vector2, side: float, t: float, depth: int, rng: RandomNumberGenerator, leaves: Array[Dictionary]) -> void:
	var top := wall.height - 0.06
	var reach := top * rng.randf_range(0.55, 1.0) * (1.0 if depth == 0 else 0.6)
	var walked := 0.0
	while walked < reach:
		dir = (dir + Vector2(rng.randf_range(-0.45, 0.45), 0.2)).normalized()
		var next := at + dir * STEP
		if blocked(wall, next.x, next.y):
			dir = Vector2(signf(next.x - _nearest_arch(wall, next.x)), 0.35).normalized()
			next = at + dir * STEP
			if blocked(wall, next.x, next.y):
				return
		if next.x < END or next.x > wall.length() - END or next.y > top:
			return
		next.y = maxf(next.y, 0.02)
		at = next
		walked += STEP
		t += STEP / RATE
		var young := 1.0 - clampf((reach - walked) / 0.4, 0.0, 1.0)
		for k in 3:
			var q := at + Vector2(rng.randf_range(-0.08, 0.08), rng.randf_range(-0.06, 0.06))
			q = q.clamp(Vector2(END, 0.0), Vector2(wall.length() - END, top))
			leaves.append(_leaf(wall, at if blocked(wall, q.x, q.y) else q, side, t + k * 0.3, young, rng))
		if depth < 3 and rng.randf() < 0.12:
			_vine(wall, at, Vector2(1.0 if rng.randf() < 0.5 else -1.0, 0.7).normalized(), side, t, depth + 1, rng, leaves)


static func _nearest_arch(wall: WallLayout, s: float) -> float:
	var best := INF
	for a in wall.live_arches:
		if absf(a - s) < absf(best - s):
			best = a
	return best


static func _leaf(wall: WallLayout, at: Vector2, side: float, t: float, young: float, rng: RandomNumberGenerator) -> Dictionary:
	var frame := wall.frame_at(at.x)
	var out: Vector3 = frame.tangent.cross(Vector3.UP) * side
	var spin := rng.randf() * TAU
	var x: Vector3 = frame.tangent.rotated(out, spin)
	var basis := Basis(x, out.cross(x), out).rotated(x, rng.randf_range(0.2, 0.7))
	var size := rng.randf_range(0.12, 0.2) * lerpf(1.0, 0.65, young)
	var origin: Vector3 = frame.point + Vector3.UP * at.y + out * (FACE + rng.randf_range(0.0, 0.03))
	var green: Color = GREENS[rng.randi() % GREENS.size()].lerp(YOUNG, young * 0.8) * rng.randf_range(0.85, 1.15)
	return {"xform": Transform3D(basis.scaled_local(Vector3.ONE * size), origin), "color": green, "t": t, "s": at.x, "y": at.y, "side": side}
