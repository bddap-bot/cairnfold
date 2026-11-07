@abstract
class_name Bake
extends RefCounted

## A volume solved on a worker: one solve at a time, the next started for whatever changed while it ran.

var texture := ImageTexture3D.new()
## The ground the volume follows, and its heights_revision the last solve stood on.
var terrain: Terrain
var _ground := -1
var _task := -1
var _out := {}


## Takes a finished solve and starts one for whatever changed since; called once a frame.
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


## Solves everything changed so far before returning.
func finish() -> void:
	update()
	while _task >= 0:
		_collect()
		update()


## Lets a solve under way end, so none outlives the game.
func stop() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## The solve to run on the worker for what changed since the last began, returning what `_take` reads; an
## invalid Callable when nothing did.
@abstract func _next() -> Callable


## On the main thread, puts a finished solve's result in the volume.
@abstract func _take(out: Dictionary) -> void


## Whether the ground changed since the last call that asked.
func _ground_moved() -> bool:
	if _ground == terrain.heights_revision:
		return false
	_ground = terrain.heights_revision
	return true


func _collect() -> void:
	stop()
	_take(_out)
