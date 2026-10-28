extends "res://../tests/support/suite.gd"

## The oil palette's board on the GPU: strokes painted onto it are laid by the canvas's own paint (an oil stroke stands
## as high and as coloured on the board as on the canvas), a brush touching it takes up the paint under it and paints
## that onto the canvas, a brush touching the canvas takes up its paint alike, and a photo of the palette saves its paint
## as one of a canvas is saved. Needs a
## RenderingDevice, so scripts/test.sh runs it on the desktop renderer: godot4 --path game --xr-mode off --script
## ../tests/gpu_palette.gd

var folder := ""


func _initialize() -> void:
	boot_main()
	_run.call_deferred()


func _run() -> void:
	if RenderingServer.get_rendering_device() == null:
		check(false, "no RenderingDevice; run on the desktop renderer")
		finish()
		return
	main.world.bounded = false
	await _one_stroke_lies_alike_on_board_and_canvas()
	await _the_brush_takes_up_what_it_touches()
	await _the_canvas_gives_up_its_paint_as_the_board_does()
	await _a_photo_of_the_palette_keeps_its_paint()
	finish()


## A surface's dry paint (rgb optical density, a the oil's height) as the GPU holds it.
func _dry(c: Canvas) -> Image:
	var rd := RenderingServer.get_rendering_device()
	var got := []
	RenderingServer.call_on_render_thread(func() -> void: got.append(rd.texture_get_data(c._dry, 0)))
	while got.is_empty():
		await process_frame
	return Image.create_from_data(c.size.x, c.size.y, false, Image.FORMAT_RGBAH, got[0])


## The mean height of the oil on `img` and its mean density where it stands, over the texels any stands on.
static func _laid(img: Image) -> Array:
	var height := 0.0
	var density := Vector3.ZERO
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.05:
				n += 1
				height += c.a
				density += Vector3(c.r, c.g, c.b)
	return [n, height / maxi(n, 1), density / maxi(n, 1)]


## One oil stroke laid on a canvas and on a board, the same length in texels at the same place in each: the same paint
## code lays it, so it covers as much, stands as high and shows the same colour on both.
func _one_stroke_lies_alike_on_board_and_canvas() -> void:
	var surfaces: Array[Canvas] = [Canvas.new(), Canvas.new(Easels.BOARD, preload("res://src/board.gdshader"))]
	var laid := []
	for c in surfaces:
		root.add_child(c)
		var samples := PackedInt32Array()
		for i in 12:
			samples.append_array(Brushwork.pack((Vector2(100, 120) + Vector2(i * 12, i * 3)) / Vector2(c.size), 0.9, 0.0, 0 if i == 0 else 2))
		var stroke := {"medium": Brushwork.Medium.OIL, "brush": Brushwork.Brush.BIG, "colour": Brushwork.absorbance(Brushwork.PIGMENTS[5]), "strength": 1.0, "load": 1.0, "gap": 0, "samples": samples}
		c.rebuild([stroke])
		await until(func() -> bool: return not c.catching_up() and c.settled(), "the stroke is laid")
		await frames(2)
		laid.append(_laid((await _dry(c)).get_region(Rect2i(0, 0, 320, 256))))
	print("palette: canvas %s, board %s" % [laid[0], laid[1]])
	check(laid[0][0] > 1000 and absf(laid[1][0] - laid[0][0]) < laid[0][0] * 0.05, "the stroke covers as much of the board as of the canvas: %d and %d texels" % [laid[1][0], laid[0][0]])
	check(absf(laid[1][1] - laid[0][1]) < 0.03 and laid[1][1] > 0.3, "stands as high: %.3f and %.3f" % [laid[1][1], laid[0][1]])
	check(laid[1][2].distance_to(laid[0][2]) < 0.05, "and lays the same colour: %s and %s" % [laid[1][2], laid[0][2]])
	for c in surfaces:
		c.queue_free()


