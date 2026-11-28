extends "res://../tests/support/booted.gd"

## Each photo style drawn over one view of a garden, held against the same view drawn plain. The grass moves between
## draws, so each measure is a share or a mean over the frame, never a pixel's match.

const STEP := 4


func _run() -> void:
	await play([
		{"op": "place", "x": 0, "z": 12},
		{"op": "house", "at": [0, 0], "size": [6, 4], "seconds": 0.3},
		{"op": "paint", "tool": "flowers", "points": [[-3, 5], [0, 4.5], [3, 5]], "radius": 1.6, "seconds": 1},
		{"op": "tree", "x": 6, "z": -1},
		{"op": "wait", "seconds": 1},
	])
	var tool: PhotoTool = main.photo_tool
	var at := Transform3D.IDENTITY.looking_at(Vector3(0, 1.5, 0) - Vector3(5, 3, 13), Vector3.UP)
	at.origin = Vector3(5, 3 + main.world.terrain.height_at(5, 13), 13)
	var seen := {}
	for kind: PhotoStyle.Kind in PhotoStyle.Kind.values():
		seen[kind] = _stats(await tool.render(at, PhotoTool.FOV, Quality.VIEW_MASK, kind))
	var plain: Dictionary = seen[PhotoStyle.Kind.PLAIN]
	for kind: PhotoStyle.Kind in seen:
		var s: Dictionary = seen[kind]
		print("%s: saturation %.3f, luma %.3f, edges %.4f, grey %.3f, warm %.3f, cool %.3f, red/blue %.2f" % [PhotoStyle.named(kind), s.saturation, s.luma, s.edges, s.grey, s.warm, s.cool, s.red / maxf(s.blue, 0.0001)])
	var painted: Dictionary = seen[PhotoStyle.Kind.PAINTERLY]
	check(painted.saturation > plain.saturation and absf(painted.luma - plain.luma) < plain.luma * 0.15, "painterly is the view more saturated, as bright: saturation %.3f over %.3f, luma %.3f against %.3f" % [painted.saturation, plain.saturation, painted.luma, plain.luma])
	var mono: Dictionary = seen[PhotoStyle.Kind.MONO]
	check(mono.grey > 0.99 and absf(mono.luma - plain.luma) < 0.03 and mono.edges > plain.edges * 0.8, "mono is grey on %.1f%% of the view, its light and edges plain's (%.3f, %.3f; %.4f, %.4f)" % [mono.grey * 100.0, mono.luma, plain.luma, mono.edges, plain.edges])
	for kind: PhotoStyle.Kind in [PhotoStyle.Kind.SEPIA, PhotoStyle.Kind.CYANOTYPE]:
		var tinted: Dictionary = seen[kind]
		var tone: Basis = PhotoStyle.TONES[kind]
		var ratio: float = tinted.red / tinted.blue
		var meant := tone[0].x / tone[2].x
		var ordered: float = tinted.warm if kind == PhotoStyle.Kind.SEPIA else tinted.cool
		check(ordered > 0.99 and absf(ratio / meant - 1.0) < 0.25, "%s orders its channels on %.1f%% of the view, its light's red to blue %.2f as its tone's %.2f" % [PhotoStyle.named(kind), ordered * 100.0, ratio, meant])
	var carved: Dictionary = seen[PhotoStyle.Kind.SCULPTURE]
	check(carved.grey > 0.99 and carved.luma > plain.luma * 2.0 and carved.spread > 0.03, "sculpture is white, grey on %.1f%%, luma %.3f against plain's %.3f, its shading kept (luma spread %.3f)" % [carved.grey * 100.0, carved.luma, plain.luma, carved.spread])
	await _screens(tool, at)
	await _photos(tool, at, plain)
	await _daubs(tool, at)
	await _shot_in_style(tool)
	finish()


