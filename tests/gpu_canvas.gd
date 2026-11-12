extends "res://../tests/support/suite.gd"

## The canvas on the GPU, pixel for pixel: a painting undone through a checkpoint, or rebuilt from one with strokes
## replayed after it, dries to exactly what a fresh replay of the same strokes dries to. Needs a RenderingDevice, so
## scripts/test.sh runs it on the desktop renderer: godot4 --path game --xr-mode off --script ../tests/gpu_canvas.gd

const N := 40


func _run() -> void:
	await _relief()
	await _smear()
	await _charcoal_contact()
	var strokes := Driver.painting(N + 1)
	var kept := strokes.slice(0, N)

	var steps := Canvas.steps
	Canvas.steps = 1.0e9
	await _runs_down()
	await _light_wash_stays()
	await _water_fills_no_more_than_full()
	await _a_wash()
	await _oil_takes_up_wet_paint()
	await _charcoal_passes_darken_less()
	await _flat_brush_is_flat()
	await _wet_paint_shows()
	await _relief_undone()
	check(await _dries_alike(strokes.slice(0, 8)), "flow run a few rows a frame dries to what it dries to run whole")
	check(await _dries_alike(_crowd()), "more dabs than a batch holds, on tiles wet again after drying, dry the same run whole or a few rows a frame")

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
	RenderingServer.call_on_render_thread(_spoil.bind(undone))
	undone.rebuild(kept)
	check(not undone.catching_up(), "the undo is a checkpoint, with nothing to replay")
	var got := await _dried(undone)
	check(got == want, "undone through a checkpoint, whatever its scratch texture held, the canvas dries to what a fresh replay dries to")

	var resumed := await _canvas()
	resumed.rebuild(strokes.slice(0, N - 3))
	await _caught_up(resumed)
	resumed.rebuild(kept)
	check(resumed.catching_up() and resumed._pending == 3, "only the strokes after the checkpoint replay")
	check(await _dried(resumed) == want, "a checkpoint and the strokes after it dry to what a fresh replay dries to")
	Canvas.steps = steps

	finish()


## Fills the canvas's scratch texture with paint that was never laid: nothing a flow step or a smear leaves may come of
## it. The paint is finite, since a smear weighs what it reads there by nothing, and nothing times infinity is not a number.
func _spoil(c: Canvas) -> void:
	c._rd.texture_clear(c._wet[1], Color(9, 9, 9, 9), 0, 1, 0, 1)


## Thin strokes over the same tiles, the last a drying time after the rest: replayed in one frame, the rest are more
## dabs than one batch has room for, and the last wets tiles that have dried since the frame's batch began.
func _crowd() -> Array:
	var out := []
	var dabs := 0
	for k in 14:
		var samples := PackedInt32Array()
		for i in 15:
			samples.append_array(Brushwork.pack(Vector2(0.2 + 0.02 * i, 0.4 + 0.005 * k), 0.1, 0.0, 0 if i == 0 else 2))
		var stroke := {"medium": Brushwork.Medium.WATER, "brush": Brushwork.Brush.SMALL, "colour": Brushwork.absorbance(Brushwork.PIGMENTS[1 + k % 4]), "strength": 0.8, "load": 1.0, "gap": Brushwork.DRY_TICKS if k == 13 else 0, "samples": samples}
		if k < 13:
			var s := Brushwork.Stroker.new(stroke)
			for i in 15:
				dabs += s.add(Brushwork.unpack(samples, i)).size() / Brushwork.DAB
		out.append(stroke)
	check(dabs > Canvas.DAB_ROOM, "the strokes before the last are more dabs than a batch holds: %d" % dabs)
	return out


## Whether `strokes` dry to the same paint replayed whole, in one frame, and a few rows a frame.
func _dries_alike(strokes: Array) -> bool:
	var whole := await _canvas()
	whole.rebuild(strokes)
	var want := await _dried(whole)
	check(whole._replay_frames == 1, "a replay run whole takes one frame: %d" % whole._replay_frames)
	Canvas.steps = 200000.0
	var slow := await _canvas()
	slow.rebuild(strokes)
	var alike := await _dried(slow) == want
	Canvas.steps = 1.0e9
	whole.queue_free()
	slow.queue_free()
	await process_frame
	return alike


