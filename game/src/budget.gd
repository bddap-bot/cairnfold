class_name Budget
extends RefCounted

## The frame every build must fit, and what building costs against it: the one source of these numbers.
## scripts/bench.sh holds the stress scene to them, and World turns down an edit that would take a garden past the
## whole.
## Lantern light is baked (`Lamps`) and costs the frame nothing however many hang: a lantern counts by its meshes.

## One graphics configuration for every headset, held to the weakest: the Quest 2 at 72 Hz.
const REFRESH_HZ := 72.0
## A standing mirror's view for each eye, in pixels: its glass's shape, a pixel about a Quest 2 pixel at a step from it.
const MIRROR_VIEW := Vector2i(448, 672)
## Fixed tread density keeps raising terrain from multiplying a path's geometry.
const PATH_TREADS_PER_ROW := 2

## What a garden's builds count as, the units COSTS prices: square metres of face of stone walls, plaster walls and
## fences (length along the ground by height, and a house's two gable ends: boards, laid as stones are but fewer, count
## as stone wall; worn plaster counts the stone it has worn back to as stone wall besides; a planked wall counts as
## plaster for the backing behind its planks), of tiled or flat roof and of thatch (laid along its slopes out to its
## eaves); fittings that add a mesh (lanterns, flags and the runs joining them, chimneys with their smoke, trapdoors, the ring of an arched or round window,
## a lived-in house's curtains and flower box at each window and its washing line, dormers, whose boarded faces count
## as stone wall and whose slopes as tiled roof besides); painted grass blades and flowers; trees and bushes standing; explicit arch
## openings, with timber members and the planks a finish lays counted separately; square metres of pond water; easels,
## each a canvas drawn and simulated; boulders, a metre-wide one a unit (`boulder`); and square metres of painted stone
## ground and of cobbled or flagged path, each stroke the ground its discs reach, a stroke over another counted again.
static var UNITS: Array = COSTS.keys().filter(func(k: String) -> bool: return not k in CAPS.values())
## Masonry draws a chunk's stones whole only near the eye (Quality.Step.stone_near_m) and coarser past it, so each of
## these costs a far rate on all of it and, as `<unit>_near` (World counts them, `Near`), a near excess on what stands in
## the chunks one eye has near.
const MASONRY := ["wall_m2", "plaster_m2", "fence_m2", "roof_m2", "thatch_m2"]
## The COSTS entry that caps a unit's whole charge: what a view full of it adds.
const CAPS := {"pond_m2": "water", "stone_m2": "stone"}

