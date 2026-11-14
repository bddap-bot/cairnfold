class_name Budget
extends RefCounted

## The one source of the frame budget: scripts/bench.sh holds the stress scene to it, BudgetBar shows a garden's
## share and World refuses an edit past the whole. Lantern light is baked (`Lamps`), so a lantern costs only its meshes.

## Every headset is held to the weakest: the Quest 2 at 72 Hz.
const REFRESH_HZ := 72.0
## The flat screen's least frame rate (Main.flat_pace). A garden fitted at REFRESH_HZ fits it with room to spare.
const FLAT_HZ := 60.0
## Per eye, in pixels: the glass's aspect, a pixel about a Quest 2 pixel from a step away.
const MIRROR_VIEW := Vector2i(448, 672)
## Fixed tread density keeps raising terrain from multiplying a path's geometry.
const PATH_TREADS_PER_ROW := 2

## The units COSTS prices. Square metres of face of stone walls, plaster walls and fences (length by height; a
## house's gable ends count as its face, boarded ones as stone wall; worn plaster also counts its worn-back stone as
## stone wall; a planked wall counts its backing as plaster), of tiled or flat roof and of thatch (along the slopes to
## the eaves), of pond water, and of painted stone ground and cobbled or flagged path (each stroke the ground its discs
## reach, a stroke over another counted again). Counts of fittings that add a mesh (lanterns, flags and their runs,
## chimneys with their smoke, trapdoors, an arched or round window's ring, a lived-in house's curtains and flower box
## at each window and its washing line, dormers, whose faces also count as stone wall and slopes as tiled roof),
## painted grass blades and flowers, standing trees and bushes, archway openings, timber members (a finish's planks
## included), easels (each a canvas drawn and simulated), and boulders (a metre-wide one a unit, `boulder`).
static var UNITS: Array = COSTS.keys().filter(func(k: String) -> bool: return not k in CAPS.values())
## Masonry draws a stone whole only within Quality.Step.stone_near_m, so these cost a far rate on all of it plus, as
## `<unit>_near` (counted by `Near`), a near excess on what stands in the chunks one eye has near.
const MASONRY := ["wall_m2", "plaster_m2", "fence_m2", "roof_m2", "thatch_m2"]
## unit -> the COSTS entry capping its whole charge: what a view full of it adds.
const CAPS := {"pond_m2": "water", "stone_m2": "stone"}

## Off in headless tests, which have no deadline to keep and run all spread-out work in one frame.
static var frame_deadline := true

## Masonry's main-thread chunk redraws a frame, in microseconds: one stress-wall chunk on the Steam Frame, which has
## about 1 ms to spare under a path stroke over the stress walls. Only drawing is clock-metered; what game logic
## reads is metered by counts (docs/replay.md).
const MASONRY_FLUSH_US := 300.0
## Main-thread microseconds a frame gives one avatar's particle births; the rest wait, so a sub-emitter's burst of
## hundreds spreads rather than stalls one frame.
const PARTICLE_BIRTHS_US := 500.0
## Painted flowers scanned a frame for butterfly spots: about 300 microseconds on the Steam Frame, kept up while a
## path stroke wears the ground every frame.
const BUTTERFLY_SCAN := 50
## Marks, or new path rows, worn into the ground a frame: about 1 ms on the Steam Frame; a 48 m path's hundred and
## more rows take later frames.
const GROUND_WEAR_ROWS := 4
## Committed-stroke plants grown a frame: about 1.5 ms on the Steam Frame, so a stroke of thousands grows over the
## frames after its command applied.
const GROW_PLANTS := 12
## Builds relaid a frame when the garden reshapes or meets them: a stress-scene two-storey house is about 0.5 ms on
## the Steam Frame, so its upper storey and joined wings follow in later frames.
const RELAYS := 1
## The fewest frames a garden wall's worker lay takes (Work); a wall in hand, which game logic does not read, takes
## its lay once done.
const LAY_FRAMES := 3
## A garden wall's lay on a Quest 2 worker, in ms: LAY_BASE_MS plus LAY_MS per unit Budget.wall counts, the
## non-negative least-squares fit to the stress scene's and demo/lays.json's lays. A lay runs up to twice as long
## beside another (WALL_LAYS) and longer under a sculpt, so it gets LAY_MARGIN times its price in frames at
## REFRESH_HZ: at 2.5 a wall relaid under the stress stroke over the hills still stalled a Quest 2 frame.
const LAY_BASE_MS := 11.0
const LAY_MS := {"wall_m2": 0.33, "plaster_m2": 0.0, "fence_m2": 0.0, "roof_m2": 2.25, "thatch_m2": 11.3, "timber": 0.18,
	"arch": 0.0, "fitting": 0.95}
