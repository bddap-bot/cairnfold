class_name Work
extends RefCounted

## A task is taken `frames` after it began, waited for then if not done, never whenever a worker finished it, so a
## replay is the session again however busy either machine was (docs/replay.md).

static var _due := {}
## A replay's first frame is paused and no session's is (Replayer); not counting paused frames keeps a task begun at
## boot due at the same frame of the record in both.
static var paused := 0


## High priority, since the frame waits for it: at normal priority other pool work held a Quest 2's perches back seconds.
static func start(job: Callable, frames: int) -> int:
	var task := WorkerThreadPool.add_task(job, true)
	_due[task] = now() + frames
	return task


static func due(task: int) -> bool:
	return now() >= _due.get(task, 0)


static func now() -> int:
	return Engine.get_process_frames() - paused


static func take(task: int) -> void:
	var at_frame := due(task)
	_due.erase(task)
	if WorkerThreadPool.is_task_completed(task) or not at_frame:
		WorkerThreadPool.wait_for_task_completion(task)
		return
	var start_us := Time.get_ticks_usec()
	WorkerThreadPool.wait_for_task_completion(task)
	Metrics.note("work: a worker ran over its frames", (Time.get_ticks_usec() - start_us) / 1000.0)