## Main-thread time the Masonry spends a frame drawing chunks changed in place (a wall laid again), in microseconds:
## one of a stress wall's chunks on the Steam Frame, whose frames under a path stroke over the stress scene's walls
## have about a millisecond to spare; the rest wait for the frames after.
const MASONRY_FLUSH_US := 300.0
## Main-thread time a frame spends looking over painted flowers for where butterflies may come, in microseconds: about
## fifty flowers on the Steam Frame; a path stroke wearing the ground every frame keeps them looking.
const BUTTERFLY_SCAN_US := 300.0
## Main-thread time a frame spends wearing a path just laid into the garden's ground, in microseconds: a few of its rows
## on the Steam Frame; a 48 m path's hundred and more take the frames after.
const GROUND_WEAR_US := 1000.0
## What a piece laid with a build's stones but apart from its courses counts as: wall courses lay roughly ten blocks a
## square metre. A path's treads and crops and every build's clutter (ClutterLayout) are charged so, a part a piece.
const PIECE_M2 := 0.1
## The largest paired Quest 2 cost per timber member in the dense village, rounded up (docs/design.md).
const TIMBER_US := 0.5
## The mean plank laid across a wall or along a walk: BOARD_RUN's, less for each run's shorter first and the turns.
const BOARD_MEAN := 1.3
## Largest residual above existing wall/timber charges in paired Quest 2 arch sweeps, rounded up.
## A larger opening still reserves a whole arch.
const ARCH_US := 60.0
## Paint flow every canvas together may run a frame, in texel-steps (one texel through one flow step): the most the
## Quest 2's four-easel bench holds its budget at with four canvases wet (docs/design.md, "Painting").
const PAINT_STEPS := 1.0e6
## The least a boulder counts, however small: a pebble still draws its mesh.
const BOULDER_LEAST := 0.25
## The most one boulder costs the Quest 2 however large, in microseconds: its dearest paired cost, carried or still, near
## or far, from 1 to 80 times a metre wide (docs/design.md, "Boulder cost by size").
const BOULDER_MOST_US := 470.0
## A moss patch's dearest paired Quest 2 cost: the pool's 256 packed into a 2 m disc 3 m from the eye; it falls with
## distance, but the pool bounds all of a garden's moss to 1.8 ms (docs/design.md, "Cost by distance").
const MOSS_US := 7.001
## The Quest 2's measured room, over the meadow without its own trees and bushes, its wildlife and the compositor's
## timewarp; see docs/design.md.
## Fixed independently of the running device, refresh rate and quality governor.
const CAPACITY_MS := 3.99
## Painted stone ground's paired Quest 2 cost a square metre over the bare meadow, and at most what a view full of it
## adds, charged however much is painted (docs/design.md, "Ground materials").
const STONE_M2_US := 0.468
const STONE_VIEW_US := 590.0
const COSTS := {"grass": 0.591, "flower": 1.682, "tree": 26.628, "bush": 4.712, "wall_m2": 4.293, "plaster_m2": 1.105, "fence_m2": 2.271, "pond_m2": 15.9, "roof_m2": 9.488, "thatch_m2": 3.834, "fitting": 15.187, "easel": 890.0, "boulder": 37.518, "water": 2570.0, "stone_m2": STONE_M2_US, "stone": STONE_VIEW_US, "timber": TIMBER_US, "arch": ARCH_US, "moss": MOSS_US, "wall_m2_near": 6.233, "plaster_m2_near": 4.282, "fence_m2_near": 3.381, "roof_m2_near": 0.0, "thatch_m2_near": 8.116}


static func fit_step() -> int:
	return Quality.ladder.size() - 1


## The GPU time a frame may take: the line the running game's governor holds (Quality.Governor.LINE), at REFRESH_HZ.
static func line_ms() -> float:
	return 1000.0 / REFRESH_HZ * Quality.Governor.LINE


static func info() -> Dictionary:
	return {"refresh_hz": REFRESH_HZ, "gpu_ms": line_ms()}


## The chunk of Masonry's near meshes `p` stands in.
static func cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / Masonry.FINE), floori(p.z / Masonry.FINE))


## How many chunks out from the one under the eye can draw their near meshes at the fit step: those whose
## centre is within its stone_near_m and a chunk's radius of the eye.
static func near_span() -> int:
	var reach := Quality.ladder[fit_step()].stone_near_m + Masonry.radius(Masonry.FINE)
	return floori((reach + Masonry.FINE * 0.5) / Masonry.FINE)


## `units`' masonry over the chunks along `points` (Vector3, ground positions), as the polyline's length falls in each:
## chunk -> units. Without length it all stands in the first point's chunk.
static func spread(units: Dictionary, points: Array) -> Dictionary:
	var stone := {}
	for k in MASONRY:
		if units.has(k):
			stone[k] = units[k]
	if stone.is_empty() or points.is_empty():
		return {}
	var share := {}
	var total := 0.0
	for i in range(1, points.size()):
		var a: Vector3 = points[i - 1]
		var b: Vector3 = points[i]
		var n := maxi(1, ceili(Vector2(b.x - a.x, b.z - a.z).length() / 0.5))
		var step := Vector2(b.x - a.x, b.z - a.z).length() / n
		for j in n:
			var c := cell(a.lerp(b, (j + 0.5) / n))
			share[c] = share.get(c, 0.0) + step
			total += step
	if total <= 0.0:
		share = {cell(points[0]): 1.0}
		total = 1.0
	var out := {}
	for c in share:
		out[c] = add({}, stone, share[c] / total)
	return out