## The camera's screen, a few eye pixels to its texels, still tells each style apart.
func _screens(tool: PhotoTool, at: Transform3D) -> void:
	var screens := {}
	for kind: PhotoStyle.Kind in [PhotoStyle.Kind.PLAIN, PhotoStyle.Kind.PAINTERLY, PhotoStyle.Kind.SCULPTURE, PhotoStyle.Kind.MONO]:
		tool.wear(kind, false)
		screens[kind] = _stats(await tool.render_screen(at))
	tool.wear(PhotoStyle.Kind.PLAIN, false)
	var plain: Dictionary = screens[PhotoStyle.Kind.PLAIN]
	var painted: Dictionary = screens[PhotoStyle.Kind.PAINTERLY]
	var carved: Dictionary = screens[PhotoStyle.Kind.SCULPTURE]
	print("screen: plain edges %.4f saturation %.3f luma %.3f, painterly edges %.4f, sculpture saturation %.3f luma %.3f" % [plain.edges, plain.saturation, plain.luma, painted.edges, carved.saturation, carved.luma])
	check(screens[PhotoStyle.Kind.MONO].grey > 0.99, "the camera's screen draws in its style: grey on %.1f%% of it" % (screens[PhotoStyle.Kind.MONO].grey * 100.0))
	check(carved.grey > 0.99 and carved.luma > plain.luma * 2.0, "the screen shows the sculpture white: grey on %.1f%%, luma %.3f against plain's %.3f" % [carved.grey * 100.0, carved.luma, plain.luma])


func _shot_in_style(tool: PhotoTool) -> void:
	var hand := main.rig.right
	hand.tool = Hand.Tool.CAMERA
	hand.held_still = true
	hand.global_transform = Transform3D(Basis.looking_at(Vector3(-5, -2, -13).normalized()), Vector3(5, 3 + main.world.terrain.height_at(5, 13), 13))
	tool.wear(PhotoStyle.Kind.SEPIA, false)
	await frames(2)
	var path := await tool.shoot(hand)
	var png := FileAccess.get_file_as_bytes(path)
	var img := Image.new()
	var loaded := img.load_png_from_buffer(png)
	var about: Dictionary = PhotoMeta.read(png).get("about", {})
	var shot := _stats(img) if loaded == OK else {"warm": 0.0}
	check(about.get("style") == "sepia" and shot.warm > 0.99, "a photo taken in sepia is sepia and says so: %s, ordered on %.1f%%" % [about.get("style"), shot.warm * 100.0])
	tool.wear(PhotoStyle.Kind.PLAIN, false)
	hand.tool = Hand.Tool.NONE


## A photo is drawn by its own pass at its own size: the strokes scale with it.
func _photos(tool: PhotoTool, at: Transform3D, plain: Dictionary) -> void:
	var painted := _stats(await tool.render(at, PhotoTool.FOV, Quality.PHOTO_MASK, PhotoStyle.Kind.PAINTERLY))
	main.rig.uncover()
	var whole := _stats(await tool.render(at, PhotoTool.FOV, Quality.PHOTO_MASK, PhotoStyle.Kind.PLAIN))
	main.rig.uncover()
	var carved := _stats(await tool.render(at, PhotoTool.FOV, Quality.PHOTO_MASK, PhotoStyle.Kind.SCULPTURE))
	main.rig.uncover()
	print("photo: plain edges %.4f saturation %.3f, painterly edges %.4f, sculpture saturation %.3f" % [whole.edges, whole.saturation, painted.edges, carved.saturation])
	check(painted.size == PhotoTool.PHOTO_SIZE and painted.saturation > whole.saturation, "a painterly photo is drawn in its style at %s: saturation %.3f over plain's %.3f" % [painted.size, painted.saturation, whole.saturation])
	check(carved.saturation < whole.saturation * 0.35, "a sculpture photo is white: saturation %.3f against plain's %.3f" % [carved.saturation, whole.saturation])
	check(absf(whole.luma - plain.luma) < plain.luma * 0.2, "the photo sees what the view does")


