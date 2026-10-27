class_name Paths
extends Node3D

## Path strokes, the ground they wear into the ground mask and what they lay on it: treads, stepping stones, crops and
## the clutter beside them.

const MIN_LENGTH := 1.0

signal laid(path: PathLayout)
signal taken(path: PathLayout)
signal previewed()

var masonry: Masonry
var terrain: Terrain
var marks: Ground
var layouts: Array[PathLayout] = []
## Each laid path's build command id; `layouts` keeps id order.
var ids := {}
## The surface this machine's player lays paths in: the one they last turned the style wheel to on a path.
var surface := PathLayout.Surface.DIRT
## Each laid path's entry in the garden, by build command id.
var _garden := {}
## Pieces being laid on workers (`_lay`), each [task, path, what it laid], and each path's latest lay.
var _jobs: Array[Array] = []
var _laying := {}
var drawing: PathLayout
var previews: Array[PathLayout] = []
var _settled_mask: Image
var _settled_rows := 0
var _since_rebuild := 0.0
var _dirty := false
## The stroke was worn again and its arches are still to cut, next frame.
var _cut_due := false
## marks.rewears when the drawing's settled mask was taken: a rewear since wiped the drawn wear.
var _seen := -1


func busy() -> bool:
	return drawing != null


func begin(p: Vector3, half: float) -> void:
	drawing = PathLayout.new()
	previews.append(drawing)
	drawing.seed = randi()
	drawing.growing = true
	drawing.surface = surface
	drawing.add(p, half)
	marks.settle()
	_settled_mask = marks.image.duplicate()
	_settled_rows = 0
	_seen = marks.rewears
	_dirty = true


## Carries the drawn stroke on to `p`; whether that laid a new point.
func extend(p: Vector3, half: float) -> bool:
	var pts := drawing.points
	if Commands.length(pts) >= Commands.STROKE_LENGTH or pts.size() >= Commands.MAX_PATH_POINTS:
		return false
	_dirty = true
	if pts.size() >= 2 and pts[-1].distance_to(pts[-2]) < WallTool.POINT_SPACING:
		pts[-1] = p
		drawing.half_widths[-1] = maxf(drawing.half_widths[-1], clampf(half, PathLayout.HALF_WIDTH.x, PathLayout.HALF_WIDTH.y))
		return false
	drawing.add(p, half)
	return true


## Holds the stroke as a ghost until its command lands.
func end() -> Dictionary:
	drawing.growing = false
	drawing.plan()
	var path := drawing
	drawing = null
	_settled_mask = null
	var ghost := {"data": path.data(), "layout": path}
	marks.hold(path)
	if path.length() < MIN_LENGTH:
		drop(ghost)
		return {}
	return ghost


## A ghost from `end` gives way: its command landed, was turned down, or the garden was swapped.
func drop(ghost: Dictionary) -> void:
	marks.release(ghost.layout)
	previews.erase(ghost.layout)
	previewed.emit()


## A stroke under way belongs to a garden being swapped away.
func forget() -> void:
	if drawing != null:
		previews.erase(drawing)
		drawing = null
		_settled_mask = null
		marks.rewear()
		previewed.emit()


## Keep paths in command order for ground wear and wall crossings.
func put(id: int, data: Dictionary) -> void:
	var path := PathLayout.of(data)
	path.plan()
	for ghost in previews:
		if ghost != drawing and ghost.same_stroke(path):
			path.share_meetings(ghost)
	_garden[id] = data
	ids[path] = id
	var i := 0
	while i < layouts.size() and ids[layouts[i]] < id:
		i += 1
	layouts.insert(i, path)
	marks.lay(path, id)
	_lay(path)
	laid.emit(path)


func take(id: int) -> void:
	var path := layout(id)
	if path == null:
		return
	layouts.erase(path)
	ids.erase(path)
	_garden.erase(id)
	_laying.erase(path)
	marks.lift(path)
	if masonry != null:
		masonry.remove(-2000000 - id)
	taken.emit(path)


## The laid path from build command `id`, or null.
func layout(id: int) -> PathLayout:
	for path in layouts:
		if ids[path] == id:
			return path
	return null