## A garden's masonry by chunk (`spread`), and the `<unit>_near` units of what the chunks within near_span of one hold,
## around whichever chunk makes that dearest. Each window's near excess is kept as builds come and go, so a change
## reads only the windows it touches.
class Near:
	var cells := {}
	## Per chunk, its near excess and its area: the area picks between windows that cost alike.
	var _dear := {}
	var _windows := {}

	func add(change: Dictionary, times := 1.0) -> void:
		for c: Vector2i in change:
			var now: Dictionary = Budget.add(cells.get(c, {}).duplicate(), change[c], times)
			var d := Near._weigh(now)
			var delta: Vector2 = d - _dear.get(c, Vector2.ZERO)
			if now.is_empty():
				cells.erase(c)
				_dear.erase(c)
			else:
				cells[c] = now
				_dear[c] = d
			for o in Near._around(c):
				var w: Vector2 = _windows.get(o, Vector2.ZERO) + delta
				if w.y < 1e-6:
					_windows.erase(o)
				else:
					_windows[o] = w

	## The near units with `change` (chunk -> units) added, without keeping it.
	func units(change := {}) -> Dictionary:
		var after := {}
		for c: Vector2i in change:
			after[c] = Budget.add(cells.get(c, {}).duplicate(), change[c])
		var touched := {}
		for c: Vector2i in change:
			for o in Near._around(c):
				touched[o] = true
		var best := Vector2(-1.0, -1.0)
		var at := Vector2i.ZERO
		for o: Vector2i in _windows:
			if not touched.has(o) and _windows[o] > best:
				best = _windows[o]
				at = o
		for o: Vector2i in touched:
			var w := Vector2.ZERO
			for c in Near._around(o):
				w += Near._weigh(after[c]) if after.has(c) else _dear.get(c, Vector2.ZERO)
			if w.y >= 1e-6 and w > best:
				best = w
				at = o
		var out := {}
		if best.y < 0.0:
			return out
		for c in Near._around(at):
			for k in after.get(c, cells.get(c, {})):
				Budget.add(out, {k + "_near": after.get(c, cells.get(c, {}))[k]})
		return out

	static func _weigh(units: Dictionary) -> Vector2:
		var out := Vector2.ZERO
		for k in units:
			out += Vector2(COSTS[k + "_near"], 1.0) * units[k]
		return out

	static func _around(c: Vector2i) -> Array[Vector2i]:
		var span := Budget.near_span()
		var out: Array[Vector2i] = []
		for dx in range(-span, span + 1):
			for dz in range(-span, span + 1):
				out.append(c + Vector2i(dx, dz))
		return out


static func cost_ms(units: Dictionary) -> float:
	var us := 0.0
	for k in units:
		var cap: float = COSTS[CAPS[k]] if k in CAPS else INF
		us += minf(units[k] * COSTS[k], cap)
	return us / 1000.0


static func fill(units: Dictionary) -> float:
	return cost_ms(units) / CAPACITY_MS


## Removing cost must remain possible in an older garden already over capacity.
static func fits(units: Dictionary, change: Dictionary) -> bool:
	var now := cost_ms(add(units.duplicate(), change))
	return now <= cost_ms(units) or now <= CAPACITY_MS


## `into` with `units` added `times` over, keys at zero dropped.
static func add(into: Dictionary, units: Dictionary, times := 1.0) -> Dictionary:
	for k in units:
		var v: float = into.get(k, 0.0) + units[k] * times
		if is_zero_approx(v):
			into.erase(k)
		else:
			into[k] = v
	return into


