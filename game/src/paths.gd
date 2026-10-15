class_name Paths
extends Node3D

## Every laid path: its stones, and the trodden earth it wears into the ground mask (Ground), which the
## terrain shader turns to earth and the grass and flower shaders read to part around the stones.

const MIN_LENGTH := 1.0
## Settled stones freeze into a chunk of this many, so a growing stroke relays only its tail.
const CHUNK := 256

## A path was laid in the garden; `taken` when it is lifted.
signal laid(path: PathLayout)
signal taken(path: PathLayout)
signal previewed()

var layouts: Array[PathLayout] = []
## Each laid path's build command id; `layouts` keeps id order.
var ids := {}
var drawing: PathLayout
var previews: Array[PathLayout] = []
## The drawing stroke's stone chunks; the last is its unsettled tail.
var _chunks: Array[Stones] = []
var _chunks_of := {}
var _frozen := 0
var _settled_mask: Image
var _settled_rows := 0
var _since_rebuild := 0.0
var _dirty := false
## Ground.rewears when the drawing's settled mask was taken: a rewear since wiped the drawn wear.
var _seen := -1
## Laying stones on a worker thread: [path, the copy of it laying them] pairs.
var _task := -1
var _jobs: Array[Array] = []
## Paths whose stones must be laid again, and the ground of paths taken, which later paths paved around.
var _stale: Array[PathLayout] = []
var _gone: Array[Rect2] = []
## Finished strokes' stones, shown until the stones laid from their commands are.
var _fading: Array[Stones] = []


func busy() -> bool:
	return drawing != null


func begin(p: Vector3, half: float) -> void:
	drawing = PathLayout.new()
	previews.append(drawing)
	drawing.seed = randi()
	drawing.others = layouts.duplicate()
	drawing.add(p, half)
	_chunks = [Stones.new(true)]
	add_child(_chunks[0])
	_frozen = 0
	_settled_mask = Ground.image.duplicate()
	_settled_rows = 0
	_seen = Ground.rewears
	_dirty = true


func extend(p: Vector3, half: float) -> void:
	var pts := drawing.points
	if Commands.length(pts) >= Commands.STROKE_LENGTH or pts.size() >= Commands.MAX_PATH_POINTS:
		return
	if pts.size() >= 2 and pts[-1].distance_to(pts[-2]) < WallTool.POINT_SPACING:
		pts[-1] = p
		drawing.half_widths[-1] = maxf(drawing.half_widths[-1], clampf(half, PathLayout.HALF_WIDTH.x, PathLayout.HALF_WIDTH.y))
	else:
		drawing.add(p, half)
	_dirty = true


## Finishes the stroke as a ghost, its stones and wear left standing until `drop`: the path's data for a
## build command, its layout, and the stone chunks. A stroke too short to read as a path is dropped at once: {}.
func end() -> Dictionary:
	_relay()
	var path := drawing
	drawing = null
	_settled_mask = null
	var chunks := _chunks
	_chunks = []
	var ghost := {"data": path.data(), "chunks": chunks, "layout": path}
	Ground.hold(path)
	if path.length() < MIN_LENGTH:
		drop(ghost)
		return {}
	return ghost


## A ghost from `end` gives way: its command landed, was turned down, or the garden was swapped.
func drop(ghost: Dictionary) -> void:
	_fading.append_array(ghost.chunks)
	Ground.release(ghost.layout)
	_launch()
	previews.erase(ghost.layout)
	previewed.emit()


## A stroke under way belongs to a garden being swapped away.
func forget() -> void:
	if drawing != null:
		previews.erase(drawing)
		drawing = null
		_settled_mask = null
		for c in _chunks:
			remove_child(c)
			c.queue_free()
		_chunks = []
		Ground.rewear()
		previewed.emit()


## The garden's side of a path being laid, from any player: kept in id order, so the arches paths open in
## walls, the ground they wear and the stones each lays around those of earlier paths come out alike on every
## machine. Its stones are laid on a worker thread.
func put(id: int, data: Dictionary) -> void:
	var path := PathLayout.of(data)
	path.plan()
	ids[path] = id
	var i := 0
	while i < layouts.size() and ids[layouts[i]] < id:
		i += 1
	layouts.insert(i, path)
	_chunks_of[path] = []
	_stale.append(path)
	_launch()
	Ground.lay(path, id)
	laid.emit(path)


func take(id: int) -> void:
	for path in layouts:
		if ids[path] == id:
			layouts.erase(path)
			ids.erase(path)
			_unlay(path)
			_chunks_of.erase(path)
			_stale.erase(path)
			_gone.append(path.area)
			_launch()
			Ground.lift(path)
			taken.emit(path)
			return


## Whether stones are still being laid on a worker thread.
func laying() -> bool:
	return _task >= 0 or not _stale.is_empty() or not _gone.is_empty()


## Lays again, on a worker thread, the stones of the stale paths and of every later path whose ground meets
## one being laid again or taken, each around the paths before it.
func _launch() -> void:
	if _task >= 0:
		return
	if not laying():
		for c in _fading:
			remove_child(c)
			c.queue_free()
		_fading.clear()
		return
	var touched := _gone.duplicate()
	var before: Array[PathLayout] = []
	var jobs: Array[Array] = []
	for path in layouts:
		if _stale.has(path) or touched.any(func(r: Rect2) -> bool: return r.intersects(path.area)):
			var job := PathLayout.of(path.data())
			job.others = before.duplicate()
			jobs.append([path, job])
			touched.append(path.area)
			before.append(job)
		else:
			before.append(path)
	_stale.clear()
	_gone.clear()
	_jobs = jobs
	_task = WorkerThreadPool.add_task(func():
		for j in jobs:
			j[1].build())


func _laid() -> void:
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	for j in _jobs:
		var path: PathLayout = j[0]
		if not ids.has(path):
			continue
		path.adopt(j[1])
		_unlay(path)
		for at in range(0, path.stones.size(), CHUNK):
			var c := Stones.new(true)
			c.lay(path.stones.slice(at, at + CHUNK))
			add_child(c)
			_chunks_of[path].append(c)
	_jobs = []
	_launch()


func _unlay(path: PathLayout) -> void:
	for c in _chunks_of[path]:
		remove_child(c)
		c.queue_free()
	_chunks_of[path] = []


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _process(delta: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		_laid()
	_since_rebuild += delta
	if _dirty and drawing != null and _since_rebuild >= WallTool.REBUILD_EVERY:
		_relay()


## Lays the stroke's unsettled tail again, freezing settled stones into chunks and settled rows into the ground mask.
func _relay() -> void:
	if _seen != Ground.rewears:
		_settled_mask = Ground.image.duplicate()
		_settled_rows = 0
		_seen = Ground.rewears
	drawing.build(drawing.settled())
	var stable := drawing.rows_before(drawing.settled())
	var settled_stones := drawing.row_starts[stable] if stable < drawing.row_starts.size() else drawing.stones.size()
	if settled_stones - _frozen >= CHUNK:
		_chunks[-1].lay(drawing.stones.slice(_frozen, settled_stones))
		_frozen = settled_stones
		_chunks.append(Stones.new(true))
		add_child(_chunks[-1])
	_chunks[-1].lay(drawing.stones.slice(_frozen))
	drawing.wear(_settled_mask, _settled_rows, stable)
	_settled_rows = stable
	Ground.image.copy_from(_settled_mask)
	drawing.wear(Ground.image, stable)
	Ground.upload()
	_dirty = false
	_since_rebuild = 0.0
	previewed.emit()
