class_name Paths
extends Node3D

## Every laid path: its stones, and the glade's ground mask (the shader global path_mask) that wears the
## terrain to earth and parts the grass and flowers along it.

const MASK_SIZE := 512
const TEXEL := Terrain.SIZE / MASK_SIZE
const MIN_LENGTH := 1.0
## The mask fades out over this much ground past a path's stones.
const VERGE := 0.3
## Settled stones freeze into a chunk of this many, so a growing stroke relays only its tail.
const CHUNK := 256

## Opaque black is untrodden; each row of stones blends a soft white disc over it.
static var mask_image := Image.create(MASK_SIZE, MASK_SIZE, false, Image.FORMAT_LA8)
static var mask := ImageTexture.create_from_image(mask_image)
static var _brushes := {}

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


## How worn the ground is at a point, 0 meadow to 1 path, as the shaders read it.
static func cover(x: float, z: float) -> float:
	var px := clampi(int((x / Terrain.SIZE + 0.5) * MASK_SIZE), 0, MASK_SIZE - 1)
	var pz := clampi(int((z / Terrain.SIZE + 0.5) * MASK_SIZE), 0, MASK_SIZE - 1)
	return mask_image.get_pixel(px, pz).r


static func clear_mask() -> void:
	mask_image.fill(Color(0, 0, 0, 1))
	mask.update(mask_image)


## A soft disc reaching `VERGE` past `half` metres: full where the stones lie, fading to nothing.
static func _brush(half: float) -> Image:
	var key := roundi(half / TEXEL * 4.0)
	if not _brushes.has(key):
		var outer := key * TEXEL / 4.0 + VERGE
		var r := ceili(outer / TEXEL)
		var img := Image.create(r * 2 + 1, r * 2 + 1, false, Image.FORMAT_LA8)
		for y in r * 2 + 1:
			for x in r * 2 + 1:
				var d := Vector2(x - r, y - r).length() * TEXEL
				img.set_pixel(x, y, Color(1, 1, 1, clampf((outer - d) / (VERGE + 0.1), 0.0, 1.0)))
		_brushes[key] = img
	return _brushes[key]


static func _stamp(onto: Image, path: PathLayout, from_row: int, to_row: int) -> void:
	for k in range(from_row, to_row):
		var f := path.frame_at(path.row_lengths[k])
		var brush := _brush(f.half)
		var r := (brush.get_width() - 1) / 2
		var at := Vector2i(roundi((f.point.x / Terrain.SIZE + 0.5) * MASK_SIZE - 0.5) - r, roundi((f.point.z / Terrain.SIZE + 0.5) * MASK_SIZE - 0.5) - r)
		onto.blend_rect(brush, Rect2i(Vector2i.ZERO, brush.get_size()), at)


func _ready() -> void:
	clear_mask()
	RenderingServer.global_shader_parameter_set(&"path_mask", mask)


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
	_settled_mask = mask_image.duplicate()
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
		_rewear()
		return null
	_chunks_of[path] = chunks
	layouts.append(path)
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
	_rewear()
	taken.emit(path)


func put(path: PathLayout) -> void:
	layouts.append(path)
	for c in _chunks_of[path]:
		add_child(c)
	_stamp(mask_image, path, 0, path.row_lengths.size())
	mask.update(mask_image)
	laid.emit(path)


func _rewear() -> void:
	mask_image.fill(Color(0, 0, 0, 1))
	for p in layouts:
		_stamp(mask_image, p, 0, p.row_lengths.size())
	mask.update(mask_image)


func _process(delta: float) -> void:
	_since_rebuild += delta
	if _dirty and drawing != null and _since_rebuild >= WallTool.REBUILD_EVERY:
		_relay()


## Lays the stroke's unsettled tail again, freezing settled stones into chunks and settled rows into the mask.
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
	_stamp(_settled_mask, drawing, _settled_rows, stable)
	_settled_rows = stable
	mask_image.copy_from(_settled_mask)
	_stamp(mask_image, drawing, stable, drawing.row_lengths.size())
	mask.update(mask_image)
	_dirty = false
	_since_rebuild = 0.0