## The row the dried pigment of four very wet strokes along one line balances on, on a canvas standing up or lying flat.
func _balance(upright: bool) -> float:
	var c := await _canvas()
	c.upright = upright
	var samples := PackedInt32Array()
	for i in 15:
		samples.append_array(Brushwork.pack(Vector2(0.3 + 0.02 * i, 0.3), 1.0, 0.0, 0 if i == 0 else 1))
	var strokes := []
	for k in 4:
		strokes.append({"medium": Brushwork.Medium.WATER, "brush": Brushwork.Brush.BIG, "colour": Brushwork.absorbance(Brushwork.PIGMENTS[5]), "strength": 1.0, "load": 1.0, "gap": 0, "samples": samples})
	c.rebuild(strokes)
	var im := Image.create_from_data(c.size.x, c.size.y, false, Image.FORMAT_RGBAH, (await _dried(c))[1])
	var mass := 0.0
	var moment := 0.0
	var row := int(0.3 * c.size.y)
	for y in range(row - 100, row + 100):
		for x in range(c.size.x / 5, c.size.x * 2 / 3, 4):
			var density := im.get_pixel(x, y).r
			mass += density
			moment += density * y
	c.queue_free()
	await process_frame
	return moment / mass


func _runs_down() -> void:
	var standing := await _balance(true)
	var lying := await _balance(false)
	check(standing > lying + 0.3, "very wet paint runs down a canvas standing up, and not one lying flat: balanced on rows %.2f and %.2f" % [standing, lying])


## A wash too thin to run dries the same on a canvas standing up as on one lying flat.
func _light_wash_stays() -> void:
	var dried := []
	for upright in [true, false]:
		var c := await _canvas()
		c.upright = upright
		c.rebuild([_water([Vector2(0.4, 0.4)], 0.5, 0.4)])
		dried.append((await _dried(c))[1])
		c.queue_free()
	await process_frame
	check(dried[0] == dried[1], "a wash too thin to run dries the same standing up and lying flat")


## A brush laying water again and again in one place fills the paper there and no more.
func _water_fills_no_more_than_full() -> void:
	var at := []
	at.resize(30)
	at.fill(Vector2(0.5, 0.5))
	var c := await _canvas()
	var wet := Image.create_from_data(c.size.x, c.size.y, false, Image.FORMAT_RGBAH, (await _lay_only(c, [_water(at, 1.0, 1.0)]))[0])
	var most := 0.0
	for y in range(c.size.y / 2 - 60, c.size.y / 2 + 60):
		for x in range(c.size.x / 2 - 60, c.size.x / 2 + 60):
			most = maxf(most, wet.get_pixel(x, y).a)
	check(most > 0.9 and most <= 1.0, "water laid over and over in one place fills the paper and no more: %.3f" % most)
	var past := 0
	var reach := Brushwork.radii(Brushwork.Brush.BIG).y + 2.0
	for y in range(c.size.y / 2 - 60, c.size.y / 2 + 60):
		for x in range(c.size.x / 2 - 60, c.size.x / 2 + 60):
			if wet.get_pixel(x, y).a > 0.0 and absf(x + 0.5 - c.size.x / 2) > reach:
				past += 1
	check(past > 0, "a big brush's ragged edge reaches past its radius in places: %d texels" % past)
	c.queue_free()
	await process_frame


## A wash flows and dries without making pigment, settles more of it into the paper's pits than onto its
## peaks, and a clean wet brush over it once dry lifts some back into the water.
func _a_wash() -> void:
	var c := await _canvas()
	var region := Rect2i(500, 400, 540, 360)
	var laid: Array = await _lay_only(c, [_water([Vector2(0.45, 0.5), Vector2(0.55, 0.5)], 1.0, 1.0)])
	c.set_process(true)
	var dried: Array = await _dried(c)
	var wet_laid := _density(laid[0], c.size, region)
	var dry_laid := _density(laid[1], c.size, region)
	var after := _density(dried[1], c.size, region)
	check(wet_laid > 100.0 and after <= wet_laid + dry_laid, "a wash makes no pigment as it flows and dries: %.1f laid, %.1f dried" % [wet_laid + dry_laid, after])
	var paper := []
	RenderingServer.call_on_render_thread(func() -> void: paper.append(c._rd.texture_get_data(c._paper, 0)))
	while paper.is_empty():
		await process_frame
	var grain := Image.create_from_data(c.size.x, c.size.y, false, Image.FORMAT_RGBA8, paper[0])
	var dry := Image.create_from_data(c.size.x, c.size.y, false, Image.FORMAT_RGBAH, dried[1])
	var pits := Vector2.ZERO
	var peaks := Vector2.ZERO
	for y in range(536, 616):
		for x in range(728, 808):
			var g := grain.get_pixel(x, y).r
			if g < 0.3:
				pits += Vector2(dry.get_pixel(x, y).r, 1)
			elif g > 0.7:
				peaks += Vector2(dry.get_pixel(x, y).r, 1)
	check(pits.y > 50 and peaks.y > 50 and pits.x / pits.y > peaks.x / peaks.y, "more of it settles into the paper's pits than onto its peaks: %.4f and %.4f" % [pits.x / maxf(pits.y, 1), peaks.x / maxf(peaks.y, 1)])
	var clean := _water([Vector2(0.5, 0.5)], 1.0, 1.0, 0.0)
	clean.colour = Vector3.ZERO
	var lifted := _density((await _lay_only(c, [clean]))[1], c.size, Rect2i(728, 536, 80, 80))
	var under := _density(dried[1], c.size, Rect2i(728, 536, 80, 80))
	check(under > 1.0 and lifted < under * 0.95, "a clean wet brush lifts dried pigment: %.1f laid, %.1f after" % [under, lifted])
	c.queue_free()
	await process_frame


