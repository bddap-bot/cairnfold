class_name PadLayout
extends RefCounted

## Where lilypads float on a pond: in rafts of a few, begun where `_favour` is highest and kept apart, then singly
## until the pond has its share, over water deep enough to root in, each pad whole on the water and clear of the others. The spots a pad may take hang on the ground points they lie by and nothing else, so a pond
## dug wider keeps most of its pads, and every player lays the same ones. Pure data, so tests run headless.

## Pads in all, shared among the ponds in the order they are shown, and the most on one pond.
const CAP := 96
const PER_POND := 12
## Wet grid points a pad.
const CELLS_EACH := 2.0
## The water under a pad's middle, and the least under its rim.
const MIN_DEPTH := 0.2
const RIM_DEPTH := 0.04
const RADIUS := Vector2(0.13, 0.24)
const GAP := 0.02
## Spots tried by each grid point, and about how many grid points a pond tries.
const SPOTS := 3
## Numbers drawn for a spot, each its own: where it lies (two), its chance, its raft's size, and its pad's radius,
## turn and colour.
const DRAWS := 7
const TRIED := 96
## The fewest and most pads of a raft, how far from its middle they lie, and how far apart rafts' middles keep.
const RAFT := Vector2i(3, 5)
const RAFT_REACH := 0.8
const RAFT_APART := 2.2
## How far chance outweighs the rafts in which spots take pads, against the rafts' own 0 to 1.
const SCATTER := 0.12
const GREENS: Array[Color] = [Color(0.2, 0.42, 0.13), Color(0.26, 0.47, 0.15), Color(0.17, 0.37, 0.16), Color(0.31, 0.46, 0.12)]


class Leaf:
	var at := Vector2.ZERO
	var radius := 0.0
	## Radians its notch is turned from +x.
	var turn := 0.0
	var colour := Color.WHITE


## How many pads a pond of `cells` wet grid points floats when `left` of the cap remain.
static func quota(cells: int, left: int) -> int:
	return mini(mini(PER_POND, ceili(cells / CELLS_EACH)), left)


## At most `count` pads on `pond`. `ground` gives the ground's height at (x, z).
static func pads(pond: PondLayout.Pond, ground: Callable, count: int) -> Array[Leaf]:
	var spots := []
	var some := pond.cells.size() > TRIED
	for g in pond.cells:
		# A lake tries the share of its points this picks, the same points however much wider it is dug.
		if some and posmod(g.x * 7919 + g.y * 104729, 1024) * pond.cells.size() >= TRIED * 1024:
			continue
		var centre := Terrain.grid_xz(g)
		for k in SPOTS:
			var at := centre + (Vector2(FloraLayout.hashed(g.x, g.y, k * DRAWS), FloraLayout.hashed(g.x, g.y, k * DRAWS + 1)) - Vector2(0.5, 0.5)) * Terrain.STEP
			spots.append([_favour(at) + FloraLayout.hashed(g.x, g.y, k * DRAWS + 2) * SCATTER, at, g, k])
	spots.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var out: Array[Leaf] = []
	var rafts: Array[Vector2] = []
	for first: Array in spots:
		if out.size() >= count:
			break
		var middle: Vector2 = first[1]
		if rafts.any(func(r: Vector2) -> bool: return r.distance_to(middle) < RAFT_APART):
			continue
		rafts.append(middle)
		var room := mini(RAFT.x + int(FloraLayout.hashed(first[2].x, first[2].y, first[3] * DRAWS + 3) * (RAFT.y - RAFT.x + 1)), count - out.size())
		for s: Array in spots:
			if room == 0:
				break
			if middle.distance_to(s[1]) <= RAFT_REACH and _float(out, s, pond, ground):
				room -= 1
	# A pond too small for the rafts its share asks for takes the rest wherever one still floats clear.
	for s: Array in spots:
		if out.size() >= count:
			break
		_float(out, s, pond, ground)
	return out


## Adds the pad of spot `s` to `out` where it floats whole on deep water clear of those there; whether it did.
static func _float(out: Array[Leaf], s: Array, pond: PondLayout.Pond, ground: Callable) -> bool:
	var p := Leaf.new()
	p.at = s[1]
	p.radius = lerpf(RADIUS.x, RADIUS.y, FloraLayout.hashed(s[2].x, s[2].y, s[3] * DRAWS + 4))
	if _depth(pond, ground, s[2], p.at) < MIN_DEPTH or out.any(func(o: Leaf) -> bool: return o.at.distance_to(p.at) < o.radius + p.radius + GAP):
		return false
	for k in 6:
		if _depth(pond, ground, s[2], p.at + Vector2.from_angle(k * TAU / 6.0) * p.radius) < RIM_DEPTH:
			return false
	p.turn = FloraLayout.hashed(s[2].x, s[2].y, s[3] * DRAWS + 5) * TAU
	p.colour = GREENS[int(FloraLayout.hashed(s[2].x, s[2].y, s[3] * DRAWS + 6) * GREENS.size()) % GREENS.size()]
	out.append(p)
	return true


## `pond`'s water over the ground at `at`, within a pad's reach of its wet grid point `g`: none where the grid point
## nearest is the floor of another hollow past the bank. That point lies cornerwise from `g`, under the pond's level,
## with dry ground at both grid points between; were either wet, the water would reach it.
static func _depth(pond: PondLayout.Pond, ground: Callable, g: Vector2i, at: Vector2) -> float:
	var step := Terrain.grid_point(at.x, at.y) - g
	if step.x != 0 and step.y != 0:
		var corner := Terrain.grid_xz(g + step)
		var along := Terrain.grid_xz(g + Vector2i(step.x, 0))
		var across := Terrain.grid_xz(g + Vector2i(0, step.y))
		if ground.call(corner.x, corner.y) < pond.level and ground.call(along.x, along.y) >= pond.level and ground.call(across.x, across.y) >= pond.level:
			return -INF
	return pond.level - ground.call(at.x, at.y)


## How much pads favour the water at `at`, 0 to 1: a slow swell over the ground a few metres across, so the pads of
## one crest gather into a raft.
static func _favour(at: Vector2) -> float:
	return 0.5 + 0.25 * (sin(at.x * 1.1 + 1.7 * sin(at.y * 0.6)) + sin(at.y * 1.3 + 1.3 * sin(at.x * 0.7)))
