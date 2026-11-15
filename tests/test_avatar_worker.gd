extends "res://../tests/support/suite.gd"

## The main thread waits on the read, as a game quitting mid-read does.


func _run() -> void:
	var bytes := FileAccess.get_file_as_bytes(avatar_file("godette-0.x.vrm"))
	var out := {}
	var task := WorkerThreadPool.add_task(func() -> void: out.scene = Avatar.read(bytes))
	WorkerThreadPool.wait_for_task_completion(task)
	check(out.get("scene") != null, "the avatar read on a worker came back empty")
	finish()
