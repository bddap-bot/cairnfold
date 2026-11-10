extends "res://../tests/support/suite.gd"

## Headless check that an avatar read on a worker thread finishes while the main thread waits for it, as a
## player's game does when it quits mid-read: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_avatar_worker.gd


func _run() -> void:
	var bytes := FileAccess.get_file_as_bytes(avatar_file("godette-0.x.vrm"))
	var out := {}
	var task := WorkerThreadPool.add_task(func() -> void: out.scene = Avatar.read(bytes))
	WorkerThreadPool.wait_for_task_completion(task)
	check(out.get("scene") != null, "the avatar read on a worker came back empty")
	finish()