## A wall as its build command carries it.
static func wall(d: Dictionary) -> Dictionary:
	var length := Commands.length(d.points)
	var clutter := ClutterLayout.count(d.get("clutter", [])) * PIECE_M2
	if d.closed and d.points.size() > 2:
		length += Vector2(d.points[0].x - d.points[-1].x, d.points[0].z - d.points[-1].z).length()
	var face := "fence_m2" if d.fence else "wall_m2" if d.finish == WallLayout.Finish.BARE else "plaster_m2"
	var out := {face: length * d.height}
	if d.wear > 0.0:
		out.wall_m2 = out.get("wall_m2", 0.0) + length * d.height * d.wear
	var span := WallLayout.stilt_span(d.foundation, d.rise) if d.get("on", PackedInt32Array()).is_empty() else 0.0
	if d.rise > 0.0:
		out.wall_m2 = out.get("wall_m2", 0.0) + length * (d.rise - span)
	var timber := TimberFrame.count(d) + boards(d, length)
	if span > 0.0:
		var stilted := WallLayout.new()
		stilted.points.assign(Array(d.points))
		stilted.closed = true
		var n := stilted.stations().size()
		if d.foundation == WallLayout.Foundation.PILLARS:
			out.wall_m2 = out.get("wall_m2", 0.0) + length * WallLayout.COURSE + n * WallLayout.PILLAR * (span - WallLayout.COURSE)
		else:
			timber += n * 2
	if timber > 0:
		out.timber = timber
	var fittings: int = d.lanterns.size() + d.flags.size() + WallLayout.flag_runs(Array(d.flags), length, d.closed).size()
	var openings: Array = d.get("openings", [])
	for opening: Vector4 in openings:
		if int(opening.z) == WallLayout.Family.ARCHWAY:
			out.arch = out.get("arch", 0) + 1
		elif WallLayout.LIGHTS[int(opening.z)].ring:
			fittings += 1
	if d.closed and d.has("roof") and WallLayout.lives(openings, not d.get("on", PackedInt32Array()).is_empty()):
		var dressed := openings.filter(func(o: Vector4) -> bool: return not WallLayout.opens_door(o) and WallLayout.LIGHTS[int(o.z)].dressed)
		if not dressed.is_empty():
			fittings += dressed.size() + 1
	if d.has("roof"):
		var slopes := RoofLayout.new()
		slopes.kind = RoofLayout.Kind.CONE
		slopes.radius = d.roof.radius
		slopes.pitch = d.roof.pitch
		slopes.curve = d.roof.curve
		slopes.overhang = d.roof.overhang
		slopes.base = d.height + WallLayout.CAP - WallLayout.SINK + d.rise
		slopes.foot = 0.0
		var eave: float = WallLayout.THICKNESS * 0.5 + minf(d.roof.overhang, slopes.reach())
		var plan: float = PI * (d.roof.radius + eave) * (d.roof.radius + eave)
		if d.roof.kind == RoofLayout.Kind.GABLE and d.points.size() == 4:
			slopes.kind = RoofLayout.Kind.GABLE
			slopes.corners.assign(Array(d.points))
			var ends := WallLayout.new()
			ends.gable_end = d.gable_end
			ends.gable = slopes
			var half_span: float = (Vector2(d.points[3].x - d.points[0].x, d.points[3].z - d.points[0].z).length() + WallLayout.THICKNESS) * 0.5
			ends.finish = d.finish
			var units := "wall_m2" if ends.gable_kind() == WallLayout.GableEnd.BOARDS else face
			out[units] = out.get(units, 0.0) + 2.0 * ends.gable_face(half_span)
			var ridge := Vector2(d.points[1].x - d.points[0].x, d.points[1].z - d.points[0].z).length()
			plan = (ridge + WallLayout.THICKNESS + 2.0 * RoofLayout.GABLE_OVERHANG) * 2.0 * (half_span + minf(d.roof.overhang, slopes.reach()))
			for c: Vector2 in d.roof.dormers:
				var area := slopes.dormer_area(c)
				if area != Vector2.ZERO:
					fittings += 1
					out.wall_m2 = out.get("wall_m2", 0.0) + area.x
					out.roof_m2 = out.get("roof_m2", 0.0) + area.y
		var covering := "thatch_m2" if d.roof.thatch and d.roof.pitch > 0.0 else "roof_m2"
		out[covering] = out.get(covering, 0.0) + plan * slopes.stretch()
		if slopes.flat():
			out.timber = out.get("timber", 0) + slopes.ceiling_units()
		fittings += d.roof.chimneys.size() + (1 if d.roof.flag else 0) + (d.roof.hatches.size() if slopes.flat() else 0)
	if fittings > 0:
		out.fitting = fittings
	if clutter > 0.0:
		out.wall_m2 = out.get("wall_m2", 0.0) + clutter
	return out


