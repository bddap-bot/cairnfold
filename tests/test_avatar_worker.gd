extends SceneTree

## Headless check that an avatar read on a worker thread finishes while the main thread waits for it, as a
## player's game does when it quits mid-read: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_avatar_worker.gd


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var bytes := FileAccess.get_file_as_bytes(ProjectSettings.globalize_path("res://").path_join("../tests/avatars/godette-0.x.vrm"))
	var out := {}
	var task := WorkerThreadPool.add_task(func() -> void: out.scene = Avatar.read(bytes))
	WorkerThreadPool.wait_for_task_completion(task)
	var ok: bool = out.get("scene") != null
	if not ok:
		print("FAIL: the avatar read on a worker came back empty")
	print("tests: %s" % ("ok" if ok else "FAILED 1"))
	Main.quit(self, 0 if ok else 1)
