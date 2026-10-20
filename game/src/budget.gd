class_name Budget
extends RefCounted

## The frame every build must fit, and what building costs against it: the one source of these numbers.
## scripts/bench.sh holds the stress scene to them; the bar on each controller (BudgetBar) shows a garden's share
## of them and World turns down an edit that would take it past the whole.
## Lantern light is baked (`Lamps`) and costs the frame nothing however many hang: a lantern counts by its meshes.

## One graphics configuration for every headset, held to the weakest: the Quest 2 at 72 Hz.
const REFRESH_HZ := 72.0
## Fixed tread density keeps raising terrain from multiplying a path's geometry.
const PATH_TREADS_PER_ROW := 2
## The share of each refresh period the game's GPU work may take; the compositor's warp needs the rest.
const GPU_SHARE := 0.9

## The headsets a garden is held to. A machine with neither, as a desktop, holds its garden to the Frame.
enum Device { QUEST_2, FRAME }

## What a garden's builds count as, the units COSTS prices: square metres of face of stone walls, plaster walls and
## fences (length along the ground by height, and a house's two gable ends: boards, laid as stones are but fewer, count
## as stone wall), of tiled or flat roof and of thatch (laid along its slopes out to its eaves);
## fittings that add a mesh (lanterns, flags, chimneys); painted grass blades and flowers, the meadow's own flowers
## included; trees and bushes standing; ponds, one a seed; easels, each a canvas drawn and simulated; and boulders, a
## metre-wide one a unit (`boulder`).
const UNITS := ["wall_m2", "plaster_m2", "fence_m2", "roof_m2", "thatch_m2", "floor_m2", "fitting", "grass", "flower", "tree", "bush", "pond", "timber", "easel", "boulder", "moss"]

## Per headset, in the governor's signal (the viewport's GPU time per frame, Quality) at its fit_step; fitted
## by `scripts/costs.py` from `demo/costs.json` played on it (see "Build budget" in docs/design.md): `budget_ms`, the
## most a frame may take there; `base_ms`, the bare meadow; then GPU microseconds a frame per unit. Hills and painted
## stone ground measured within noise of the bare meadow, so terrain counts nothing.
const COSTS := {
	Device.QUEST_2: QUEST_2_COSTS,
	Device.FRAME: FRAME_COSTS,
}
## The largest paired Quest 2 cost per timber member in the dense village (docs/design.md), rounded up; the Frame
## shares it until measured.
const TIMBER_US := 0.5
## The open picture book's paired Quest 2 GPU cost a frame over it tucked away in the stress scene, in milliseconds
## (docs/design.md, "Picture book"). A garden's room does not reserve it: the book is read between builds.
const BOOK_OPEN_MS := 1.2
## The least a boulder counts, however small: a pebble still draws its mesh.
const BOULDER_LEAST := 0.25
## The Frame's runtime halves the rate once a frame nears 0.88 of the period: held to the governor's line under it.
## A moss patch spans roughly four flower widths: reserve sixteen flower allowances for its pixels.
## This is conservative accounting until moss is measured on a headset.
## Each opaque patch is twelve triangles, with no shadow pass or CPU animation.
const FRAME_COSTS := {"budget_ms": 1000.0 / REFRESH_HZ * Quality.Governor.LINE, "base_ms": 5.7, "wall_m2": 6.073, "plaster_m2": 2.915, "fence_m2": 1.82, "roof_m2": 4.794, "thatch_m2": 4.794, "fitting": 3.111, "grass": 0.061, "flower": 0.072, "tree": 21.275, "bush": 2.852, "pond": 35.294, "timber": TIMBER_US, "easel": 615.312, "floor_m2": 5.534, "boulder": 6.2, "moss": 0.072 * 16.0}
const QUEST_2_COSTS := {"budget_ms": 1000.0 / REFRESH_HZ * Quality.Governor.LINE, "base_ms": 7.28, "grass": 0.449, "flower": 0.678, "tree": 70.711, "wall_m2": 19.054, "plaster_m2": 6.46, "fence_m2": 4.348, "pond": 89.764, "roof_m2": 30.465, "thatch_m2": 51.347, "fitting": 21.346, "bush": 0.0, "easel": 1091.208, "timber": TIMBER_US, "floor_m2": 22.809, "boulder": 20.6, "moss": 0.678 * 16.0}


## The ladder step `on`'s COSTS are fitted at (demo/costs.json), so a garden within its budget holds 72 Hz there: the
## Frame's last with the sun's shadows and the full 3D resolution, keeping both; the Quest 2's bottom, the only one its
## bare meadow holds 72 Hz at.
static func fit_step(on: Device) -> int:
	if on == Device.QUEST_2:
		return Quality.ladder.size() - 1
	var last := 0
	for i in Quality.ladder.size():
		if Quality.ladder[i].shadows and Quality.ladder[i].scale_3d == 1.0:
			last = i
	return last


static func gpu_ms() -> float:
	return 1000.0 / REFRESH_HZ * GPU_SHARE


static func info() -> Dictionary:
	return {"refresh_hz": REFRESH_HZ, "gpu_ms": gpu_ms()}


static func device() -> Device:
	return Device.QUEST_2 if OS.get_name() == "Android" else Device.FRAME


