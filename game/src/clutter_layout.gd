class_name ClutterLayout
extends RefCounted

## The small things a house, wall or path gathers of its own when it is built: benches by a house's front, pumpkins or
## flowers the other side, barrels and crates at its corners, now and then a market stall or an anvil, swallows' nests
## under its eaves; barrels, crates, flowers and benches along a wall's foot and nests on its top; benches, barrels,
## crates and pumpkins beside a path. Each is a decoration's style (DecorationLayout) laid as part of its build, so it
## costs a draw call no more than the build's own stones do. A build keeps them as `clutter`, a list of
## Vector4(s, off, turn, style): its arc length along the build; how far out it stands, from a wall's face to its
## middle or from a path's spine, the sign the side (`WallLayout._normal`, or a path's right); its turn from facing
## out; and its style. A hand moves, turns, copies or takes each away as a fitting of its build.

## Most pieces a build gathers, and most it may hold once hands copy some.
const GATHERED := 16
const MOST := 64
## How far a piece stands out from its wall, least and most, or past a path's edge at most.
const OUT := Vector2(0.05, 3.0)
const PAST_PATH := 3.0
## A path gathers a piece this far from its start, then one each EVERY metres, none within CLEAR of its end.
const PATH_FIRST := 1.2
const PATH_EVERY := 7.0
const PATH_CLEAR := 1.5
## A plain wall gathers something at its foot about each WALL_EVERY metres, and a nest on its top each NEST_EVERY.
const WALL_EVERY := 5.0
const NEST_EVERY := 8.0
## Pieces a house gathers stand at least this far apart along it.
const CLEAR := 1.1

static var _shapes := {}


## The style named `name` in DecorationLayout.
static func style(name: String) -> int:
	return DecorationLayout.named(name)


## Whether pieces of `style` sit up on a wall rather than on the ground at its foot.
static func perched(style: int) -> bool:
	return style == DecorationLayout.named("Bird nest")


## What wall `d` (a build command's wall) gathers: none for a fence or a ruin; for a house or tower its front and corners
## dressed, now and then a stall or a smithy, a nest under its eaves; for a house standing on another build the nest
## alone; along a plain wall pieces at its foot and nests on its top.
static func of_wall(d: Dictionary) -> PackedVector4Array:
	var out := PackedVector4Array()
	if d.fence or not d.ruins.is_empty():
		return out
	var points: PackedVector3Array = d.points
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([d.seed, "clutter"])
	var sides := _sides(points, d.closed)
	var length: float = 0.0 if sides.is_empty() else sides[-1].end
	if length <= 0.0:
		return out
	var outward := _outward(points, sides) if d.closed else 1.0
	if d.has("roof"):
		var corners: Array = sides.map(func(side: Dictionary) -> float: return side.start)
		var front: Dictionary = sides[0]
		var door: float = front.start + front.run * 0.5
		for o: Vector4 in d.openings:
			if WallLayout.opens_door(o):
				door = o.x
				break
		var grounded: bool = d.on.is_empty()
		if grounded and front.run >= 3.0:
			out.append(Vector4(door - 1.35, outward * 0.32, 0.0, style("Bench")))
			if rng.randf() < 0.5:
				out.append(Vector4(door + 1.05, outward * 0.3, rng.randf_range(-0.4, 0.4), style("Carved pumpkin")))
				out.append(Vector4(door + 1.45, outward * 0.34, rng.randf_range(-0.4, 0.4), style("Carved pumpkin")))
			else:
				out.append(Vector4(door + 1.3, outward * 0.24, 0.0, style("Flower box")))
		if grounded:
			for i in corners.size():
				var side: Dictionary = sides[i]
				if side.run < 1.6 or rng.randf() > 0.5:
					continue
				var name: String = "Rain barrel" if rng.randf() < 0.5 else "Crates"
				if _clear(out, side.start + 0.6, length):
					out.append(Vector4(side.start + 0.6, outward * 0.4, rng.randf_range(-0.3, 0.3), style(name)))
			var trade := rng.randf()
			var back: Dictionary = sides[mini(2, sides.size() - 1)]
			if trade < 0.25 and back.run >= 2.6:
				out.append(Vector4(back.start + back.run * 0.5, outward * 0.75, 0.0, style("Market stall")))
			elif trade < 0.45 and sides.size() > 1 and sides[1].run >= 1.8:
				var end: Dictionary = sides[1]
				out.append(Vector4(end.start + end.run * 0.45, outward * 0.75, rng.randf_range(-0.5, 0.5), style("Anvil")))
		var eave: Dictionary = sides[mini(2, sides.size() - 1)]
		out.append(Vector4(eave.start + eave.run * rng.randf_range(0.25, 0.75), outward, 0.0, style("Bird nest")))
		return out
	var s := WALL_EVERY * rng.randf_range(0.3, 0.8)
	while s < length - 0.6 and out.size() < GATHERED:
		if rng.randf() < 0.6:
			var name: String = ["Rain barrel", "Crates", "Flower box", "Bench"][rng.randi() % 4]
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			out.append(Vector4(s, side * (0.3 if name != "Rain barrel" else 0.4), rng.randf_range(-0.25, 0.25), style(name)))
		s += WALL_EVERY * rng.randf_range(0.8, 1.2)
	s = NEST_EVERY * rng.randf_range(0.3, 0.7)
	while s < length - 0.3 and out.size() < GATHERED:
		if rng.randf() < 0.7:
			out.append(Vector4(s, 0.0, rng.randf() * TAU, style("Bird nest")))
		s += NEST_EVERY * rng.randf_range(0.8, 1.2)
	return out


