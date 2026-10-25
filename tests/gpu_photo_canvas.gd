extends "res://../tests/support/suite.gd"

## A photo of easels saves each canvas it is of beside itself, pixel for pixel the canvas's own paint at its full size,
## flat, and its height off the board; a wide shot with the canvases small in it, and a shot of neither, save the photo
## alone. Needs a RenderingDevice, so scripts/test.sh runs it on the desktop renderer:
## godot4 --path game --xr-mode off --script ../tests/gpu_photo_canvas.gd

var folder := ""


func _initialize() -> void:
	boot_main()
	_run.call_deferred()


func _run() -> void:
	if RenderingServer.get_rendering_device() == null:
		check(false, "no RenderingDevice; run on the desktop renderer")
		finish()
		return
	folder = OS.get_user_data_dir().path_join("photo-canvas-%d" % OS.get_process_id())
	main.photo_tool.folder = folder
	await play([
		{"op": "place", "x": 0, "z": 6},
		{"op": "easel", "x": -0.75, "z": 3, "facing": [-0.75, 6]},
		{"op": "easel", "x": 0.75, "z": 3, "facing": [0.75, 6]},
		{"op": "painting", "easel": 0, "strokes": 6},
		{"op": "painting", "easel": 1, "strokes": 14},
		{"op": "pick", "hand": "right", "tool": "camera"},
	])
	var easels: Array = main.easels.easels.keys()
	easels.sort()
	easels = easels.map(main.easels.find)
	await until(func() -> bool: return easels.all(func(e: Easels.Easel) -> bool: return not e.canvas.wet()), "the paintings dry")

	var close := await _shoot([0, 1.45, 4.85], [0, 1.3, 0])
	var covers := easels.map(func(e: Easels.Easel) -> float: return PhotoTool.coverage(close.lens, e.canvas_corners()))
	check(covers.all(func(c: float) -> bool: return c >= PhotoTool.SUBJECT), "a close shot is of both canvases: %s" % [covers])
	check(close.canvases.size() == 2, "and saves both beside the photo: %s" % [close.files])
	for i in mini(close.canvases.size(), easels.size()):
		await _is_the_canvas(close.canvases[i], easels[i])

	var wide := await _shoot([0, 1.6, 13], [0, 1.3, 0])
	covers = easels.map(func(e: Easels.Easel) -> float: return PhotoTool.coverage(wide.lens, e.canvas_corners()))
	check(covers.all(func(c: float) -> bool: return c > 0.0 and c < PhotoTool.SUBJECT), "a wide shot has the canvases in view, small: %s" % [covers])
	check(wide.files.size() == 1 and wide.canvases.is_empty(), "and saves the photo alone: %s" % [wide.files])

	var away := await _shoot([0, 1.45, 4.85], [0, 1.3, 20])
	check(away.files.size() == 1 and away.canvases.is_empty(), "a shot of neither saves the photo alone: %s" % [away.files])

	for f in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(f))
	DirAccess.remove_absolute(folder)
	finish()


## Takes a photo with the right hand's camera, the eye at `eye` looking at `at`: {"lens", "files": every file it saved,
## "canvases": the paths of the canvases' colour images, in order}.
func _shoot(eye: Array, at: Array) -> Dictionary:
	var before := Array(DirAccess.get_files_at(folder)) if DirAccess.dir_exists_absolute(folder) else []
	await play([
		{"op": "view", "eye": eye, "at": at},
		{"op": "hands", "right": [0.0, -0.12, -0.32], "tip": 0},
	])
	var lens := PhotoTool.lens(main.rig.right)
	var photo := await main.photo_tool.shoot(main.rig.right)
	check(photo != "", "the photo is saved")
	var files := Array(DirAccess.get_files_at(folder)).filter(func(f: String) -> bool: return not f in before)
	files.sort()
	var stem := photo.get_file().get_basename()
	var canvases := files.filter(func(f: String) -> bool: return f.begins_with(stem + "-canvas-") and not f.ends_with("-height.png"))
	check(files.all(func(f: String) -> bool: return f == photo.get_file() or f.begins_with(stem + "-canvas-")), "everything it saves is named for the photo: %s" % [files])
	return {"lens": lens, "files": files, "canvases": canvases.map(folder.path_join)}


## The canvas's wet, dry and paper as the GPU holds them.
func _textures(c: Canvas) -> Array[Image]:
	var out: Array[Image] = []
	var rd := RenderingServer.get_rendering_device()
	var got := []
	RenderingServer.call_on_render_thread(func() -> void:
		for t in c._shown:
			got.append(rd.texture_get_data(t.texture_rd_rid, 0)))
	while got.size() < 3:
		await process_frame
	for i in 3:
		out.append(Image.create_from_data(Brushwork.SIZE.x, Brushwork.SIZE.y, false, Image.FORMAT_RGBAH if i < 2 else Image.FORMAT_RGBA8, got[i]))
	return out


