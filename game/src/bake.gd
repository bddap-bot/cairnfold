@abstract
class_name Bake
extends RefCounted

var terrain: Terrain
## `terrain`'s heights_revision the last solve stood on.
var _ground := -1
var _task := -1
var _out := {}


## What was given the fields `step` drives before this frame is drawn.
static var drawn_before := -1
static var _began := -1
static var _stepped := -1


## Called once a frame with every field a build reads. What they solved is taken in one frame, so those fields change
## together, and a build waiting for them (Wall) shows its lay in that frame; then each starts on what it has been given.
static func step(bakes: Array[Bake]) -> void:
	_stepped = Engine.get_process_frames()
	for b in bakes:
		if b._task >= 0 and not WorkerThreadPool.is_task_completed(b._task):
			return
	for b in bakes:
		if b._task >= 0:
			b._collect()
	drawn_before = _began
	_began = Engine.get_process_frames()
	for b in bakes:
		b._begin()


## Whether anything steps the fields: a build waits for them only then.
static func stepping() -> bool:
	return _stepped >= Engine.get_process_frames() - 1


func finish() -> void:
	if _task >= 0:
		_collect()
	_begin()
	while _task >= 0:
		_collect()
		_begin()


func _begin() -> void:
	var work := _next()
	if not work.is_valid():
		return
	var out := {}
	_out = out
	_task = WorkerThreadPool.add_task(func() -> void: out.merge(work.call()), false)


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
	_take(_out)
