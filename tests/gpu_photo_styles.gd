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
	check(painted.edges < plain.edges * 0.8 and painted.saturation > plain.saturation and absf(painted.luma - plain.luma) < plain.luma * 0.15, "painterly lays the view in strokes: %.4f of plain's edges %.4f, saturation %.3f over %.3f, as bright" % [painted.edges, plain.edges, painted.saturation, plain.saturation])
	var mono: Dictionary = seen[PhotoStyle.Kind.MONO]
	check(mono.grey > 0.99 and absf(mono.luma - plain.luma) < 0.03, "mono is grey on %.1f%% of the view, its light plain's (%.3f, %.3f)" % [mono.grey * 100.0, mono.luma, plain.luma])
	var sepia: Dictionary = seen[PhotoStyle.Kind.SEPIA]
	check(sepia.warm > 0.99 and sepia.red > sepia.blue * 1.4, "sepia runs red over green over blue on %.1f%% of the view" % (sepia.warm * 100.0))
	var cyan: Dictionary = seen[PhotoStyle.Kind.CYANOTYPE]
	check(cyan.cool > 0.99 and cyan.blue > cyan.red * 2.0, "cyanotype runs blue over green over red on %.1f%% of the view" % (cyan.cool * 100.0))
	var carved: Dictionary = seen[PhotoStyle.Kind.SCULPTURE]
	check(carved.saturation < plain.saturation * 0.35 and carved.spread > 0.03, "sculpture is white, saturation %.3f against plain's %.3f, its shading kept (luma spread %.3f)" % [carved.saturation, plain.saturation, carved.spread])
	check((await tool.render_screen(at)) != null, "the camera's screen draws in its style")
	await _photos(tool, at, plain)
	finish()


## A photo is drawn by its own pass at its own size: the strokes scale with it.
func _photos(tool: PhotoTool, at: Transform3D, plain: Dictionary) -> void:
	var painted := _stats(await tool.render(at, PhotoTool.FOV, Quality.PHOTO_MASK, PhotoStyle.Kind.PAINTERLY))
	main.rig.uncover()
	var whole := _stats(await tool.render(at, PhotoTool.FOV, Quality.PHOTO_MASK, PhotoStyle.Kind.PLAIN))
	main.rig.uncover()
	var carved := _stats(await tool.render(at, PhotoTool.FOV, Quality.PHOTO_MASK, PhotoStyle.Kind.SCULPTURE))
	main.rig.uncover()
	print("photo: plain edges %.4f saturation %.3f, painterly edges %.4f, sculpture saturation %.3f" % [whole.edges, whole.saturation, painted.edges, carved.saturation])
	check(painted.size == PhotoTool.PHOTO_SIZE and painted.edges < whole.edges * 0.8, "a painterly photo is laid in strokes at %s: edges %.4f of plain's %.4f" % [painted.size, painted.edges, whole.edges])
	check(carved.saturation < whole.saturation * 0.35, "a sculpture photo is white: saturation %.3f against plain's %.3f" % [carved.saturation, whole.saturation])
	check(absf(whole.luma - plain.luma) < plain.luma * 0.2, "the photo sees what the view does")


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