## Painterly lays daubs an eye can see on the screen and in a photo: on a smooth sky, where plain draws next to no edges,
## its daubs' ridges and furrows do; and a photo's tiles lay one picture's daubs, meeting without a seam.
func _daubs(tool: PhotoTool, at: Transform3D) -> void:
	var up := Transform3D(Basis.looking_at(Vector3(0.3, 0.8, -1.0).normalized()), at.origin)
	for screen in [true, false]:
		var seen := {}
		for kind: PhotoStyle.Kind in [PhotoStyle.Kind.PLAIN, PhotoStyle.Kind.PAINTERLY]:
			tool.wear(kind, false)
			seen[kind] = _stats(await tool.render_screen(up) if screen else await tool.render(up, PhotoTool.FOV, Quality.PHOTO_MASK, kind))
			main.rig.uncover()
		tool.wear(PhotoStyle.Kind.PLAIN, false)
		var plain: Dictionary = seen[PhotoStyle.Kind.PLAIN]
		var painted: Dictionary = seen[PhotoStyle.Kind.PAINTERLY]
		var where := "the screen" if screen else "a photo"
		print("%s's sky: plain edges %.4f, painterly %.4f" % [where, plain.edges, painted.edges])
		check(painted.edges > plain.edges * 3.0, "%s lays painterly's sky in daubs: edges %.4f against plain's %.4f" % [where, painted.edges, plain.edges])
	var photo := await tool.render(at, PhotoTool.FOV, Quality.PHOTO_MASK, PhotoStyle.Kind.PAINTERLY)
	main.rig.uncover()
	var worst := 0.0
	for k in range(1, PhotoTool.TILES.x):
		worst = maxf(worst, _seam(photo, k * PhotoTool.PHOTO_SIZE.x / PhotoTool.TILES.x, true))
	for k in range(1, PhotoTool.TILES.y):
		worst = maxf(worst, _seam(photo, k * PhotoTool.PHOTO_SIZE.y / PhotoTool.TILES.y, false))
	print("painterly photo: worst tile seam %.2f" % worst)
	check(worst < 1.5, "a painterly photo's tiles meet without a seam: the worst seam changes %.2f times as much as the lines beside it" % worst)


## Across the line before `at`, a column (`columns`) or a row, the mean change against the lines a few pixels either
## side.
static func _seam(img: Image, at: int, columns: bool) -> float:
	var across := func(i: int) -> float:
		var sum := 0.0
		var n := img.get_height() if columns else img.get_width()
		for j in range(0, n, 2):
			sum += _gap(img.get_pixel(i - 1, j), img.get_pixel(i, j)) if columns else _gap(img.get_pixel(j, i - 1), img.get_pixel(j, i))
		return sum
	var beside := 0.0
	for d in [-12, -8, -4, 4, 8, 12]:
		beside += across.call(at + d) / 6.0
	return across.call(at) / maxf(beside, 1e-6)


static func _stats(img: Image) -> Dictionary:
	var n := 0
	var sat := 0.0
	var luma := 0.0
	var lumas := 0.0
	var edges := 0.0
	var grey := 0
	var warm := 0
	var cool := 0
	var red := 0.0
	var blue := 0.0
	var tie := 1.5 / 255.0
	for y in range(0, img.get_height() - 1, STEP):
		for x in range(0, img.get_width() - 1, STEP):
			var c := img.get_pixel(x, y)
			var l := c.srgb_to_linear()
			var hi := maxf(c.r, maxf(c.g, c.b))
			var lo := minf(c.r, minf(c.g, c.b))
			n += 1
			sat += (hi - lo) / hi if hi > 0.0 else 0.0
			var y_lin := l.r * PhotoStyle.LUMA.x + l.g * PhotoStyle.LUMA.y + l.b * PhotoStyle.LUMA.z
			luma += y_lin
			lumas += y_lin * y_lin
			edges += _gap(c, img.get_pixel(x + 1, y)) + _gap(c, img.get_pixel(x, y + 1))
			grey += int(hi - lo <= tie * 2.0)
			warm += int(c.r + tie >= c.g and c.g + tie >= c.b)
			cool += int(c.b + tie >= c.g and c.g + tie >= c.r)
			red += l.r
			blue += l.b
	var mean := luma / n
	return {"size": img.get_size(), "saturation": sat / n, "luma": mean, "spread": sqrt(maxf(lumas / n - mean * mean, 0.0)),
		"edges": edges / n, "grey": float(grey) / n, "warm": float(warm) / n, "cool": float(cool) / n, "red": red / n, "blue": blue / n}


static func _gap(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
