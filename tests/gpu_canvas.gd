extends "res://../tests/support/suite.gd"

## The canvas on the GPU, pixel for pixel: a painting undone through a checkpoint, or rebuilt from one with strokes
## replayed after it, dries to exactly what a fresh replay of the same strokes dries to. Needs a RenderingDevice, so
## scripts/test.sh runs it on the desktop renderer: godot4 --path game --xr-mode off --script ../tests/gpu_canvas.gd

const N := 40


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if RenderingServer.get_rendering_device() == null:
		check(false, "no RenderingDevice; run on the desktop renderer")
		finish()
		return
	await _relief()
	await _smear()
	await _charcoal_contact()
	var strokes := Driver.painting(N + 1)
	var kept := strokes.slice(0, N)

	var steps := Canvas.steps
	Canvas.steps = 1.0e9
	var few := strokes.slice(0, 8)
	var whole := await _canvas()
	whole.rebuild(few)
	var unsplit := await _dried(whole)
	Canvas.steps = 200000.0
	var slow := await _canvas()
	slow.rebuild(few)
	check(await _dried(slow) == unsplit, "flow run a few rows a frame dries to what it dries to run whole")
	Canvas.steps = 1.0e9

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
	check(not undone.catching_up(), "the undo is a checkpoint, with nothing to replay")
	var got := await _dried(undone)
	check(got == want, "undone through a checkpoint, the canvas dries to what a fresh replay dries to")

	var resumed := await _canvas()
	resumed.rebuild(strokes.slice(0, N - 3))
	await _caught_up(resumed)
	resumed.rebuild(kept)
	check(resumed.catching_up() and resumed._pending == 3, "only the strokes after the checkpoint replay")
	check(await _dried(resumed) == want, "a checkpoint and the strokes after it dry to what a fresh replay dries to")
	Canvas.steps = steps

	finish()


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
	while c.wet() or not c.settled():
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


func _charcoal_image(side: float, drag: bool, pressure := 0.8) -> Dictionary:
	var c := await _canvas()
	var samples := Brushwork.pack(Vector2(0.5, 0.5), pressure, 0.0, 0, side)
	if drag:
		samples.append_array(Brushwork.pack(Vector2(0.6, 0.5), pressure, 0.0, 1, side))
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
	check(tap.total > 0.0 and tap.total < drag.total * 0.01 and tap.peak < drag.peak * 0.05, "rendered tap is faint beside drag at equal pressure: %s / %s" % [tap, drag])
	check(side.span.x > tap.span.x * 10 and side.span.y < tap.span.y * 1.5, "rendered side footprint follows stick length and width: %s / %s" % [side, tap])
	for lying in [0.0, 1.0]:
		var light := await _charcoal_image(lying, true, Brushwork.pressure(0.001))
		var firm := await _charcoal_image(lying, true, Brushwork.pressure(Brushwork.PRESS_DEPTH))
		var how := "on its side" if lying > 0.0 else "with its tip"
		check(light.total > 0.0 and firm.total > light.total * 3.0 and firm.peak > light.peak * 1.5, "a stick pushed in %s marks darker than one grazing the canvas: %s / %s" % [how, firm, light])
		check(firm.span.y > light.span.y * 1.5, "and wider: %s / %s" % [firm.span, light.span])


func _smear() -> void:
	var c := await _canvas()
	c.set_process(false)
	var rd := RenderingServer.get_rendering_device()
	var image := Image.create(Brushwork.SIZE.x, Brushwork.SIZE.y, false, Image.FORMAT_RGBAH)
	image.fill(Color(0, 0, 0, 0))
	for y in range(550, 600):
		for x in range(750, 770):
			image.set_pixel(x, y, Color(0.5, 0.25, 0.125, 0.75))
	RenderingServer.call_on_render_thread(func() -> void:
		var initial := rd.texture_create(rd.texture_get_format(c._wet[0]), RDTextureView.new(), [image.get_data()])
		c._copy(initial, c._wet[0])
		rd.free_rid(initial))
	var before := await _pixels(c)
	var stroke := {"medium": Brushwork.Medium.SMEAR, "brush": Brushwork.Brush.FLAT, "colour": Vector3.ZERO, "strength": 0.0, "load": 1.0, "gap": 0, "samples": Brushwork.pack(Vector2(0.5, 0.5), 1.0, 0.0, 0)}
	check(Brushwork.clean(stroke) != null, "smear stroke validates")
	var forged := stroke.duplicate()
	forged.colour = Vector3.ONE
	check(Brushwork.clean(forged) == null, "smear cannot introduce pigment")
	c.lay(stroke, Brushwork.Stroker.new(stroke).add(Brushwork.unpack(stroke.samples, 0)))
	c._process(0.0)
	var after := await _pixels(c)
	check(before[0] != after[0], "feathers move existing wet paint")
	check(before[1] == after[1], "smear leaves dry paint untouched")
	var moved := Image.create_from_data(Brushwork.SIZE.x, Brushwork.SIZE.y, false, Image.FORMAT_RGBAH, after[0])
	var total := Vector4.ZERO
	for y in range(500, 650):
		for x in range(700, 850):
			var pixel := moved.get_pixel(x, y)
			total += Vector4(pixel.r, pixel.g, pixel.b, pixel.a)
	check((total - Vector4(500,250,125,750)).length() < 1.0, "smear conserves pigment and water within half-float rounding")
	c.queue_free()
	await process_frame


func _normal_pixels(c: Canvas, frozen := false) -> PackedByteArray:
	var out := []
	RenderingServer.call_on_render_thread(func() -> void:
		out.append(c._rd.texture_get_data(c._frozen[2] if frozen else c._normal, 0)))
	while out.is_empty():
		await process_frame
	return out[0]


func _relief() -> void:
	var c := Canvas.new(Vector2i(192, 128))
	root.add_child(c)
	c.set_process(false)
	await process_frame
	var bare := await _normal_pixels(c)
	var rect := Rect2i(181, 117, 11, 11)
	var image := Image.create(c.size.x, c.size.y, false, Image.FORMAT_RGBAH)
	image.fill(Color(0, 0, 0, 0))
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			image.set_pixel(x, y, Color(0, 0, 0, 0.25 if y % 2 == 0 else 0.75))
	RenderingServer.call_on_render_thread(func() -> void:
		var rd := c._rd
		var initial := rd.texture_create(rd.texture_get_format(c._dry), RDTextureView.new(), [image.get_data()])
		c._copy(initial, c._dry)
		rd.free_rid(initial)
		c._update_normals(rect))
	var incremental := await _normal_pixels(c)
	check(incremental != bare, "paint changes the relief normal mip chain")
	RenderingServer.call_on_render_thread(c._update_normals.bind(Rect2i(Vector2i.ZERO, c.size)))
	check(await _normal_pixels(c) == incremental, "dirty normal updates match a full rebuild through odd-sized mips and texture edges")
	c._blank = false
	c._freeze()
	check(await _normal_pixels(c, true) == incremental, "a replay's frozen painting retains every normal mip")
	c._thaw()
	check(c._shown[3].texture_rd_rid == c._normal, "a completed replay shows the live normal chain")
	c.queue_free()
	await process_frame