## What the units cost a frame on `on`, in milliseconds, over the bare meadow.
static func cost_ms(units: Dictionary, on: Device) -> float:
	var c: Dictionary = COSTS[on]
	var us := 0.0
	for k in units:
		us += units[k] * c[k]
	return us / 1000.0


## The milliseconds builds may take on `on`.
static func room_ms(on: Device) -> float:
	return COSTS[on].budget_ms - COSTS[on].base_ms


## The share of the room `units` take on the most loaded of `devices`.
static func fill(units: Dictionary, devices: Array) -> float:
	var most := 0.0
	for d: Device in devices:
		most = maxf(most, cost_ms(units, d) / room_ms(d))
	return most


## Whether a garden of `units` may take `change` on every one of `devices`: anything that costs nothing more fits,
## so taking things away always does, even in a garden already over.
static func fits(units: Dictionary, change: Dictionary, devices: Array) -> bool:
	for d: Device in devices:
		if cost_ms(change, d) > 0.0 and cost_ms(units, d) + cost_ms(change, d) > room_ms(d):
			return false
	return true


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
	if d.closed and d.points.size() > 2:
		length += Vector2(d.points[0].x - d.points[-1].x, d.points[0].z - d.points[-1].z).length()
	var face := "fence_m2" if d.fence else ("plaster_m2" if d.plaster else "wall_m2")
	var out := {face: length * d.height}
	if d.rise > 0.0:
		out.wall_m2 = out.get("wall_m2", 0.0) + length * d.rise
	var timber := TimberFrame.count(d)
	if timber > 0:
		out.timber = timber
	var fittings: int = d.lanterns.size() + d.flags.size()
	if d.has("roof"):
		var eave := WallLayout.THICKNESS * 0.5 + RoofLayout.OVERHANG
		var plan: float = PI * (d.roof.radius + eave) * (d.roof.radius + eave)
		var slopes := RoofLayout.new()
		slopes.kind = RoofLayout.Kind.CONE
		slopes.radius = d.roof.radius
		slopes.pitch = d.roof.pitch
		slopes.curve = d.roof.curve
		if d.roof.kind == RoofLayout.Kind.GABLE and d.points.size() == 4:
			slopes.kind = RoofLayout.Kind.GABLE
			slopes.corners.assign(Array(d.points))
			var ends := WallLayout.new()
			ends.height = d.height
			ends.gable_end = d.gable_end
			ends.gable = RoofLayout.new()
			ends.gable.pitch = d.roof.pitch
			ends.gable.curve = d.roof.curve
			var half_span: float = (Vector2(d.points[3].x - d.points[0].x, d.points[3].z - d.points[0].z).length() + WallLayout.THICKNESS) * 0.5
			var units := "wall_m2" if ends.gable_end == WallLayout.GableEnd.BOARDS else face
			out[units] = out.get(units, 0.0) + 2.0 * ends.gable_face(half_span)
			var ridge := Vector2(d.points[1].x - d.points[0].x, d.points[1].z - d.points[0].z).length()
			plan = (ridge + WallLayout.THICKNESS + 2.0 * RoofLayout.GABLE_OVERHANG) * 2.0 * (half_span + RoofLayout.OVERHANG)
		out["thatch_m2" if d.roof.thatch and d.roof.pitch > 0.0 else "roof_m2"] = plan * slopes.stretch()
		fittings += d.roof.chimneys.size() + (1 if d.roof.flag else 0)
		var upper := WallLayout.upper_floors(d.height) if d.storey_floors else 0
		if upper > 0:
			out.floor_m2 = upper * _plan(d.points)
	if fittings > 0:
		out.fitting = fittings
	return out


## The area a closed loop of points encloses on the ground plane.
static func _plan(points: Variant) -> float:
	var twice := 0.0
	for i in points.size():
		var a: Vector3 = points[i]
		var b: Vector3 = points[(i + 1) % points.size()]
		twice += a.x * b.z - b.x * a.z
	return absf(twice) * 0.5


## `n` plants of a plant group's kind.
static func plants(kind: String, n: int) -> Dictionary:
	if n <= 0:
		return {}
	return {("flower" if kind == "flowers" else kind): n}


## What a boulder grown `scale` times counts as: the ground it covers and the face it shows grow as its scale squared.
static func boulder(scale: float) -> float:
	return maxf(scale * scale, BOULDER_LEAST)


static func stairs(d: Dictionary) -> Dictionary:
	var run := d.a.distance_to(d.b) as float
	# Charge the treads and both rails against the existing stone-face budget.
	return {"wall_m2": run * (d.width + 2.0 * StairLayout.RAIL_HEIGHT)}


## Reserve the whole path for treads, so raising ground cannot exceed the build budget.
static func path(d: Dictionary) -> Dictionary:
	var layout := PathLayout.of(d)
	layout.plan()
	var stones := 0
	for row in layout.row_ends.size():
		var start := layout.row_ends[row - 1] if row > 0 else 0.0
		var end := minf(layout.row_ends[row], layout.length())
		for i in PATH_TREADS_PER_ROW:
			var f := layout.frame_at(lerpf(start, end, (i + 0.5) / PATH_TREADS_PER_ROW))
			stones += maxi(1, ceili(f.half * 2.0 / 0.5))
	# Wall courses lay roughly ten blocks per square metre.
	return {"wall_m2": stones * 0.1}