## The planks a wall or fence `length` long lays as its finish: planked across, rows two to a course of planks
## BOARD_MEAN long, scaled as a round loop's stones are, one more a row each time the wall turns BOARD_TURN, on each
## side and at each opening and ruin, or between a fence's posts FENCE_BOARDS rows; planked upright, a column BOARD.x
## or FENCE_PALE wide, a wall's broken in two round each opening and course by course down a ruin's stepped ends; framed in timber with no pitched roof, the walk's
## lanes and a square on each corner.
static func boards(d: Dictionary, length: float) -> int:
	if d.finish == WallLayout.Finish.BARE or d.finish == WallLayout.Finish.PLASTER or d.finish == WallLayout.Finish.TIMBER and d.get("roof") != null and d.roof.pitch > 0.0:
		return 0
	var points: PackedVector3Array = d.points
	var n := points.size()
	var turn := 0.0
	var sides := 0
	for i in range(0 if d.closed else 1, n if d.closed else n - 1):
		var a := points[(i + n - 1) % n]
		var b := points[i]
		var c := points[(i + 1) % n]
		var bend := absf(Vector2(b.x - a.x, b.z - a.z).angle_to(Vector2(c.x - b.x, c.z - b.z)))
		if bend > WallLayout.CORNER_TURN:
			sides += 1
		else:
			turn += bend
	var scale := clampf(length / TAU / 3.0, 0.45, 1.0) if d.closed and sides == 0 else 1.0
	var along: int = ceili(length / (BOARD_MEAN * scale) + turn / WallLayout.BOARD_TURN) + sides + 1 + d.get("ruins", []).size()
	var openings: Array = d.get("openings", [])
	match d.finish:
		WallLayout.Finish.BOARDS_ACROSS:
			if d.fence:
				return ceili(length / WallLayout.POST_SPACING) * WallLayout.FENCE_BOARDS.size()
			return (along + openings.size()) * ceili((d.height - WallLayout.COURSE) / WallLayout.COURSE) * WallLayout.rows_of(WallLayout.COURSE)
		WallLayout.Finish.BOARDS_UPRIGHT:
			if d.fence:
				return ceili(length / WallLayout.FENCE_PALE)
			return ceili(length / WallLayout.BOARD.x) + d.get("ruins", []).size() * 2 * ceili(d.height / WallLayout.COURSE) + openings.reduce(func(n: int, o: Vector4) -> int: return n + ceili(WallLayout.ARCH_HALF * 2.0 * o.w / WallLayout.BOARD.x) + 2, 0)
	return WallLayout.WALK_LANES * along + sides


## `n` plants of a plant group's kind.
static func plants(kind: String, n: int) -> Dictionary:
	if n <= 0:
		return {}
	return {("flower" if kind == "flowers" else kind): n}


## What a boulder grown `scale` times counts as: the face it shows grows as its scale squared until near the eye it
## fills the view, past which a larger one costs no more.
static func boulder(scale: float) -> float:
	return clampf(scale * scale, BOULDER_LEAST, BOULDER_MOST_US / COSTS.boulder)


static func stairs(d: Dictionary) -> Dictionary:
	var run := d.a.distance_to(d.b) as float
	var rails := 2.0 * StairLayout.RAIL_HEIGHT * run if StairLayout.railed(d) else 0.0
	var sides := 0.0
	if StairLayout.classify(d) == StairLayout.Kind.FLIGHT:
		sides = Vector2(d.b.x - d.a.x, d.b.z - d.a.z).length() * absf(d.b.y - d.a.y) * 0.5
	return {"wall_m2": run * d.width + rails + sides}


