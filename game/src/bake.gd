@abstract
class_name Bake
extends RefCounted

var terrain: Terrain
## `terrain`'s heights_revision the last solve stood on.
var _ground := -1
var _task := -1
var _out := {}
## Before any room is known.
static var no_rooms := Lamps.Rooms.new()
## The rooms what this shows was solved for. Solves for other rooms are `held`, in order, until Look shows them
## together with the other bake's for the same rooms: one showing a room the other does not yet lights the walls on
## its edge wrong.
var shown_rooms := no_rooms
var held: Array[Dictionary] = []


## Called once a frame.
func update() -> void:
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task):
			return
		_collect()
	var work := _next()
	if not work.is_valid():
		return
	var out := {}
	_out = out
	_task = WorkerThreadPool.add_task(func() -> void: out.merge(work.call()), false)


func finish() -> void:
	update()
	while _task >= 0:
		_collect()
		update()
	if not held.is_empty():
		show_held()


func show_held() -> void:
	for out in held:
		_take(out)
	shown_rooms = held[-1].rooms
	held = []


func stop() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## Runs on the worker and returns what `_take` reads; an invalid Callable when nothing changed.
@abstract func _next() -> Callable


## On the main thread.
@abstract func _take(out: Dictionary) -> void


## Consumes the change: true once per heights_revision.
func _ground_moved() -> bool:
	if _ground == terrain.heights_revision:
		return false
	_ground = terrain.heights_revision
	return true


func _collect() -> void:
	stop()
	var rooms: Lamps.Rooms = _out.get("rooms", shown_rooms)
	if rooms == shown_rooms:
		_take(_out)
		return
	if not held.is_empty() and held[-1].rooms != rooms:
		for out in held:
			_take(out)
		held = []
	held.append(_out)