## Blue painted onto the board, then yellow worked into it, mix there; a clean brush touching the mix comes away loaded
## with it, and its stroke on the canvas is that colour.
func _the_brush_takes_up_what_it_touches() -> void:
	await play([{"op": "place", "x": 0, "z": 6}, {"op": "easel", "x": 0, "z": 3}, {"op": "take", "what": "big"}, {"op": "dip", "what": "oil", "index": 5}])
	var e: Easels.Easel = main.easels.easels.values()[-1]
	var p: EaselTool.Painter = main.easel_tool.painter(main.rig.right)
	var blue := Brushwork.absorbance(Brushwork.PIGMENTS[5])
	var lemon := Brushwork.absorbance(Brushwork.PIGMENTS[1])
	await play([{"op": "mix", "points": [[-0.3, -0.1, 0.9], [0.3, -0.1, 0.9], [0.3, 0.1, 0.9], [-0.3, 0.1, 0.9]], "seconds": 1.0}])
	await play([{"op": "dip", "what": "oil", "index": 1}, {"op": "mix", "points": [[-0.2, -0.1, 0.9], [0.2, 0.1, 0.9], [-0.2, 0.1, 0.9], [0.2, -0.1, 0.9], [-0.2, -0.1, 0.9], [0.2, 0.1, 0.9]], "seconds": 2.0}])
	var stirred: Array = main.world.state.easels[e.id].palette
	print("palette: %d strokes stirred, colours %s" % [stirred.size(), stirred.map(func(s: Dictionary) -> String: return str(Brushwork.colour(s.colour)))])
	check(stirred.size() > 2, "stirring yellow into the blue lays strokes in the brush's paint as it changes: %d" % stirred.size())
	check(stirred.slice(2).any(func(s: Dictionary) -> bool: return Vector3(s.colour).distance_to(lemon) > 0.3 and Vector3(s.colour).distance_to(blue) > 0.3), "some in a mix of the two")
	await play([{"op": "take", "what": "small"}])
	check(p.load == 0.0, "a fresh brush is clean")
	await play([{"op": "mix", "points": [[0.0, 0.0, 0.7], [0.03, 0.0, 0.7], [0.0, 0.0, 0.7]], "seconds": 0.5}])
	var tip := Brushwork.colour(p.colour)
	print("palette: took up %s at load %.2f" % [tip, p.load])
	check(p.medium == Brushwork.Medium.OIL and p.load == 1.0, "touching the mix loads the clean brush full of oil: load %.2f" % p.load)
	check(p.colour.distance_to(blue) > 0.3 and p.colour.distance_to(lemon) > 0.3 and tip.g > tip.b, "the mix's colour, neither the blue nor the yellow: %s" % tip)
	var took := p.colour
	await play([{"op": "brush", "points": [[0.3, 0.3, 0.8], [0.45, 0.32, 0.8]], "seconds": 0.3}])
	main.world.flush()
	await frames(2)
	var strokes: Array = main.world.state.easels[e.id].strokes
	check(strokes.size() == 1 and strokes[0].medium == Brushwork.Medium.OIL and Vector3(strokes[0].colour).distance_to(took) < 1e-4, "and paints it onto the canvas")


## Blue laid on the canvas, then a clean brush touching it there: it comes away full of the blue, as off the board, and
## its strokes over it carry that paint.
func _the_canvas_gives_up_its_paint_as_the_board_does() -> void:
	var e: Easels.Easel = main.easels.easels.values()[-1]
	var p: EaselTool.Painter = main.easel_tool.painter(main.rig.right)
	var blue := Brushwork.absorbance(Brushwork.PIGMENTS[5])
	await play([{"op": "take", "what": "big"}, {"op": "dip", "what": "oil", "index": 5}, {"op": "brush", "points": [[0.6, 0.6, 0.9], [0.75, 0.6, 0.9], [0.75, 0.65, 0.9], [0.6, 0.65, 0.9]], "seconds": 0.8}])
	main.world.flush()
	await frames(4)
	await play([{"op": "take", "what": "small"}])
	check(p.load == 0.0, "a fresh brush is clean")
	await play([{"op": "brush", "points": [[0.66, 0.62, 0.7], [0.68, 0.62, 0.7], [0.66, 0.62, 0.7]], "seconds": 0.5}])
	print("canvas: took up %s at load %.2f" % [Brushwork.colour(p.colour), p.load])
	check(p.medium == Brushwork.Medium.OIL and p.load == 1.0, "touching the canvas's oil loads the clean brush full: load %.2f" % p.load)
	check(p.colour.distance_to(blue) < 0.3, "with the blue there: %s" % Brushwork.colour(p.colour))
	main.world.flush()
	await frames(2)
	var strokes: Array = main.world.state.easels[e.id].strokes
	check(strokes.size() >= 2 and strokes[-1].brush == Brushwork.Brush.SMALL and Vector3(strokes[-1].colour).distance_to(blue) < 0.3, "and its stroke on the canvas lays that paint")


## A photo looking down onto the palette saves its paint beside it, at the board's own size.
func _a_photo_of_the_palette_keeps_its_paint() -> void:
	folder = OS.get_user_data_dir().path_join("photo-palette-%d" % OS.get_process_id())
	main.photo_tool.folder = folder
	var e: Easels.Easel = main.easels.easels.values()[-1]
	var board := e.board_mesh.global_transform
	var eye := board * Vector3(0, -0.1, 0.75)
	await play([
		{"op": "pick", "hand": "right", "tool": "camera"},
		{"op": "view", "eye": [eye.x, eye.y, eye.z], "at": [board.origin.x, board.origin.y, board.origin.z]},
		{"op": "hands", "right": [0.0, -0.12, -0.32], "tip": 0},
	])
	var lens := PhotoTool.lens(main.rig.right)
	print("palette: photo covers %.2f of the frame" % PhotoTool.coverage(lens, board, e.board.metres))
	var photo := await main.photo_tool.shoot(main.rig.right)
	var stem := photo.get_basename()
	var saved := Image.load_from_file(stem + "-palette-1.png")
	check(saved != null and saved.get_size() == Easels.BOARD, "a photo of the palette saves its paint at the board's size: %s" % [saved.get_size() if saved != null else null])
	check(FileAccess.file_exists(stem + "-palette-1-height.png"), "and its height off the board")
	for f in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(f))
	DirAccess.remove_absolute(folder)