## Lays path `id` again as `data`, the garden's entry after a reshape.
func resurface(id: int, data: Dictionary) -> void:
	_garden[id] = data
	settle(id)


## Shows path `id` in the surface and with the clutter a reshape with `data` would give it, here alone, until `settle`.
func show_reshaped(id: int, data: Dictionary) -> void:
	var path := layout(id)
	if path == null:
		return
	var shown := World.reshaped(_garden[id], data)
	var surfaced: bool = path.surface != shown.surface
	if not surfaced and PackedVector4Array(path.clutter) == shown.clutter:
		return
	path.surface = shown.surface
	path.clutter.assign(Array(shown.clutter))
	if surfaced:
		marks.rewear_mark(path)
	_lay(path)


## Shows path `id` as the garden has it.
func settle(id: int) -> void:
	show_reshaped(id, {})


func _process(delta: float) -> void:
	marks.settle_due()
	_place()
	_since_rebuild += delta
	if _cut_due:
		_cut_due = false
		previewed.emit()
	elif _dirty and drawing != null and _since_rebuild >= WallTool.REBUILD_EVERY:
		_wear_tip()
		_cut_due = true


## Keep settled wear while rebuilding the moving tip, its arches cut at once.
func _relay() -> void:
	_wear_tip()
	_cut_due = false
	previewed.emit()


## Plans the stroke again and wears it: what a relay shows first. Its arches follow the frame after, so the two
## don't spend one frame.
func _wear_tip() -> void:
	marks.settle()
	if _seen != marks.rewears:
		_settled_mask = marks.image.duplicate()
		_settled_rows = 0
		_seen = marks.rewears
	drawing.plan()
	var stable := drawing.rows_before(drawing.settled())
	drawing.wear(_settled_mask, _settled_rows, stable)
	_settled_rows = stable
	marks.image.copy_from(_settled_mask)
	drawing.wear(marks.image, stable)
	marks.upload()
	_dirty = false
	_since_rebuild = 0.0


## The ground or the water over `area` changed: the paths there lay their treads, stepping stones and crops again.
func reground(area: Rect2, settled: bool) -> void:
	if settled:
		for path in layouts:
			if path.area.intersects(area):
				_lay(path)


## Lays `path`'s treads, stepping stones and crops on a worker from the ground and water as they stand, placed once done
## (`_place`); a bed's hundreds of plants took 8 ms on the main thread of a desktop.
func _lay(path: PathLayout) -> void:
	if masonry == null:
		return
	var out: Array[Dictionary] = []
	var task := WorkerThreadPool.add_task(_pack.bind(path.data(), terrain.held_height(), terrain.held_water(), Wall.kinds(), out))
	_laying[path] = out
	_jobs.append([task, path, out])


## The masonry parts a path from `data` lays on ground of `height` under water at `water`, into `out`, on a worker: it
## reads nothing but its arguments.
static func _pack(data: Dictionary, height: Callable, water: Callable, kinds: Array[Masonry.Kind], out: Array[Dictionary]) -> void:
	var layout := PathLayout.of(data)
	layout.plan()
	var wall := WallLayout.new()
	wall.stones = layout.pieces(height, water)
	var packed := Wall.pack(wall, kinds, Palette.plain())
	for k in Wall.Part.size():
		out.append(packed.chunks.get(k, {}))


## Places what finished workers laid, each path's latest only; with `all`, waits for every one first.
func _place(all := false) -> void:
	for i in range(_jobs.size() - 1, -1, -1):
		var job := _jobs[i]
		if not all and not WorkerThreadPool.is_task_completed(job[0]):
			continue
		WorkerThreadPool.wait_for_task_completion(job[0])
		_jobs.remove_at(i)
		var path: PathLayout = job[1]
		if is_same(_laying.get(path), job[2]):
			_laying.erase(path)
			if ids.has(path):
				masonry.place(-2000000 - ids[path], job[2])


## Whether path `id` is being laid again.
func laying(id: int) -> bool:
	return _laying.has(layout(id))


## Places every lay under way now: what a script or test reads next sees the paths' pieces.
func lay_now() -> void:
	_place(true)


func _exit_tree() -> void:
	_place(true)