const LAY_MARGIN := 3.0
## Frames a wall's perches take on a worker before its birds get them (Work).
const PERCH_FRAMES := 3
## Frames a command's water takes on a worker before the command runs (Work, World._drain).
const WATER_FRAMES := 6
## A piece laid apart from a build's courses (path treads and crops, ClutterLayout clutter), as wall square metres:
## courses lay about ten blocks a square metre.
const PIECE_M2 := 0.1
## The largest paired Quest 2 cost per timber member in the dense village, rounded up (docs/design.md).
const TIMBER_US := 0.5
## Mean plank length across a wall or along a walk: WallLayout.BOARD_RUN's, less each run's shorter first and the turns.
const BOARD_MEAN := 1.3
## Largest residual above wall/timber charges in paired Quest 2 arch sweeps, rounded up; any larger opening is one arch.
const ARCH_US := 60.0
## Sharing flow texel-steps across canvases prevents each wet painting from multiplying the frame cost.
const PAINT_STEPS := 3.0e5
## A pebble still draws its mesh.
const BOULDER_LEAST := 0.25
## One boulder's dearest paired Quest 2 cost, carried or still, near or far, 1 to 80 m wide (docs/design.md, "Boulder
## cost by size").
const BOULDER_MOST_US := 470.0
## A moss patch's dearest paired Quest 2 cost: the pool's 256 packed into a 2 m disc 3 m from the eye; it falls with
## distance, but the pool bounds all of a garden's moss to 1.8 ms (docs/design.md, "Cost by distance").
const MOSS_US := 7.001
## The Quest 2's measured room over the meadow, less its own trees and bushes, wildlife and compositor timewarp
## (docs/design.md); fixed whatever the running device, refresh rate or quality governor.
const CAPACITY_MS := 4.27
## Painted stone ground's paired Quest 2 cost a square metre over the bare meadow, and at most what a view full of it
## adds, charged however much is painted (docs/design.md, "Ground materials").
const STONE_M2_US := 0.468
const STONE_VIEW_US := 590.0
const COSTS := {"grass": 0.55, "flower": 1.682, "tree": 26.628, "bush": 4.712, "wall_m2": 5.924, "plaster_m2": 1.752, "fence_m2": 2.271, "pond_m2": 15.9, "roof_m2": 18.613, "thatch_m2": 7.11, "fitting": 15.187, "easel": 890.0, "boulder": 37.518, "water": 2570.0, "stone_m2": STONE_M2_US, "stone": STONE_VIEW_US, "timber": TIMBER_US, "arch": ARCH_US, "moss": MOSS_US, "wall_m2_near": 3.761, "plaster_m2_near": 3.883, "fence_m2_near": 2.626, "roof_m2_near": 0.0, "thatch_m2_near": 9.47}


static func fit_step() -> int:
	return Quality.ladder.size() - 1


## GPU frame time the governor holds to (Quality.Governor.LINE) at REFRESH_HZ.
static func line_ms() -> float:
	return 1000.0 / REFRESH_HZ * Quality.Governor.LINE


static func info() -> Dictionary:
	return {"refresh_hz": REFRESH_HZ, "gpu_ms": line_ms()}


static func cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / Masonry.FINE), floori(p.z / Masonry.FINE))


static func near_span() -> int:
	var reach := Quality.ladder[fit_step()].stone_near_m + Masonry.radius(Masonry.FINE)
	return floori((reach + Masonry.FINE * 0.5) / Masonry.FINE)


## `units`' masonry split over the chunks along `points` (Vector3 ground positions) by polyline length: chunk -> units.
## With no length, all of it in the first point's chunk.
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
		var run := Vector2(b.x - a.x, b.z - a.z).length()
		var n := maxi(1, ceili(run / 0.5))
		var step := run / n
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


## A garden's masonry by chunk (`spread`) and the `<unit>_near` units of its dearest near_span window. Each window's
## near excess is kept as builds come and go, so a change reads only the windows it touches.
class Near:
	var cells := {}
	## chunk -> Vector2(near excess, area); the area breaks ties between windows that cost alike.
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
	var ms := 0.0
	for v: float in charges(units).values():
		ms += v
	return ms


## unit -> its frame cost in milliseconds.
static func charges(units: Dictionary) -> Dictionary:
	var out := {}
	for k in units:
		var cap: float = COSTS[CAPS[k]] if k in CAPS else INF
		out[k] = minf(units[k] * COSTS[k], cap) / 1000.0
	return out