## Whether arc length `s` round a loop `length` long stands CLEAR of every piece in `out`.
static func _clear(out: PackedVector4Array, s: float, length: float) -> bool:
	return Array(out).all(func(v: Vector4) -> bool: return absf(fposmod(v.x - s + length * 0.5, length) - length * 0.5) >= CLEAR)


## What path `d` (a build command's path) gathers: a piece beside it PATH_FIRST from its start and each PATH_EVERY after,
## on either side in turn, facing it, none near its end, where it may run into a house.
static func of_path(d: Dictionary) -> PackedVector4Array:
	var out := PackedVector4Array()
	var points: PackedVector3Array = d.points
	var halves: PackedFloat32Array = d.half_widths
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([d.seed, "clutter"])
	var length := Commands.length(points)
	var names := ["Bench", "Rain barrel", "Crates", "Carved pumpkin", "Flower box"]
	var s := PATH_FIRST
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	while s <= length - PATH_CLEAR and out.size() < GATHERED:
		out.append(Vector4(s, side * (_half_at(points, halves, s) + 0.55), PI, style(names[rng.randi() % names.size()])))
		side = -side
		s += PATH_EVERY * rng.randf_range(0.85, 1.15)
	return out


## Each straight run of `points` (closing back to the first when `closed`): where it starts and ends along them, how
## long it runs and which way.
static func _sides(points: PackedVector3Array, closed: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var s := 0.0
	var n := points.size()
	for i in n if closed else n - 1:
		var a := points[i]
		var b := points[(i + 1) % n]
		var run := Vector2(b.x - a.x, b.z - a.z).length()
		out.append({"start": s, "end": s + run, "run": run, "from": a, "to": b})
		s += run
	return out


## Which side of a closed loop of `points` looks out, as `WallLayout._normal` signs it: +1 or -1.
static func _outward(points: PackedVector3Array, sides: Array[Dictionary]) -> float:
	var outline := PackedVector2Array()
	for p in points:
		outline.append(Vector2(p.x, p.z))
	var side: Dictionary = sides[0]
	var along: Vector3 = (side.to - side.from).normalized()
	var normal := along.cross(Vector3.UP)
	var probe: Vector3 = (side.from + side.to) * 0.5 + normal * 0.1
	return -1.0 if Geometry2D.is_point_in_polygon(Vector2(probe.x, probe.z), outline) else 1.0


## A path's half width `s` along its points.
static func _half_at(points: PackedVector3Array, halves: PackedFloat32Array, s: float) -> float:
	var at := 0.0
	for i in range(1, points.size()):
		var run := Vector2(points[i].x - points[i - 1].x, points[i].z - points[i - 1].z).length()
		if at + run >= s:
			return lerpf(halves[i - 1], halves[i], clampf((s - at) / maxf(run, 1e-5), 0.0, 1.0))
		at += run
	return halves[-1]


## Whether `v` is a piece a build may keep: a clutter style, standing on its build within reach of it.
static func valid(v: Vector4) -> bool:
	return v.is_finite() and v.x >= 0.0 and v.x < 4000.0 and absf(v.y) <= OUT.y + PathLayout.HALF_WIDTH.y and v.w == floorf(v.w) and v.w >= 0.0 and v.w < DecorationLayout.STYLES.size() and DecorationLayout.stands(int(v.w), "ground")


## Piece `v`'s parts laid about frame `x` (its middle on the ground, facing out along +z), seeded `seed`.
static func parts(v: Vector4, x: Transform3D, seed: int) -> Array[Dictionary]:
	var layout := DecorationLayout.new()
	layout.build(int(v.w), seed, 0.6, "ground")
	var out: Array[Dictionary] = []
	for p in layout.parts:
		var part := p.duplicate()
		part.xform = x * p.xform
		out.append(part)
	return out


## Piece `v`'s room about its frame.
static func bounds(v: Vector4) -> AABB:
	return _shape(int(v.w)).bounds


## How many parts a list of pieces lays, which the budget charges as wall stone.
static func count(list: Variant) -> int:
	var n := 0
	for v: Vector4 in list:
		n += _shape(int(v.w)).parts.size()
	return n


## Style `style` laid once, for its size and parts: every seed lays as many.
static func _shape(style: int) -> DecorationLayout:
	if not _shapes.has(style):
		var layout := DecorationLayout.new()
		layout.build(style, 0, 0.6, "ground")
		_shapes[style] = layout
	return _shapes[style]


## The frame a piece standing out `off` from `point`, whose run goes along `tangent`, stands in, turned `turn`.
static func facing(point: Vector3, tangent: Vector3, off: float, out_by: float, turn: float) -> Transform3D:
	var normal := tangent.cross(Vector3.UP).normalized() * (1.0 if off >= 0.0 else -1.0)
	return Transform3D(Basis(Vector3.UP, atan2(normal.x, normal.z) + turn), point + normal * out_by)