## A stroke of stone ground: the texels of Ground's mask its discs reach, fade included. Other kinds count nothing.
static func ground(d: Dictionary) -> Dictionary:
	if d.kind != Ground.Kind.STONE:
		return {}
	var reached := Image.create(Ground.SIZE, Ground.SIZE, false, Image.FORMAT_L8)
	for st: Vector4 in d.stamps:
		reach(st, reached)
	return stone(reached)


## Marks on `onto`, an L8 image the size of Ground's mask, the texels the disc `stamp` reaches, fade included.
static func reach(stamp: Vector4, onto: Image) -> void:
	var at := (Vector2(stamp.x, stamp.y) / Terrain.SIZE + Vector2(0.5, 0.5)) * Ground.SIZE
	var r := (stamp.z + stamp.w) / Ground.TEXEL
	for j in range(maxi(0, floori(at.y - r)), mini(Ground.SIZE - 1, ceili(at.y + r)) + 1):
		var dy := j + 0.5 - at.y
		if dy * dy > r * r:
			continue
		var half := sqrt(r * r - dy * dy)
		var x0 := maxi(0, ceili(at.x - half - 0.5))
		var x1 := mini(Ground.SIZE - 1, floori(at.x + half - 0.5))
		if x1 >= x0:
			onto.fill_rect(Rect2i(x0, j, x1 - x0 + 1, 1), Color.WHITE)


## The square metres of stone the texels marked on `reached` (`reach`) count as.
static func stone(reached: Image) -> Dictionary:
	var n := reached.get_data().count(255)
	return {"stone_m2": n * Ground.TEXEL * Ground.TEXEL} if n > 0 else {}


## Reserve the whole path for treads, so raising ground cannot exceed the build budget, or a bed for its crops and
## stepping stones; cobbles and flagstones count the ground their discs reach as painted stone does.
static func path(d: Dictionary) -> Dictionary:
	var layout := PathLayout.of(d)
	layout.plan()
	var out := {}
	if layout.surface == PathLayout.Surface.BED:
		var stones := ceili(layout.length() / PathLayout.STRIDE)
		for spot in layout.crop_spots():
			stones += PathLayout.crop(spot.crop).size()
		out = {"wall_m2": stones * PIECE_M2}
	else:
		var stones := 0
		var timbers := 0
		for row in layout.row_ends.size():
			var start := layout.row_ends[row - 1] if row > 0 else 0.0
			var end := minf(layout.row_ends[row], layout.length())
			for i in PATH_TREADS_PER_ROW:
				var f := layout.frame_at(lerpf(start, end, (i + 0.5) / PATH_TREADS_PER_ROW))
				stones += maxi(1, ceili(f.half * 2.0 / 0.5))
				# Stringers come to at most three timbers a tread, where every flight is two treads long.
				timbers += 3
		out = {"wall_m2": stones * PIECE_M2, "timber": timbers}
	out.wall_m2 += ClutterLayout.count(d.get("clutter", [])) * PIECE_M2
	if layout.kind == Ground.Kind.STONE:
		var reached := Image.create(Ground.SIZE, Ground.SIZE, false, Image.FORMAT_L8)
		for k in layout.row_ends.size():
			reach(layout.disc(k), reached)
		out.merge(stone(reached))
	return out


## A decoration's paired Quest 2 cost, the least linear rule at or over every style's dearest of two 24-copy runs of
## demo/decoration-costs.json (docs/decorations.md), each piece laid in its house's or ground cell's batch: a piece and
## each solid, in microseconds, its flames and pictures costing nothing the runs resolve; its flowers are charged as
## painted ones.
const DECORATION_PIECE_US := 35.7
const DECORATION_SOLID_US := 2.6

## Wall lays on worker threads at once; the rest wait their turn (`Wall._build_live`).
const WALL_LAYS := 2


static func decoration(d: Dictionary) -> Dictionary:
	var layout := DecorationLayout.new()
	layout.build(d.style, 0, 4.8, d.mount, Decorations.span(d), d.get("drop", Vector2.ZERO))
	var us := DECORATION_PIECE_US + DECORATION_SOLID_US * layout.parts.size()
	return {"fitting": us / COSTS.fitting, "flower": float(layout.flowers.size())}