## The optical density summed over the red channel of paint `data`, a surface `texels` large, inside `rect`.
static func _density(data: PackedByteArray, texels: Vector2i, rect: Rect2i) -> float:
	var im := Image.create_from_data(texels.x, texels.y, false, Image.FORMAT_RGBAH, data)
	var total := 0.0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			total += im.get_pixel(x, y).r
	return total


## Oil laid over a wet wash takes the wet paint up where it covers.
func _oil_takes_up_wet_paint() -> void:
	var wash := _water([Vector2(0.3, 0.3)], 1.0, 1.0)
	var oil := {"medium": Brushwork.Medium.OIL, "brush": Brushwork.Brush.BIG, "colour": Brushwork.absorbance(Brushwork.PIGMENTS[1]), "strength": 1.0, "load": 1.0, "gap": 0, "samples": Brushwork.pack(Vector2(0.3, 0.3), 1.0, 0.0, 0)}
	var water := []
	for strokes in [[wash], [wash, oil]]:
		var c := await _canvas()
		var wet := Image.create_from_data(c.size.x, c.size.y, false, Image.FORMAT_RGBAH, (await _lay_only(c, strokes))[0])
		var total := 0.0
		for y in range(335, 356):
			for x in range(451, 471):
				total += wet.get_pixel(x, y).a
		water.append(total)
		c.queue_free()
	await process_frame
	check(water[0] > 50.0 and water[1] < water[0] * 0.5, "oil over a wet wash takes up the wet paint it covers: water %.1f before, %.1f after" % water)


## A second charcoal pass over the first darkens it by less than the first did.
func _charcoal_passes_darken_less() -> void:
	var samples := Brushwork.pack(Vector2(0.4, 0.7), 0.8, 0.0, 0) + Brushwork.pack(Vector2(0.5, 0.7), 0.8, 0.0, 1)
	var drag := {"medium": Brushwork.Medium.CHARCOAL, "brush": Brushwork.Brush.STICK, "colour": Brushwork.CHARCOAL, "strength": 1.0, "load": 1.0, "gap": 0, "samples": samples}
	var marks := []
	for strokes in [[drag], [drag, drag]]:
		var c := await _canvas()
		marks.append(_density((await _lay_only(c, strokes))[1], c.size, Rect2i(560, 760, 260, 90)))
		c.queue_free()
	await process_frame
	check(marks[0] > 1.0 and marks[1] - marks[0] < marks[0] * 0.9, "a second charcoal pass darkens by less than the first: %.1f, then %.1f more" % [marks[0], marks[1] - marks[0]])


## A flat brush lays a dab far longer one way than the other.
func _flat_brush_is_flat() -> void:
	var c := await _canvas()
	var stroke := {"medium": Brushwork.Medium.OIL, "brush": Brushwork.Brush.FLAT, "colour": Brushwork.absorbance(Brushwork.PIGMENTS[5]), "strength": 1.0, "load": 1.0, "gap": 0, "samples": Brushwork.pack(Vector2(0.5, 0.5), 1.0, 0.0, 0)}
	var dry := Image.create_from_data(c.size.x, c.size.y, false, Image.FORMAT_RGBAH, (await _lay_only(c, [stroke]))[1])
	var low := Vector2i(c.size)
	var high := Vector2i.ZERO
	for y in range(c.size.y / 2 - 70, c.size.y / 2 + 70):
		for x in range(c.size.x / 2 - 70, c.size.x / 2 + 70):
			if dry.get_pixel(x, y).a > 0.05:
				low = low.min(Vector2i(x, y))
				high = high.max(Vector2i(x, y))
	var span := high - low
	check(span.x > span.y * 2, "a flat brush's dab is far longer than it is wide: %s" % span)
	c.queue_free()
	await process_frame


## Paint still wet shows its colour in the canvas's flat view, as it does once dry.
func _wet_paint_shows() -> void:
	var c := await _canvas()
	await _lay_only(c, [_water([Vector2(0.5, 0.5)], 1.0, 1.0)])
	var vp := c.flat_view(false)
	root.add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var im := vp.get_texture().get_image()
	var wash := im.get_pixel(c.size.x / 2, c.size.y / 2).r
	var bare := im.get_pixel(40, 40).r
	check(wash < bare * 0.85, "a wet wash shows its colour: red %.3f on bare paper's %.3f" % [wash, bare])
	vp.queue_free()
	c.queue_free()
	await process_frame