func _is_the_canvas(path: String, e: Easels.Easel) -> void:
	var colour := Image.load_from_file(path)
	var height_png := FileAccess.get_file_as_bytes(path.get_basename() + "-height.png")
	var height := _gray16(height_png)
	check(colour.get_size() == Brushwork.SIZE, "%s is the canvas's full %s: %s" % [path.get_file(), Brushwork.SIZE, colour.get_size()])
	check(height.size == Brushwork.SIZE, "and so is its height: %s" % height.size)
	var heard := Image.new()
	check(heard.load_png_from_buffer(height_png) == OK, "the height map is a PNG other readers open")
	if colour.get_size() != Brushwork.SIZE or height.size != Brushwork.SIZE:
		return
	var tex := await _textures(e.canvas)
	var exact := 0
	var worst := 0
	var edge := 0.0
	var exact_height := 0
	var worst_height := 0
	var painted := 0
	var tall := 0
	var top := Canvas.IMPASTO + Canvas.GRAIN
	for y in Brushwork.SIZE.y:
		for x in Brushwork.SIZE.x:
			var w := tex[0].get_pixel(x, y)
			var d := tex[1].get_pixel(x, y)
			var tooth := tex[2].get_pixel(x, y)
			var sheet := Vector3(0.93, 0.91, 0.86) * (0.97 + 0.03 * tooth.r + 0.02 * tooth.g)
			var damp := smoothstep(0.0, 0.25, w.a)
			var lin := Color(sheet.x * exp(-(d.r + w.r)), sheet.y * exp(-(d.g + w.g)), sheet.z * exp(-(d.b + w.b))) * (1.0 - 0.12 * damp)
			var want := lin.clamp().linear_to_srgb()
			var got := colour.get_pixel(x, y)
			var off := 0
			for k in 3:
				var step := absi(roundi(want[k] * 255) - roundi(got[k] * 255))
				off = maxi(off, step)
				if step != 0:
					edge = maxf(edge, absf(fposmod(want[k] * 255, 1.0) - 0.5))
			exact += int(off == 0)
			worst = maxi(worst, off)
			painted += int(d.r + d.g + d.b > 0.05)
			var h := roundi(clampf((d.a * Canvas.IMPASTO + tooth.r * Canvas.GRAIN) / top, 0.0, 1.0) * 65535.0)
			var got_h: int = height.samples.decode_u16((y * Brushwork.SIZE.x + x) * 2)
			got_h = ((got_h & 0xFF) << 8) | (got_h >> 8)
			exact_height += int(got_h == h)
			worst_height = maxi(worst_height, absi(got_h - h))
			tall += int(d.a > 0.0)
	var n := Brushwork.SIZE.x * Brushwork.SIZE.y
	print("canvas %d: %d of %d texels painted; colour exact on %d, at most %d/255 off, a value at most %.3f of a step from where its rounding turns; height exact on %d, at most %d/65535 off" % [e.id, painted, n, exact, worst, edge, exact_height, worst_height])
	check(painted > n / 100, "the canvas is painted: %d texels" % painted)
	check(worst <= 1 and edge < 0.001, "every pixel is the canvas's texel there, flattened and sRGB-encoded, the same 8-bit step this float evaluation rounds it to but where the value lies on a step's boundary: %d of %d exact, the others %.4f of a step from it" % [exact, n, edge])
	check(worst_height <= 1 and exact_height > n * 0.999, "every height sample is the texel's height off the board, to the last 16-bit step: %d exact, worst %d" % [exact_height, worst_height])


## A 16-bit greyscale PNG as PhotoMeta.gray16 writes it: {"size", "samples": big-endian, row by row}.
static func _gray16(png: PackedByteArray) -> Dictionary:
	var at := 8
	var size := Vector2i.ZERO
	var packed := PackedByteArray()
	while at + 12 <= png.size():
		var n := (png[at] << 24) | (png[at + 1] << 16) | (png[at + 2] << 8) | png[at + 3]
		var type := png.slice(at + 4, at + 8).get_string_from_ascii()
		var data := png.slice(at + 8, at + 8 + n)
		if type == "IHDR":
			size = Vector2i(data.decode_u32(0), data.decode_u32(4))
			size = Vector2i(_swap(size.x), _swap(size.y))
			if data[8] != 16 or data[9] != 0:
				return {"size": Vector2i.ZERO, "samples": PackedByteArray()}
		elif type == "IDAT":
			packed.append_array(data)
		at += 12 + n
	var lines := packed.decompress_dynamic(-1, FileAccess.COMPRESSION_DEFLATE)
	var samples := PackedByteArray()
	for y in size.y:
		samples.append_array(lines.slice(y * (size.x * 2 + 1) + 1, (y + 1) * (size.x * 2 + 1)))
	return {"size": size, "samples": samples}


static func _swap(n: int) -> int:
	return ((n & 0xFF) << 24) | ((n & 0xFF00) << 8) | ((n >> 8) & 0xFF00) | ((n >> 24) & 0xFF)
