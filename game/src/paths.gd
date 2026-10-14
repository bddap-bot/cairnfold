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

var layouts: Array[PathLayout] = []
## Each laid path's build command id; `layouts` keeps id order.
var ids := {}
var drawing: PathLayout
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


func busy() -> bool:
	return drawing != null


func begin(p: Vector3, half: float) -> void:
	drawing = PathLayout.new()
	drawing.seed = randi()
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
	var ghost := {"data": {"points": PackedVector3Array(path.points), "half_widths": PackedFloat32Array(path.half_widths), "seed": path.seed}, "chunks": chunks, "layout": path}
	Ground.hold(path)
	if path.length() < MIN_LENGTH:
		drop(ghost)
		return {}
	return ghost


## A ghost from `end` gives way: its command landed, was turned down, or the garden was swapped.
func drop(ghost: Dictionary) -> void:
	for c: Stones in ghost.chunks:
		remove_child(c)
		c.queue_free()
	Ground.release(ghost.layout)


## A stroke under way belongs to a garden being swapped away.
func forget() -> void:
	if drawing != null:
		drawing = null
		_settled_mask = null
		for c in _chunks:
			remove_child(c)
			c.queue_free()
		_chunks = []
		Ground.rewear()


## The garden's side of a path being laid, from any player: built from its data and kept in id order, so
## the arches paths open in walls and the ground they wear come out alike on every machine.
func put(id: int, data: Dictionary) -> void:
	var path := PathLayout.new()
	path.seed = data.seed
	for i in data.points.size():
		path.add(data.points[i], data.half_widths[i])
	path.build()
	var chunks: Array[Stones] = []
	for at in range(0, path.stones.size(), CHUNK):
		var c := Stones.new(true)
		c.lay(path.stones.slice(at, at + CHUNK))
		add_child(c)
		chunks.append(c)
	_chunks_of[path] = chunks
	ids[path] = id
	var i := 0
	while i < layouts.size() and ids[layouts[i]] < id:
		i += 1
	layouts.insert(i, path)
	Ground.lay(path, id)
	laid.emit(path)


func take(id: int) -> void:
	for path in layouts:
		if ids[path] == id:
			layouts.erase(path)
			ids.erase(path)
			for c in _chunks_of[path]:
				remove_child(c)
				c.queue_free()
			_chunks_of.erase(path)
			Ground.lift(path)
			taken.emit(path)
			return


func _process(delta: float) -> void:
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
	var stable := drawing.row_lengths.bsearch(drawing.settled())
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