## A water stroke of the big brush through `at`, every sample at `pressure`.
static func _water(at: Array, pressure: float, load: float, strength := 0.8) -> Dictionary:
	var samples := PackedInt32Array()
	for i in at.size():
		samples.append_array(Brushwork.pack(at[i], pressure, 0.0, 0 if i == 0 else 1))
	return {"medium": Brushwork.Medium.WATER, "brush": Brushwork.Brush.BIG, "colour": Brushwork.absorbance(Brushwork.PIGMENTS[5]), "strength": strength, "load": load, "gap": 0, "samples": samples}


## Lays `strokes` on `c` with its flow held, and returns its wet and dry paint as the dabs alone leave them.
func _lay_only(c: Canvas, strokes: Array) -> Array:
	c.set_process(false)
	for s: Dictionary in strokes:
		var st := Brushwork.Stroker.new(s, c.size)
		for i in Brushwork.count(s):
			c.lay(s, st.add(Brushwork.unpack(s.samples, i)))
	c._process(0.0)
	return await _pixels(c)


func _relief_undone() -> void:
	var daubs := Driver.daubs(2)
	var fresh := await _canvas()
	fresh.rebuild([daubs[0]])
	await _dried(fresh)
	var want := await _normal_pixels(fresh)
	var undone := await _canvas()
	undone.rebuild([daubs[0]])
	await _caught_up(undone)
	var at := undone.last_end
	undone.play(daubs[1], 0)
	while undone.last_end == at:
		await process_frame
	await _dried(undone)
	check(await _normal_pixels(undone) != want, "the second daub stands in the relief")
	undone.rebuild([daubs[0]])
	check(not undone.catching_up(), "the undo is a checkpoint")
	await _dried(undone)
	check(await _normal_pixels(undone) == want, "undone through a checkpoint, the relief is what a fresh replay leaves")
	for c: Canvas in [fresh, undone]:
		c.queue_free()
	await process_frame


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
	var out := await _pixels(c)
	var none := PackedByteArray()
	none.resize(out[0].size())
	check(out[0] == none, "a dried canvas holds nothing wet")
	return out


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
		rd.free_rid(initial)
		_spoil(c))
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
	var along := 0.0
	for y in range(500, 650):
		for x in range(700, 850):
			var pixel := moved.get_pixel(x, y)
			total += Vector4(pixel.r, pixel.g, pixel.b, pixel.a)
			along += pixel.a * x
	print("smear: conserved within %.4f; water's middle at x %.2f" % [(total - Vector4(500, 250, 125, 750)).length(), along / total.w])
	check((total - Vector4(500, 250, 125, 750)).length() < 0.5, "smear conserves pigment and water within half-float rounding")
	check(along / total.w > 760.0, "and moves it along the brush's heading: the water's middle from x 760 to %.2f" % (along / total.w))
	var drag := {"medium": Brushwork.Medium.SMEAR, "brush": Brushwork.Brush.FLAT, "colour": Vector3.ZERO, "strength": 0.0, "load": 1.0, "gap": 0, "samples": Brushwork.pack(Vector2(0.49, 0.5), 1.0, 0.0, 0) + Brushwork.pack(Vector2(0.51, 0.5), 1.0, 0.0, 1)}
	var smeared := Image.create_from_data(Brushwork.SIZE.x, Brushwork.SIZE.y, false, Image.FORMAT_RGBAH, (await _lay_only(c, [drag]))[0])
	var least := 0.0
	for y in range(500, 650):
		for x in range(700, 850):
			least = minf(least, smeared.get_pixel(x, y).a)
	check(least >= 0.0, "a smear of many dabs takes no texel below empty: %.3f" % least)
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
	var reds := {}
	for i in range(0, c.size.x * c.size.y * 4, 4):
		reds[bare[i]] = true
	check(reds.size() > 1, "bare paper's grain stands in the relief: %d slopes across it" % reds.size())
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
	check(incremental[(122 * c.size.x + 180) * 4] < 120, "paint rising to the right tilts the relief's normal left: red %d" % incremental[(122 * c.size.x + 180) * 4])
	RenderingServer.call_on_render_thread(c._update_normals.bind(Rect2i(Vector2i.ZERO, c.size)))
	check(await _normal_pixels(c) == incremental, "dirty normal updates match a full rebuild through odd-sized mips and texture edges")
	c._blank = false
	c._freeze()
	check(await _normal_pixels(c, true) == incremental, "a replay's frozen painting retains every normal mip")
	c._thaw()
	check(c._shown[3].texture_rd_rid == c._normal, "a completed replay shows the live normal chain")
	c.queue_free()
	await process_frame
