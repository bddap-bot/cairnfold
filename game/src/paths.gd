class_name Paths
extends Node3D

## Dirt strokes and the earth they wear into the ground mask.

const MIN_LENGTH := 1.0

signal laid(path: PathLayout)
signal taken(path: PathLayout)
signal previewed()

var terrain: Terrain
var marks: Ground
var masonry: Masonry
var layouts: Array[PathLayout] = []
## Each laid path's build command id; `layouts` keeps id order.
var ids := {}
var drawing: PathLayout
var previews: Array[PathLayout] = []
var _settled_mask: Image
var _settled_rows := 0
var _since_rebuild := 0.0
var _dirty := false
## `marks.rewears` when the drawing's settled mask was taken: a rewear since wiped the drawn wear.
var _seen := -1


func busy() -> bool:
	return drawing != null


func begin(p: Vector3, half: float) -> void:
	drawing = PathLayout.new()
	previews.append(drawing)
	drawing.seed = randi()
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
	ids[path] = id
	var i := 0
	while i < layouts.size() and ids[layouts[i]] < id:
		i += 1
	layouts.insert(i, path)
	marks.lay(path, id)
	_steps(path)
	laid.emit(path)


func take(id: int) -> void:
	for path in layouts:
		if ids[path] == id:
			layouts.erase(path)
			ids.erase(path)
			marks.lift(path)
			if masonry != null:
				masonry.remove(-2000000 - id)
			taken.emit(path)
			return


func _process(delta: float) -> void:
	marks.settle_due()
	_since_rebuild += delta
	if _dirty and drawing != null and _since_rebuild >= WallTool.REBUILD_EVERY:
		_relay()


## Keep settled wear while rebuilding the moving tip.
func _relay() -> void:
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
	previewed.emit()


func reground(area: Rect2, settled: bool) -> void:
	if settled:
		for path in layouts:
			if path.area.intersects(area):
				_steps(path)


func _steps(path: PathLayout) -> void:
	if masonry == null:
		return
	var wall := WallLayout.new()
	wall.stones = path.steps(terrain.held_height())
	var packed := Wall.pack(wall, Wall.kinds(), Palette.plain())
	var parts: Array[Dictionary] = []
	for k in Wall.Part.size():
		parts.append(packed.chunks.get(k, {}))
	masonry.place(-2000000 - ids[path], parts)