static func fill(units: Dictionary) -> float:
	return cost_ms(units) / CAPACITY_MS


## Removing cost must remain possible in an older garden already over capacity. `limit` is the fill it may reach.
static func fits(units: Dictionary, change: Dictionary, limit := 1.0) -> bool:
	var now := cost_ms(add(units.duplicate(), change))
	return now <= cost_ms(units) or now <= CAPACITY_MS * limit


static func add(into: Dictionary, units: Dictionary, times := 1.0) -> Dictionary:
	for k in units:
		var v: float = into.get(k, 0.0) + units[k] * times
		if is_zero_approx(v):
			into.erase(k)
		else:
			into[k] = v
	return into


static func lay_frames(units: Dictionary) -> int:
	var ms := LAY_BASE_MS
	for k: String in units:
		ms += LAY_MS[k] * units[k]
	return maxi(LAY_FRAMES, ceili(LAY_MARGIN * ms * REFRESH_HZ / 1000.0))


## `d`: a wall build command.
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


## A round loop's planks are scaled as its stones are.
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


static func plants(kind: String, n: int) -> Dictionary:
	if n <= 0:
		return {}
	return {("flower" if kind == "flowers" else kind): n}


## A boulder's face grows with its scale squared until near the eye it fills the view; past that a larger one costs
## no more.
static func boulder(scale: float) -> float:
	return clampf(scale * scale, BOULDER_LEAST, BOULDER_MOST_US / COSTS.boulder)


static func stairs(d: Dictionary) -> Dictionary:
	var run := d.a.distance_to(d.b) as float
	var rails := 2.0 * StairLayout.RAIL_HEIGHT * run if StairLayout.railed(d) else 0.0
	var sides := 0.0
	if StairLayout.classify(d) == StairLayout.Kind.FLIGHT:
		sides = Vector2(d.b.x - d.a.x, d.b.z - d.a.z).length() * absf(d.b.y - d.a.y) * 0.5
	return {"wall_m2": run * d.width + rails + sides}


static func ground(d: Dictionary) -> Dictionary:
	return _stone_of(d.stamps) if d.kind == Ground.Kind.STONE else {}


## Each texel counted once however many discs reach it.
static func _stone_of(stamps: Array) -> Dictionary:
	var reached := Image.create(Ground.SIZE, Ground.SIZE, false, Image.FORMAT_L8)
	for st: Vector4 in stamps:
		reach(st, reached)
	return stone(reached)


## Marks on `onto`, an L8 image the size of Ground's mask, the texels the disc `stamp` reaches: centre x, z (.x, .y),
## radius .z plus fade .w, in metres.
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


static func stone(reached: Image) -> Dictionary:
	var n := reached.get_data().count(255)
	return {"stone_m2": n * Ground.TEXEL * Ground.TEXEL} if n > 0 else {}


## Treads are reserved for the whole path, so raising the ground cannot exceed the build budget.
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
			var span := layout.row_span(row)
			for i in PATH_TREADS_PER_ROW:
				var f := layout.frame_at(lerpf(span.x, span.y, (i + 0.5) / PATH_TREADS_PER_ROW))
				stones += PathLayout.tread_columns(f.half)
				# At most three stringer timbers a tread, every flight being two treads long.
				timbers += 3
		out = {"wall_m2": stones * PIECE_M2, "timber": timbers}
	out.wall_m2 += ClutterLayout.count(d.get("clutter", [])) * PIECE_M2
	if layout.kind == Ground.Kind.STONE:
		out.merge(_stone_of(range(layout.row_ends.size()).map(layout.disc)))
	return out


## A decoration's paired Quest 2 cost in microseconds, per piece and per solid: the least linear rule at or over every
## style's dearest of two 24-copy runs of demo/decoration-costs.json (docs/decorations.md), each piece in its house's
## or ground cell's batch. Flames and pictures cost nothing the runs resolve; flowers are charged as painted ones.
const DECORATION_PIECE_US := 35.7
const DECORATION_SOLID_US := 2.6

## Wall lays on worker threads at once; the rest wait (`Wall._build_live`).
const WALL_LAYS := 2


static func decoration(d: Dictionary) -> Dictionary:
	var layout := DecorationLayout.new()
	layout.build(d.style, 0, 4.8, d.mount, Decorations.span(d), d.get("drop", Vector2.ZERO))
	var us := DECORATION_PIECE_US + DECORATION_SOLID_US * layout.parts.size()
	return {"fitting": us / COSTS.fitting, "flower": float(layout.flowers.size())}


static func over(start_us: int, budget_us: float) -> bool:
	return frame_deadline and Time.get_ticks_usec() - start_us > budget_us
