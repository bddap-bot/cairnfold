class_name Work
extends RefCounted

## Worker-pool tasks whose results game logic reads, each taken at a frame the frames decide: `frames` after the one it
## began in, and waited for then if it is not done, never on whichever frame a worker happened to finish it. So a
## replay is the session again however busy either machine was (docs/replay.md).

static var _due := {}
## Frames the tree spent paused, which a replay's first frame is and no session has (Replayer): frames count without
## them, so a task begun as the game booted is due at the same frame of the record in both.
static var paused := 0


## Starts `job` on the worker pool, to be taken `frames` frames from now. It runs at high priority, since the frame
## waits for it then: at normal priority the pool's other work held a Quest 2's perches back for seconds.
static func start(job: Callable, frames: int) -> int:
	var task := WorkerThreadPool.add_task(job, true)
	_due[task] = now() + frames
	return task


## Whether `task` is to be taken this frame; a task Work did not start is due at once.
static func due(task: int) -> bool:
	return now() >= _due.get(task, 0)


## The frame under way, the replay's paused one not counted.
static func now() -> int:
	return Engine.get_process_frames() - paused


## Waits for `task`, as at its frame or for a caller that reads it at once. Only a wait at its frame is noted, the time
## its job ran over the frames it was given.
static func take(task: int) -> void:
	var at_frame := due(task)
	_due.erase(task)
	if WorkerThreadPool.is_task_completed(task) or not at_frame:
		WorkerThreadPool.wait_for_task_completion(task)
		return
	var start_us := Time.get_ticks_usec()
	WorkerThreadPool.wait_for_task_completion(task)
	Metrics.note("work: a worker ran over its frames", (Time.get_ticks_usec() - start_us) / 1000.0)
