class_name TerrainTool
extends Node3D

## Shapes the ground: a grabbed point follows the hand up into a hill or down into a hollow, and the
## stroke is baked into the ground when it lets go.

const MIN_RADIUS := 2.0
const MAX_RADIUS := 9.0
## Hills widen with height so their flanks stay walkable and walls on them stay standing.
const SPREAD := 3.0
const MAX_LIFT := 6.0
const FOLLOW_EVERY := 0.06

## Ground under `area` moved; `settled` once a stroke ends or a step is undone or redone.
signal reshaped(area: Rect2, settled: bool)


## One stroke's heights before and after, for undo and redo.
class Edit:
	var cells: Rect2i
	var before: PackedFloat32Array
	var after: PackedFloat32Array


var _grabbed: Variant = null
var _base_radius := MIN_RADIUS
var _radius := MIN_RADIUS
var _moved := Rect2()
var _since_follow := 0.0


func pulling() -> bool:
	return _grabbed != null


func begin(ground: Vector3, radius: float) -> void:
	assert(_grabbed == null)
	_grabbed = ground
	_base_radius = clampf(radius, MIN_RADIUS, MAX_RADIUS)
	_radius = _base_radius
	_since_follow = 0.0
	_moved = _span(_radius)


## Raises the grabbed ground `metres` above where the stroke began (negative digs).
func pull(metres: float) -> void:
	var g: Vector3 = _grabbed
	var lift := clampf(metres, clampf(Terrain.LOWEST - g.y, -MAX_LIFT, 0.0), clampf(Terrain.HIGHEST - g.y, 0.0, MAX_LIFT))
	_radius = maxf(_base_radius, absf(lift) * SPREAD)
	Terrain.set_hump(g.x, g.z, _radius, lift)
	_moved = _moved.merge(_span(_radius))


## Lets walls and the player catch up with a stroke, at most every FOLLOW_EVERY.
func follow(delta: float) -> void:
	_since_follow += delta
	if _since_follow >= FOLLOW_EVERY:
		_since_follow = 0.0
		reshaped.emit(_moved, false)


func end() -> Edit:
	var g: Vector3 = _grabbed
	_grabbed = null
	var e := Edit.new()
	e.cells = Terrain.cells_around(g.x, g.z, _radius)
	e.before = Terrain.read(e.cells)
	Terrain.bake()
	e.after = Terrain.read(e.cells)
	reshaped.emit(_moved, true)
	return e


func restore(cells: Rect2i, values: PackedFloat32Array) -> void:
	Terrain.write(cells, values)
	reshaped.emit(Terrain.world_rect(cells), true)


func _span(r: float) -> Rect2:
	var g: Vector3 = _grabbed
	return Rect2(g.x - r, g.z - r, r * 2.0, r * 2.0).grow(Terrain.STEP)
