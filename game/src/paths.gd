class_name Paths
extends Node3D

## Every laid path: its stones, and the trodden earth it wears into the ground mask (Ground), which the
## terrain shader turns to earth and the grass and flower shaders read to part around the stones.

const MIN_LENGTH := 1.0
## Settled stones freeze into a chunk of this many, so a growing stroke relays only its tail.
const CHUNK := 256

## A path was laid, or put back by redo; `taken` when undo lifts it.
signal laid(path: PathLayout)
signal taken(path: PathLayout)

var layouts: Array[PathLayout] = []
var drawing: PathLayout
## The drawing stroke's stone chunks; the last is its unsettled tail.
var _chunks: Array[Stones] = []
var _chunks_of := {}
var _frozen := 0
var _settled_mask: Image
var _settled_rows := 0
var _since_rebuild := 0.0
var _dirty := false
var _seed := 1


func busy() -> bool:
	return drawing != null


func begin(p: Vector3, half: float) -> void:
	drawing = PathLayout.new()
	drawing.seed = _seed
	_seed += 1
	drawing.add(p, half)
	_chunks = [Stones.new(true)]
	add_child(_chunks[0])
	_frozen = 0
	_settled_mask = Ground.image.duplicate()
	_settled_rows = 0
	_dirty = true


func extend(p: Vector3, half: float) -> void:
	var pts := drawing.points
	if pts.size() >= 2 and pts[-1].distance_to(pts[-2]) < WallTool.POINT_SPACING:
		pts[-1] = p
		drawing.half_widths[-1] = maxf(drawing.half_widths[-1], clampf(half, PathLayout.HALF_WIDTH.x, PathLayout.HALF_WIDTH.y))
	else:
		drawing.add(p, half)
	_dirty = true


## Finishes the stroke; a stroke too short to read as a path is dropped with the ground it wore.
func end() -> PathLayout:
	_relay()
	var path := drawing
	drawing = null
	_settled_mask = null
	var chunks := _chunks
	_chunks = []
	if path.length() < MIN_LENGTH:
		for c in chunks:
			c.queue_free()
		Ground.rewear()
		return null
	_chunks_of[path] = chunks
	layouts.append(path)
	Ground.lay(path, true)
	laid.emit(path)
	return path


## The stone chunks of a laid path, for a history step to hold.
func chunks(path: PathLayout) -> Array[Node]:
	var out: Array[Node] = []
	out.assign(_chunks_of[path])
	return out


## Lifts a laid path, stones and wear, for undo.
func take(path: PathLayout) -> void:
	layouts.erase(path)
	for c in _chunks_of[path]:
		remove_child(c)
	Ground.lift(path)
	taken.emit(path)


func put(path: PathLayout) -> void:
	layouts.append(path)
	for c in _chunks_of[path]:
		add_child(c)
	Ground.lay(path)
	laid.emit(path)


func _process(delta: float) -> void:
	_since_rebuild += delta
	if _dirty and drawing != null and _since_rebuild >= WallTool.REBUILD_EVERY:
		_relay()


## Lays the stroke's unsettled tail again, freezing settled stones into chunks and settled rows into the ground mask.
func _relay() -> void:
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
