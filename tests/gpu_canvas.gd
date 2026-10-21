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
	await _charcoal_contact()
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


func _charcoal_image(side: float, drag: bool) -> Dictionary:
	var c := await _canvas()
	var samples := Brushwork.pack(Vector2(0.5, 0.5), 0.8, 0.0, 0, side)
	if drag:
		samples.append_array(Brushwork.pack(Vector2(0.6, 0.5), 0.8, 0.0, 1, side))
	var stroke := {"medium": Brushwork.Medium.CHARCOAL, "brush": Brushwork.Brush.STICK, "colour": Brushwork.CHARCOAL, "strength": 1.0, "load": 1.0, "gap": 0, "samples": samples}
	c.rebuild([stroke])
	var pixels := await _dried(c)
	var im := Image.create_from_data(Brushwork.SIZE.x, Brushwork.SIZE.y, false, Image.FORMAT_RGBAH, pixels[1])
	var total := 0.0
	var peak := 0.0
	var low := Vector2i(Brushwork.SIZE)
	var high := Vector2i.ZERO
	for y in range(Brushwork.SIZE.y / 2 - 160, Brushwork.SIZE.y / 2 + 160):
		for x in range(Brushwork.SIZE.x / 2 - 160, Brushwork.SIZE.x / 2 + 320):
			var density := im.get_pixel(x, y).r
			total += density
			peak = maxf(peak, density)
			if density > 0.0001:
				low = Vector2i(mini(low.x, x), mini(low.y, y))
				high = Vector2i(maxi(high.x, x), maxi(high.y, y))
	c.queue_free()
	await process_frame
	return {"total": total, "peak": peak, "span": high - low}


func _charcoal_contact() -> void:
	var tap := await _charcoal_image(0.0, false)
	var drag := await _charcoal_image(0.0, true)
	var side := await _charcoal_image(1.0, false)
	_check(tap.total > 0.0 and tap.total < drag.total * 0.01 and tap.peak < drag.peak * 0.05, "rendered tap is faint beside drag at equal pressure: %s / %s" % [tap, drag])
	_check(side.span.x > tap.span.x * 10 and side.span.y < tap.span.y * 1.5, "rendered side footprint follows stick length and width: %s / %s" % [side, tap])
