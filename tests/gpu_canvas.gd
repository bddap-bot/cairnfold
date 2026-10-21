extends SceneTree

## The canvas on the GPU, pixel for pixel: a painting undone through a checkpoint, or rebuilt from one with strokes
## replayed after it, dries to exactly what a fresh replay of the same strokes dries to. Needs a RenderingDevice, so
## scripts/test.sh runs it on the desktop renderer: godot4 --path game --xr-mode off --script ../tests/gpu_canvas.gd

const N := 40

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if RenderingServer.get_rendering_device() == null:
		print("FAIL: no RenderingDevice; run on the desktop renderer")
		Main.quit(self, 1)
		return
	var strokes := Driver.painting(N + 1)
	var kept := strokes.slice(0, N)

	var fresh := await _canvas()
	fresh.rebuild(kept)
	var want := await _dried(fresh)

	var undone := await _canvas()
	undone.rebuild(kept)
	await _caught_up(undone)
	undone.play(strokes[N], 30)
	var at := undone.last_end
	while undone.last_end == at:
		await process_frame
	undone.rebuild(kept)
	_check(not undone.catching_up(), "the undo is a checkpoint, with nothing to replay")
	var got := await _dried(undone)
	_check(got == want, "undone through a checkpoint, the canvas dries to what a fresh replay dries to")

	var resumed := await _canvas()
	resumed.rebuild(strokes.slice(0, N - 3))
	await _caught_up(resumed)
	resumed.rebuild(kept)
	_check(resumed.catching_up() and resumed._pending == 3, "only the strokes after the checkpoint replay")
	_check(await _dried(resumed) == want, "a checkpoint and the strokes after it dry to what a fresh replay dries to")

	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _canvas() -> Canvas:
	var c := Canvas.new()
	root.add_child(c)
	await process_frame
	return c


func _caught_up(c: Canvas) -> void:
	while c.catching_up():
		await process_frame


## The canvas's wet and dry paint once it has caught up and every tile has dried.
func _dried(c: Canvas) -> Array:
	await _caught_up(c)
	while c.wet():
		await process_frame
	return await _pixels(c)


func _pixels(c: Canvas) -> Array:
	var out := []
	var rd := RenderingServer.get_rendering_device()
	await process_frame
	RenderingServer.call_on_render_thread(func() -> void:
		out.append(rd.texture_get_data(c._wet[0], 0))
		out.append(rd.texture_get_data(c._dry, 0)))
	while out.size() < 2:
		await process_frame
	return out


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)
